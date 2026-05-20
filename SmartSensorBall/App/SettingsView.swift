import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bluetooth: SensorBallBluetoothManager
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var soundEffects: SoundEffectManager
    @Environment(\.dismiss) private var dismiss
    @Binding var language: AppLanguage
    @State private var showingLegal: LegalDocument?
    @State private var showingDeveloperInfo = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    bluetoothCard
                    soundEffectCard
                    languageCard
                    developerCard
                }
                .padding(18)
            }
            .background(Color(hex: "040C08").ignoresSafeArea())
            .navigationTitle(L10n.text("settings_title", language))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.text("done", language)) { dismiss() }
                }
            }
            .sheet(item: $showingLegal) { document in
                LegalDocumentView(document: document, language: language)
            }
            .alert(L10n.text("developer_info", language), isPresented: $showingDeveloperInfo) {
                Button(L10n.text("done", language), role: .cancel) {}
            } message: {
                Text("GlowPeak / Smart sensor ball\nsupport: 869501402@qq.com\nVersion \(cloud.appVersion)")
            }
        }
        .navigationViewStyle(.stack)
        .onDisappear {
            soundEffects.stopPreview()
        }
    }

    private var bluetoothCard: some View {
        SettingsCard(stroke: Color(hex: "00FF88")) {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionHeader(
                    title: L10n.text("bluetooth_connection", language),
                    subtitle: L10n.text("bluetooth_hint", language),
                    color: Color(hex: "80FFB0")
                )

                Text(bluetooth.statusText)
                    .font(.callout)
                    .foregroundStyle(Color(hex: "B9F8D0"))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "082018"), in: RoundedRectangle(cornerRadius: 12))

                if !bluetooth.lastScanDebugText.isEmpty {
                    Text(bluetooth.lastScanDebugText)
                        .font(.caption)
                        .foregroundStyle(Color(hex: "8FEFBC"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button(L10n.text("scan", language)) { bluetooth.startScan() }
                        .buttonStyle(SettingsActionStyle(color: Color(hex: "008840")))
                        .disabled(bluetooth.isConnected)
                    Button(L10n.text("connect", language)) { bluetooth.connectSelected() }
                        .buttonStyle(SettingsActionStyle(color: Color(hex: "16384A")))
                        .disabled(bluetooth.isConnected || bluetooth.selectedDevice == nil)
                    Button(L10n.text("disconnect", language)) { bluetooth.disconnect() }
                        .buttonStyle(SettingsActionStyle(color: Color(hex: "5B2D2D")))
                        .disabled(!bluetooth.isConnected)
                }

                HStack(spacing: 10) {
                    bluetoothMetric(label: L10n.text("battery", language), value: bluetooth.telemetry?.batteryText ?? "--")
                    bluetoothMetric(label: L10n.text("punch_count", language), value: "\(bluetooth.displayHitCount)")
                    bluetoothMetric(label: L10n.text("peak_force", language), value: "\(bluetooth.peakForce)")
                }

                VStack(spacing: 8) {
                    if bluetooth.devices.isEmpty {
                        Text(L10n.text("no_devices", language))
                            .foregroundStyle(Color(hex: "8FEFBC"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        ForEach(bluetooth.devices) { device in
                            Button {
                                bluetooth.selectedDevice = device
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(device.name)
                                            .font(.headline)
                                        Text(device.advertisedServices.isEmpty ? device.identifier.uuidString : device.advertisedServices.joined(separator: ", "))
                                            .font(.caption)
                                    }
                                    Spacer()
                                    Text("\(device.rssi)")
                                        .font(.caption.bold())
                                    if bluetooth.selectedDevice?.id == device.id {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(bluetooth.selectedDevice?.id == device.id ? Color(hex: "1B6F48") : Color(hex: "0A241A"), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }
        }
    }

    private var soundEffectCard: some View {
        SettingsCard(stroke: Color(hex: "C084FC")) {
            VStack(alignment: .leading, spacing: 12) {
                settingsSectionHeader(
                    title: L10n.text("cloud_sound_effects", language),
                    subtitle: L10n.text("cloud_sound_effects_hint", language),
                    color: Color(hex: "E7D7FF")
                )
                Button {
                    Task { await cloud.refreshSoundEffects(language: language) }
                } label: {
                    Label(L10n.text("refresh_effects", language), systemImage: "arrow.clockwise")
                }
                .buttonStyle(SettingsActionStyle(color: Color(hex: "17354A")))

                ForEach(cloud.soundEffects) { effect in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(effect.name(language: language))
                                .font(.headline)
                                .foregroundStyle(Color(hex: "FFF6E5"))
                            Text(effect.detail(language: language))
                                .font(.caption)
                                .foregroundStyle(Color(hex: "DFFFF0"))
                        }
                        Spacer()
                        Button {
                            soundEffects.preview(effect, language: language)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(SettingsIconStyle())
                        Button {
                            soundEffects.apply(effect, language: language)
                        } label: {
                            Image(systemName: soundEffects.selectedEffectId == effect.id ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(SettingsIconStyle())
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                if !soundEffects.previewStatus.isEmpty {
                    Text(soundEffects.previewStatus)
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: "E7D7FF"))
                }
            }
        }
    }

    private var languageCard: some View {
        SettingsCard(stroke: Color(hex: "2A6A8F")) {
            VStack(alignment: .leading, spacing: 12) {
                settingsSectionHeader(title: L10n.text("language", language), subtitle: L10n.text("language_helper", language), color: Color(hex: "8FD8FF"))
                Picker(L10n.text("language", language), selection: $language) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: language) { newValue in
                    newValue.save()
                }
            }
        }
    }

    private var developerCard: some View {
        SettingsCard(stroke: Color(hex: "FFD060")) {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionHeader(title: L10n.text("developer_info", language), subtitle: L10n.text("developer_info_hint", language), color: Color(hex: "FFD060"))
                HStack(spacing: 10) {
                    Button(L10n.text("developer_info", language)) { showingDeveloperInfo = true }
                        .buttonStyle(SettingsActionStyle(color: Color(hex: "8A5A12")))
                    Button(L10n.text("privacy_policy", language)) { showingLegal = .privacy }
                        .buttonStyle(SettingsActionStyle(color: Color(hex: "3A2A16")))
                }
                Button(L10n.text("user_agreement", language)) { showingLegal = .agreement }
                    .buttonStyle(SettingsActionStyle(color: Color(hex: "3A2A16")))
            }
        }
    }

    private func settingsSectionHeader(title: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Color(hex: "D7FDE8"))
        }
    }

    private func bluetoothMetric(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(Color(hex: "DFFFF0"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(Color(hex: "FFD060"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SettingsCard<Content: View>: View {
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
            .background(Color(hex: "07140F"), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(stroke, lineWidth: 1))
    }
}

private struct SettingsActionStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(color.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingsIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(hex: "E7D7FF"))
            .frame(width: 38, height: 38)
            .background(Color.white.opacity(configuration.isPressed ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
