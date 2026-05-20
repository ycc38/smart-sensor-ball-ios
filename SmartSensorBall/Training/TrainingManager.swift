import Combine
import Foundation

enum TrainingMode: String, CaseIterable, Codable, Identifiable {
    case seconds30
    case seconds60
    case burst10
    case burst15

    var id: String { rawValue }

    var durationSeconds: Int {
        switch self {
        case .seconds30: return 30
        case .seconds60: return 60
        case .burst10: return 10
        case .burst15: return 15
        }
    }

    var labelKey: String {
        switch self {
        case .seconds30: return "mode_30"
        case .seconds60: return "mode_60"
        case .burst10: return "mode_burst10"
        case .burst15: return "mode_burst15"
        }
    }
}

enum TrainingPlayMode: String, CaseIterable, Codable, Identifiable {
    case classic30
    case classic60
    case burst10
    case burst15
    case levelChallenge
    case dailyChallenge

    var id: String { rawValue }

    var mode: TrainingMode {
        switch self {
        case .classic30, .levelChallenge, .dailyChallenge: return .seconds30
        case .classic60: return .seconds60
        case .burst10: return .burst10
        case .burst15: return .burst15
        }
    }

    var titleKey: String {
        switch self {
        case .classic30: return "play_classic30"
        case .classic60: return "play_classic60"
        case .burst10: return "play_burst10"
        case .burst15: return "play_burst15"
        case .levelChallenge: return "play_level"
        case .dailyChallenge: return "play_daily"
        }
    }

    var subtitleKey: String {
        switch self {
        case .classic30: return "play_classic30_body"
        case .classic60: return "play_classic60_body"
        case .burst10: return "play_burst10_body"
        case .burst15: return "play_burst15_body"
        case .levelChallenge: return "play_level_body"
        case .dailyChallenge: return "play_daily_body"
        }
    }
}

enum TrainingPhase: String, Codable {
    case idle
    case countdown
    case running
    case finished
    case error
}

struct TrainingReport: Identifiable, Codable, Equatable {
    let id: UUID
    let mode: TrainingMode
    let playMode: TrainingPlayMode
    let totalHits: Int
    let averageFrequency: Double
    let bestBurstCount: Int
    let bestBurstStartSec: Double
    let endedAtEpochMs: Int
    let targetHits: Int?
    let goalMet: Bool
    let levelBefore: Int
    let levelAfter: Int
    let streak: Int
    let xpGain: Int
    let coachMessage: String

    init(
        id: UUID = UUID(),
        mode: TrainingMode,
        playMode: TrainingPlayMode,
        totalHits: Int,
        averageFrequency: Double,
        bestBurstCount: Int,
        bestBurstStartSec: Double,
        endedAtEpochMs: Int,
        targetHits: Int?,
        goalMet: Bool,
        levelBefore: Int,
        levelAfter: Int,
        streak: Int,
        xpGain: Int,
        coachMessage: String
    ) {
        self.id = id
        self.mode = mode
        self.playMode = playMode
        self.totalHits = totalHits
        self.averageFrequency = averageFrequency
        self.bestBurstCount = bestBurstCount
        self.bestBurstStartSec = bestBurstStartSec
        self.endedAtEpochMs = endedAtEpochMs
        self.targetHits = targetHits
        self.goalMet = goalMet
        self.levelBefore = levelBefore
        self.levelAfter = levelAfter
        self.streak = streak
        self.xpGain = xpGain
        self.coachMessage = coachMessage
    }
}

@MainActor
final class TrainingManager: ObservableObject {
    @Published var phase: TrainingPhase = .idle
    @Published var selectedPlayMode: TrainingPlayMode = .classic30
    @Published var isRunning = false
    @Published var countdownText = "3"
    @Published var realTimeHits = 0
    @Published var remainingMillis = 0
    @Published var latestReport: TrainingReport?
    @Published var reportHistory: [TrainingReport] = []
    @Published var trainingLevel = 1
    @Published var trainingXP = 0
    @Published var currentStreak = 0
    @Published private var statusKey = "ready"

    private weak var bluetoothManager: SensorBallBluetoothManager?
    private weak var soundEffectManager: SoundEffectManager?
    private weak var speechCueService: SpeechCueService?
    private var timerTask: Task<Void, Never>?
    private var hitTimes: [Double] = []

    private enum Keys {
        static let reports = "training_reports_v2"
        static let level = "training_level"
        static let xp = "training_xp"
        static let streak = "training_streak"
        static let lastTrainingDay = "training_last_day"
    }

