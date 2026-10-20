import Combine
import CoreBluetooth
import Foundation

struct SensorBallDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let identifier: UUID
    let rssi: Int
    let advertisedServices: [String]
    fileprivate let peripheral: CBPeripheral

    static func == (lhs: SensorBallDevice, rhs: SensorBallDevice) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

struct SensorBallTelemetry: Equatable {
    let packetIndex: Int
    let batteryRaw: Int
    let hitCount: Int
    let chargingFlagRaw: Int
    let forceLow: Int
    let forceHigh: Int
    let forceN: Int

    var peak: Int { forceN }

    var batteryLevel: Int? {
        switch batteryRaw {
        case 0...100: return batteryRaw
        case 102: return 100
        default: return nil
        }
    }

    var isCharging: Bool {
        batteryRaw == 101 || (batteryLevel != nil && chargingFlagRaw == 1)
    }

    var batteryText: String {
        batteryLevel.map { "\($0)%" } ?? (isCharging ? "" : "--")
    }

    func batteryText(language: AppLanguage) -> String {
        if batteryRaw == 102 {
            return L10n.text("battery_full", language)
        }
        return batteryText
    }
}

enum SensorBallBluetoothStatus: Equatable {
    case disconnected
    case notPoweredOn
    case poweredOff
    case unauthorized
    case unavailable
    case ready
    case scanning
    case scanningLastDevice
    case lastDeviceNotFound
    case devicesFound(Int)
    case autoSelected(String)
    case selectDeviceFirst
    case connecting(String)
    case autoConnecting(String)
    case reconnecting(String)
    case discoveringServices
    case packetReceived(Int)
    case gyroscopeEnabled
    case gyroscopeDisabled
    case lightEnabled
    case lightDisabled
    case lightNeedsConnection
    case writeUnavailable
    case reconnectScheduled(delaySeconds: Double, attempt: Int, maxAttempts: Int)
    case reconnectPaused
    case reconnectedDuringTraining(String)

