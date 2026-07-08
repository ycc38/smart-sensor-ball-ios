import Foundation
import SwiftUI

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
    @EnvironmentObject private var soundEffects: SoundEffectManager

    @State private var selectedLanguage: AppLanguage = AppLanguage.current
    @State private var selectedPage: HomePage = .training
    @State private var showingSettings = false
    @State private var showingLegal: LegalDocument?
    @State private var showingFirstUsePrompt = false
    @State private var showingEditProfile = false
    @State private var serialInput = ""
    @State private var codeInput = ""
    @State private var profileName = ""
    @State private var profileColor = "#145DA0"
    @State private var shareItems: [Any]?
    @State private var pendingCloudUploadReport: TrainingReport?
    @State private var showingLeaderboardConsent = false
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
                        Task { await cloud.upload(report: report, language: selectedLanguage) }
                    }
                }
            } message: {
                Text(L10n.text("leaderboard_consent_message", selectedLanguage))
            }
            .onAppear {
                selectedLanguage = AppLanguage.current
                profileName = cloud.profile?.nickname ?? ""
                profileColor = cloud.profile?.avatarColor ?? "#145DA0"
                if !UserDefaults.standard.bool(forKey: "bluetooth_first_use_prompt_shown") && !bluetooth.isConnected {
                    UserDefaults.standard.set(true, forKey: "bluetooth_first_use_prompt_shown")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        showingFirstUsePrompt = true
                    }
                }
                Task {
                    await cloud.bootstrap(language: selectedLanguage)
                    if cloud.isActivated {
                        await cloud.refreshLeaderboard(language: selectedLanguage)
                    }
                }
            }
            .onChange(of: selectedLanguage) { language in
                language.save()
                Task { await cloud.bootstrap(language: language) }
            }
            .onChange(of: training.latestReport) { report in
                guard let report = report else { return }
                guard cloud.isActivated else { return }
                if leaderboardUploadConsent {
                    Task { await cloud.upload(report: report, language: selectedLanguage) }
                } else {
                    pendingCloudUploadReport = report
                    showingLeaderboardConsent = true
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Smart sensor ball")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Color(hex: "FFF6E5"))
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(bluetooth.isConnected ? Color(hex: "44FF88") : Color(hex: "FF5C5C"))
                    BatteryBadge(text: bluetooth.telemetry?.batteryText ?? "--")
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

    private var activationCard: some View {
        SurfaceCard(stroke: Color(hex: "FFD060")) {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text("activation_title", selectedLanguage), systemImage: "key.fill")
                    .font(.headline.bold())
                    .foregroundStyle(Color(hex: "FFD060"))
                Text(L10n.text("activation_hint", selectedLanguage))
                    .font(.callout)
                    .foregroundStyle(Color(hex: "FFF0C9"))
                TextField(L10n.text("serial_placeholder", selectedLanguage), text: $serialInput)
                    .textInputAutocapitalization(.characters)
                    .keyboardType(.numberPad)
                    .fieldStyle()
                TextField(L10n.text("code_placeholder", selectedLanguage), text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .fieldStyle()
                HStack(spacing: 10) {
                    Button(L10n.text("activate", selectedLanguage)) {
                        Task { await cloud.activate(serial: serialInput, code: codeInput, language: selectedLanguage) }
                    }
                    .buttonStyle(ActionButtonStyle(color: Color(hex: "008840")))
                    Button(L10n.text("restore", selectedLanguage)) {
                        Task { await cloud.restoreActivation(language: selectedLanguage) }
                    }
                    .buttonStyle(ActionButtonStyle(color: Color(hex: "17354A")))
                }
                if !cloud.statusMessage.isEmpty {
                    Text(cloud.statusMessage)
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: "FFD060"))
                }
            }
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
                Text(cloud.isActivated ? training.statusText(language: selectedLanguage) : L10n.text("activation_required", selectedLanguage))
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(Color(hex: "F5E7CF"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)

                Text(training.countdownText)
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
                        Task { await training.start(isActivated: cloud.isActivated) }
                    } label: {
                        Text(L10n.text("start", selectedLanguage))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillTrainingButtonStyle(color: Color(hex: "F15A13")))
                    .disabled(training.isBusy || !bluetooth.isConnected || !cloud.isActivated)
                    .opacity(training.isBusy || !bluetooth.isConnected || !cloud.isActivated ? 0.58 : 1.0)

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
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
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

            Text("\(local("最佳30秒", "Best 30s")) \(best30Value()) \(local("次", "hits")) · \(local("最佳60秒", "Best 60s")) \(best60Value()) \(local("次", "hits")) · \(local("累计", "Total")) \(totalHitsValue()) \(local("次", "hits"))")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "CFE9DC"))
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(training.latestReport == nil ? local("暂无最新战报，完成一轮训练后这里会展示你的核心成绩。", "No latest report yet. Finish a session to show your result here.") : training.latestReport?.coachMessage ?? "")
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
            Text(local("最新报告", "Latest Report"))
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
            Text(local("战报", "Report"))
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color(hex: "1A1B18"))
                .padding(.horizontal, 40)
                .padding(.vertical, 8)
                .background(LinearGradient(colors: [Color(hex: "E6FAFF"), Color(hex: "FF9A30")], startPoint: .leading, endPoint: .trailing), in: Capsule())
            Text(local("等待首份训练战报", "Waiting for your first training report"))
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Color(hex: "FFF6E5"))
            Text(local("暂无训练报告。", "No training report yet."))
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
                Text(report.coachMessage)
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
            pageHeading(title: local("成就徽章", "Achievement Badges"), subtitle: local("解锁 24 个训练成就徽章，记录你的成长。", "Unlock 24 training badges and track progress."))

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(local("已解锁 \(unlockedCount) / \(items.count)", "Unlocked \(unlockedCount) / \(items.count)"))
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
                    Text("\(local("已解锁", "Unlocked")) \(unlockedCount) / \(items.count)")
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

            Text(local("训练记录", "Training Records"))
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
            pageHeading(title: local("榜单排名", "Rankings"), subtitle: local("按 30 秒历史最佳成绩排名", "Ranked by best 30-second history."))
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
                    Text(local("当前尚未上榜。", "Not ranked yet."))
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
            Text("\(entry?.bestHits ?? 0) \(local("次", "hits"))")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(tint)
            Text("\(local("段位", "Tier")) \(tierLabel(entry?.tierKey, fallbackLevel: entry?.tierLevel ?? 1))")
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
                Text("\(boardShortTitle(cloud.selectedBoard)) \(entry.bestHits) \(local("次", "hits")) | \(local("段位", "Tier")) \(tierLabel(entry.tierKey, fallbackLevel: entry.tierLevel ?? 1))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "D8C08A"))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(tierLabel(entry.tierKey, fallbackLevel: entry.tierLevel ?? 1))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color(hex: "CFE9DC"))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(hex: "17384B"), in: Capsule())
                Text(entry.serialMasked ?? "********")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color(hex: "FFF6E5"))
            }
        }
    }

    private var profilePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading(title: local("个人中心", "Profile Center"), subtitle: local("查看你的段位、训练统计与最近获得的徽章", "Review tier, stats, and recent badges."))

            if !cloud.isActivated {
                activationCard
            }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(local("拳击训练档案", "Boxing Training Profile"))
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Color(hex: "1A1B18"))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [Color(hex: "FFF0A6"), Color(hex: "D99A1E")], startPoint: .leading, endPoint: .trailing), in: Capsule())

                    HStack(spacing: 18) {
                        ZStack {
                            Circle().fill(Color(hex: cloud.profile?.avatarColor ?? profileColor))
                            Circle().stroke(Color(hex: "D8FFF0"), lineWidth: 4)
                            Text(avatarInitial())
                                .font(.system(size: 42, weight: .black))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 104, height: 104)

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
                            Text("\(local("用户ID", "User ID")): \(cloud.profile?.serialMasked ?? cloud.activationState?.serial ?? "********\(profileSuffix())") | \(local("语言", "Language")): \(selectedLanguage.displayName)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: "D8C08A"))
                                .lineLimit(2)
                                .minimumScaleFactor(0.68)
                            Text("\(tierLabel(cloud.tier?.key, fallbackLevel: cloud.tier?.level ?? training.trainingLevel))  Lv.\(cloud.tier?.level ?? training.trainingLevel)  |  \(local("下一段位", "Next")): \(tierLabel(cloud.tier?.nextKey, fallbackLevel: (cloud.tier?.level ?? training.trainingLevel) + 1))")
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

                Text(local("最近徽章：继续训练以解锁首枚徽章", "Recent badge: keep training to unlock your first badge"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "C9A56B"))

                Text(cloud.statusMessage.isEmpty ? "leaderboard_ready" : cloud.statusMessage)
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
                        showingEditProfile = true
                    }
                    .buttonStyle(CompactOutlineButtonStyle())

                    Button(local("刷新云端", "Refresh Cloud")) {
                        Task { await cloud.bootstrap(language: selectedLanguage) }
                    }
                    .buttonStyle(PillTrainingButtonStyle(color: Color(hex: "E07010")))
                }

                Button {
                    showingSettings = true
                } label: {
                    Text(local("联系我们", "Contact Us"))
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
            VStack(spacing: 16) {
                TextField(L10n.text("nickname", selectedLanguage), text: $profileName)
                    .fieldStyle()
                TextField("#145DA0", text: $profileColor)
                    .fieldStyle()
                Button(L10n.text("save", selectedLanguage)) {
                    Task {
                        await cloud.updateProfile(nickname: profileName, language: selectedLanguage, avatarColor: profileColor)
                        showingEditProfile = false
                    }
                }
                .buttonStyle(ActionButtonStyle(color: Color(hex: "008840")))
                Spacer()
            }
            .padding(20)
            .background(Color(hex: "040C08").ignoresSafeArea())
            .navigationTitle(L10n.text("edit_profile", selectedLanguage))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.text("done", selectedLanguage)) { showingEditProfile = false }
                }
            }
        }
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
            footer: "Smart sensor ball"
        )
        shareItems = [image, report.coachMessage]
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
            footer: "Smart sensor ball"
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
            footer: "Smart sensor ball"
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

    private func local(_ chinese: String, _ english: String) -> String {
        selectedLanguage == .chinese ? chinese : english
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
        cloud.statistics?.longestStreak ?? max(training.currentStreak, training.reportHistory.map(\.streak).max() ?? 0)
    }

    private func activeDaysValue() -> Int {
        cloud.statistics?.activeDays ?? 0
    }

    private func globalBestValue() -> Int {
        cloud.profile?.bestScoreCached ?? cloud.statistics?.personalBestHits ?? max(best30Value(), best60Value())
    }

    private func profileStatsLines() -> [String] {
        [
            local("总训练次数: \(totalSessionsValue()) | 总击打次数: \(totalHitsValue())", "Sessions: \(totalSessionsValue()) | Total hits: \(totalHitsValue())"),
            local("30 秒最佳: \(best30Value()) | 60 秒最佳: \(best60Value())", "Best 30s: \(best30Value()) | Best 60s: \(best60Value())"),
            local("最佳 3 秒爆发: \(bestBurstValue()) | 最长连续: \(longestStreakValue())", "Best 3s burst: \(bestBurstValue()) | Longest streak: \(longestStreakValue())"),
            local("活跃天数: \(activeDaysValue()) | 全局最佳: \(globalBestValue())", "Active days: \(activeDaysValue()) | Global best: \(globalBestValue())")
        ]
    }

    private func profileSuffix() -> String {
        let serial = cloud.profile?.serialMasked ?? cloud.activationState?.serial ?? cloud.installId
        let digits = serial.filter(\.isNumber)
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
        case "beginner": return local("拳坛新丁", "New Blood")
        case "prospect": return local("热血新秀", "Rising Rookie")
        case "contender": return local("擂台争锋者", "Arena Contender")
        case "striker": return local("铁拳出击手", "Iron Fist Striker")
        case "challenger": return local("风暴挑战者", "Storm Challenger")
        case "elite": return local("荣耀精英", "Glory Elite")
        case "master": return local("宗师", "Grand Master")
        case "legend": return local("不朽传奇", "Immortal Legend")
        case "champion": return local("至尊拳王", "Supreme Champion")
        default: return local("拳坛新丁", "New Blood")
        }
    }

    private func nextTierLine() -> String {
        let nextKey = cloud.tier?.nextKey ?? "prospect"
        let target = cloud.tier?.nextHits ?? 40
        let current = cloud.tier?.bestHits ?? best30Value()
        let remaining = max(0, target - current)
        return local("距离 \(tierLabel(nextKey, fallbackLevel: 2)) 还差 \(remaining) 击", "\(remaining) hits to \(tierLabel(nextKey, fallbackLevel: 2))")
    }

    private func boardShortTitle(_ board: LeaderboardBoard) -> String {
        switch board {
        case .best30:
            return local("30秒榜", "30s")
        case .best60:
            return local("60秒榜", "60s")
        case .totalHits:
            return local("累计榜", "Total")
        case .longestStreak:
            return local("连续榜", "Streak")
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
            AchievementGroup(title: local("训练里程碑", "Training Milestones"), items: [
                item("first_training", goal: 1, metric: "sessions"),
                item("sessions_5", goal: 5, metric: "sessions"),
                item("sessions_15", goal: 15, metric: "sessions"),
                item("sessions_30", goal: 30, metric: "sessions")
            ]),
            AchievementGroup(title: local("累计击打", "Total Hits"), items: [
                item("hits_100", goal: 100, metric: "total_hits"),
                item("hits_500", goal: 500, metric: "total_hits"),
                item("hits_1000", goal: 1000, metric: "total_hits"),
                item("hits_5000", goal: 5000, metric: "total_hits")
            ]),
            AchievementGroup(title: local("30 秒成绩徽章", "30s Badges"), items: [
                item("best_30_40", goal: 40, metric: "best_30"),
                item("best_30_60", goal: 60, metric: "best_30"),
                item("best_30_80", goal: 80, metric: "best_30"),
                item("best_30_100", goal: 100, metric: "best_30")
            ]),
            AchievementGroup(title: local("60 秒成绩徽章", "60s Badges"), items: [
                item("best_60_90", goal: 90, metric: "best_60"),
                item("best_60_120", goal: 120, metric: "best_60"),
                item("best_60_150", goal: 150, metric: "best_60"),
                item("best_60_180", goal: 180, metric: "best_60")
            ]),
            AchievementGroup(title: local("爆发能力", "Burst Power"), items: [
                item("burst_6", goal: 6, metric: "burst"),
                item("burst_10", goal: 10, metric: "burst"),
                item("burst_12", goal: 12, metric: "burst"),
                item("burst_15", goal: 15, metric: "burst")
            ]),
            AchievementGroup(title: local("坚持打卡", "Training Streak"), items: [
                item("streak_3", goal: 3, metric: "streak"),
                item("streak_7", goal: 7, metric: "streak"),
                item("streak_14", goal: 14, metric: "streak"),
                item("streak_30", goal: 30, metric: "streak")
            ])
        ]
    }

    private func achievementName(_ key: String) -> String {
        switch key {
        case "first_training": return local("初次登台", "First Session")
        case "sessions_5": return local("持续热身", "Warm Streak")
        case "sessions_15": return local("训练常客", "Regular")
        case "sessions_30": return local("擂台老兵", "Veteran")
        case "hits_100": return local("百拳试锋", "100 Hits")
        case "hits_500": return local("五百重击", "500 Hits")
        case "hits_1000": return local("千拳风暴", "1,000 Hits")
        case "hits_5000": return local("万击宗师", "5,000 Hits")
        case "best_30_40": return local("30秒40击", "30s 40")
        case "best_30_60": return local("30秒60击", "30s 60")
        case "best_30_80": return local("30秒80击", "30s 80")
        case "best_30_100": return local("30秒100击", "30s 100")
        case "best_60_90": return local("60秒90击", "60s 90")
        case "best_60_120": return local("60秒120击", "60s 120")
        case "best_60_150": return local("60秒150击", "60s 150")
        case "best_60_180": return local("60秒180击", "60s 180")
        case "burst_6": return local("爆发新星", "Burst 6")
        case "burst_10": return local("爆发高手", "Burst 10")
        case "burst_12": return local("爆发强者", "Burst 12")
        case "burst_15": return local("爆发王者", "Burst 15")
        case "streak_3": return local("连续3天", "3-Day Streak")
        case "streak_7": return local("连续7天", "7-Day Streak")
        case "streak_14": return local("连续14天", "14-Day Streak")
        case "streak_30": return local("连续30天", "30-Day Streak")
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
        let name = cloud.profile?.nickname ?? "S"
        return String(name.prefix(1)).uppercased()
    }

    private func remainingText() -> String {
        let seconds = Double(max(0, training.remainingMillis)) / 1_000.0
        let value = String(format: "%.1f", seconds)
        return selectedLanguage == .chinese ? "剩余 \(value) 秒" : "Remaining \(value)s"
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

private struct BatteryBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "battery.25")
            Text(text)
                .font(.caption.bold())
        }
        .foregroundStyle(Color(hex: "D8D0BE"))
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
