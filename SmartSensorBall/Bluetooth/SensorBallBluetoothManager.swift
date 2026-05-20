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
    let forceLow: Int
    let forceHigh: Int
    let forceN: Int

    var peak: Int { forceN }

    var batteryText: String {
        switch batteryRaw {
        case 101: return "Charging"
        case 102: return "Full"
        case 0...100: return "\(batteryRaw)%"
        default: return "--"
        }
    }
}

@MainActor
final class SensorBallBluetoothManager: NSObject, ObservableObject {
    @Published var devices: [SensorBallDevice] = []
    @Published var selectedDevice: SensorBallDevice?
    @Published var connectedDevice: SensorBallDevice?
    @Published var telemetry: SensorBallTelemetry?
    @Published var statusText: String = "Bluetooth disconnected"
    @Published var lastScanDebugText: String = ""
    @Published var displayHitCount: Int = 0
    @Published var peakForce: Int = 0

    private var central: CBCentralManager!
    private var notifyCharacteristics: [CBCharacteristic] = []
    private var readableCharacteristics: [CBCharacteristic] = []
    private var writeCharacteristic: CBCharacteristic?
    private var lastRawHitCount: Int?

    private static let devicePrefix = "SENBALL#"
    private static let sensorBallServiceUUIDs = ["FFE0", "0000FFE0-0000-1000-8000-00805F9B34FB"]
    private static let telemetryPacketSize = 11
    private static let telemetryHeader: [UInt8] = [0xD5, 0x5D, 0x03]
    private static let commandOpenGyro = Data([0xC5, 0x5C, 0x04, 0x01])
    private static let commandCloseGyro = Data([0xC5, 0x5C, 0x04, 0x00])

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var isConnected: Bool {
        connectedDevice != nil
    }

    func connectionTitle(language: AppLanguage) -> String {
        if let connectedDevice {
            return connectedDevice.name
        }
        return L10n.text("connect_first", language)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            statusText = "Bluetooth is not powered on"
            return
        }
        devices.removeAll()
        selectedDevice = nil
        lastScanDebugText = ""
        statusText = "Scanning SENBALL# devices..."
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
    }

    func connectSelected() {
        guard let selectedDevice else {
            statusText = "Select a SENBALL# device first"
            return
        }
        central.stopScan()
        statusText = "Connecting \(selectedDevice.name)..."
        central.connect(selectedDevice.peripheral)
    }

    func disconnect() {
        if let peripheral = connectedDevice?.peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        connectedDevice = nil
        writeCharacteristic = nil
        readableCharacteristics.removeAll()
        notifyCharacteristics.removeAll()
        statusText = "Bluetooth disconnected"
    }

    func resetDisplayHitCount() {
        lastRawHitCount = nil
        displayHitCount = 0
        peakForce = 0
    }

    @discardableResult
    func setGyroscopeEnabled(_ enabled: Bool) -> Bool {
        guard let connectedDevice, let writeCharacteristic else {
            statusText = "Bluetooth write channel unavailable"
            return false
        }
        let payload = enabled ? Self.commandOpenGyro : Self.commandCloseGyro
        let type: CBCharacteristicWriteType =
            writeCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        connectedDevice.peripheral.writeValue(payload, for: writeCharacteristic, type: type)
        statusText = enabled ? "Gyroscope enabled" : "Gyroscope disabled"
        return true
    }

    @discardableResult
    func requestTelemetryRefresh(allowGyroscopeOffFallback: Bool = true) -> Bool {
        guard let peripheral = connectedDevice?.peripheral else {
            return false
        }
        if let readable = readableCharacteristics.sorted(by: { Self.characteristicScore($0) > Self.characteristicScore($1) }).first {
            peripheral.readValue(for: readable)
            return true
        }
        if allowGyroscopeOffFallback {
            return setGyroscopeEnabled(false)
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
        statusText = "Packet \(telemetry.packetIndex) received"
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

    private static func matchesSensorBall(name: String, serviceUUIDs: [CBUUID]) -> Bool {
        if name.uppercased().hasPrefix(devicePrefix) {
            return true
        }
        return serviceUUIDs.contains { uuid in
            sensorBallServiceUUIDs.contains(uuid.uuidString.uppercased())
        }
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
                statusText = "Bluetooth ready"
            case .poweredOff:
                statusText = "Bluetooth is off"
            case .unauthorized:
                statusText = "Bluetooth permission denied"
            default:
                statusText = "Bluetooth unavailable"
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

            guard Self.matchesSensorBall(name: name, serviceUUIDs: serviceUUIDs) else {
                return
            }
            let displayName = name.isEmpty ? "\(Self.devicePrefix)\(peripheral.identifier.uuidString.prefix(6))" : name
            let item = SensorBallDevice(
                id: peripheral.identifier,
                name: displayName,
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
            statusText = "\(devices.count) SENBALL# device(s) found"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            connectedDevice = devices.first(where: { $0.identifier == peripheral.identifier }) ??
                SensorBallDevice(
                    id: peripheral.identifier,
                    name: peripheral.name ?? "SENBALL#",
                    identifier: peripheral.identifier,
                    rssi: 0,
                    advertisedServices: [],
                    peripheral: peripheral
                )
            writeCharacteristic = nil
            readableCharacteristics.removeAll()
            notifyCharacteristics.removeAll()
            statusText = "Connected. Discovering services..."
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectedDevice = nil
            writeCharacteristic = nil
            readableCharacteristics.removeAll()
            notifyCharacteristics.removeAll()
            statusText = "Bluetooth disconnected"
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
            if writeCharacteristic != nil {
                statusText = "Bluetooth ready"
                setGyroscopeEnabled(false)
                requestTelemetryRefresh(allowGyroscopeOffFallback: false)
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