    func text(language: AppLanguage) -> String {
        switch self {
        case .disconnected:
            return language.localized("蓝牙已断开", "Bluetooth disconnected", fr: "Bluetooth déconnecté", th: "ตัดการเชื่อมต่อบลูทูธแล้ว")
        case .notPoweredOn:
            return language.localized("蓝牙未开启", "Bluetooth is not powered on", fr: "Le Bluetooth n'est pas activé", th: "บลูทูธยังไม่ได้เปิด")
        case .poweredOff:
            return language.localized("蓝牙已关闭", "Bluetooth is off", fr: "Le Bluetooth est désactivé", th: "บลูทูธปิดอยู่")
        case .unauthorized:
            return language.localized(
                "未获得蓝牙权限，无法连接设备。",
                "Bluetooth permission is required to connect.",
                fr: "L'autorisation Bluetooth est nécessaire pour se connecter.",
                th: "ต้องอนุญาตบลูทูธเพื่อเชื่อมต่อ"
            )
        case .unavailable:
            return language.localized("蓝牙不可用", "Bluetooth unavailable", fr: "Bluetooth indisponible", th: "บลูทูธไม่พร้อมใช้งาน")
        case .ready:
            return language.localized("蓝牙已就绪", "Bluetooth ready", fr: "Bluetooth prêt", th: "บลูทูธพร้อมใช้งาน")
        case .scanning:
            return language.localized(
                "正在扫描 SENBALL# 设备...",
                "Scanning SENBALL# devices...",
                fr: "Recherche d'appareils SENBALL#...",
                th: "กำลังสแกนอุปกรณ์ SENBALL#..."
            )
        case .scanningLastDevice:
            return language.localized(
                "正在搜索上次连接的设备...",
                "Scanning for the last connected device...",
                fr: "Recherche du dernier appareil connecté...",
                th: "กำลังค้นหาอุปกรณ์ที่เชื่อมต่อล่าสุด..."
            )
        case .lastDeviceNotFound:
            return language.localized(
                "未找到上次连接的设备，请唤醒设备后重新扫描。",
                "Last connected device not found. Wake the device and scan again.",
                fr: "Dernier appareil connecté introuvable. Réveillez l'appareil et relancez la recherche.",
                th: "ไม่พบอุปกรณ์ที่เชื่อมต่อล่าสุด โปรดปลุกอุปกรณ์แล้วสแกนอีกครั้ง"
            )
        case .devicesFound(let count):
            return language.localized(
                "已扫描到 \(count) 个设备，请选择设备",
                "\(count) devices found. Select one.",
                fr: "\(count) appareils trouvés. Sélectionnez-en un.",
                th: "พบอุปกรณ์ \(count) เครื่อง โปรดเลือกอุปกรณ์"
            )
        case .autoSelected(let name):
            return language.localized("已自动选择 \(name)", "Auto-selected \(name)", fr: "\(name) sélectionné automatiquement", th: "เลือก \(name) โดยอัตโนมัติ")
        case .selectDeviceFirst:
            return language.localized("请先扫描并选择设备", "Scan and select a device first", fr: "Scannez puis sélectionnez un appareil", th: "โปรดสแกนและเลือกอุปกรณ์ก่อน")
        case .connecting(let name):
            return language.localized("正在连接 \(name)...", "Connecting \(name)...", fr: "Connexion à \(name)...", th: "กำลังเชื่อมต่อ \(name)...")
        case .autoConnecting(let name):
            return language.localized(
                "正在自动连接上次设备 \(name)...",
                "Auto-connecting last device \(name)...",
                fr: "Connexion automatique au dernier appareil \(name)...",
                th: "กำลังเชื่อมต่ออุปกรณ์ล่าสุด \(name) อัตโนมัติ..."
            )
        case .reconnecting(let name):
            return language.localized("正在重新连接 \(name)...", "Reconnecting \(name)...", fr: "Reconnexion à \(name)...", th: "กำลังเชื่อมต่อ \(name) อีกครั้ง...")
        case .discoveringServices:
            return language.localized(
                "已连接，正在发现服务...",
                "Connected. Discovering services...",
                fr: "Connecté. Recherche des services...",
                th: "เชื่อมต่อแล้ว กำลังค้นหาบริการ..."
            )
        case .packetReceived(let index):
            return language.localized("已接收数据包 \(index)", "Packet \(index) received", fr: "Paquet \(index) reçu", th: "ได้รับแพ็กเก็ต \(index) แล้ว")
        case .gyroscopeEnabled:
            return language.localized("陀螺仪已开启", "Gyroscope enabled", fr: "Gyroscope activé", th: "เปิดไจโรสโคปแล้ว")
        case .gyroscopeDisabled:
            return language.localized("陀螺仪已关闭", "Gyroscope disabled", fr: "Gyroscope désactivé", th: "ปิดไจโรสโคปแล้ว")
        case .lightEnabled:
            return language.localized("灯光已打开", "Light enabled", fr: "Éclairage activé", th: "เปิดไฟแล้ว")
        case .lightDisabled:
            return language.localized("灯光已关闭", "Light disabled", fr: "Éclairage désactivé", th: "ปิดไฟแล้ว")
        case .lightNeedsConnection:
            return language.localized(
                "请先连接蓝牙再打开灯光",
                "Connect Bluetooth before turning on the light",
                fr: "Connectez le Bluetooth avant d'allumer l'éclairage",
                th: "โปรดเชื่อมต่อบลูทูธก่อนเปิดไฟ"
            )
        case .writeUnavailable:
            return language.localized(
                "未找到可写入的蓝牙通道",
                "Bluetooth write channel unavailable",
                fr: "Canal d'écriture Bluetooth indisponible",
                th: "ไม่พบช่องทางเขียนข้อมูลบลูทูธ"
            )
        case .reconnectScheduled(let delaySeconds, let attempt, let maxAttempts):
            let delay = String(format: "%.1f", delaySeconds)
            return language.localized(
                "蓝牙信号中断，\(delay) 秒后自动重连 (\(attempt)/\(maxAttempts))",
                "Bluetooth signal lost. Reconnecting in \(delay)s (\(attempt)/\(maxAttempts))",
                fr: "Signal Bluetooth perdu. Reconnexion dans \(delay) s (\(attempt)/\(maxAttempts))",
                th: "สัญญาณบลูทูธขาดหาย จะเชื่อมต่อใหม่ใน \(delay) วินาที (\(attempt)/\(maxAttempts))"
            )
        case .reconnectPaused:
            return language.localized(
                "蓝牙信号不稳定，自动重连已暂停，请靠近设备后重新连接",
                "Bluetooth signal is unstable. Auto-reconnect paused. Move closer to the device and connect again.",
                fr: "Signal Bluetooth instable. Reconnexion automatique suspendue. Rapprochez-vous de l'appareil et reconnectez-le.",
                th: "สัญญาณบลูทูธไม่เสถียร หยุดเชื่อมต่ออัตโนมัติชั่วคราว โปรดเข้าใกล้อุปกรณ์แล้วเชื่อมต่อใหม่"
            )
        case .reconnectedDuringTraining(let name):
            return language.localized(
                "已重新连接 \(name)，训练继续",
                "Reconnected to \(name). Training continues.",
                fr: "\(name) reconnecté. L'entraînement continue.",
                th: "เชื่อมต่อ \(name) อีกครั้งแล้ว ฝึกต่อได้"
            )
        }
    }
}

