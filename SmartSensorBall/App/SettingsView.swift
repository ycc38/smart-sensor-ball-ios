import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bluetooth: SensorBallBluetoothManager
    @Environment(\.dismiss) private var dismiss
    @Binding var language: AppLanguage
    @State private var showingLegal: LegalDocument?
    @State private var showingDeveloperInfo = false
    @State private var lightBrightnessDraft = 20.0
    @AppStorage("leaderboard_upload_consent_v1") private var leaderboardUploadConsent = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    bluetoothCard
                    lightControlCard
                    languageCard
                    privacyCard
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
            .sheet(isPresented: $showingDeveloperInfo) {
                DeveloperInfoView(language: language)
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            lightBrightnessDraft = Double(bluetooth.lightBrightness)
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

                Label(L10n.text("bluetooth_wake_hint", language), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color(hex: "FFD060"))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "241A08"), in: RoundedRectangle(cornerRadius: 8))

                Text(bluetooth.statusText(language: language))
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
                    bluetoothMetric(
                        label: L10n.text("battery", language),
                        value: bluetooth.telemetry?.batteryText(language: language) ?? "--",
                        systemImage: bluetooth.telemetry?.isCharging == true ? "bolt.fill" : nil
                    )
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

    private var lightControlCard: some View {
        SettingsCard(stroke: Color(hex: "FFD060")) {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionHeader(
                    title: L10n.text("light_control", language),
                    subtitle: L10n.text("light_control_hint", language),
                    color: Color(hex: "FFE58A")
                )

                Toggle(
                    isOn: Binding(
                        get: { bluetooth.isLightOn },
                        set: { enabled in
                            _ = bluetooth.setLightEnabled(enabled)
                        }
                    )
                ) {
                    Label(
                        L10n.text(bluetooth.isLightOn ? "light_on" : "light_off", language),
                        systemImage: bluetooth.isLightOn ? "lightbulb.fill" : "lightbulb"
                    )
                    .font(.headline)
                    .foregroundStyle(Color(hex: "FFF6E5"))
                }
                .tint(Color(hex: "00C968"))
                .disabled(!bluetooth.isConnected)

                if bluetooth.isLightOn {
                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.text("light_brightness", language))
                                .font(.subheadline.bold())
                                .foregroundStyle(Color(hex: "DFFFF0"))
                            Spacer()
                            Text("\(Int(lightBrightnessDraft.rounded()))%")
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(Color(hex: "FFD060"))
                        }

                        Slider(
                            value: $lightBrightnessDraft,
                            in: 0...100,
                            step: 1,
                            onEditingChanged: { isEditing in
                                if !isEditing {
                                    _ = bluetooth.setLightBrightness(Int(lightBrightnessDraft.rounded()))
                                }
                            }
                        )
                        .tint(Color(hex: "FFD060"))
                    }
                } else if !bluetooth.isConnected {
                    Text(L10n.text("light_connect_first", language))
                        .font(.caption)
                        .foregroundStyle(Color(hex: "B9F8D0"))
                }
            }
        }
    }

    private var languageCard: some View {
        SettingsCard(stroke: Color(hex: "2A6A8F")) {
            VStack(alignment: .leading, spacing: 12) {
                settingsSectionHeader(title: L10n.text("language", language), subtitle: L10n.text("language_helper", language), color: Color(hex: "8FD8FF"))
                // An explicit list instead of an inline Picker: outside a List/Form that renders as a wheel
                // with system-colored text, which was invisible on this dark card in Light Mode.
                VStack(spacing: 8) {
                    ForEach(AppLanguage.allCases) { item in
                        Button {
                            language = item
                            item.save()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: language == item ? "largecircle.fill.circle" : "circle")
                                    .font(.headline)
                                    .foregroundStyle(language == item ? Color(hex: "80FFB0") : Color(hex: "8FEFBC"))
                                Text(item.displayName)
                                    .font(.headline)
                                    .foregroundStyle(Color(hex: "FFF6E5"))
                                Spacer()
                            }
                            .padding(12)
                            .background(language == item ? Color(hex: "1B6F48") : Color(hex: "0A241A"), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityAddTraits(language == item ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var privacyCard: some View {
        SettingsCard(stroke: Color(hex: "00C9A7")) {
            VStack(alignment: .leading, spacing: 12) {
                settingsSectionHeader(
                    title: L10n.text("leaderboard_upload_setting", language),
                    subtitle: L10n.text("leaderboard_upload_setting_hint", language),
                    color: Color(hex: "8FFFE4")
                )
                Toggle(isOn: $leaderboardUploadConsent) {
                    Text(L10n.text("leaderboard_upload_toggle", language))
                        .font(.headline)
                        .foregroundStyle(Color(hex: "FFF6E5"))
                }
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "00A85A")))
                Text(leaderboardUploadConsent ? L10n.text("leaderboard_upload_enabled", language) : L10n.text("leaderboard_upload_disabled", language))
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: "DFFFF0"))
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

    private func bluetoothMetric(label: String, value: String, systemImage: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(Color(hex: "DFFFF0"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                if !value.isEmpty {
                    Text(value)
                }
            }
            .font(.headline.bold())
            .foregroundStyle(Color(hex: "FFD060"))
            .frame(minHeight: 22)
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
        SettingsActionLabel(configuration: configuration, color: color)
    }
}

/// Reads isEnabled from the environment so disabled buttons are dimmed (0.42, like Android's setBluetoothButtonEnabled).
private struct SettingsActionLabel: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(color.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? 1.0 : 0.42)
    }
}
