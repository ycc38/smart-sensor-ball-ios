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
                    .environmentObject(soundEffects)
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
                    await cloud.refreshSoundEffects(language: selectedLanguage)
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
                Task { await cloud.upload(report: report, language: selectedLanguage) }
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
        VStack(spacing: 16) {
            VStack(spacing: 12) {
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
                    .font(.system(size: 80, weight: .black))
                    .foregroundStyle(Color(hex: "FFF0E0"))

                Text(remainingText())
                    .font(.system(size: 16, weight: .black))
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
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("mode", selectedLanguage))
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color(hex: "FFF6E5"))
                modeList
            }

            if let report = training.latestReport {
                reportCard(report)
            }
        }
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
        return VStack(spacing: 14) {
            SurfaceCard(stroke: Color(hex: "FFD060")) {
                VStack(alignment: .leading, spacing: 8) {
                    Badge(text: L10n.text("current_tier", selectedLanguage), color: Color(hex: "FFD060"), textColor: Color(hex: "140800"))
                    Text(tierName(cloud.tier?.key, fallbackLevel: cloud.tier?.level ?? training.trainingLevel))
                        .font(.title2.weight(.black))
                        .foregroundStyle(Color(hex: "FFF6E5"))
                    Text("\(items.filter(\.unlocked).count)/\(items.count) \(L10n.text("badges_unlocked", selectedLanguage))")
                        .font(.callout)
                        .foregroundStyle(Color(hex: "FFF0C9"))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(items.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }) { item in
                    achievementCard(item)
                }
            }
            Button {
                shareAchievements(items: items)
            } label: {
                Label(L10n.text("share_achievements", selectedLanguage), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ActionButtonStyle(color: Color(hex: "8A5A12")))
        }
    }

    private func achievementCard(_ item: CloudAchievementItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(achievementImageName(item.key))
                .resizable()
                .scaledToFit()
                .frame(height: 72)
                .frame(maxWidth: .infinity)
                .opacity(item.unlocked ? 1 : 0.45)
            Text(achievementName(item.key))
                .font(.headline)
                .foregroundStyle(Color(hex: "FFF6E5"))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            ProgressView(value: Double(item.progress), total: Double(max(1, item.goal)))
                .tint(item.unlocked ? Color(hex: "FFD060") : Color(hex: "B88A54"))
            Text("\(item.progress)/\(item.goal)")
                .font(.caption.bold())
                .foregroundStyle(item.unlocked ? Color(hex: "FFD060") : Color(hex: "CAA26A"))
        }
        .padding(13)
        .background(Color(hex: item.unlocked ? "11242F" : "0C1822"), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(item.unlocked ? Color(hex: "FFD060") : Color(hex: "233A4B"), lineWidth: 1))
    }

    private var leaderboardPage: some View {
        VStack(spacing: 14) {
            SurfaceCard(stroke: Color(hex: "FF9A30")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("leaderboard_title", selectedLanguage))
                        .font(.title2.weight(.black))
                        .foregroundStyle(Color(hex: "FFF6E5"))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(LeaderboardBoard.allCases) { board in
                            Button {
                                cloud.selectedBoard = board
                                Task { await cloud.refreshLeaderboard(language: selectedLanguage) }
                            } label: {
                                Text(board.title(language: selectedLanguage))
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(cloud.selectedBoard == board ? Color(hex: "140800") : Color(hex: "FFF0C9"))
                                    .background(cloud.selectedBoard == board ? Color(hex: "FFB347") : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    Button {
                        Task { await cloud.refreshLeaderboard(language: selectedLanguage) }
                    } label: {
                        Label(L10n.text("refresh", selectedLanguage), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ActionButtonStyle(color: Color(hex: "17354A")))
                }
            }

            let top = cloud.leaderboard?.top ?? []
            if top.isEmpty {
                emptyState(title: L10n.text("leaderboard_empty_title", selectedLanguage), body: L10n.text("leaderboard_empty", selectedLanguage))
            } else {
                VStack(spacing: 12) {
                    ForEach(top.prefix(3)) { entry in
                        podiumRow(entry)
                    }
                    ForEach(top.dropFirst(3)) { entry in
                        leaderboardRow(entry)
                    }
                    if let me = cloud.leaderboard?.me {
                        SurfaceCard(stroke: Color(hex: "FFD060")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Badge(text: L10n.text("leaderboard_me", selectedLanguage), color: Color(hex: "FFD060"), textColor: Color(hex: "140800"))
                                leaderboardRowContent(me)
                            }
                        }
                    }
                    Button {
                        shareLeaderboard()
                    } label: {
                        Label(L10n.text("share_leaderboard", selectedLanguage), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ActionButtonStyle(color: Color(hex: "8A5A12")))
                }
            }
        }
    }

    private func podiumRow(_ entry: CloudLeaderboardEntry) -> some View {
        SurfaceCard(stroke: Color(hex: entry.rank == 1 ? "FFD060" : "B88A54")) {
            leaderboardRowContent(entry)
        }
    }

    private func leaderboardRow(_ entry: CloudLeaderboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            leaderboardRowContent(entry)
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func leaderboardRowContent(_ entry: CloudLeaderboardEntry) -> some View {
        HStack {
            Text("#\(entry.rank)")
                .font(.title3.weight(.black))
                .foregroundStyle(Color(hex: "FFD060"))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.nickname)
                    .font(.headline.bold())
                    .foregroundStyle(Color(hex: "FFF6E5"))
                Text(tierName(entry.tierKey, fallbackLevel: entry.tierLevel ?? 1))
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: "DFFFF0"))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(leaderboardPrimary(entry))
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color(hex: "80FFB0"))
                Text(String(format: "%.2f/s", entry.averageFrequency))
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: "FFF0C9"))
            }
        }
    }

    private var profilePage: some View {
        VStack(spacing: 14) {
            if !cloud.isActivated {
                activationCard
            }
            SurfaceCard(stroke: Color(hex: "8FD8FF")) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color(hex: cloud.profile?.avatarColor ?? profileColor))
                        Text(avatarInitial())
                            .font(.title.weight(.black))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 74, height: 74)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(cloud.profile?.nickname ?? L10n.text("guest_trainer", selectedLanguage))
                            .font(.title3.weight(.black))
                            .foregroundStyle(Color(hex: "FFF6E5"))
                        Text(cloud.profile?.serialMasked ?? cloud.activationState?.serial ?? L10n.text("not_activated", selectedLanguage))
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: "DFFFF0"))
                        Text(tierName(cloud.tier?.key, fallbackLevel: cloud.profile?.currentTier ?? training.trainingLevel))
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: "FFD060"))
                    }
                    Spacer()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(title: L10n.text("total_sessions", selectedLanguage), value: "\(cloud.statistics?.totalSessions ?? training.reportHistory.count)")
                MetricTile(title: L10n.text("total_hits", selectedLanguage), value: "\(cloud.statistics?.totalHits ?? training.reportHistory.reduce(0) { $0 + $1.totalHits })")
                MetricTile(title: L10n.text("best_30", selectedLanguage), value: "\(cloud.statistics?.best30Hits ?? localBest(seconds: 30))")
                MetricTile(title: L10n.text("streak", selectedLanguage), value: "\(cloud.statistics?.currentStreak ?? training.currentStreak)")
            }
            HStack(spacing: 10) {
                Button(L10n.text("edit_profile", selectedLanguage)) {
                    profileName = cloud.profile?.nickname ?? ""
                    profileColor = cloud.profile?.avatarColor ?? "#145DA0"
                    showingEditProfile = true
                }
                .buttonStyle(ActionButtonStyle(color: Color(hex: "17354A")))
                Button(L10n.text("refresh", selectedLanguage)) {
                    Task { await cloud.bootstrap(language: selectedLanguage) }
                }
                .buttonStyle(ActionButtonStyle(color: Color(hex: "008840")))
            }
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

    private func achievementName(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
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
        guard let key = key, !key.isEmpty else {
            return "Lv.\(fallbackLevel)"
        }
        return key.replacingOccurrences(of: "_", with: " ").capitalized + " Lv.\(fallbackLevel)"
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
