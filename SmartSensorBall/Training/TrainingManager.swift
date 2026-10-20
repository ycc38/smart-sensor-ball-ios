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
}

enum TrainingPhase: String, Codable {
    case idle
    case countdown
    case running
    case finished
    case error
}

/// Hit trend over the most recent local sessions, kept with each report so its
/// coach message can be rebuilt in whichever language is selected later.
struct TrainingTrend: Codable, Equatable {
    let sampleCount: Int
    let delta: Double
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
    var coachMessage: String
    let trend: TrainingTrend?

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
        coachMessage: String,
        trend: TrainingTrend? = nil
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
        self.trend = trend
    }
}

@MainActor
final class TrainingManager: ObservableObject {
    static let levelTargets = [12, 18, 25, 32, 40, 50, 60, 75, 90]
    static let burst10TargetHits = 25
    static let burst15TargetHits = 38
    private static let maxTrainingXP = 999_999
    private static let maxStoredReports = 60
    private static let trendSessionCount = 12

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
    @Published private(set) var bestStreak = 0
    @Published private var statusKey = "ready"
    @Published private var dailyTaskDate = ""
    @Published private var dailyTaskTrained = false
    @Published private var dailyTaskTargetDone = false
    @Published private var dailyTaskShared = false

    private weak var bluetoothManager: SensorBallBluetoothManager?
    private weak var soundEffectManager: SoundEffectManager?
    private weak var speechCueService: SpeechCueService?
    private weak var cloudStore: CloudStore?
    private var timerTask: Task<Void, Never>?
    private var hitTimes: [Double] = []

    private enum Keys {
        static let reports = "training_reports_v2"
        static let level = "training_level"
        static let xp = "training_xp"
        static let streak = "training_streak"
        static let bestStreak = "training_best_streak"
        static let lastTrainingDay = "training_last_day"
        static let dailyTaskDate = "daily_task_date"
        static let dailyTaskTrained = "daily_task_trained"
        static let dailyTaskTargetDone = "daily_task_target_done"
        static let dailyTaskShared = "daily_task_shared"
    }

    init() {
        loadLocalState()
    }

    func attach(
        bluetoothManager: SensorBallBluetoothManager,
        soundEffectManager: SoundEffectManager? = nil,
        speechCueService: SpeechCueService? = nil,
        cloudStore: CloudStore? = nil
    ) {
        self.bluetoothManager = bluetoothManager
        self.soundEffectManager = soundEffectManager
        self.speechCueService = speechCueService
        self.cloudStore = cloudStore
    }

    func statusText(language: AppLanguage) -> String {
        L10n.text(statusKey, language)
    }

    func countdownLabel(language: AppLanguage) -> String {
        switch countdownText {
        case "GO": return L10n.text("go_label", language)
        case "DONE": return L10n.text("done_short", language)
        default: return countdownText
        }
    }

    var isBusy: Bool {
        phase == .countdown || phase == .running
    }

    func modeTitle(language: AppLanguage) -> String {
        goalTitle(for: selectedPlayMode, language: language)
    }

    func modeBody(language: AppLanguage) -> String {
        goalBody(for: selectedPlayMode, language: language)
    }

    func targetHits(for playMode: TrainingPlayMode? = nil) -> Int? {
        let mode = playMode ?? selectedPlayMode
        switch mode {
        case .classic30, .classic60:
            return nil
        case .burst10:
            return Self.burst10TargetHits
        case .burst15:
            return Self.burst15TargetHits
        case .levelChallenge:
            return levelTargetHits
        case .dailyChallenge:
            return dailyChallengeTarget()
        }
    }

    var levelTargetHits: Int {
        Self.levelTargets[clampedLevel - 1]
    }

