import AVFoundation
import AudioToolbox
import Foundation
import SwiftUI
import UIKit

struct ActivationState: Codable, Equatable {
    let serial: String
    let activationToken: String
    let installId: String
    let deviceHash: String
    let activatedAtEpochMs: Int
    let lastCheckAtEpochMs: Int
}

struct ActivationApiResult: Codable {
    let status: String?
    let success: Bool?
    let message: String?
    let reason: String?
    let serial: String?
    let activationToken: String?
    let licenseState: String?

    var isOK: Bool {
        status == "ok" || success == true
    }
}

struct CloudUserProfile: Codable, Equatable {
    let userId: Int?
    let serial: String?
    let serialMasked: String?
    let nickname: String?
    let languageCode: String?
    let countryCode: String?
    let avatarColor: String?
    let currentTier: Int?
    let highestTier: Int?
    let bestScoreCached: Int?
    let best30HitsCached: Int?
    let best60HitsCached: Int?
    let bestBurstCached: Int?
    let longestStreakCached: Int?
    let activeDaysCached: Int?
    let createdAt: String?
    let lastSeenAt: String?
}

struct CloudUserStatistics: Codable, Equatable {
    let totalSessions: Int?
    let totalHits: Int?
    let best30Hits: Int?
    let best60Hits: Int?
    let average30Frequency: Double?
    let average60Frequency: Double?
    let personalBestHits: Int?
    let bestBurstRecord: Int?
    let bestAverageFrequency: Double?
    let activeDays: Int?
    let currentStreak: Int?
    let longestStreak: Int?
}

struct CloudTierProgress: Codable, Equatable {
    let level: Int?
    let key: String?
    let bestHits: Int?
    let nextLevel: Int?
    let nextKey: String?
    let nextHits: Int?
    let progressHits: Int?
    let progressTargetHits: Int?
}

struct CloudAchievementItem: Codable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let metric: String?
    let goal: Int
    let progress: Int
    let unlocked: Bool
    let unlockedAt: String?
    let sortOrder: Int?
}

struct CloudTrainingHistoryItem: Codable, Equatable, Identifiable {
    var id: Int { sessionId }
    let sessionId: Int
    let modeSeconds: Int
    let totalHits: Int
    let averageFrequency: Double
    let bestBurstCount: Int
    let bestBurstStartSec: Double
    let startedAt: String?
    let endedAt: String?
}

struct CloudLeaderboardEntry: Codable, Equatable, Identifiable {
    var id: String { "\(rank)-\(userId ?? 0)-\(nickname)" }
    let rank: Int
    let userId: Int?
    let nickname: String
    let serialMasked: String?
    let countryCode: String?
    let tierLevel: Int?
    let tierKey: String?
    let bestHits: Int
    let averageFrequency: Double
    let bestBurstCount: Int
    let bestBurstStartSec: Double
    let endedAt: String?
    let isMe: Bool?
}

struct CloudBootstrapResult: Codable {
    let status: String?
    let success: Bool?
    let message: String?
    let reason: String?
    let profile: CloudUserProfile?
    let statistics: CloudUserStatistics?
    let history: [CloudTrainingHistoryItem]?
    let achievements: [CloudAchievementItem]?
    let tier: CloudTierProgress?
    let promoted: Bool?

    var isOK: Bool { status == "ok" || success == true }
}

struct CloudSessionUploadResult: Codable {
    let status: String?
    let success: Bool?
    let message: String?
    let reason: String?
    let sessionId: Int?
    let profile: CloudUserProfile?
    let statistics: CloudUserStatistics?
    let history: [CloudTrainingHistoryItem]?
    let achievements: [CloudAchievementItem]?
    let tier: CloudTierProgress?
    let promoted: Bool?

    var isOK: Bool { status == "ok" || success == true }
}

struct CloudLeaderboardResult: Codable {
    let status: String?
    let success: Bool?
    let message: String?
    let reason: String?
    let boardKey: String?
    let modeSeconds: Int?
    let window: String?
    let top: [CloudLeaderboardEntry]?
    let me: CloudLeaderboardEntry?

    var isOK: Bool { status == "ok" || success == true }
}

struct CloudSoundEffect: Codable, Equatable, Identifiable {
    let id: String
    let nameZh: String
    let nameEn: String
    let descriptionZh: String
    let descriptionEn: String
    let style: String
    let bpm: Int
    let durationMs: Int
    let url: String