@MainActor
final class SensorBallBluetoothManager: NSObject, ObservableObject {
    @Published var devices: [SensorBallDevice] = []
    @Published var selectedDevice: SensorBallDevice?
    @Published var connectedDevice: SensorBallDevice?
    @Published var telemetry: SensorBallTelemetry?
    @Published private(set) var status: SensorBallBluetoothStatus = .disconnected
    @Published var lastScanDebugText: String = ""
    @Published var displayHitCount: Int = 0
    @Published var peakForce: Int = 0
    @Published private(set) var isLightOn = false
    @Published private(set) var lightBrightness: Int
    /// Set by the training manager while a session counts down or runs; battery refresh pauses meanwhile.
    var isTrainingActive = false

    private var central: CBCentralManager!
    private var notifyCharacteristics: [CBCharacteristic] = []
    private var readableCharacteristics: [CBCharacteristic] = []
    private var writeCharacteristic: CBCharacteristic?
    private var lastRawHitCount: Int?
    private var autoReconnectIdentifier: UUID?
    private var gyroscopeEnabled = false
    private var readyDispatched = false
    private var manualDisconnectRequested = false
    private var reconnectTarget: SensorBallDevice?
    private var pendingPeripheral: CBPeripheral?
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var connectionWatchdogTask: Task<Void, Never>?
    private var batteryRefreshTask: Task<Void, Never>?
    private var batteryRefreshPausedUntil = Date.distantPast

    private static let devicePrefix = "SENBALL#"
    private static let telemetryPacketSize = 11
    private static let telemetryHeader: [UInt8] = [0xD5, 0x5D, 0x03]
    private static let commandOpenGyro = Data([0xC5, 0x5C, 0x04, 0x01])
    private static let commandCloseGyro = Data([0xC5, 0x5C, 0x04, 0x00])
    private static let commandLightPrefix: [UInt8] = [0xC5, 0x5C, 0x07]
    private static let lightBrightnessKey = "sensor_ball_light_brightness"
    private static let defaultLightBrightness = 20
    private static let lastDeviceIdentifierKey = "sensor_ball_last_device_identifier"
    private static let lastDeviceNameKey = "sensor_ball_last_device_name"
    private static let autoReconnectScanTimeout: TimeInterval = 12
    private static let connectionTimeout: TimeInterval = 12
    private static let maxReconnectAttempts = 12
    private static let initialReconnectDelay: TimeInterval = 0.8
    private static let maxReconnectDelay: TimeInterval = 8
    private static let batteryRefreshInterval: TimeInterval = 3
    private static let chargingBatteryRefreshInterval: TimeInterval = 1.2
    private static let lightCommandRefreshPause: TimeInterval = 1.2