    func progressLine(language: AppLanguage) -> String {
        let targetText = targetHits().map { target in
            language.localized(
                "本轮目标 \(target) 击",
                "Target \(target) hits",
                fr: "Objectif \(target) coups",
                th: "เป้าหมาย \(target) ครั้ง"
            )
        } ?? language.localized("自由训练", "Free training", fr: "Entraînement libre", th: "ฝึกอิสระ")
        return "\(targetText) · \(dailyTaskSummary(language: language)) · \(trendText(currentTrend(), language: language))"
    }

    func dailyTaskSummary(language: AppLanguage) -> String {
        let done = dailyTasksDoneCount
        return language.localized(
            "今日任务 \(done)/3 · 连续 \(currentStreak) 天 · XP \(trainingXP)",
            "Daily tasks \(done)/3 · Streak \(currentStreak) · XP \(trainingXP)",
            fr: "Tâches du jour \(done)/3 · Série \(currentStreak) · XP \(trainingXP)",
            th: "ภารกิจวันนี้ \(done)/3 · ต่อเนื่อง \(currentStreak) วัน · XP \(trainingXP)"
        )
    }

    /// Trained, target met and shared, counted only for today.
    var dailyTasksDoneCount: Int {
        guard dailyTaskDate == Self.dayKey(Date()) else {
            return 0
        }
        return [dailyTaskTrained, dailyTaskTargetDone, dailyTaskShared].filter { $0 }.count
    }

    func markTrainingShared() {
        resetDailyTasksIfNeeded(today: Self.dayKey(Date()))
        dailyTaskShared = true
        saveDailyTasks()
    }

    func coachMessage(for report: TrainingReport, language: AppLanguage) -> String {
        guard let trend = report.trend else {
            return report.coachMessage
        }
        let challenge = challengeLine(for: report, language: language)
        let pace = paceLine(for: report.averageFrequency, language: language)
        let trendLine = trendText(trend, language: language)
        return language.localized(
            "\(challenge) \(pace) 连续训练 \(report.streak) 天，XP +\(report.xpGain)。\(trendLine)",
            "\(challenge) \(pace) Streak \(report.streak) day(s), XP +\(report.xpGain). \(trendLine)",
            fr: "\(challenge) \(pace) Série de \(report.streak) jour(s), XP +\(report.xpGain). \(trendLine)",
            th: "\(challenge) \(pace) ฝึกต่อเนื่อง \(report.streak) วัน XP +\(report.xpGain) \(trendLine)"
        )
    }