    private enum CodingKeys: String, CodingKey {
        case id
        case nameZh = "name_zh"
        case nameEn = "name_en"
        case descriptionZh = "description_zh"
        case descriptionEn = "description_en"
        case style
        case bpm
        case durationMs = "duration_ms"
        case url
    }

    func name(language: AppLanguage) -> String {
        language == .chinese ? nameZh : nameEn
    }

    func detail(language: AppLanguage) -> String {
        language == .chinese ? descriptionZh : descriptionEn
    }

    static let bundled: [CloudSoundEffect] = [
        CloudSoundEffect(id: "sensorball_punch_arena_thunder", nameZh: "赛场雷击", nameEn: "Arena Thunder", descriptionZh: "厚重冲击音效，适合标准训练。", descriptionEn: "Heavy impact sound for standard training.", style: "heavy", bpm: 100, durationMs: 460, url: "asset://SFX/01_sensorball_punch_arena_thunder.wav"),
        CloudSoundEffect(id: "sensorball_punch_street_spark", nameZh: "街头火花", nameEn: "Street Spark", descriptionZh: "清脆明亮音效，适合快速击打。", descriptionEn: "Bright punch sound for fast hits.", style: "street", bpm: 110, durationMs: 460, url: "asset://SFX/02_sensorball_punch_street_spark.wav"),
        CloudSoundEffect(id: "sensorball_punch_iron_hook", nameZh: "铁拳冲击", nameEn: "Iron Hook", descriptionZh: "金属质感音效，适合力量训练。", descriptionEn: "Metallic punch sound for power work.", style: "metal", bpm: 95, durationMs: 460, url: "asset://SFX/03_sensorball_punch_iron_hook.wav"),
        CloudSoundEffect(id: "sensorball_punch_neon_jab", nameZh: "霓虹快拳", nameEn: "Neon Jab", descriptionZh: "轻快短促音效，适合节奏训练。", descriptionEn: "Snappy punch sound for rhythm training.", style: "fast", bpm: 120, durationMs: 460, url: "asset://SFX/04_sensorball_punch_neon_jab.wav"),
        CloudSoundEffect(id: "sensorball_punch_bass_smash", nameZh: "低频重锤", nameEn: "Bass Smash", descriptionZh: "低频厚实音效，适合重击反馈。", descriptionEn: "Deep punch sound for heavy feedback.", style: "bass", bpm: 90, durationMs: 460, url: "asset://SFX/05_sensorball_punch_bass_smash.wav")
    ]
}

struct CloudSoundEffectCatalog: Codable {
    let status: String?
    let success: Bool?
    let message: String?
    let version: Int?
    let updatedAt: String?
    let items: [CloudSoundEffect]?

    private enum CodingKeys: String, CodingKey {
        case status
        case success
        case message
        case version
        case updatedAt = "updated_at"
        case items
    }

    var isOK: Bool { status == "ok" || success == true }
}

enum LeaderboardBoard: String, CaseIterable, Identifiable {
    case best30 = "best_30_hits"
    case best60 = "best_60_hits"
    case totalHits = "total_hits"
    case longestStreak = "longest_streak"

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .best30: return L10n.text("leaderboard_best30", language)
        case .best60: return L10n.text("leaderboard_best60", language)
        case .totalHits: return L10n.text("leaderboard_total", language)
        case .longestStreak: return L10n.text("leaderboard_streak", language)
        }
    }
}

private enum AppAPIConfig {
    static let baseURL = URL(string: "https://sensorball.86086.cn/sensorball")!
}

struct SensorBallAPIClient {
    let baseURL = AppAPIConfig.baseURL
    private let session: URLSession = .shared

    func activate(serial: String, code: String, installId: String, deviceHash: String, appVersion: String) async throws -> ActivationApiResult {
        try await post(path: "/api/v1/activate", payload: [
            "serial": serial,
            "code": code,
            "install_id": installId,
            "device_hash": deviceHash,
            "app_version": appVersion
        ])
    }

    func checkActivation(state: ActivationState, appVersion: String) async throws -> ActivationApiResult {
        try await post(path: "/api/v1/check", payload: authPayload(state: state, appVersion: appVersion))
    }