    init() {
        loadLocalState()
    }

    func attach(
        bluetoothManager: SensorBallBluetoothManager,
        soundEffectManager: SoundEffectManager? = nil,
        speechCueService: SpeechCueService? = nil
    ) {
        self.bluetoothManager = bluetoothManager
        self.soundEffectManager = soundEffectManager
        self.speechCueService = speechCueService
    }

    func statusText(language: AppLanguage) -> String {
        L10n.text(statusKey, language)
    }

    func modeTitle(language: AppLanguage) -> String {
        L10n.text(selectedPlayMode.titleKey, language)
    }

    func modeBody(language: AppLanguage) -> String {
        L10n.text(selectedPlayMode.subtitleKey, language)
    }

    func targetHits(for playMode: TrainingPlayMode? = nil) -> Int? {
        let mode = playMode ?? selectedPlayMode
        switch mode {
        case .classic30, .classic60:
            return nil
        case .burst10:
            return 6
        case .burst15:
            return 10
        case .levelChallenge:
            return 20 + trainingLevel * 5
        case .dailyChallenge:
            return dailyChallengeTarget()
        }
    }

    func progressLine(language: AppLanguage) -> String {
        if let target = targetHits() {
            return "\(L10n.text("target", language)): \(target) | XP \(trainingXP) | Lv.\(trainingLevel)"
        }
        return "XP \(trainingXP) | Lv.\(trainingLevel) | \(L10n.text("streak", language)) \(currentStreak)"
    }