    func start(isActivated: Bool = true) async {
        guard !isBusy else {
            return
        }
        guard isActivated else {
            phase = .error
            statusKey = "activation_required"
            return
        }
        guard let bluetoothManager = bluetoothManager, bluetoothManager.isConnected else {
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
        bluetoothManager.isTrainingActive = true
        isRunning = false
        realTimeHits = 0
        remainingMillis = sessionMode.durationSeconds * 1_000
        latestReport = nil
        countdownText = "3"
        phase = .countdown
        statusKey = "countdown"

        timerTask?.cancel()
        timerTask = Task { [weak self, weak bluetoothManager] in
            guard let self = self, let bluetoothManager = bluetoothManager else { return }
            for value in stride(from: 3, through: 1, by: -1) {
                if Task.isCancelled { return }
                self.countdownText = "\(value)"
                self.statusKey = "countdown"
                self.speechCueService?.speakCue("\(value)")
                try? await Task.sleep(nanoseconds: 850_000_000)
            }

            self.countdownText = "GO"
            self.statusKey = "running"
            self.speechCueService?.speakCue(L10n.text("go_label", AppLanguage.current))
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
                    self.realTimeHits = max(0, bluetoothManager.displayHitCount)
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
        bluetoothManager?.isTrainingActive = false
        isRunning = false
        phase = .finished
        statusKey = "stopped"
        countdownText = "--"
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
        bluetoothManager?.isTrainingActive = false
        isRunning = false
        phase = .finished
        statusKey = "complete"
        countdownText = "DONE"
        remainingMillis = 0

        let totalHits = realTimeHits
        let average = elapsedSeconds > 0 ? Double(totalHits) / elapsedSeconds : 0
        let burst = bestBurst()
        resetDailyTasksIfNeeded(today: Self.dayKey(Date()))
        let streak = updateTrainingStreak()
        dailyTaskTrained = true

        let goalMet = targetHits.map { totalHits >= $0 } ?? false
        var xpGain = 10
        if goalMet {
            xpGain += 10
            dailyTaskTargetDone = true
        }
        switch playMode {
        case .levelChallenge:
            if goalMet {
                trainingLevel = min(levelBefore + 1, Self.levelTargets.count)
                xpGain += 25
            }
        case .dailyChallenge:
            if goalMet {
                xpGain += 20
            }
        case .burst10, .burst15:
            if goalMet {
                xpGain += 15
            }
        case .classic30, .classic60:
            break
        }
        trainingXP = min(trainingXP + xpGain, Self.maxTrainingXP)

        let recentHits = reportHistory.prefix(Self.trendSessionCount - 1).reversed().map(\.totalHits)
        var report = TrainingReport(
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
            coachMessage: "",
            trend: Self.trend(forHitsOldestFirst: recentHits + [totalHits])
        )
        report.coachMessage = coachMessage(for: report, language: AppLanguage.current)
        latestReport = report
        reportHistory.insert(report, at: 0)
        reportHistory = Array(reportHistory.prefix(Self.maxStoredReports))
        saveLocalState()
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

    private var clampedLevel: Int {
        min(max(trainingLevel, 1), Self.levelTargets.count)
    }

    private func goalTitle(for playMode: TrainingPlayMode, language: AppLanguage) -> String {
        switch playMode {
        case .classic30:
            return language.localized("经典训练", "Classic Training", fr: "Entraînement classique", th: "ฝึกคลาสสิก")
        case .classic60:
            return language.localized("耐力训练", "Endurance Training", fr: "Entraînement endurance", th: "ฝึกความอึด")
        case .burst10:
            return language.localized("10 秒爆发", "10-second Burst", fr: "Explosif 10 s", th: "ระเบิด 10 วิ")
        case .burst15:
            return language.localized("15 秒爆发", "15-second Burst", fr: "Explosif 15 s", th: "ระเบิด 15 วิ")
        case .levelChallenge:
            let level = clampedLevel
            let target = levelTargetHits
            return language.localized(
                "第 \(level) 关 · 目标 \(target) 击",
                "Level \(level) · \(target) hits",
                fr: "Niveau \(level) · \(target) coups",
                th: "ด่าน \(level) · เป้าหมาย \(target) ครั้ง"
            )
        case .dailyChallenge:
            let target = dailyChallengeTarget()
            return language.localized(
                "今日挑战 · 目标 \(target) 击",
                "Daily Challenge · \(target) hits",
                fr: "Défi du jour · \(target) coups",
                th: "ภารกิจวันนี้ · \(target) ครั้ง"
            )
        }
    }

    private func goalBody(for playMode: TrainingPlayMode, language: AppLanguage) -> String {
        switch playMode {
        case .classic30:
            return language.localized(
                "30 秒稳定计数，适合每天热身、测试节奏和刷新历史最佳。",
                "A steady 30-second session for warm-up, rhythm checks, and best-score attempts.",
                fr: "Session stable de 30 s pour s'échauffer, tester le rythme et battre son record.",
                th: "ฝึก 30 วินาทีแบบมั่นคง เหมาะสำหรับวอร์มอัพ เช็กจังหวะ และทำสถิติใหม่"
            )
        case .classic60:
            return language.localized(
                "60 秒持续输出，适合练稳定性、耐力和连续节奏。",
                "A 60-second session for consistency, stamina, and sustained rhythm.",
                fr: "Session de 60 s pour travailler la régularité, l'endurance et le rythme continu.",
                th: "ฝึก 60 วินาที เพื่อความสม่ำเสมอ ความอึด และจังหวะต่อเนื่อง"
            )
        case .burst10:
            let target = Self.burst10TargetHits
            return language.localized(
                "短时间冲刺，目标 \(target) 击；更适合练启动速度和瞬间爆发。",
                "Short sprint mode. Target \(target) hits for launch speed and explosive rhythm.",
                fr: "Sprint court. Objectif \(target) coups pour travailler le départ et l'explosivité.",
                th: "โหมดสปรินต์สั้น เป้าหมาย \(target) ครั้ง เพื่อฝึกความเร็วเริ่มต้นและแรงระเบิด"
            )
        case .burst15:
            let target = Self.burst15TargetHits
            return language.localized(
                "稍长冲刺，目标 \(target) 击；兼顾爆发和控制。",
                "A longer sprint. Target \(target) hits while keeping control.",
                fr: "Sprint plus long. Objectif \(target) coups en gardant le contrôle.",
                th: "สปรินต์นานขึ้น เป้าหมาย \(target) ครั้ง พร้อมคุมจังหวะให้ดี"
            )
        case .levelChallenge:
            return language.localized(
                "完成本关即可解锁下一关。闯关模式会把训练变成可持续推进的成长路线。",
                "Clear the target to unlock the next level and turn training into steady progression.",
                fr: "Atteignez l'objectif pour débloquer le niveau suivant et progresser régulièrement.",
                th: "ทำให้ถึงเป้าหมายเพื่อปลดล็อกด่านถัดไป และเปลี่ยนการฝึกให้เป็นเส้นทางเติบโต"
            )
        case .dailyChallenge:
            return language.localized(
                "每天一个轻量目标，完成后记录今日任务奖励，适合培养连续训练习惯。",
                "A lightweight daily target that rewards consistency and helps build a training habit.",
                fr: "Un objectif léger chaque jour pour récompenser la régularité et créer l'habitude.",
                th: "เป้าหมายเบา ๆ รายวัน ช่วยให้ฝึกต่อเนื่องและสร้างนิสัยการฝึก"
            )
        }
    }

    private func challengeLine(for report: TrainingReport, language: AppLanguage) -> String {
        switch report.playMode {
        case .levelChallenge:
            if report.goalMet {
                if report.levelAfter > report.levelBefore {
                    return language.localized(
                        "闯关成功，已解锁第 \(report.levelAfter) 关。",
                        "Level cleared. Level \(report.levelAfter) unlocked.",
                        fr: "Niveau réussi. Niveau \(report.levelAfter) débloqué.",
                        th: "ผ่านด่านแล้ว ปลดล็อกด่าน \(report.levelAfter) แล้ว"
                    )
                }
                return language.localized(
                    "已完成最高关卡，继续刷新极限。",
                    "Top level cleared. Keep pushing your limit.",
                    fr: "Niveau maximal réussi. Continuez à repousser vos limites.",
                    th: "ผ่านด่านสูงสุดแล้ว ท้าทายขีดจำกัดของคุณต่อไป"
                )
            }
            let remaining = max(0, (report.targetHits ?? 0) - report.totalHits)
            return language.localized(
                "本关还差 \(remaining) 击，下次优先稳住节奏。",
                "\(remaining) hits to clear this level. Keep the rhythm steady next time.",
                fr: "Encore \(remaining) coups pour réussir ce niveau. Gardez un rythme régulier la prochaine fois.",
                th: "อีก \(remaining) ครั้งจะผ่านด่านนี้ ครั้งหน้ารักษาจังหวะให้คงที่"
            )
        case .dailyChallenge:
            if report.goalMet {
                return language.localized(
                    "今日挑战完成，已记录任务奖励。",
                    "Daily challenge completed and rewarded.",
                    fr: "Défi du jour réussi, récompense enregistrée.",
                    th: "ภารกิจวันนี้สำเร็จ บันทึกรางวัลแล้ว"
                )
            }
            let remaining = max(0, (report.targetHits ?? 0) - report.totalHits)
            return language.localized(
                "今日挑战还差 \(remaining) 击，可以再来一轮。",
                "\(remaining) hits short of today's challenge. One more run can do it.",
                fr: "Il manque \(remaining) coups pour le défi du jour. Une séance de plus peut suffire.",
                th: "ยังขาดอีก \(remaining) ครั้งสำหรับภารกิจวันนี้ ลองอีกสักรอบ"
            )
        case .burst10, .burst15:
            if report.goalMet {
                return language.localized(
                    "爆发目标达成，启动速度很漂亮。",
                    "Burst target reached. Your launch speed looks sharp.",
                    fr: "Objectif explosif atteint. Votre départ est très vif.",
                    th: "ทำเป้าระเบิดได้แล้ว ออกตัวได้คมมาก"
                )
            }
            return language.localized(
                "爆发训练已完成，下一轮可以尝试把前 3 秒打得更主动。",
                "Burst session complete. Try attacking the first 3 seconds harder next round.",
                fr: "Séance explosive terminée. Attaquez plus fort les 3 premières secondes au prochain tour.",
                th: "ฝึกระเบิดเสร็จแล้ว รอบหน้าลองเร่งช่วง 3 วินาทีแรกให้หนักขึ้น"
            )
        case .classic30, .classic60:
            return language.localized(
                "训练已记录，今天的节奏又往前推进了一步。",
                "Session recorded. Today's rhythm moved one step forward.",
                fr: "Séance enregistrée. Votre rythme a encore progressé aujourd'hui.",
                th: "บันทึกการฝึกแล้ว วันนี้จังหวะของคุณก้าวหน้าขึ้นอีกขั้น"
            )
        }
    }

    private func paceLine(for averageFrequency: Double, language: AppLanguage) -> String {
        if averageFrequency >= 3.0 {
            return language.localized(
                "高爆发节奏，注意保持动作质量。",
                "High burst rhythm. Keep the movement quality clean.",
                fr: "Rythme très explosif. Gardez des mouvements propres.",
                th: "จังหวะระเบิดสูง รักษาคุณภาพท่าทางให้ดี"
            )
        }
        if averageFrequency >= 2.0 {
            return language.localized(
                "节奏很稳，适合继续挑战更高目标。",
                "Solid rhythm. You are ready to chase a higher target.",
                fr: "Rythme solide. Vous êtes prêt à viser plus haut.",
                th: "จังหวะมั่นคง พร้อมท้าทายเป้าหมายที่สูงขึ้น"
            )
        }
        return language.localized(
            "先稳住命中质量，再逐步加速。",
            "Lock in clean hits first, then build speed gradually.",
            fr: "Assurez d'abord des frappes propres, puis accélérez progressivement.",
            th: "เน้นหมัดที่แม่นยำก่อน แล้วค่อย ๆ เพิ่มความเร็ว"
        )
    }

    private func trendText(_ trend: TrainingTrend, language: AppLanguage) -> String {
        guard trend.sampleCount >= 2 else {
            return language.localized(
                "7天趋势：等待更多数据",
                "7-day trend: collecting data",
                fr: "Tendance 7 jours : collecte des données",
                th: "แนวโน้ม 7 วัน: กำลังรวบรวมข้อมูล"
            )
        }
        let value = String(format: "%.1f", trend.delta)
        if trend.delta >= 2.0 {
            return language.localized(
                "7天趋势：提升 +\(value)",
                "7-day trend: +\(value)",
                fr: "Tendance 7 jours : +\(value)",
                th: "แนวโน้ม 7 วัน: ดีขึ้น +\(value)"
            )
        }
        if trend.delta <= -2.0 {
            return language.localized(
                "7天趋势：回落 \(value)",
                "7-day trend: \(value)",
                fr: "Tendance 7 jours : \(value)",
                th: "แนวโน้ม 7 วัน: ลดลง \(value)"
            )
        }
        return language.localized("7天趋势：稳定", "7-day trend: stable", fr: "Tendance 7 jours : stable", th: "แนวโน้ม 7 วัน: คงที่")
    }

    private func currentTrend() -> TrainingTrend {
        Self.trend(forHitsOldestFirst: reportHistory.prefix(Self.trendSessionCount).reversed().map(\.totalHits))
    }

    /// Compares the average hits of the newer half of the sessions with the older half.
    private static func trend(forHitsOldestFirst hits: [Int]) -> TrainingTrend {
        guard hits.count >= 2 else {
            return TrainingTrend(sampleCount: hits.count, delta: 0)
        }
        let splitIndex = max(1, hits.count / 2)
        let early = hits.prefix(splitIndex)
        let recent = hits.dropFirst(splitIndex)
        let earlyAverage = Double(early.reduce(0, +)) / Double(early.count)
        let recentAverage = Double(recent.reduce(0, +)) / Double(recent.count)
        return TrainingTrend(sampleCount: hits.count, delta: recentAverage - earlyAverage)
    }

    func dailyChallengeTarget() -> Int {
        let localBest30 = reportHistory.filter { $0.mode.durationSeconds == 30 }.map(\.totalHits).max() ?? 0
        let best30 = max(cloudStore?.statistics?.best30Hits ?? 0, localBest30)
        guard best30 > 0 else {
            return 20
        }
        return min(max(18, Int(Float(best30) * 0.82)), 120)
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
        bestStreak = max(bestStreak, currentStreak)
        defaults.set(today, forKey: Keys.lastTrainingDay)
        defaults.set(currentStreak, forKey: Keys.streak)
        defaults.set(bestStreak, forKey: Keys.bestStreak)
        return currentStreak
    }

    private func resetDailyTasksIfNeeded(today: String) {
        guard dailyTaskDate != today else {
            return
        }
        dailyTaskDate = today
        dailyTaskTrained = false
        dailyTaskTargetDone = false
        dailyTaskShared = false
    }

    private func saveDailyTasks() {
        let defaults = UserDefaults.standard
        defaults.set(dailyTaskDate, forKey: Keys.dailyTaskDate)
        defaults.set(dailyTaskTrained, forKey: Keys.dailyTaskTrained)
        defaults.set(dailyTaskTargetDone, forKey: Keys.dailyTaskTargetDone)
        defaults.set(dailyTaskShared, forKey: Keys.dailyTaskShared)
    }

    private func loadLocalState() {
        let defaults = UserDefaults.standard
        let storedLevel = defaults.integer(forKey: Keys.level)
        trainingLevel = min(max(storedLevel, 1), Self.levelTargets.count)
        if storedLevel != trainingLevel {
            defaults.set(trainingLevel, forKey: Keys.level)
        }
        trainingXP = defaults.integer(forKey: Keys.xp)
        currentStreak = defaults.integer(forKey: Keys.streak)
        if let data = defaults.data(forKey: Keys.reports),
           let reports = try? JSONDecoder().decode([TrainingReport].self, from: data) {
            reportHistory = reports
            latestReport = reports.first
        }
        bestStreak = max(defaults.integer(forKey: Keys.bestStreak), currentStreak, reportHistory.map(\.streak).max() ?? 0)
        dailyTaskDate = defaults.string(forKey: Keys.dailyTaskDate) ?? ""
        dailyTaskTrained = defaults.bool(forKey: Keys.dailyTaskTrained)
        dailyTaskTargetDone = defaults.bool(forKey: Keys.dailyTaskTargetDone)
        dailyTaskShared = defaults.bool(forKey: Keys.dailyTaskShared)
    }

    private func saveLocalState() {
        let defaults = UserDefaults.standard
        defaults.set(trainingLevel, forKey: Keys.level)
        defaults.set(trainingXP, forKey: Keys.xp)
        defaults.set(currentStreak, forKey: Keys.streak)
        defaults.set(bestStreak, forKey: Keys.bestStreak)
        saveDailyTasks()
        if let data = try? JSONEncoder().encode(reportHistory) {
            defaults.set(data, forKey: Keys.reports)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