    func reactivateByDevice(installId: String, deviceHash: String, appVersion: String) async throws -> ActivationApiResult {
        try await post(path: "/api/v1/reactivate-by-device", payload: [
            "install_id": installId,
            "device_hash": deviceHash,
            "app_version": appVersion
        ])
    }

    func bootstrap(state: ActivationState, language: AppLanguage, appVersion: String) async throws -> CloudBootstrapResult {
        var payload = authPayload(state: state, appVersion: appVersion)
        payload["language_code"] = language.rawValue
        return try await post(path: "/api/v1/user/bootstrap", payload: payload)
    }

    func updateProfile(state: ActivationState, nickname: String, language: AppLanguage, avatarColor: String, appVersion: String) async throws -> CloudBootstrapResult {
        var payload = authPayload(state: state, appVersion: appVersion)
        payload["nickname"] = nickname
        payload["language_code"] = language.rawValue
        payload["avatar_color"] = avatarColor
        return try await post(path: "/api/v1/user/profile/update", payload: payload)
    }

    func uploadTrainingSession(state: ActivationState, report: TrainingReport, appVersion: String) async throws -> CloudSessionUploadResult {
        var payload = authPayload(state: state, appVersion: appVersion)
        payload["mode_seconds"] = report.mode.durationSeconds
        payload["total_hits"] = report.totalHits
        payload["average_frequency"] = report.averageFrequency
        payload["best_burst_count"] = report.bestBurstCount
        payload["best_burst_start_sec"] = report.bestBurstStartSec
        payload["ended_at_epoch_ms"] = report.endedAtEpochMs
        return try await post(path: "/api/v1/training/session", payload: payload)
    }

    func fetchLeaderboard(state: ActivationState, board: LeaderboardBoard, appVersion: String, window: String = "all", limit: Int = 20) async throws -> CloudLeaderboardResult {
        var payload = authPayload(state: state, appVersion: appVersion)
        payload["board_key"] = board.rawValue
        payload["window"] = window
        payload["limit"] = limit
        return try await post(path: "/api/v1/leaderboard", payload: payload)
    }

    func fetchSoundEffects() async throws -> CloudSoundEffectCatalog {
        try await get(path: "/api/v1/sound-effects")
    }