    func start() async {
        guard !isRunning else {
            return
        }
        guard let bluetoothManager, bluetoothManager.isConnected else {
            phase = .error
            statusKey = "connect_first"
            return
        }

        let sessionPlayMode = selectedPlayMode
        let sessionMode = sessionPlayMode.mode
        let target = targetHits(for: sessionPlayMode)
        let levelBefore = trainingLevel
        hitTimes.removeAll()
        bluetoothManager.resetDisplayHitCount()
        realTimeHits = 0
        remainingMillis = sessionMode.durationSeconds * 1_000
        latestReport = nil
        countdownText = "3"
        phase = .countdown
        statusKey = "countdown"

        timerTask?.cancel()
        timerTask = Task { [weak self, weak bluetoothManager] in
            guard let self, let bluetoothManager else { return }
            for value in stride(from: 3, through: 1, by: -1) {
                if Task.isCancelled { return }
                self.countdownText = "\(value)"
                self.statusKey = "countdown"
                self.speechCueService?.speakCue("\(value)")
                try? await Task.sleep(nanoseconds: 850_000_000)
            }

            self.countdownText = "GO"
            self.statusKey = "running"
            self.speechCueService?.speakCue("GO")
            try? await Task.sleep(nanoseconds: 450_000_000)

            self.isRunning = true
            self.phase = .running
            bluetoothManager.setGyroscopeEnabled(true)

            let start = Date()
            var lastCount = 0
            let durationMs = sessionMode.durationSeconds * 1_000
            while !Task.isCancelled {
                let elapsedMs = Int(Date().timeIntervalSince(start) * 1_000)
                if elapsedMs >= durationMs {
                    self.finish(
                        mode: sessionMode,
                        playMode: sessionPlayMode,
                        targetHits: target,
                        levelBefore: levelBefore,
                        elapsedSeconds: Double(sessionMode.durationSeconds)
                    )
                    return
                }

                let currentCount = max(0, bluetoothManager.displayHitCount)
                if currentCount > lastCount {
                    let delta = currentCount - lastCount
                    for _ in 0..<delta {
                        self.hitTimes.append(Date().timeIntervalSince(start))
                    }
                    self.soundEffectManager?.playHit(forceN: bluetoothManager.peakForce)
                }
                lastCount = currentCount
                self.realTimeHits = currentCount
                self.remainingMillis = max(0, durationMs - elapsedMs)
                self.countdownText = "\(max(0, Int(ceil(Double(self.remainingMillis) / 1_000.0))))"
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func stop() async {
        guard isRunning || phase == .countdown || phase == .running else {
            return
        }
        timerTask?.cancel()
        timerTask = nil
        bluetoothManager?.setGyroscopeEnabled(false)
        isRunning = false
        phase = .finished
        statusKey = "stopped"
        countdownText = "DONE"
    }

    private func finish(
        mode: TrainingMode,
        playMode: TrainingPlayMode,
        targetHits: Int?,
        levelBefore: Int,
        elapsedSeconds: Double
    ) {
        timerTask?.cancel()
        timerTask = nil
        bluetoothManager?.setGyroscopeEnabled(false)
        isRunning = false
        phase = .finished
        statusKey = "complete"
        countdownText = "DONE"
        remainingMillis = 0

        let totalHits = realTimeHits
        let average = elapsedSeconds > 0 ? Double(totalHits) / elapsedSeconds : 0
        let burst = bestBurst()
        let goalMet = targetHits.map { totalHits >= $0 } ?? true
        let xpGain = max(8, totalHits / 2 + (goalMet ? 10 : 0))
        trainingXP += xpGain
        if playMode == .levelChallenge && goalMet {
            trainingLevel += 1
        }
        let streak = updateTrainingStreak()
        let report = TrainingReport(
            mode: mode,
            playMode: playMode,
            totalHits: totalHits,
            averageFrequency: average,
            bestBurstCount: burst.count,
            bestBurstStartSec: burst.start,
            endedAtEpochMs: Int(Date().timeIntervalSince1970 * 1000),
            targetHits: targetHits,
            goalMet: goalMet,
            levelBefore: levelBefore,
            levelAfter: trainingLevel,
            streak: streak,
            xpGain: xpGain,
            coachMessage: coachMessage(totalHits: totalHits, targetHits: targetHits, goalMet: goalMet, playMode: playMode)
        )
        latestReport = report
        reportHistory.insert(report, at: 0)
        reportHistory = Array(reportHistory.prefix(20))
        saveLocalState()
        speechCueService?.speakCelebration(report.goalMet ? "Training complete" : "Good work")
    }

    private func bestBurst() -> (count: Int, start: Double) {
        guard !hitTimes.isEmpty else {
            return (0, 0)
        }
        var bestCount = 0
        var bestStart = hitTimes[0]
        var left = 0
        for right in hitTimes.indices {
            while hitTimes[right] - hitTimes[left] > 3.0 {
                left += 1
            }
            let count = right - left + 1
            if count > bestCount {
                bestCount = count
                bestStart = hitTimes[left]
            }
        }
        return (bestCount, bestStart)
    }

    private func coachMessage(totalHits: Int, targetHits: Int?, goalMet: Bool, playMode: TrainingPlayMode) -> String {
        if let targetHits {
            if goalMet {
                return "Target cleared: \(totalHits)/\(targetHits). Keep the rhythm and push the next tier."
            }
            return "You reached \(totalHits)/\(targetHits). Stay relaxed and chase the next clear."
        }
        switch playMode {
        case .classic60:
            return "Strong endurance session. Hold the pace and keep your breathing steady."
        case .classic30:
            return "Clean 30-second session. Try to raise the first 10 seconds next time."
        default:
            return "Session complete. Build the next burst from a calm stance."
        }
    }

    private func dailyChallengeTarget() -> Int {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: Date())
        return 24 + (day % 7) * 3
    }

    private func updateTrainingStreak() -> Int {
        let today = Self.dayKey(Date())
        let defaults = UserDefaults.standard
        let lastDay = defaults.string(forKey: Keys.lastTrainingDay)
        let yesterday = Self.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        if lastDay == today {
            currentStreak = max(1, currentStreak)
        } else if lastDay == yesterday {
            currentStreak += 1
        } else {
            currentStreak = 1
        }
        defaults.set(today, forKey: Keys.lastTrainingDay)
        defaults.set(currentStreak, forKey: Keys.streak)
        return currentStreak
    }

    private func loadLocalState() {
        let defaults = UserDefaults.standard
        trainingLevel = max(1, defaults.integer(forKey: Keys.level))
        trainingXP = defaults.integer(forKey: Keys.xp)
        currentStreak = defaults.integer(forKey: Keys.streak)
        if let data = defaults.data(forKey: Keys.reports),
           let reports = try? JSONDecoder().decode([TrainingReport].self, from: data) {
            reportHistory = reports
            latestReport = reports.first
        }
    }

    private func saveLocalState() {
        let defaults = UserDefaults.standard
        defaults.set(trainingLevel, forKey: Keys.level)
        defaults.set(trainingXP, forKey: Keys.xp)
        defaults.set(currentStreak, forKey: Keys.streak)
        if let data = try? JSONEncoder().encode(reportHistory) {
            defaults.set(data, forKey: Keys.reports)
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