    override init() {
        let storedBrightness = UserDefaults.standard.object(forKey: Self.lightBrightnessKey) as? Int
        lightBrightness = min(max(storedBrightness ?? Self.defaultLightBrightness, 0), 100)
        autoReconnectIdentifier =
            UserDefaults.standard.string(forKey: Self.lastDeviceIdentifierKey).flatMap { UUID(uuidString: $0) }
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var isConnected: Bool {
        connectedDevice != nil
    }

    func statusText(language: AppLanguage) -> String {
        status.text(language: language)
    }

    func connectionTitle(language: AppLanguage) -> String {
        if let connectedDevice {
            return connectedDevice.name
        }
        return L10n.text("connect_first", language)
    }

    func startScan() {
        stopAutoReconnect()
        beginScan(autoReconnectTo: nil)
    }

    private func beginScan(autoReconnectTo identifier: UUID?) {
        guard central.state == .poweredOn else {
            status = .notPoweredOn
            return
        }
        autoReconnectIdentifier = identifier
        clearDeviceList()
        lastScanDebugText = ""
        status = identifier == nil ? .scanning : .scanningLastDevice
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        guard let identifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoReconnectScanTimeout) { [weak self] in
            guard let self,
                  self.autoReconnectIdentifier == identifier,
                  self.connectedDevice == nil else { return }
            self.central.stopScan()
            self.autoReconnectIdentifier = nil
            self.status = .lastDeviceNotFound
        }
    }

    func stopScan() {
        central.stopScan()
    }

    func connectSelected() {
        guard let selectedDevice = selectedDevice else {
            status = .selectDeviceFirst
            return
        }
        central.stopScan()
        autoReconnectIdentifier = nil
        beginConnection(to: selectedDevice, status: .connecting(selectedDevice.name))
    }