    private func authPayload(state: ActivationState, appVersion: String) -> [String: Any] {
        [
            "serial": state.serial,
            "activation_token": state.activationToken,
            "install_id": state.installId,
            "device_hash": state.deviceHash,
            "app_version": appVersion
        ]
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let request = URLRequest(url: endpoint(path))
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(path: String, payload: [String: Any]) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(T.self, from: data)
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

@MainActor
final class CloudStore: ObservableObject {
    @Published var activationState: ActivationState?
    @Published var installId: String = ""
    @Published var deviceHash: String = ""
    @Published var statusMessage: String = ""
    @Published var isBusy = false
    @Published var profile: CloudUserProfile?
    @Published var statistics: CloudUserStatistics?
    @Published var history: [CloudTrainingHistoryItem] = []
    @Published var achievements: [CloudAchievementItem] = []
    @Published var tier: CloudTierProgress?
    @Published var leaderboard: CloudLeaderboardResult?
    @Published var selectedBoard: LeaderboardBoard = .best30
    @Published var soundEffects: [CloudSoundEffect] = CloudSoundEffect.bundled
    @Published var promoted = false

    private let client = SensorBallAPIClient()

    private enum Keys {
        static let activation = "activation_state_v1"
        static let installId = "install_id_v1"
    }

    init() {
        ensureInstallIdentity()
        loadActivationState()
    }

    var isActivated: Bool {
        activationState != nil
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version)(\(build))"
    }

    func ensureInstallIdentity() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Keys.installId), !stored.isEmpty {
            installId = stored
        } else {
            installId = UUID().uuidString
            defaults.set(installId, forKey: Keys.installId)
        }
        deviceHash = UIDevice.current.identifierForVendor?.uuidString ?? installId
    }

    func activate(serial: String, code: String, language: AppLanguage) async {
        let cleanSerial = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSerial.isEmpty, !cleanCode.isEmpty else {
            statusMessage = L10n.text("activation_input_required", language)
            return
        }
        await runBusy {
            let result = try await client.activate(serial: cleanSerial, code: cleanCode, installId: installId, deviceHash: deviceHash, appVersion: appVersion)
            if result.isOK, let token = result.activationToken {
                let now = Int(Date().timeIntervalSince1970 * 1000)
                activationState = ActivationState(
                    serial: result.serial ?? cleanSerial,
                    activationToken: token,
                    installId: installId,
                    deviceHash: deviceHash,
                    activatedAtEpochMs: now,
                    lastCheckAtEpochMs: now
                )
                saveActivationState()
                statusMessage = result.message ?? L10n.text("activation_success", language)
                await bootstrap(language: language)
            } else {
                statusMessage = result.message ?? L10n.text("activation_failed", language)
            }
        }
    }

    func restoreActivation(language: AppLanguage) async {
        await runBusy {
            let result = try await client.reactivateByDevice(installId: installId, deviceHash: deviceHash, appVersion: appVersion)
            if result.isOK, let token = result.activationToken, let serial = result.serial {
                let now = Int(Date().timeIntervalSince1970 * 1000)
                activationState = ActivationState(serial: serial, activationToken: token, installId: installId, deviceHash: deviceHash, activatedAtEpochMs: now, lastCheckAtEpochMs: now)
                saveActivationState()
                statusMessage = result.message ?? L10n.text("activation_restored", language)
                await bootstrap(language: language)
            } else {
                statusMessage = result.message ?? L10n.text("activation_restore_failed", language)
            }
        }
    }

    func bootstrap(language: AppLanguage) async {
        guard let activationState = activationState else {
            statusMessage = L10n.text("cloud_needs_activation", language)
            return
        }
        await runBusy {
            let result = try await client.bootstrap(state: activationState, language: language, appVersion: appVersion)
            apply(result)
            statusMessage = result.message ?? L10n.text(result.isOK ? "cloud_ready" : "cloud_failed", language)
        }
    }

    func updateProfile(nickname: String, language: AppLanguage, avatarColor: String) async {
        guard let activationState = activationState else {
            statusMessage = L10n.text("cloud_needs_activation", language)
            return
        }
        await runBusy {
            let result = try await client.updateProfile(state: activationState, nickname: nickname, language: language, avatarColor: avatarColor, appVersion: appVersion)
            apply(result)
            statusMessage = result.message ?? L10n.text("profile_saved", language)
        }
    }

    func upload(report: TrainingReport, language: AppLanguage) async {
        guard let activationState = activationState else {
            statusMessage = L10n.text("cloud_needs_activation", language)
            return
        }
        await runBusy {
            let result = try await client.uploadTrainingSession(state: activationState, report: report, appVersion: appVersion)
            apply(result)
            statusMessage = result.message ?? L10n.text(result.isOK ? "cloud_synced" : "cloud_failed", language)
        }
    }

    func refreshLeaderboard(language: AppLanguage) async {
        guard let activationState = activationState else {
            statusMessage = L10n.text("cloud_needs_activation", language)
            return
        }
        await runBusy {
            let result = try await client.fetchLeaderboard(state: activationState, board: selectedBoard, appVersion: appVersion)
            leaderboard = result
            statusMessage = result.message ?? L10n.text(result.isOK ? "leaderboard_ready" : "cloud_failed", language)
        }
    }

    func refreshSoundEffects(language: AppLanguage) async {
        await runBusy {
            let result = try await client.fetchSoundEffects()
            if result.isOK, let items = result.items, !items.isEmpty {
                soundEffects = items
            }
            statusMessage = result.message ?? L10n.text("sound_effects_ready", language)
        }
    }

    func fallbackAchievements() -> [CloudAchievementItem] {
        let sessions = statistics?.totalSessions ?? 0
        let totalHits = statistics?.totalHits ?? 0
        let best30 = statistics?.best30Hits ?? 0
        let best60 = statistics?.best60Hits ?? 0
        let burst = statistics?.bestBurstRecord ?? 0
        let streak = statistics?.currentStreak ?? 0

        func item(_ key: String, metric: String, goal: Int, progress: Int, order: Int) -> CloudAchievementItem {
            CloudAchievementItem(
                key: key,
                metric: metric,
                goal: goal,
                progress: min(goal, progress),
                unlocked: progress >= goal,
                unlockedAt: nil,
                sortOrder: order
            )
        }

        return [
            item("first_training", metric: "sessions", goal: 1, progress: sessions, order: 1),
            item("sessions_5", metric: "sessions", goal: 5, progress: sessions, order: 2),
            item("sessions_15", metric: "sessions", goal: 15, progress: sessions, order: 3),
            item("sessions_30", metric: "sessions", goal: 30, progress: sessions, order: 4),
            item("hits_100", metric: "total_hits", goal: 100, progress: totalHits, order: 5),
            item("hits_500", metric: "total_hits", goal: 500, progress: totalHits, order: 6),
            item("hits_1000", metric: "total_hits", goal: 1000, progress: totalHits, order: 7),
            item("hits_5000", metric: "total_hits", goal: 5000, progress: totalHits, order: 8),
            item("best_30_40", metric: "best_30", goal: 40, progress: best30, order: 9),
            item("best_30_60", metric: "best_30", goal: 60, progress: best30, order: 10),
            item("best_30_80", metric: "best_30", goal: 80, progress: best30, order: 11),
            item("best_30_100", metric: "best_30", goal: 100, progress: best30, order: 12),
            item("best_60_90", metric: "best_60", goal: 90, progress: best60, order: 13),
            item("best_60_120", metric: "best_60", goal: 120, progress: best60, order: 14),
            item("best_60_150", metric: "best_60", goal: 150, progress: best60, order: 15),
            item("best_60_180", metric: "best_60", goal: 180, progress: best60, order: 16),
            item("burst_6", metric: "burst", goal: 6, progress: burst, order: 17),
            item("burst_10", metric: "burst", goal: 10, progress: burst, order: 18),
            item("burst_12", metric: "burst", goal: 12, progress: burst, order: 19),
            item("burst_15", metric: "burst", goal: 15, progress: burst, order: 20),
            item("streak_3", metric: "streak", goal: 3, progress: streak, order: 21),
            item("streak_7", metric: "streak", goal: 7, progress: streak, order: 22),
            item("streak_14", metric: "streak", goal: 14, progress: streak, order: 23),
            item("streak_30", metric: "streak", goal: 30, progress: streak, order: 24)
        ]
    }

    private func apply(_ result: CloudBootstrapResult) {
        profile = result.profile ?? profile
        statistics = result.statistics ?? statistics
        history = result.history ?? history
        achievements = result.achievements ?? achievements
        tier = result.tier ?? tier
        promoted = result.promoted ?? false
    }

    private func apply(_ result: CloudSessionUploadResult) {
        profile = result.profile ?? profile
        statistics = result.statistics ?? statistics
        history = result.history ?? history
        achievements = result.achievements ?? achievements
        tier = result.tier ?? tier
        promoted = result.promoted ?? false
    }

    private func runBusy(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadActivationState() {
        if let data = UserDefaults.standard.data(forKey: Keys.activation),
           let state = try? JSONDecoder().decode(ActivationState.self, from: data) {
            activationState = state
        }
    }

    private func saveActivationState() {
        if let activationState = activationState,
           let data = try? JSONEncoder().encode(activationState) {
            UserDefaults.standard.set(data, forKey: Keys.activation)
        }
    }
}

