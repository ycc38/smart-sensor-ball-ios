import Foundation
import SwiftUI
import UIKit

private enum HomePage: String, CaseIterable, Identifiable {
    case training
    case achievements
    case leaderboard
    case profile

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .training: return "play.fill"
        case .achievements: return "star.fill"
        case .leaderboard: return "line.3.horizontal.decrease"
        case .profile: return "person.fill"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .training: return L10n.text("tab_training", language)
        case .achievements: return L10n.text("tab_achievements", language)
        case .leaderboard: return L10n.text("tab_leaderboard", language)
        case .profile: return L10n.text("tab_profile", language)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var bluetooth: SensorBallBluetoothManager
    @EnvironmentObject private var training: TrainingManager
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var speech: SpeechCueService
    @StateObject private var avatarStore = ProfileAvatarStore()

    @State private var selectedLanguage: AppLanguage = AppLanguage.current
    @State private var showingLaunchSplash = true
    @State private var launchSplashDismissing = false
    @State private var contentSettled = false
    @State private var selectedPage: HomePage = .training
    @State private var showingSettings = false
    @State private var showingDeveloperInfo = false
    @State private var showingLegal: LegalDocument?
    @State private var showingFirstUsePrompt = false
    @State private var showingEditProfile = false
    @State private var profileName = ""
    @State private var profileColor = "#145DA0"
    @State private var draftAvatarPhoto: UIImage?
    @State private var avatarPhotoEdited = false
    @State private var showingPhotoPicker = false
    @State private var shareItems: [Any]?
    @State private var pendingCloudUploadReport: TrainingReport?
    @State private var showingLeaderboardConsent = false
    @State private var celebrationQueue: [CelebrationItem] = []
    @State private var activeCelebration: CelebrationItem?
    @AppStorage("leaderboard_upload_consent_v1") private var leaderboardUploadConsent = false

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(hex: "070806"), Color(hex: "17110C"), Color(hex: "050806")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 28)
                        .padding(.top, 50)
                        .padding(.bottom, 14)

                    ScrollView(showsIndicators: false) {
                        pageBody
                            .padding(.horizontal, 28)
                            .padding(.bottom, 14)
                    }

                    tabBar
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 18)
                }
                .opacity(contentSettled ? 1 : 0.94)
                .offset(y: contentSettled ? 0 : 10)

                if let celebration = activeCelebration {
                    CelebrationOverlay(item: celebration, hint: celebrationHint()) {
                        dismissCelebration()
                    }
                    .zIndex(1)
                }

                if showingLaunchSplash {
                    LaunchSplashView(language: selectedLanguage, dismissing: launchSplashDismissing) {
                        dismissLaunchSplash()
                    }
                    .zIndex(2)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSettings) {
                SettingsView(language: $selectedLanguage)
                    .environmentObject(bluetooth)
                    .environmentObject(cloud)
            }
            .sheet(item: $showingLegal) { document in
                LegalDocumentView(document: document, language: selectedLanguage)
            }
            .sheet(isPresented: $showingDeveloperInfo) {
                DeveloperInfoView(language: selectedLanguage)
            }
            .sheet(isPresented: $showingEditProfile) {
                editProfileSheet
            }
            .sheet(item: Binding(
                get: { shareItems.map { SharePayload(items: $0) } },
                set: { shareItems = $0?.items }
            )) { payload in
                ShareSheet(items: payload.items)
            }
            .alert(Text(L10n.text("first_use_title", selectedLanguage)), isPresented: $showingFirstUsePrompt) {
                Button(L10n.text("later", selectedLanguage), role: .cancel) {}
                Button(L10n.text("open_settings", selectedLanguage)) { showingSettings = true }
            } message: {
                Text(L10n.text("first_use_message", selectedLanguage))
            }
            .alert(Text(L10n.text("leaderboard_consent_title", selectedLanguage)), isPresented: $showingLeaderboardConsent) {
                Button(L10n.text("leaderboard_consent_decline", selectedLanguage), role: .cancel) {
                    pendingCloudUploadReport = nil
                    cloud.statusMessage = L10n.text("leaderboard_consent_declined_status", selectedLanguage)
                }
                Button(L10n.text("leaderboard_consent_accept", selectedLanguage)) {
                    leaderboardUploadConsent = true
                    if let report = pendingCloudUploadReport {
                        pendingCloudUploadReport = nil
                        uploadReport(report)
                    }
                }
            } message: {
                Text(L10n.text("leaderboard_consent_message", selectedLanguage))
            }
            .onAppear {
                selectedLanguage = AppLanguage.current
                profileName = cloud.profile?.nickname ?? ""
                profileColor = cloud.profile?.avatarColor ?? "#145DA0"
                Task {
                    await cloud.bootstrap(language: selectedLanguage)
                    await cloud.refreshLeaderboard(language: selectedLanguage)
                }
            }
            .onChange(of: selectedLanguage) { language in
                language.save()
                Task { await cloud.bootstrap(language: language) }
            }
            .onChange(of: training.latestReport) { report in
                guard let report = report else { return }
                enqueueCelebration(trainingOutcomeCelebration(for: report))
                guard CloudStore.isCloudUploadable(report) else {
                    // Burst results stay on this phone: no upload and no consent prompt.
                    cloud.statusMessage = L10n.text("burst_saved_locally", selectedLanguage)
                    return
                }
                if leaderboardUploadConsent {
                    uploadReport(report)
                } else {
                    pendingCloudUploadReport = report
                    showingLeaderboardConsent = true
                }
            }
            .onChange(of: training.phase) { _ in
                if training.isBusy {
                    // Never keep a celebration on screen while a session is counting down or running.
                    activeCelebration = nil
                } else {
                    showNextCelebrationIfIdle()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Vimai Smart Sensor Ball")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Color(hex: "FFF6E5"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(bluetooth.isConnected ? Color(hex: "44FF88") : Color(hex: "FF5C5C"))
                    BatteryBadge(telemetry: bluetooth.telemetry, language: selectedLanguage)
                }
            }
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "wrench.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: "44FF88"))
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel(L10n.text("settings", selectedLanguage))
            .disabled(training.isBusy)
            .opacity(training.isBusy ? 0.5 : 1.0)
        }
    }

    private var tabBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(HomePage.allCases) { page in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedPage = page
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: page.icon)
                            .font(.system(size: selectedPage == page ? 27 : 23, weight: .black))
                        Text(page.title(language: selectedLanguage))
                            .font(.system(size: 12, weight: .black))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, minHeight: selectedPage == page ? 82 : 64)
                    .padding(.vertical, selectedPage == page ? 10 : 4)
                    .foregroundStyle(selectedPage == page ? Color(hex: "12381E") : Color(hex: "67CC76"))
                    .background(selectedPage == page ? Color(hex: "5DD264") : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    @ViewBuilder
    private var pageBody: some View {
        switch selectedPage {
        case .training:
            trainingPage
        case .achievements:
            achievementsPage
        case .leaderboard:
            leaderboardPage
        case .profile:
            profilePage
        }
    }

    private var trainingPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            trainingConsoleCard
            trainingRankCard
            latestReportBlock
        }
    }

    private var trainingConsoleCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 11) {
                Text(training.statusText(language: selectedLanguage))
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(Color(hex: "F5E7CF"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)

                Text(training.countdownLabel(language: selectedLanguage))
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(Color(hex: "E59A32"))

                Text("\(training.realTimeHits)")
                    .font(.system(size: 78, weight: .black))
                    .foregroundStyle(Color(hex: "FFF0E0"))

                Text(remainingText())
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color(hex: "E59A32"))

                HStack(spacing: 14) {
                    Button {
                        Task { await training.start() }
                    } label: {
                        Text(L10n.text("start", selectedLanguage))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillTrainingButtonStyle(color: Color(hex: "F15A13")))
                    .disabled(training.isBusy || !bluetooth.isConnected)
                    .opacity(training.isBusy || !bluetooth.isConnected ? 0.58 : 1.0)

                    Button {
                        Task { await training.stop() }
                    } label: {
                        Text(L10n.text("end", selectedLanguage))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillTrainingButtonStyle(color: Color(hex: "8E3E4D")))
                    .disabled(!training.isBusy)
                    .opacity(training.isBusy ? 1.0 : 0.58)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("mode", selectedLanguage))
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(Color(hex: "FFF6E5"))
                modeList
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(training.modeTitle(language: selectedLanguage))
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(Color(hex: "FFF6E5"))
                Text(training.modeBody(language: selectedLanguage))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "D8C08A"))
                    .fixedSize(horizontal: false, vertical: true)
                Text(training.progressLine(language: selectedLanguage))
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color(hex: "FFF3D3"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "10283A").opacity(0.86), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "FF9A30"), lineWidth: 1.2))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "26333D").opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(hex: "183B29"), lineWidth: 1))
    }

    private var trainingRankCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("tab_training", selectedLanguage))
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color(hex: "0B3A1E"))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(hex: "73FF94"), Color(hex: "D8FFD5")], startPoint: .leading, endPoint: .trailing), in: Capsule())

            Text(tierLabel(cloud.tier?.key, fallbackLevel: cloud.profile?.currentTier ?? training.trainingLevel))
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Color(hex: "FFF6E5"))

            Text(trainingSummaryLine())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "CFE9DC"))
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(latestCoachLine())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "D8C08A"))
                .fixedSize(horizontal: false, vertical: true)

            Text(nextTierLine())
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color(hex: "9CFF61"))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: "082415"), Color(hex: "0A161D")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: "00D26A"), lineWidth: 1.2))
    }

    private var latestReportBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localText("最新报告", "Latest Report", fr: "Dernier rapport", th: "รายงานล่าสุด", es: "Último informe", de: "Letzter Bericht", ko: "최신 리포트"))
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Color(hex: "FFF6E5"))
            if let report = training.latestReport {
                reportCard(report)
            } else {
                emptyReportPanel
            }
        }
    }

    private var emptyReportPanel: some View {
        VStack(spacing: 12) {
            Text(localText("战报", "Report", fr: "Rapport", th: "รายงาน"))
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color(hex: "1A1B18"))
                .padding(.horizontal, 40)
                .padding(.vertical, 8)
                .background(LinearGradient(colors: [Color(hex: "E6FAFF"), Color(hex: "FF9A30")], startPoint: .leading, endPoint: .trailing), in: Capsule())
            Text(localText("等待首份训练战报", "Waiting for your first training report", fr: "En attente de votre premier rapport", th: "รอรายงานการฝึกครั้งแรก"))
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Color(hex: "FFF6E5"))
                .multilineTextAlignment(.center)
            Text(localText("暂无训练报告。", "No training report yet.", fr: "Aucune séance pour le moment.", th: "ยังไม่มีการฝึก"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: "B8C8C0"))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "10283A").opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "FF9A30"), lineWidth: 1))
    }

    private var modeList: some View {
        VStack(spacing: 8) {
            ForEach(TrainingPlayMode.allCases) { mode in
                Button {
                    training.selectedPlayMode = mode
                } label: {
                    HStack(spacing: 12) {
                        Text(modeMarker(mode))
                            .font(.system(size: 19, weight: .black))
                            .foregroundStyle(modeAccent(mode))
                        Text(L10n.text(mode.titleKey, selectedLanguage))
                            .font(.system(size: 16, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .padding(.horizontal, 14)
                    .foregroundStyle(training.selectedPlayMode == mode ? Color(hex: "FFF8E8") : Color(hex: "E5C98A"))
                    .background(training.selectedPlayMode == mode ? Color(hex: "173247").opacity(0.96) : Color(hex: "0A1721").opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(training.selectedPlayMode == mode ? modeAccent(mode) : Color(hex: "1B3344"), lineWidth: 1.2))
                }
                .disabled(training.isBusy)
                .opacity(training.isBusy ? 0.62 : 1)
            }
        }
    }

    private func reportCard(_ report: TrainingReport) -> some View {
        SurfaceCard(stroke: report.goalMet ? Color(hex: "FFD060") : Color(hex: "FF9A30")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Badge(text: report.goalMet ? "VICTORY" : "GOOD WORK", color: Color(hex: "FFD060"), textColor: Color(hex: "140800"))
                        Text(L10n.text("training_report", selectedLanguage))
                        .font(.title3.weight(.black))
                            .foregroundStyle(Color(hex: "FFF6E5"))
                    }
                    Spacer()
                    Button {
                        shareTraining(report)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline.bold())
                    }
                    .buttonStyle(IconButtonStyle())
                }
                HStack(spacing: 10) {
                    MetricPill(title: L10n.text("total_hits", selectedLanguage), value: "\(report.totalHits)")
                    MetricPill(title: L10n.text("avg_freq", selectedLanguage), value: String(format: "%.2f", report.averageFrequency))
                    MetricPill(title: L10n.text("best_burst", selectedLanguage), value: "\(report.bestBurstCount)")
                }
                Text(training.coachMessage(for: report, language: selectedLanguage))
                    .font(.callout)
                    .foregroundStyle(Color(hex: "FFF0C9"))
                Text("XP +\(report.xpGain) | \(L10n.text("streak", selectedLanguage)) \(report.streak) | Lv.\(report.levelAfter)")
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: "FFD060"))
            }
        }
    }

    private var achievementsPage: some View {
        let items = cloud.achievements.isEmpty ? cloud.fallbackAchievements() : cloud.achievements
        let groups = achievementGroups(items)
        let unlockedCount = items.filter(\.unlocked).count
        return VStack(alignment: .leading, spacing: 16) {
            pageHeading(
                title: localText("成就徽章", "Achievement Badges", fr: "Succès", th: "ความสำเร็จ"),
                subtitle: localText(
                    "解锁 24 个训练成就徽章，记录你的成长。",
                    "Unlock 24 training badges and track progress.",
                    fr: "Débloquez 24 badges d'entraînement et suivez votre progression.",
                    th: "ปลดล็อกเหรียญความสำเร็จ 24 รายการและติดตามพัฒนาการ"
                )
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(unlockedSummary(unlockedCount, items.count))
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color(hex: "E2D3A0"))
                    Spacer()
                    Button {
                        shareAchievements(items: items)
                    } label: {
                        Text(L10n.text("share_achievements", selectedLanguage))
                            .font(.system(size: 12, weight: .black))
                    }
                    .buttonStyle(CompactOutlineButtonStyle())
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(tierLabel(cloud.tier?.key, fallbackLevel: cloud.tier?.level ?? training.trainingLevel))
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(Color(hex: "FFF6E5"))
                    Text(unlockedSummary(unlockedCount, items.count))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "D8C08A"))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(hex: "17384B"), Color(hex: "28150A")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "FFD060"), lineWidth: 1))

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(group.title)
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(Color(hex: "FFF6E5"))
                            Spacer()
                            Text("\(group.items.filter(\.unlocked).count)/\(group.items.count)")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(Color(hex: "CFE9DC"))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color(hex: "17384B"), in: Capsule())
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(group.items) { item in
                                achievementCard(item)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(hex: "0B1B27").opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "24495A"), lineWidth: 1))
                }
            }
            .padding(14)
            .background(Color(hex: "10283A").opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(hex: "163B2A"), lineWidth: 1))

            Text(localText("训练记录", "Training Records", fr: "Historique", th: "ประวัติการฝึก", es: "Historial de entrenamiento", de: "Trainingsverlauf", ko: "훈련 기록"))
                .font(.system(size: 23, weight: .black))
                .foregroundStyle(Color(hex: "FFF6E5"))
            historySection
        }
    }

    private func achievementCard(_ item: CloudAchievementItem) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Image(achievementImageName(item.key))
                .resizable()
                .scaledToFit()
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .saturation(item.unlocked ? 1 : 0)
                .opacity(item.unlocked ? 1 : 0.38)
            Text(achievementName(item.key))
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color(hex: "FFF6E5"))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.65)
            ProgressView(value: Double(item.progress), total: Double(max(1, item.goal)))
                .tint(item.unlocked ? Color(hex: "FFD060") : Color(hex: "8A4A1E"))
            Text("\(item.progress)/\(item.goal)")
                .font(.caption2.weight(.black))
                .foregroundStyle(item.unlocked ? Color(hex: "FFD060") : Color(hex: "CAA26A"))
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 168)
        .background(LinearGradient(colors: [Color(hex: "0C1822"), Color(hex: item.unlocked ? "2A1A0A" : "1B0C07")], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(item.unlocked ? Color(hex: "B88A54") : Color(hex: "233A4B"), lineWidth: 1))
    }

    private var leaderboardPage: some View {
        let top = cloud.leaderboard?.top ?? []
        return VStack(alignment: .leading, spacing: 16) {
            pageHeading(
                title: localText("榜单排名", "Rankings", fr: "Classement", th: "อันดับ", es: "Clasificación", de: "Rangliste", ko: "순위표"),
                subtitle: boardSubtitle(cloud.selectedBoard)
            )
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ForEach(LeaderboardBoard.allCases) { board in
                        Button {
                            cloud.selectedBoard = board
                            Task { await cloud.refreshLeaderboard(language: selectedLanguage) }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .stroke(cloud.selectedBoard == board ? Color(hex: "00D0B6") : Color(hex: "22313B"), lineWidth: 2)
                                    .background(Circle().fill(cloud.selectedBoard == board ? Color(hex: "00D0B6").opacity(0.35) : Color.clear))
                                    .frame(width: 16, height: 16)
                                Text(boardShortTitle(board))
                                    .font(.system(size: 13, weight: .black))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(cloud.selectedBoard == board ? Color(hex: "FFF6E5") : Color(hex: "B8C8C0"))
                        }
                    }
                }

                Button {
                    Task { await cloud.refreshLeaderboard(language: selectedLanguage) }
                } label: {
                    Text(L10n.text("refresh", selectedLanguage))
                        .font(.system(size: 14, weight: .black))
                }
                .buttonStyle(CompactOutlineButtonStyle())
            }

            if top.isEmpty {
                emptyState(title: L10n.text("leaderboard_empty_title", selectedLanguage), body: L10n.text("leaderboard_empty", selectedLanguage))
            } else {
                leaderboardArena(top)
            }
        }
    }

    private func leaderboardArena(_ entries: [CloudLeaderboardEntry]) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                podiumSlot(entry: entries.first(where: { $0.rank == 2 }), fallbackRank: 2, height: 178, tint: Color(hex: "CFEAFF"))
                podiumSlot(entry: entries.first(where: { $0.rank == 1 }), fallbackRank: 1, height: 224, tint: Color(hex: "FFD060"))
                podiumSlot(entry: entries.first(where: { $0.rank == 3 }), fallbackRank: 3, height: 164, tint: Color(hex: "FFB37B"))
            }
            .padding(.top, 8)

            ForEach(entries.filter { $0.rank > 3 }) { entry in
                leaderboardRow(entry)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(L10n.text("leaderboard_me", selectedLanguage)) · \(boardShortTitle(cloud.selectedBoard))")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color(hex: "00FF88"))
                    Spacer()
                    Button {
                        shareLeaderboard()
                    } label: {
                        Text(L10n.text("share_leaderboard", selectedLanguage))
                            .font(.system(size: 13, weight: .black))
                    }
                    .buttonStyle(CompactOutlineButtonStyle())
                }
                if let me = cloud.leaderboard?.me {
                    leaderboardRowContent(me)
                } else {
                    Text(localText("当前尚未上榜。", "Not ranked yet.", fr: "Vous n'êtes pas encore classé.", th: "คุณยังไม่มีอันดับ"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "FFF6E5"))
                }
            }
            .padding(18)
            .background(Color(hex: "10283A").opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "00D26A"), lineWidth: 1.2))
        }
        .padding(16)
        .background(Color(hex: "10283A").opacity(0.94), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(hex: "24495A"), lineWidth: 1))
    }

    private func podiumSlot(entry: CloudLeaderboardEntry?, fallbackRank: Int, height: CGFloat, tint: Color) -> some View {
        VStack(spacing: 8) {
            Text("TOP \(fallbackRank)")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Color(hex: "182018"))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(tint, in: Capsule())
            Text("#\(entry?.rank ?? fallbackRank)")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(tint)
            Text(entry?.nickname ?? "--")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(Color(hex: "FFF6E5"))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
            Text(boardShortTitle(cloud.selectedBoard))
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Color(hex: "FFD060"))
                .multilineTextAlignment(.center)
            Text("\(entry?.bestHits ?? 0) \(boardValueUnit())")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(tint)
            Text("\(tierWord()) \(tierLabel(entry?.tierKey, fallbackLevel: entry?.tierLevel ?? 1))")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: "D8C08A"))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(LinearGradient(colors: [Color(hex: "17384B").opacity(0.88), tint.opacity(0.20)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(tint.opacity(0.8), lineWidth: 1.1))
    }

    private func leaderboardRow(_ entry: CloudLeaderboardEntry) -> some View {
        leaderboardRowContent(entry)
            .padding(16)
            .background(Color(hex: "10283A").opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "24495A"), lineWidth: 1))
    }

    private func leaderboardRowContent(_ entry: CloudLeaderboardEntry) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "00FF88"))
                .frame(width: 6, height: 58)
            Text("#\(entry.rank)")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Color(hex: "00FF88"))
                .frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.nickname)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color(hex: "FFF6E5"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(boardShortTitle(cloud.selectedBoard)) \(entry.bestHits) \(boardValueUnit()) | \(tierWord()) \(tierLabel(entry.tierKey, fallbackLevel: entry.tierLevel ?? 1))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "D8C08A"))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Text(tierLabel(entry.tierKey, fallbackLevel: entry.tierLevel ?? 1))
                .font(.caption2.weight(.black))
                .foregroundStyle(Color(hex: "CFE9DC"))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(hex: "17384B"), in: Capsule())
        }
    }

    private var profilePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading(
                title: localText("个人中心", "Profile Center", fr: "Profil", th: "โปรไฟล์", es: "Perfil", de: "Profil", ko: "프로필"),
                subtitle: localText(
                    "查看你的段位、训练统计与最近获得的徽章",
                    "Review tier, stats, and recent badges.",
                    fr: "Consultez votre rang, vos statistiques et vos badges récents.",
                    th: "ดูระดับ สถิติหลัก และเหรียญล่าสุดของคุณ"
                )
            )

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(localText("拳击训练档案", "Boxing Training Profile", fr: "Dossier du boxeur", th: "โปรไฟล์นักชก"))
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Color(hex: "1A1B18"))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [Color(hex: "FFF0A6"), Color(hex: "D99A1E")], startPoint: .leading, endPoint: .trailing), in: Capsule())

                    HStack(spacing: 18) {
                        avatarView(
                            photo: avatarStore.image,
                            colorHex: cloud.profile?.avatarColor ?? profileColor,
                            initial: avatarInitial(),
                            size: 104,
                            strokeWidth: 4
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(tierLabel(cloud.tier?.key, fallbackLevel: cloud.profile?.currentTier ?? training.trainingLevel))
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(Color(hex: "1A1B18"))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(LinearGradient(colors: [Color(hex: "FFF0A6"), Color(hex: "D99A1E")], startPoint: .leading, endPoint: .trailing), in: Capsule())
                            Text(cloud.profile?.nickname ?? "Player-\(profileSuffix())")
                                .font(.system(size: 31, weight: .black))
                                .foregroundStyle(Color(hex: "FFF6E5"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.58)
                            Text("\(localText("语言", "Language", fr: "Langue", th: "ภาษา", es: "Idioma", de: "Sprache", ko: "언어")): \(selectedLanguage.displayName)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: "D8C08A"))
                                .lineLimit(2)
                                .minimumScaleFactor(0.68)
                            Text("\(tierLabel(cloud.tier?.key, fallbackLevel: cloud.tier?.level ?? training.trainingLevel))  Lv.\(cloud.tier?.level ?? training.trainingLevel)  |  \(localText("下一段位", "Next", fr: "Rang suivant", th: "ระดับถัดไป")): \(tierLabel(cloud.tier?.nextKey, fallbackLevel: (cloud.tier?.level ?? training.trainingLevel) + 1))")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(Color(hex: "FFD060"))
                                .lineLimit(2)
                                .minimumScaleFactor(0.68)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profileStatsLines(), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 19, weight: .black))
                            .foregroundStyle(Color(hex: "FFF6E5"))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }

                Text(recentBadgesLine())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "C9A56B"))
                    .fixedSize(horizontal: false, vertical: true)

                Text(cloud.statusMessage.isEmpty ? L10n.text("cloud_sync_idle", selectedLanguage) : cloud.statusMessage)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color(hex: "E59A32"))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(hex: "241D14").opacity(0.8), in: Capsule())
                    .overlay(Capsule().stroke(Color(hex: "FF9A30"), lineWidth: 1))

                HStack(spacing: 14) {
                    Button(L10n.text("edit_profile", selectedLanguage)) {
                        profileName = cloud.profile?.nickname ?? ""
                        profileColor = cloud.profile?.avatarColor ?? "#145DA0"
                        draftAvatarPhoto = avatarStore.image
                        avatarPhotoEdited = false
                        showingEditProfile = true
                    }
                    .buttonStyle(CompactOutlineButtonStyle())

                    Button(localText("刷新云端", "Refresh Cloud", fr: "Actualiser le cloud", th: "รีเฟรชคลาวด์", es: "Actualizar nube", de: "Cloud aktualisieren", ko: "클라우드 새로고침")) {
                        Task { await cloud.bootstrap(language: selectedLanguage) }
                    }
                    .buttonStyle(PillTrainingButtonStyle(color: Color(hex: "E07010")))
                }

                Button {
                    showingDeveloperInfo = true
                } label: {
                    Text(localText("联系我们", "Contact Us", fr: "Nous contacter", th: "ติดต่อเรา"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactOutlineButtonStyle())
            }
            .padding(22)
            .background(LinearGradient(colors: [Color(hex: "10283A"), Color(hex: "062016")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color(hex: "1D5C3D"), lineWidth: 1))

            historySection
            legalButtons
        }
    }

    private var historySection: some View {
        let cloudItems = cloud.history.prefix(6)
        return SurfaceCard(stroke: Color(hex: "2B5870")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("history_title", selectedLanguage))
                    .font(.headline.bold())
                    .foregroundStyle(Color(hex: "FFF6E5"))
                if cloudItems.isEmpty && training.reportHistory.isEmpty {
                    Text(L10n.text("history_empty", selectedLanguage))
                        .font(.callout)
                        .foregroundStyle(Color(hex: "DFFFF0"))
                } else if !cloudItems.isEmpty {
                    ForEach(Array(cloudItems)) { item in
                        historyRow(title: "\(item.modeSeconds)s", hits: item.totalHits, freq: item.averageFrequency)
                    }
                } else {
                    ForEach(training.reportHistory.prefix(6)) { report in
                        historyRow(title: L10n.text(report.mode.labelKey, selectedLanguage), hits: report.totalHits, freq: report.averageFrequency)
                    }
                }
            }
        }
    }

    private func historyRow(title: String, hits: Int, freq: Double) -> some View {
        HStack {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(Color(hex: "FFD060"))
            Spacer()
            Text("\(hits) \(L10n.text("hits_short", selectedLanguage))")
                .font(.caption.bold())
                .foregroundStyle(Color(hex: "FFF6E5"))
            Text(String(format: "%.2f/s", freq))
                .font(.caption.bold())
                .foregroundStyle(Color(hex: "80FFB0"))
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var legalButtons: some View {
        HStack(spacing: 10) {
            Button(L10n.text("privacy_policy", selectedLanguage)) { showingLegal = .privacy }
                .buttonStyle(ActionButtonStyle(color: Color(hex: "3A2A16")))
            Button(L10n.text("user_agreement", selectedLanguage)) { showingLegal = .agreement }
                .buttonStyle(ActionButtonStyle(color: Color(hex: "3A2A16")))
        }
    }

    private var editProfileSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    editSectionLabel(L10n.text("nickname", selectedLanguage))
                    TextField(L10n.text("nickname", selectedLanguage), text: $profileName)
                        .fieldStyle()

                    editSectionLabel(localText("个人头像", "Avatar", fr: "Avatar", th: "รูปโปรไฟล์", es: "Avatar", de: "Avatar", ko: "아바타"))
                    VStack(spacing: 12) {
                        avatarView(
                            photo: draftAvatarPhoto,
                            colorHex: profileColor,
                            initial: avatarInitial(from: profileName),
                            size: 68,
                            strokeWidth: 2
                        )
                        HStack(spacing: 12) {
                            Button(localText("选择图片", "Choose Photo", fr: "Choisir une photo", th: "เลือกรูปภาพ")) {
                                showingPhotoPicker = true
                            }
                            .buttonStyle(CompactOutlineButtonStyle())
                            Button(localText("移除图片", "Remove Photo", fr: "Supprimer la photo", th: "ลบรูปภาพ")) {
                                draftAvatarPhoto = nil
                                avatarPhotoEdited = true
                            }
                            .buttonStyle(CompactOutlineButtonStyle())
                        }
                        Text(localText(
                            "可从手机相册选择头像图片，未选择时使用颜色头像。",
                            "Choose an avatar photo from this phone, or keep the color avatar.",
                            fr: "Choisissez une photo sur ce téléphone ou gardez l'avatar coloré.",
                            th: "เลือกรูปโปรไฟล์จากโทรศัพท์ หรือใช้รูปแบบสีเดิม"
                        ))
                        .font(.footnote.bold())
                        .foregroundStyle(Color(hex: "B88A54"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        avatarPalettePicker
                    }
                    .frame(maxWidth: .infinity)

                    Button(L10n.text("save", selectedLanguage)) {
                        saveProfileEdits()
                    }
                    .buttonStyle(ActionButtonStyle(color: Color(hex: "008840")))
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .background(Color(hex: "040C08").ignoresSafeArea())
            .navigationTitle(L10n.text("edit_profile", selectedLanguage))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.text("done", selectedLanguage)) { showingEditProfile = false }
                }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPicker { image in
                    showingPhotoPicker = false
                    if let image {
                        draftAvatarPhoto = image
                        avatarPhotoEdited = true
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func editSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.black))
            .foregroundStyle(Color(hex: "DFFFF0"))
    }

    /// Android's eight avatar color swatches.
    private var avatarPalettePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(Self.avatarPalette.enumerated()), id: \.offset) { index, color in
                    Button {
                        profileColor = color
                    } label: {
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(sanitizedAvatarColor(profileColor) == color ? Color.white : Color.clear, lineWidth: 2))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(localText(
                        "头像颜色 \(index + 1)",
                        "Avatar color \(index + 1)",
                        fr: "Couleur d'avatar \(index + 1)",
                        th: "สีรูปโปรไฟล์ \(index + 1)"
                    ))
                }
            }
        }
    }

    /// The photo, when set, stays on this phone; only the color goes to the server.
    private func saveProfileEdits() {
        if avatarPhotoEdited {
            if let photo = draftAvatarPhoto {
                avatarStore.save(photo)
            } else {
                avatarStore.remove()
            }
            avatarPhotoEdited = false
        }
        let avatarColor = sanitizedAvatarColor(profileColor)
        Task {
            await cloud.updateProfile(nickname: profileName, language: selectedLanguage, avatarColor: avatarColor)
            showingEditProfile = false
        }
    }

    private func avatarView(photo: UIImage?, colorHex: String, initial: String, size: CGFloat, strokeWidth: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(hex: sanitizedAvatarColor(colorHex)))
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.system(size: size * 0.4, weight: .black))
                    .foregroundStyle(.white)
            }
            Circle().stroke(Color(hex: "D8FFF0"), lineWidth: strokeWidth)
        }
        .frame(width: size, height: size)
    }

    /// Same rule as Android's sanitizeAvatarColor: "#RRGGBB" in upper case, otherwise the default green.
    private func sanitizedAvatarColor(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isHexColor = trimmed.count == 7 && trimmed.hasPrefix("#") && trimmed.dropFirst().allSatisfy(\.isHexDigit)
        return isHexColor ? trimmed.uppercased() : "#008840"
    }

    private static let avatarPalette = ["#CC4400", "#E07010", "#A73A54", "#FFD060", "#5C3D99", "#7A1400", "#8B5E3C", "#C06014"]

    // MARK: - Launch splash

    private func dismissLaunchSplash() {
        guard showingLaunchSplash, !launchSplashDismissing else {
            return
        }
        launchSplashDismissing = true
        withAnimation(.easeOut(duration: 0.32)) {
            contentSettled = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            showingLaunchSplash = false
            showFirstUsePromptIfNeeded()
        }
    }

    /// Shown after the launch splash so the Bluetooth hint does not cover the intro video.
    private func showFirstUsePromptIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "bluetooth_first_use_prompt_shown"), !bluetooth.isConnected else {
            return
        }
        UserDefaults.standard.set(true, forKey: "bluetooth_first_use_prompt_shown")
        showingFirstUsePrompt = true
    }

    private func emptyState(title: String, body: String) -> some View {
        SurfaceCard(stroke: Color(hex: "2B5870")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(Color(hex: "FFF6E5"))
                Text(body)
                    .font(.callout)
                    .foregroundStyle(Color(hex: "DFFFF0"))
            }
        }
    }

    private func shareTraining(_ report: TrainingReport) {
        let image = SharePosterRenderer.poster(
            title: L10n.text("training_report", selectedLanguage),
            subtitle: report.goalMet ? "VICTORY" : "GOOD WORK",
            metrics: [
                (L10n.text("total_hits", selectedLanguage), "\(report.totalHits)"),
                (L10n.text("avg_freq", selectedLanguage), String(format: "%.2f/s", report.averageFrequency)),
                (L10n.text("best_burst", selectedLanguage), "\(report.bestBurstCount)")
            ],
            footer: "Vimai Smart Sensor Ball"
        )
        shareItems = [image, training.coachMessage(for: report, language: selectedLanguage)]
        training.markTrainingShared()
    }

    private func shareAchievements(items: [CloudAchievementItem]) {
        let unlocked = items.filter(\.unlocked).count
        let image = SharePosterRenderer.poster(
            title: L10n.text("tab_achievements", selectedLanguage),
            subtitle: tierName(cloud.tier?.key, fallbackLevel: training.trainingLevel),
            metrics: [
                (L10n.text("badges_unlocked", selectedLanguage), "\(unlocked)/\(items.count)"),
                ("XP", "\(training.trainingXP)"),
                (L10n.text("streak", selectedLanguage), "\(training.currentStreak)")
            ],
            footer: "Vimai Smart Sensor Ball"
        )
        shareItems = [image]
    }

    private func shareLeaderboard() {
        let me = cloud.leaderboard?.me
        let image = SharePosterRenderer.poster(
            title: L10n.text("leaderboard_title", selectedLanguage),
            subtitle: cloud.selectedBoard.title(language: selectedLanguage),
            metrics: [
                (L10n.text("rank", selectedLanguage), me.map { "#\($0.rank)" } ?? "--"),
                (L10n.text("score", selectedLanguage), me.map(leaderboardPrimary) ?? "--"),
                (L10n.text("avg_freq", selectedLanguage), me.map { String(format: "%.2f/s", $0.averageFrequency) } ?? "--")
            ],
            footer: "Vimai Smart Sensor Ball"
        )
        shareItems = [image]
    }

    private func leaderboardPrimary(_ entry: CloudLeaderboardEntry) -> String {
        switch cloud.selectedBoard {
        case .longestStreak:
            return "\(entry.bestHits)d"
        default:
            return "\(entry.bestHits)"
        }
    }

    private func pageHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 31, weight: .black))
                .foregroundStyle(Color(hex: "FFF6E5"))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: "B8C8C0"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func localText(
        _ chinese: String,
        _ english: String,
        fr french: String,
        th thai: String,
        es spanish: String? = nil,
        de german: String? = nil,
        ko korean: String? = nil
    ) -> String {
        selectedLanguage.localized(chinese, english, fr: french, th: thai, es: spanish, de: german, ko: korean)
    }

    private func hitsWord() -> String {
        localText("次", "hits", fr: "coups", th: "ครั้ง", es: "golpes", de: "Treffer", ko: "회")
    }

    private func tierWord() -> String {
        localText("段位", "Tier", fr: "Niveau", th: "ระดับ", es: "Nivel", de: "Stufe", ko: "등급")
    }

    private func boardValueUnit() -> String {
        if cloud.selectedBoard == .longestStreak {
            return localText("天", "days", fr: "jours", th: "วัน")
        }
        return hitsWord()
    }

    private func trainingSummaryLine() -> String {
        let best30 = best30Value()
        let best60 = best60Value()
        let total = totalHitsValue()
        return localText(
            "最佳30秒 \(best30) 次 · 最佳60秒 \(best60) 次 · 累计 \(total) 次",
            "Best 30s \(best30) hits · Best 60s \(best60) hits · Total \(total) hits",
            fr: "Meilleur 30 s \(best30) · Meilleur 60 s \(best60) · \(total) frappes au total",
            th: "ดีที่สุด 30 วินาที \(best30) · ดีที่สุด 60 วินาที \(best60) · สะสมทั้งหมด \(total) ครั้ง"
        )
    }

    private func latestCoachLine() -> String {
        guard let report = training.latestReport else {
            return localText(
                "暂无最新战报，完成一轮训练后这里会展示你的核心成绩。",
                "No latest report yet. Finish a session to show your result here.",
                fr: "Pas encore de rapport. Terminez une séance pour afficher vos résultats ici.",
                th: "ยังไม่มีรายงานล่าสุด ฝึกให้จบหนึ่งรอบเพื่อแสดงผลลัพธ์ของคุณที่นี่"
            )
        }
        return training.coachMessage(for: report, language: selectedLanguage)
    }

    private func unlockedSummary(_ unlockedCount: Int, _ totalCount: Int) -> String {
        localText(
            "已解锁 \(unlockedCount) / \(totalCount)",
            "Unlocked \(unlockedCount) / \(totalCount)",
            fr: "\(unlockedCount) / \(totalCount) débloqués",
            th: "ปลดล็อกแล้ว \(unlockedCount) / \(totalCount)"
        )
    }

    /// Up to three of the most recently unlocked badges, like the Android profile page.
    private func recentBadgesLine() -> String {
        let recent = cloud.achievements
            .filter(\.unlocked)
            .sorted { ($0.unlockedAt ?? "") > ($1.unlockedAt ?? "") }
            .prefix(3)
        guard !recent.isEmpty else {
            return localText(
                "最近徽章：继续训练以解锁首枚徽章",
                "Recent badges: keep training to unlock your first badge",
                fr: "Badges récents : continuez à vous entraîner pour débloquer votre premier badge",
                th: "เหรียญล่าสุด: ฝึกต่อเพื่อปลดล็อกเหรียญแรก"
            )
        }
        let names = recent.map { achievementName($0.key) }.joined(separator: " · ")
        return localText("最近徽章：\(names)", "Recent badges: \(names)", fr: "Badges récents : \(names)", th: "เหรียญล่าสุด: \(names)")
    }

    private func uploadReport(_ report: TrainingReport) {
        Task { @MainActor in
            guard let highlights = await cloud.upload(report: report, language: selectedLanguage) else {
                return
            }
            if !highlights.unlockedAchievements.isEmpty {
                enqueueCelebration(badgeCelebration(for: highlights.unlockedAchievements))
            }
            if let tier = highlights.promotedTier {
                enqueueCelebration(rankUpCelebration(for: tier))
            }
        }
    }

    // MARK: - Post-training celebrations

    private func enqueueCelebration(_ item: CelebrationItem) {
        celebrationQueue.append(item)
        showNextCelebrationIfIdle()
    }

    private func showNextCelebrationIfIdle() {
        guard activeCelebration == nil, !training.isBusy, !celebrationQueue.isEmpty else {
            return
        }
        let next = celebrationQueue.removeFirst()
        withAnimation(.easeOut(duration: 0.28)) {
            activeCelebration = next
        }
        speech.speakCelebration(celebrationVoiceText(next.title))
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if activeCelebration?.id == next.id {
                dismissCelebration()
            }
        }
    }

    private func dismissCelebration() {
        withAnimation(.easeIn(duration: 0.2)) {
            activeCelebration = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showNextCelebrationIfIdle()
        }
    }

    private func trainingOutcomeCelebration(for report: TrainingReport) -> CelebrationItem {
        let title: String
        switch report.playMode {
        case .levelChallenge:
            title = report.goalMet
                ? localText("闯关成功", "Level Cleared", fr: "Niveau réussi", th: "ผ่านด่านแล้ว")
                : localText("闯关继续", "Keep Challenging", fr: "Continuez le défi", th: "ท้าทายต่อไป")
        case .dailyChallenge:
            title = report.goalMet
                ? localText("挑战成功", "Challenge Complete", fr: "Défi réussi", th: "ภารกิจสำเร็จ")
                : localText("每日挑战进行中", "Daily Challenge Progress", fr: "Défi du jour en cours", th: "ภารกิจวันนี้กำลังดำเนินอยู่")
        case .burst10, .burst15:
            title = report.goalMet
                ? localText("爆发达成", "Burst Target Hit", fr: "Objectif explosif atteint", th: "ทำเป้าระเบิดได้แล้ว")
                : localText("爆发训练完成", "Burst Session Complete", fr: "Séance explosive terminée", th: "ฝึกระเบิดเสร็จแล้ว")
        case .classic30, .classic60:
            title = localText("训练完成", "Training Complete", fr: "Entraînement terminé", th: "ฝึกเสร็จแล้ว")
        }
        var chips = [
            CelebrationChip(text: "XP +\(report.xpGain)", colorHex: "FFD060"),
            CelebrationChip(
                text: localText("连练 \(report.streak) 天", "\(report.streak)-day streak", fr: "Série de \(report.streak) jours", th: "ต่อเนื่อง \(report.streak) วัน"),
                colorHex: "FFB347"
            ),
            CelebrationChip(text: L10n.text(report.mode.labelKey, selectedLanguage), colorHex: "FF9A30")
        ]
        if report.goalMet {
            chips.append(CelebrationChip(text: localText("任务完成", "Task done", fr: "Tâche accomplie", th: "ภารกิจสำเร็จ"), colorHex: "E07010"))
        }
        return CelebrationItem(
            accentHex: report.goalMet ? "FFD060" : "FF9A30",
            eyebrow: report.goalMet ? "VICTORY" : "GOOD WORK",
            title: title,
            body: training.coachMessage(for: report, language: selectedLanguage),
            chips: chips
        )
    }

    private func badgeCelebration(for items: [CloudAchievementItem]) -> CelebrationItem {
        let count = items.count
        return CelebrationItem(
            accentHex: "FFB347",
            eyebrow: "NEW BADGES",
            title: localText("新徽章解锁", "New badges unlocked", fr: "Nouveaux badges débloqués", th: "ปลดล็อกเหรียญใหม่แล้ว"),
            body: localText(
                "本次训练解锁 \(count) 枚徽章，继续保持节奏，冲击更高段位。",
                "You unlocked \(count) new badges in this session. Keep pushing for the next tier.",
                fr: "Vous avez débloqué \(count) nouveaux badges pendant cette séance. Continuez pour atteindre le rang suivant.",
                th: "คุณปลดล็อกเหรียญใหม่ \(count) เหรียญในการฝึกครั้งนี้ ฝึกต่อเพื่อไปสู่ระดับถัดไป"
            ),
            chips: items.prefix(3).map { CelebrationChip(text: achievementName($0.key), colorHex: achievementAccentHex($0.key)) }
        )
    }

    private func rankUpCelebration(for tier: CloudTierProgress) -> CelebrationItem {
        let level = tier.level ?? training.trainingLevel
        let name = tierLabel(tier.key, fallbackLevel: level)
        let best = tier.bestHits ?? best30Value()
        return CelebrationItem(
            accentHex: "FFD060",
            eyebrow: "RANK UP",
            title: localText("段位升级：\(name)", "Rank Up: \(name)", fr: "Promotion : \(name)", th: "เลื่อนระดับ: \(name)"),
            body: localText(
                "当前最佳 30 秒成绩提升至 \(best)，成功晋升为 \(name)。",
                "Your best 30-second score is now \(best). You have been promoted to \(name).",
                fr: "Votre meilleur score sur 30 s est maintenant de \(best). Vous êtes promu au rang \(name).",
                th: "คะแนนดีที่สุด 30 วินาทีของคุณตอนนี้คือ \(best) คุณได้เลื่อนเป็น \(name) แล้ว"
            ),
            chips: [CelebrationChip(text: "Lv.\(level)", colorHex: "FFD060")]
        )
    }

    private func celebrationHint() -> String {
        localText(
            "点击任意位置继续，或 10 秒后自动关闭",
            "Tap anywhere to continue, or it closes in 10 seconds",
            fr: "Touchez n'importe où pour continuer, ou fermeture dans 10 secondes",
            th: "แตะที่ใดก็ได้เพื่อดำเนินการต่อ หรือปิดอัตโนมัติใน 10 วินาที"
        )
    }

    private func celebrationVoiceText(_ title: String) -> String {
        localText(
            "太棒了！\(title)！继续保持，向更强进发！",
            "Amazing! \(title)! Keep going strong!",
            fr: "Magnifique ! \(title) ! Continuez comme ça !",
            th: "ยอดเยี่ยม! \(title)! ลุยต่อไป!"
        )
    }

    private func achievementAccentHex(_ key: String) -> String {
        if key.hasPrefix("best_30") { return "00A86B" }
        if key.hasPrefix("best_60") { return "6E9E00" }
        if key.hasPrefix("hits_") { return "2E9E6A" }
        if key.hasPrefix("burst_") { return "00A88A" }
        if key.hasPrefix("streak_") { return "4C9E73" }
        return "00A86B"
    }

    private func totalSessionsValue() -> Int {
        cloud.statistics?.totalSessions ?? training.reportHistory.count
    }

    private func totalHitsValue() -> Int {
        cloud.statistics?.totalHits ?? training.reportHistory.reduce(0) { $0 + $1.totalHits }
    }

    private func best30Value() -> Int {
        cloud.statistics?.best30Hits ?? localBest(seconds: 30)
    }

    private func best60Value() -> Int {
        cloud.statistics?.best60Hits ?? localBest(seconds: 60)
    }

    private func bestBurstValue() -> Int {
        cloud.statistics?.bestBurstRecord ?? training.reportHistory.map(\.bestBurstCount).max() ?? 0
    }

    private func longestStreakValue() -> Int {
        cloud.statistics?.longestStreak ?? training.bestStreak
    }

    private func activeDaysValue() -> Int {
        cloud.statistics?.activeDays ?? 0
    }

    private func globalBestValue() -> Int {
        cloud.profile?.bestScoreCached ?? cloud.statistics?.personalBestHits ?? max(best30Value(), best60Value())
    }

    private func profileStatsLines() -> [String] {
        let sessions = localText("总训练次数", "Sessions", fr: "Séances totales", th: "จำนวนการฝึกทั้งหมด", es: "Sesiones totales", de: "Einheiten gesamt", ko: "총 훈련 수")
        let totalHits = localText("总击打次数", "Total hits", fr: "Frappes totales", th: "จำนวนหมัดทั้งหมด", es: "Golpes totales", de: "Treffer gesamt", ko: "총 타격 수")
        let best30 = localText("30 秒最佳", "Best 30s", fr: "Meilleur 30 s", th: "ดีที่สุด 30 วินาที", es: "Mejor 30 s", de: "Beste 30 s", ko: "30초 최고")
        let best60 = localText("60 秒最佳", "Best 60s", fr: "Meilleur 60 s", th: "ดีที่สุด 60 วินาที", es: "Mejor 60 s", de: "Beste 60 s", ko: "60초 최고")
        let burst = localText(
            "最佳 3 秒爆发",
            "Best 3s burst",
            fr: "Meilleure série de 3 s",
            th: "ช่วง 3 วินาทีที่ดีที่สุด",
            es: "Mejor ráfaga de 3 segundos",
            de: "Beste 3-Sekunden-Serie",
            ko: "최고 3초 버스트"
        )
        let streak = localText("最长连续", "Longest streak", fr: "Meilleure série", th: "ต่อเนื่องสูงสุด")
        let activeDays = localText("活跃天数", "Active days", fr: "Jours actifs", th: "วันที่ใช้งาน")
        let globalBest = localText("全局最佳", "Global best", fr: "Meilleur score", th: "ดีที่สุดรวม")
        return [
            "\(sessions): \(totalSessionsValue()) | \(totalHits): \(totalHitsValue())",
            "\(best30): \(best30Value()) | \(best60): \(best60Value())",
            "\(burst): \(bestBurstValue()) | \(streak): \(longestStreakValue())",
            "\(activeDays): \(activeDaysValue()) | \(globalBest): \(globalBestValue())"
        ]
    }

    private func profileSuffix() -> String {
        let digits = cloud.installId.filter(\.isNumber)
        return String((digits.isEmpty ? "9811" : digits).suffix(4))
    }

    private func tierKeyForLevel(_ level: Int) -> String {
        switch min(max(level, 1), 9) {
        case 1: return "beginner"
        case 2: return "prospect"
        case 3: return "contender"
        case 4: return "striker"
        case 5: return "challenger"
        case 6: return "elite"
        case 7: return "master"
        case 8: return "legend"
        default: return "champion"
        }
    }

    private func tierLabel(_ key: String?, fallbackLevel: Int) -> String {
        let resolved = key?.isEmpty == false ? key! : tierKeyForLevel(fallbackLevel)
        switch resolved {
        case "beginner": return localText("拳坛新丁", "New Blood", fr: "Débutant", th: "มือใหม่")
        case "prospect": return localText("热血新秀", "Rising Rookie", fr: "Espoir montant", th: "ดาวรุ่ง")
        case "contender": return localText("擂台争锋者", "Arena Contender", fr: "Prétendant", th: "ผู้ท้าชิง")
        case "striker": return localText("铁拳出击手", "Iron Fist Striker", fr: "Frappeur d'acier", th: "หมัดเหล็ก")
        case "challenger": return localText("风暴挑战者", "Storm Challenger", fr: "Challenger tempête", th: "ผู้ท้าชิงพายุ")
        case "elite": return localText("荣耀精英", "Glory Elite", fr: "Élite glorieuse", th: "ยอดฝีมือ")
        case "master": return localText("宗师", "Grand Master", fr: "Grand maître", th: "ปรมาจารย์")
        case "legend": return localText("不朽传奇", "Immortal Legend", fr: "Légende immortelle", th: "ตำนาน")
        case "champion": return localText("至尊拳王", "Supreme Champion", fr: "Champion suprême", th: "แชมป์สูงสุด")
        default: return localText("拳坛新丁", "New Blood", fr: "Débutant", th: "มือใหม่")
        }
    }

    private func nextTierLine() -> String {
        if let tier = cloud.tier, tier.nextKey == nil || tier.nextHits == nil {
            return localText(
                "已达到当前最高段位，继续保持你的拳击状态",
                "Top tier reached. Keep pushing your boxing pace.",
                fr: "Rang maximal atteint. Continuez à maintenir votre rythme.",
                th: "ถึงระดับสูงสุดแล้ว รักษาจังหวะการฝึกของคุณต่อไป"
            )
        }
        let nextKey = cloud.tier?.nextKey ?? "prospect"
        let target = cloud.tier?.nextHits ?? 40
        let current = cloud.tier?.bestHits ?? best30Value()
        let remaining = max(0, target - current)
        let nextTier = tierLabel(nextKey, fallbackLevel: 2)
        return localText(
            "距离 \(nextTier) 还差 \(remaining) 击",
            "\(remaining) hits to \(nextTier)",
            fr: "Encore \(remaining) frappes pour \(nextTier)",
            th: "อีก \(remaining) ครั้งจะถึง \(nextTier)"
        )
    }

    private func boardShortTitle(_ board: LeaderboardBoard) -> String {
        switch board {
        case .best30:
            return localText("30秒榜", "30s", fr: "30 s", th: "30 วิ")
        case .best60:
            return localText("60秒榜", "60s", fr: "60 s", th: "60 วิ")
        case .totalHits:
            return localText("累计榜", "Total", fr: "Total", th: "สะสม")
        case .longestStreak:
            return localText("连续榜", "Streak", fr: "Série", th: "ต่อเนื่อง")
        }
    }

    private func boardSubtitle(_ board: LeaderboardBoard) -> String {
        switch board {
        case .best30:
            return localText(
                "按 30 秒历史最佳成绩排名",
                "Ranked by best 30-second history.",
                fr: "Classé selon le meilleur score sur 30 s.",
                th: "จัดอันดับตามคะแนนดีที่สุด 30 วินาที"
            )
        case .best60:
            return localText(
                "按 60 秒历史最佳成绩排名",
                "Ranked by best 60-second history.",
                fr: "Classé selon le meilleur score sur 60 s.",
                th: "จัดอันดับตามคะแนนดีที่สุด 60 วินาที"
            )
        case .totalHits:
            return localText(
                "按累计击打总数排名",
                "Ranked by lifetime hit count.",
                fr: "Classé selon le nombre total de frappes.",
                th: "จัดอันดับตามจำนวนหมัดสะสมทั้งหมด"
            )
        case .longestStreak:
            return localText(
                "按最长连续打卡天数排名",
                "Ranked by longest training streak.",
                fr: "Classé selon la plus longue série d'entraînement.",
                th: "จัดอันดับตามจำนวนวันที่ฝึกต่อเนื่องนานที่สุด"
            )
        }
    }

    private func achievementGroups(_ items: [CloudAchievementItem]) -> [AchievementGroup] {
        var byKey: [String: CloudAchievementItem] = [:]
        for item in items {
            byKey[item.key] = item
        }

        func item(_ key: String, goal: Int, metric: String) -> CloudAchievementItem {
            byKey[key] ?? CloudAchievementItem(key: key, metric: metric, goal: goal, progress: 0, unlocked: false, unlockedAt: nil, sortOrder: nil)
        }

        return [
            AchievementGroup(title: localText("训练里程碑", "Training Milestones", fr: "Jalons d'entraînement", th: "เป้าหมายการฝึก"), items: [
                item("first_training", goal: 1, metric: "sessions"),
                item("sessions_5", goal: 5, metric: "sessions"),
                item("sessions_15", goal: 15, metric: "sessions"),
                item("sessions_30", goal: 30, metric: "sessions")
            ]),
            AchievementGroup(title: localText("累计击打", "Total Hits", fr: "Frappes totales", th: "หมัดสะสม"), items: [
                item("hits_100", goal: 100, metric: "total_hits"),
                item("hits_500", goal: 500, metric: "total_hits"),
                item("hits_1000", goal: 1000, metric: "total_hits"),
                item("hits_5000", goal: 5000, metric: "total_hits")
            ]),
            AchievementGroup(title: localText("30 秒成绩徽章", "30s Badges", fr: "Badges 30 s", th: "เหรียญ 30 วินาที"), items: [
                item("best_30_40", goal: 40, metric: "best_30"),
                item("best_30_60", goal: 60, metric: "best_30"),
                item("best_30_80", goal: 80, metric: "best_30"),
                item("best_30_100", goal: 100, metric: "best_30")
            ]),
            AchievementGroup(title: localText("60 秒成绩徽章", "60s Badges", fr: "Badges 60 s", th: "เหรียญ 60 วินาที"), items: [
                item("best_60_90", goal: 90, metric: "best_60"),
                item("best_60_120", goal: 120, metric: "best_60"),
                item("best_60_150", goal: 150, metric: "best_60"),
                item("best_60_180", goal: 180, metric: "best_60")
            ]),
            AchievementGroup(title: localText("爆发能力", "Burst Power", fr: "Puissance explosive", th: "พลังระเบิด"), items: [
                item("burst_6", goal: 6, metric: "burst"),
                item("burst_10", goal: 10, metric: "burst"),
                item("burst_12", goal: 12, metric: "burst"),
                item("burst_15", goal: 15, metric: "burst")
            ]),
            AchievementGroup(title: localText("坚持打卡", "Training Streak", fr: "Série d'entraînement", th: "ฝึกต่อเนื่อง"), items: [
                item("streak_3", goal: 3, metric: "streak"),
                item("streak_7", goal: 7, metric: "streak"),
                item("streak_14", goal: 14, metric: "streak"),
                item("streak_30", goal: 30, metric: "streak")
            ])
        ]
    }

    private func achievementName(_ key: String) -> String {
        switch key {
        case "first_training": return localText("初次登台", "First Session", fr: "Début", th: "เปิดตัว")
        case "sessions_5": return localText("持续热身", "Warm Streak", fr: "Échauffement régulier", th: "วอร์มอัพต่อเนื่อง")
        case "sessions_15": return localText("训练常客", "Regular", fr: "Combattant régulier", th: "นักชกประจำ")
        case "sessions_30": return localText("擂台老兵", "Veteran", fr: "Vétéran du ring", th: "มือเก๋า")
        case "hits_100": return localText("百拳试锋", "100 Hits", fr: "Essai 100 coups", th: "ทดสอบ 100 หมัด")
        case "hits_500": return localText("五百重击", "500 Hits", fr: "500 frappes", th: "500 หมัดหนัก")
        case "hits_1000": return localText("千拳风暴", "1,000 Hits", fr: "Tempête 1K coups", th: "พายุ 1K หมัด")
        case "hits_5000": return localText("万击宗师", "5,000 Hits", fr: "Maître 5K coups", th: "ปรมาจารย์ 5K")
        case "best_30_40": return localText("30秒40击", "30s 40", fr: "30 s • 40 coups", th: "30วิ • 40 หมัด")
        case "best_30_60": return localText("30秒60击", "30s 60", fr: "30 s • 60 coups", th: "30วิ • 60 หมัด")
        case "best_30_80": return localText("30秒80击", "30s 80", fr: "30 s • 80 coups", th: "30วิ • 80 หมัด")
        case "best_30_100": return localText("30秒100击", "30s 100", fr: "30 s • 100 coups", th: "30วิ • 100 หมัด")
        case "best_60_90": return localText("60秒90击", "60s 90", fr: "60 s • 90 coups", th: "60วิ • 90 หมัด")
        case "best_60_120": return localText("60秒120击", "60s 120", fr: "60 s • 120 coups", th: "60วิ • 120 หมัด")
        case "best_60_150": return localText("60秒150击", "60s 150", fr: "60 s • 150 coups", th: "60วิ • 150 หมัด")
        case "best_60_180": return localText("60秒180击", "60s 180", fr: "60 s • 180 coups", th: "60วิ • 180 หมัด")
        case "burst_6": return localText("爆发新星", "Burst 6", fr: "Rookie explosif", th: "มือใหม่สายสปีด")
        case "burst_10": return localText("爆发高手", "Burst 10", fr: "Expert explosif", th: "ผู้เชี่ยวชาญสปีด")
        case "burst_12": return localText("爆发强者", "Burst 12", fr: "Maître explosif", th: "มาสเตอร์สปีด")
        case "burst_15": return localText("爆发王者", "Burst 15", fr: "Roi explosif", th: "ราชาสปีด")
        case "streak_3": return localText("连续3天", "3-Day Streak", fr: "Série 3 jours", th: "ต่อเนื่อง 3 วัน")
        case "streak_7": return localText("连续7天", "7-Day Streak", fr: "Série 7 jours", th: "ต่อเนื่อง 7 วัน")
        case "streak_14": return localText("连续14天", "14-Day Streak", fr: "Série 14 jours", th: "ต่อเนื่อง 14 วัน")
        case "streak_30": return localText("连续30天", "30-Day Streak", fr: "Série 30 jours", th: "ต่อเนื่อง 30 วัน")
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func achievementImageName(_ key: String) -> String {
        switch key {
        case "first_training":
            return "achievement_milestone_01"
        case "sessions_5":
            return "achievement_milestone_02"
        case "sessions_15":
            return "achievement_milestone_03"
        case "sessions_30":
            return "achievement_milestone_04"
        case "hits_100":
            return "achievement_hits_01"
        case "hits_500":
            return "achievement_hits_02"
        case "hits_1000":
            return "achievement_hits_03"
        case "hits_5000":
            return "achievement_hits_04"
        case "best_30_40":
            return "achievement_best30_05"
        case "best_30_60":
            return "achievement_best30_06"
        case "best_30_80":
            return "achievement_best30_07"
        case "best_30_100":
            return "achievement_best30_08"
        case "best_60_90":
            return "achievement_best60_09"
        case "best_60_120":
            return "achievement_best60_10"
        case "best_60_150":
            return "achievement_best60_11"
        case "best_60_180":
            return "achievement_best60_12"
        case "burst_6":
            return "achievement_burst_13"
        case "burst_10":
            return "achievement_burst_14"
        case "burst_12":
            return "achievement_burst_15"
        case "burst_15":
            return "achievement_burst_16"
        case "streak_3":
            return "achievement_streak_17"
        case "streak_7":
            return "achievement_streak_18"
        case "streak_14":
            return "achievement_streak_19"
        case "streak_30":
            return "achievement_streak_20"
        default:
            if key.contains("best_30") { return "achievement_best30_05" }
            if key.contains("best_60") { return "achievement_best60_09" }
            if key.contains("burst") { return "achievement_burst_13" }
            if key.contains("streak") { return "achievement_streak_17" }
            if key.contains("hits") { return "achievement_hits_01" }
            return "achievement_milestone_01"
        }
    }

    private func tierName(_ key: String?, fallbackLevel: Int) -> String {
        "\(tierLabel(key, fallbackLevel: fallbackLevel)) Lv.\(fallbackLevel)"
    }

    private func localBest(seconds: Int) -> Int {
        training.reportHistory.filter { $0.mode.durationSeconds == seconds }.map(\.totalHits).max() ?? 0
    }

    private func avatarInitial() -> String {
        avatarInitial(from: cloud.profile?.nickname)
    }

    private func avatarInitial(from name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String((trimmed.isEmpty ? "S" : trimmed).prefix(1)).uppercased()
    }

    private func remainingText() -> String {
        let seconds = Double(max(0, training.remainingMillis)) / 1_000.0
        let value = String(format: "%.1f", seconds)
        return localText("剩余 \(value) 秒", "Remaining \(value)s", fr: "\(value)s restantes", th: "เหลือ \(value) วินาที")
    }

    private func modeMarker(_ mode: TrainingPlayMode) -> String {
        switch mode {
        case .classic30:
            return "●"
        case .classic60:
            return "◆"
        case .burst10, .burst15:
            return "▲"
        case .levelChallenge:
            return "★"
        case .dailyChallenge:
            return "✓"
        }
    }

    private func modeAccent(_ mode: TrainingPlayMode) -> Color {
        switch mode {
        case .classic30:
            return Color(hex: "FF9A30")
        case .classic60:
            return Color(hex: "FFB347")
        case .burst10:
            return Color(hex: "FFD060")
        case .burst15:
            return Color(hex: "FF9A30")
        case .levelChallenge:
            return Color(hex: "C084FC")
        case .dailyChallenge:
            return Color(hex: "E07010")
        }
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct AchievementGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [CloudAchievementItem]
}

private struct CelebrationChip: Hashable {
    let text: String
    let colorHex: String
}

private struct CelebrationItem: Identifiable, Equatable {
    let id = UUID()
    let accentHex: String
    let eyebrow: String
    let title: String
    let body: String
    let chips: [CelebrationChip]
}

/// Post-training dialog (training outcome, new badges, rank up), dismissed by a tap anywhere.
private struct CelebrationOverlay: View {
    let item: CelebrationItem
    let hint: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(red: 4 / 255, green: 10 / 255, blue: 18 / 255)
                .opacity(0.62)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Badge(text: item.eyebrow, color: Color(hex: item.accentHex), textColor: Color(hex: "140800"))
                Text(item.title)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color(hex: "FFF8E8"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                Text(item.body)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "C7D6E4"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                if !item.chips.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(item.chips, id: \.self) { chip in
                            Text(chip.text)
                                .font(.caption.weight(.black))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(Color(hex: "FFF8E8"))
                                .background(Color(hex: chip.colorHex), in: Capsule())
                        }
                    }
                    .padding(.top, 16)
                }
                Text(hint)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "7F97AA"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            .background(Color(hex: "0F2130"), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color(hex: item.accentHex), lineWidth: 1.4))
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}