    /// Manual disconnect: cancels any pending reconnect but keeps the saved last device for the next launch.
    func disconnect() {
        manualDisconnectRequested = true
        cancelReconnect()
        cancelConnectionWatchdog()
        reconnectTarget = nil
        reconnectAttempts = 0
        if let peripheral = connectedDevice?.peripheral {
            let lightOffQueued = setLightEnabled(false)
            if lightOffQueued {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.central.cancelPeripheralConnection(peripheral)
                }
            } else {
                central.cancelPeripheralConnection(peripheral)
            }
        } else if let pendingPeripheral {
            central.cancelPeripheralConnection(pendingPeripheral)
        }
        pendingPeripheral = nil
        clearConnectionState()
        clearDeviceList()
        status = .disconnected
    }

    func resetDisplayHitCount() {
        lastRawHitCount = nil
        displayHitCount = 0
        peakForce = 0
    }

    @discardableResult
    func setGyroscopeEnabled(_ enabled: Bool) -> Bool {
        gyroscopeEnabled = enabled
        let payload = enabled ? Self.commandOpenGyro : Self.commandCloseGyro
        return writeCommand(payload, status: enabled ? .gyroscopeEnabled : .gyroscopeDisabled)
    }

    @discardableResult
    func setLightEnabled(_ enabled: Bool) -> Bool {
        if !enabled {
            isLightOn = false
        }
        guard connectedDevice != nil, writeCharacteristic != nil else {
            if enabled {
                status = .lightNeedsConnection
            }
            return false
        }

        let payload: Data
        if enabled {
            let protocolBrightness = UInt8(min(lightBrightness, 99))
            payload = Data(Self.commandLightPrefix + [0x01, protocolBrightness])
        } else {
            payload = Data(Self.commandLightPrefix + [0x00])
        }
        batteryRefreshPausedUntil = Date().addingTimeInterval(Self.lightCommandRefreshPause)
        guard writeCommand(payload, status: enabled ? .lightEnabled : .lightDisabled) else {
            return false
        }
        isLightOn = enabled
        return true
    }

    @discardableResult
    func setLightBrightness(_ brightness: Int) -> Bool {
        let clampedBrightness = min(max(brightness, 0), 100)
        lightBrightness = clampedBrightness
        UserDefaults.standard.set(clampedBrightness, forKey: Self.lightBrightnessKey)
        guard isLightOn else {
            return true
        }
        return setLightEnabled(true)
    }

    /// Writes a control packet. A nil status sends it silently (used for periodic telemetry refreshes).
    private func writeCommand(_ payload: Data, status newStatus: SensorBallBluetoothStatus?) -> Bool {
        guard let connectedDevice = connectedDevice, let writeCharacteristic = writeCharacteristic else {
            if newStatus != nil && !isReconnecting {
                status = .writeUnavailable
            }
            return false
        }
        let type: CBCharacteristicWriteType =
            writeCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        connectedDevice.peripheral.writeValue(payload, for: writeCharacteristic, type: type)
        if let newStatus {
            status = newStatus
        }
        return true
    }

    @discardableResult
    func requestTelemetryRefresh(allowGyroscopeOffFallback: Bool = true, forceGyroscopeOffFallback: Bool = false) -> Bool {
        guard let peripheral = connectedDevice?.peripheral else {
            return false
        }
        if allowGyroscopeOffFallback && forceGyroscopeOffFallback {
            return writeCommand(Self.commandCloseGyro, status: nil)
        }
        if let readable = readableCharacteristics.sorted(by: { Self.characteristicScore($0) > Self.characteristicScore($1) }).first {
            peripheral.readValue(for: readable)
            return true
        }
        if allowGyroscopeOffFallback {
            return writeCommand(Self.commandCloseGyro, status: nil)
        }
        return false
    }

    private func handleTelemetry(_ data: Data) {
        guard let telemetry = Self.parseTelemetry(data) else {
            return
        }
        self.telemetry = telemetry
        peakForce = telemetry.forceN
        updateHitCount(rawCount: telemetry.hitCount)
        status = .packetReceived(telemetry.packetIndex)
    }

    private func updateHitCount(rawCount: Int) {
        guard let previous = lastRawHitCount else {
            lastRawHitCount = rawCount
            return
        }
        let delta: Int
        if rawCount >= previous {
            delta = rawCount - previous
        } else if previous >= 240 && rawCount <= 15 {
            delta = rawCount + 256 - previous
        } else {
            delta = 0
        }
        if delta > 0 {
            displayHitCount += delta
        }
        lastRawHitCount = rawCount
    }

    // MARK: - Connection lifecycle

    private var isReconnecting: Bool {
        reconnectTask != nil || pendingPeripheral != nil
    }

    /// Starts a connection the user (or the launch auto-connect) asked for and resets the auto-reconnect budget.
    private func beginConnection(to device: SensorBallDevice, status newStatus: SensorBallBluetoothStatus) {
        manualDisconnectRequested = false
        reconnectAttempts = 0
        cancelReconnect()
        if let pendingPeripheral, pendingPeripheral.identifier != device.identifier {
            central.cancelPeripheralConnection(pendingPeripheral)
        }
        reconnectTarget = device
        connect(device.peripheral, status: newStatus)
    }

    private func connect(_ peripheral: CBPeripheral, status newStatus: SensorBallBluetoothStatus) {
        guard central.state == .poweredOn else {
            status = .notPoweredOn
            return
        }
        central.stopScan()
        readyDispatched = false
        pendingPeripheral = peripheral
        status = newStatus
        central.connect(peripheral)
        // CoreBluetooth never times out a pending connect, so give each attempt Android's 12 s window.
        startConnectionWatchdog(for: peripheral)
    }

    private func dispatchReady() {
        readyDispatched = true
        cancelConnectionWatchdog()
        reconnectAttempts = 0
        if gyroscopeEnabled {
            // The link dropped during a running session: keep counting hits.
            setGyroscopeEnabled(true)
            status = .reconnectedDuringTraining(connectedDevice?.name ?? Self.devicePrefix)
        } else {
            setGyroscopeEnabled(false)
            setLightEnabled(false)
            requestTelemetryRefresh(allowGyroscopeOffFallback: false)
            status = .ready
        }
        startBatteryRefreshLoop()
    }

    private func clearConnectionState() {
        stopBatteryRefreshLoop()
        isLightOn = false
        connectedDevice = nil
        writeCharacteristic = nil
        readableCharacteristics.removeAll()
        notifyCharacteristics.removeAll()
        readyDispatched = false
    }

    /// After any disconnect only Scan stays available, like Android; the reconnect target is kept separately.
    private func clearDeviceList() {
        devices.removeAll()
        selectedDevice = nil
    }

    /// Lists and selects the connected device, like Android's onConnected.
    private func rememberDevice(_ device: SensorBallDevice) {
        if let index = devices.firstIndex(where: { $0.identifier == device.identifier }) {
            devices[index] = device
        } else {
            devices.insert(device, at: 0)
        }
        selectedDevice = device
    }

    /// Mirrors the Android app: up to 12 reconnect attempts with exponential backoff after a non-manual disconnect.
    /// Connection timeouts and failed connects land here too and count as attempts.
    private func handleUnexpectedDisconnect() {
        cancelConnectionWatchdog()
        pendingPeripheral = nil
        clearDeviceList()
        guard !manualDisconnectRequested, let target = reconnectTarget else {
            status = .disconnected
            return
        }
        guard central.state == .poweredOn else {
            return
        }
        guard reconnectAttempts < Self.maxReconnectAttempts else {
            status = .reconnectPaused
            return
        }
        reconnectAttempts += 1
        let attempt = reconnectAttempts
        let delay = Self.reconnectDelay(forAttempt: attempt)
        status = .reconnectScheduled(delaySeconds: delay, attempt: attempt, maxAttempts: Self.maxReconnectAttempts)
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            guard !self.manualDisconnectRequested, self.connectedDevice == nil else { return }
            self.connect(target.peripheral, status: .reconnecting(target.name))
        }
    }

    private static func reconnectDelay(forAttempt attempt: Int) -> TimeInterval {
        let slot = min(max(attempt - 1, 0), 4)
        return min(initialReconnectDelay * Double(1 << slot), maxReconnectDelay)
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    private func stopAutoReconnect() {
        cancelReconnect()
        cancelConnectionWatchdog()
        reconnectAttempts = 0
        if connectedDevice == nil, let pendingPeripheral, central.state == .poweredOn {
            central.cancelPeripheralConnection(pendingPeripheral)
        }
        pendingPeripheral = nil
    }

    private func startConnectionWatchdog(for peripheral: CBPeripheral) {
        connectionWatchdogTask?.cancel()
        connectionWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.connectionTimeout * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.connectionWatchdogTask = nil
            let isCurrentAttempt =
                self.pendingPeripheral?.identifier == peripheral.identifier ||
                self.connectedDevice?.identifier == peripheral.identifier
            guard isCurrentAttempt, !self.readyDispatched, !self.manualDisconnectRequested else { return }
            self.central.cancelPeripheralConnection(peripheral)
            self.clearConnectionState()
            self.handleUnexpectedDisconnect()
        }
    }

    private func cancelConnectionWatchdog() {
        connectionWatchdogTask?.cancel()
        connectionWatchdogTask = nil
    }

    private func handleBluetoothUnavailable(status newStatus: SensorBallBluetoothStatus) {
        cancelReconnect()
        cancelConnectionWatchdog()
        pendingPeripheral = nil
        clearConnectionState()
        clearDeviceList()
        status = newStatus
    }

    /// Launch auto-connect: connect straight to the saved device without scanning, like Android's
    /// autoConnectLastBluetoothDevice. Falls back to scanning for it when the system no longer knows it.
    private func autoConnectLastDevice(identifier: UUID) {
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first else {
            beginScan(autoReconnectTo: identifier)
            return
        }
        autoReconnectIdentifier = nil
        let name = UserDefaults.standard.string(forKey: Self.lastDeviceNameKey) ?? peripheral.name ?? Self.devicePrefix
        let device = SensorBallDevice(
            id: peripheral.identifier,
            name: name,
            identifier: peripheral.identifier,
            rssi: 0,
            advertisedServices: [],
            peripheral: peripheral
        )
        rememberDevice(device)
        beginConnection(to: device, status: .autoConnecting(name))
    }

    // MARK: - Battery refresh

    /// Polls telemetry every 3 s (1.2 s while charging), like the Android battery refresh loop.
    private func startBatteryRefreshLoop() {
        stopBatteryRefreshLoop()
        batteryRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            while !Task.isCancelled {
                guard let self, self.connectedDevice != nil else { return }
                let interval: TimeInterval
                if self.isTrainingActive || self.gyroscopeEnabled {
                    interval = Self.batteryRefreshInterval
                } else if Date() < self.batteryRefreshPausedUntil {
                    interval = 0.2
                } else {
                    let charging = self.telemetry?.isCharging == true
                    self.requestTelemetryRefresh(
                        allowGyroscopeOffFallback: !self.isLightOn,
                        forceGyroscopeOffFallback: charging && !self.isLightOn
                    )
                    interval = charging ? Self.chargingBatteryRefreshInterval : Self.batteryRefreshInterval
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func stopBatteryRefreshLoop() {
        batteryRefreshTask?.cancel()
        batteryRefreshTask = nil
    }

    static func parseTelemetry(_ data: Data) -> SensorBallTelemetry? {
        let bytes = [UInt8](data)
        guard bytes.count >= telemetryPacketSize else {
            return nil
        }
        for index in 0...(bytes.count - telemetryPacketSize) {
            guard bytes[index] == telemetryHeader[0],
                  bytes[index + 1] == telemetryHeader[1],
                  bytes[index + 2] == telemetryHeader[2] else {
                continue
            }
            let forceLow = Int(bytes[index + 9])
            let forceHigh = Int(bytes[index + 10])
            return SensorBallTelemetry(
                packetIndex: Int(bytes[index + 3]),
                batteryRaw: Int(bytes[index + 4]),
                hitCount: Int(bytes[index + 5]),
                chargingFlagRaw: Int(bytes[index + 6]),
                forceLow: forceLow,
                forceHigh: forceHigh,
                forceN: forceLow | (forceHigh << 8)
            )
        }
        return nil
    }

    private static func advertisedServiceUUIDs(from advertisementData: [String: Any]) -> [CBUUID] {
        var serviceUUIDs: [CBUUID] = []
        serviceUUIDs.append(contentsOf: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
        serviceUUIDs.append(contentsOf: advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        serviceUUIDs.append(contentsOf: advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? [])
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            serviceUUIDs.append(contentsOf: serviceData.keys)
        }
        return serviceUUIDs
    }

    /// Same rule as Android's isBoxingDeviceName: trimmed, "SENBALL#" prefix in any case, last character an ASCII digit.
    private static func matchesSensorBall(name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: devicePrefix, options: [.anchored, .caseInsensitive]) != nil,
              let lastScalar = normalized.unicodeScalars.last else {
            return false
        }
        return (48...57).contains(Int(lastScalar.value))
    }

    private static func characteristicScore(_ characteristic: CBCharacteristic) -> Int {
        var score = 0
        if characteristic.uuid.uuidString.lowercased().contains("ffe4") { score += 10 }
        if characteristic.properties.contains(.notify) { score += 4 }
        if characteristic.properties.contains(.read) { score += 2 }
        return score
    }
}

extension SensorBallBluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if connectedDevice == nil, !manualDisconnectRequested, let reconnectTarget {
                    reconnectAttempts = 0
                    connect(reconnectTarget.peripheral, status: .reconnecting(reconnectTarget.name))
                } else if let autoReconnectIdentifier, connectedDevice == nil {
                    autoConnectLastDevice(identifier: autoReconnectIdentifier)
                } else {
                    status = .ready
                }
            case .poweredOff:
                handleBluetoothUnavailable(status: .poweredOff)
            case .unauthorized:
                handleBluetoothUnavailable(status: .unauthorized)
            default:
                handleBluetoothUnavailable(status: .unavailable)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = advertisedName ?? peripheral.name ?? ""
            let serviceUUIDs = Self.advertisedServiceUUIDs(from: advertisementData)
            let serviceText = serviceUUIDs.map(\.uuidString).joined(separator: ",")
            lastScanDebugText = "Last seen: \(name.isEmpty ? "N/A" : name), services: \(serviceText.isEmpty ? "N/A" : serviceText), RSSI: \(RSSI.intValue)"

            guard Self.matchesSensorBall(name: name) else {
                return
            }
            let item = SensorBallDevice(
                id: peripheral.identifier,
                name: name,
                identifier: peripheral.identifier,
                rssi: RSSI.intValue,
                advertisedServices: serviceUUIDs.map(\.uuidString),
                peripheral: peripheral
            )
            if let existingIndex = devices.firstIndex(where: { $0.identifier == item.identifier }) {
                devices[existingIndex] = item
            } else {
                devices.append(item)
            }
            if devices.count == 1 {
                selectedDevice = item
            }
            if autoReconnectIdentifier == peripheral.identifier {
                autoReconnectIdentifier = nil
                selectedDevice = item
                central.stopScan()
                beginConnection(to: item, status: .autoConnecting(item.name))
                return
            }
            status = devices.count == 1 ? .autoSelected(item.name) : .devicesFound(devices.count)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard pendingPeripheral?.identifier == peripheral.identifier else {
                // A connection that is no longer wanted, e.g. it finished after the user disconnected.
                central.cancelPeripheralConnection(peripheral)
                return
            }
            pendingPeripheral = nil
            peripheral.delegate = self
            let knownDevice = reconnectTarget?.identifier == peripheral.identifier
                ? reconnectTarget
                : devices.first(where: { $0.identifier == peripheral.identifier })
            let device = knownDevice ??
                SensorBallDevice(
                    id: peripheral.identifier,
                    name: peripheral.name ?? Self.devicePrefix,
                    identifier: peripheral.identifier,
                    rssi: 0,
                    advertisedServices: [],
                    peripheral: peripheral
                )
            connectedDevice = device
            rememberDevice(device)
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastDeviceIdentifierKey)
            UserDefaults.standard.set(device.name, forKey: Self.lastDeviceNameKey)
            autoReconnectIdentifier = nil
            writeCharacteristic = nil
            readableCharacteristics.removeAll()
            notifyCharacteristics.removeAll()
            readyDispatched = false
            isLightOn = false
            status = .discoveringServices
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard pendingPeripheral?.identifier == peripheral.identifier else {
                return
            }
            clearConnectionState()
            handleUnexpectedDisconnect()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let isCurrentPeripheral =
                connectedDevice?.identifier == peripheral.identifier ||
                pendingPeripheral?.identifier == peripheral.identifier
            guard isCurrentPeripheral else {
                // Already handled: a manual disconnect or a timed-out attempt we cancelled ourselves.
                return
            }
            clearConnectionState()
            if manualDisconnectRequested {
                pendingPeripheral = nil
                clearDeviceList()
                status = .disconnected
                return
            }
            handleUnexpectedDisconnect()
        }
    }
}

extension SensorBallBluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            peripheral.services?.forEach { service in
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard connectedDevice?.identifier == peripheral.identifier else {
                return
            }
            service.characteristics?.forEach { characteristic in
                if writeCharacteristic == nil && (characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)) {
                    writeCharacteristic = characteristic
                }
                if characteristic.properties.contains(.read) {
                    readableCharacteristics.append(characteristic)
                }
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    notifyCharacteristics.append(characteristic)
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if writeCharacteristic != nil && !readyDispatched {
                dispatchReady()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else {
            return
        }
        Task { @MainActor in
            handleTelemetry(data)
        }
    }
}