@MainActor
final class SoundEffectManager: ObservableObject {
    @Published var selectedEffectId: String = SoundEffectManager.fixedEffect.id
    @Published var selectedEffectName: String = SoundEffectManager.fixedEffect.nameEn
    @Published var previewStatus: String = ""

    private static let fixedEffect = CloudSoundEffect.bundled.first { $0.id == "sensorball_punch_arena_thunder" } ?? CloudSoundEffect.bundled[0]
    private var previewPlayer: AVAudioPlayer?
    private var hitPlayers: [AVAudioPlayer] = []
    private var selectedURL: String = SoundEffectManager.fixedEffect.url

    init() {
        configureAudioSession()
        applyFixedSelection(language: .english)
    }

    func apply(_ _: CloudSoundEffect, language: AppLanguage) {
        applyFixedSelection(language: language)
        previewStatus = selectedEffectName
    }

    func preview(_ effect: CloudSoundEffect, language: AppLanguage) {
        previewPlayer?.stop()
        guard let url = mediaURL(from: effect.url) else {
            previewStatus = "\(effect.name(language: language)) selected"
            AudioServicesPlaySystemSound(1104)
            return
        }
        do {
            let player = try preparedPlayer(for: url)
            previewPlayer = player
            player.play()
            previewStatus = effect.name(language: language)
        } catch {
            previewStatus = "\(effect.name(language: language)) selected"
            AudioServicesPlaySystemSound(1104)
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    func playHit(forceN: Int) {
        applyFixedSelection(language: .english)
        let urlString = selectedURL
        if let url = mediaURL(from: urlString) {
            do {
                hitPlayers.removeAll { !$0.isPlaying }
                let player = try preparedPlayer(for: url)
                player.volume = volume(for: forceN)
                hitPlayers.append(player)
                player.play()
            } catch {
                AudioServicesPlaySystemSound(forceN > 150 ? 1152 : 1104)
            }
        } else {
            AudioServicesPlaySystemSound(forceN > 150 ? 1152 : 1104)
        }
    }

    private func applyFixedSelection(language: AppLanguage) {
        let effect = Self.fixedEffect
        selectedEffectId = effect.id
        selectedEffectName = effect.name(language: language)
        selectedURL = effect.url
        UserDefaults.standard.set(effect.id, forKey: "selected_sound_effect_id")
        UserDefaults.standard.set(selectedEffectName, forKey: "selected_sound_effect_name")
        UserDefaults.standard.set(effect.url, forKey: "selected_sound_effect_url")
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // System fallback sounds still work if the app cannot take an audio session.
        }
    }

    private func preparedPlayer(for url: URL) throws -> AVAudioPlayer {
        configureAudioSession()
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        return player
    }

    private func mediaURL(from urlString: String) -> URL? {
        guard !urlString.isEmpty else {
            return nil
        }
        if urlString.hasPrefix("asset://") {
            let assetPath = String(urlString.dropFirst("asset://".count))
            let fileName = (assetPath as NSString).lastPathComponent
            let subdirectory = (assetPath as NSString).deletingLastPathComponent
            let resourceName = (fileName as NSString).deletingPathExtension
            let fileExtension = (fileName as NSString).pathExtension
            let extensionValue: String? = fileExtension.isEmpty ? nil : fileExtension
            if let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: extensionValue,
                subdirectory: subdirectory.isEmpty ? nil : subdirectory
            ) {
                return url
            }
            if subdirectory.lowercased() == "sfx" {
                return Bundle.main.url(forResource: resourceName, withExtension: extensionValue, subdirectory: "SFX")
            }
            return Bundle.main.url(forResource: resourceName, withExtension: extensionValue)
        }
        return URL(string: urlString)
    }