private struct BatteryBadge: View {
    let telemetry: SensorBallTelemetry?
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            if let text = telemetry?.batteryText(language: language), !text.isEmpty {
                Text(text)
                    .font(.caption.bold())
            } else if telemetry == nil {
                Text("--")
                    .font(.caption.bold())
            }
        }
        .foregroundStyle(Color(hex: "D8D0BE"))
    }

    private var statusIcon: String {
        guard let telemetry else {
            return "battery.0"
        }
        if telemetry.isCharging {
            return "bolt.fill"
        }
        switch telemetry.batteryLevel ?? 0 {
        case 76...100: return "battery.100"
        case 51...75: return "battery.75"
        case 26...50: return "battery.50"
        case 1...25: return "battery.25"
        default: return "battery.0"
        }
    }
}

private struct SurfaceCard<Content: View>: View {
    let stroke: Color
    let content: Content

    init(stroke: Color, @ViewBuilder content: () -> Content) {
        self.stroke = stroke
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "08120E").opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(stroke.opacity(0.78), lineWidth: 1))
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    let textColor: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.black))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(textColor)
            .background(color, in: Capsule())
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(Color(hex: "DFFFF0"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(Color(hex: "FFD060"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(hex: "B9F8D0"))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(hex: "092016"), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "1D5C3D"), lineWidth: 1))
    }
}

private struct ActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct PillTrainingButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .black))
            .foregroundStyle(Color(hex: "FFF2E6"))
            .padding(.vertical, 15)
            .background(color.opacity(configuration.isPressed ? 0.74 : 1), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

private struct CompactOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(Color(hex: "FFF6E5"))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(hex: "17384B").opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: "D8FFF0"), lineWidth: 1.2))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(hex: "FFD060"))
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func fieldStyle() -> some View {
        self
            .padding(12)
            .foregroundStyle(Color(hex: "FFF6E5"))
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "4B3720"), lineWidth: 1))
    }
}