    private func bundledFallbackForSelection() -> CloudSoundEffect? {
        Self.fixedEffect
    }

    private func volume(for forceN: Int) -> Float {
        if forceN >= 70 { return 1.0 }
        if forceN >= 30 { return 0.82 }
        return 0.66
    }
}

@MainActor
final class SpeechCueService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speakCue(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.05
        synthesizer.speak(utterance)
    }

    func speakCelebration(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.08
        synthesizer.speak(utterance)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum SharePosterRenderer {
    static func poster(title: String, subtitle: String, metrics: [(String, String)], footer: String) -> UIImage {
        let view = PosterView(title: title, subtitle: subtitle, metrics: metrics, footer: footer)
            .frame(width: 760, height: 1080)
        let controller = UIHostingController(rootView: view)
        controller.view.bounds = CGRect(x: 0, y: 0, width: 760, height: 1080)
        controller.view.backgroundColor = .clear
        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

private struct PosterView: View {
    let title: String
    let subtitle: String
    let metrics: [(String, String)]
    let footer: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "040C08"), Color(hex: "3B1608"), Color(hex: "111E18")], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 28) {
                Image("app_logo_aurora")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                Text(title)
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(Color(hex: "FFF6E5"))
                Text(subtitle)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(hex: "FFD060"))
                VStack(spacing: 18) {
                    ForEach(metrics, id: \.0) { metric in
                        HStack {
                            Text(metric.0)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color(hex: "DFFFF0"))
                            Spacer()
                            Text(metric.1)
                                .font(.system(size: 34, weight: .black))
                                .foregroundStyle(Color(hex: "80FFB0"))
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                Spacer()
                Text(footer)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(hex: "FFF0C9"))
            }
            .padding(54)
        }
    }
}
