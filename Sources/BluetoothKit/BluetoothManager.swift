import Foundation
import CoreBluetooth

// MARK: - Bluetooth Manager

/// Core Bluetooth를 사용한 디바이스 연결 및 데이터 통신을 관리하는 클래스입니다.
///
/// 이 클래스는 Bluetooth LE 디바이스의 스캔, 연결, 서비스 및 특성 탐지,
/// 데이터 읽기/쓰기 기능을 제공합니다. BluetoothKit의 내부 구현체로 사용됩니다.
internal class BluetoothManager: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Bluetooth 연결 상태 변화를 처리하는 델리게이트입니다.
    public weak var delegate: BluetoothManagerDelegate?
    
    /// 센서 데이터 수신을 처리하는 델리게이트입니다.
    public weak var sensorDataDelegate: SensorDataDelegate?
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var discoveredDevices: [BluetoothDevice] = []
    
    private let configuration: SensorConfiguration
    private let dataParser: SensorDataParser
    private let logger: InternalLogger
    
    // 단순화된 상태 관리
    private var connectionState: ConnectionState = .disconnected {
        didSet {
            notifyStateChange(connectionState)
        }
    }
    
    // Auto-reconnection 관리
    private var lastConnectedPeripheralIdentifier: UUID?
    private var isAutoReconnectEnabled: Bool
    
    // MARK: - Initialization
    
    /// 새로운 BluetoothManager 인스턴스를 생성합니다.
    ///
    /// - Parameters:
    ///   - configuration: 센서 하드웨어 설정
    ///   - logger: 디버깅을 위한 로거 구현
    public init(configuration: SensorConfiguration, logger: InternalLogger) {
        self.configuration = configuration
        self.logger = logger
        self.dataParser = SensorDataParser(configuration: configuration)
        self.isAutoReconnectEnabled = true  // 기본값, 외부에서 설정됨
        
        super.init()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Interface
    
    /// 현재 디바이스 스캔 중인지 여부를 나타냅니다.
    public var isScanning: Bool {
        return centralManager.isScanning
    }
    
    /// 현재 디바이스에 연결되어 있는지 여부를 나타냅니다.
    public var isConnected: Bool {
        return connectedPeripheral?.state == .connected
    }
    
    /// 현재 연결 상태를 반환합니다.
    public var currentConnectionState: ConnectionState {
        return connectionState
    }
    
    /// 스캔 중 발견된 디바이스 목록을 반환합니다.
    public var discoveredDevicesList: [BluetoothDevice] {
        return discoveredDevices
    }
    
    /// Bluetooth 디바이스 스캔을 시작합니다.
    ///
    /// 설정된 디바이스 이름 접두사와 일치하는 디바이스만 검색됩니다.
    /// Bluetooth가 비활성화된 경우 스캔이 실패할 수 있습니다.
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            log("Cannot start scanning: Bluetooth not available")
            connectionState = .failed(BluetoothKitError.bluetoothUnavailable)
            return
        }
        
        centralManager.stopScan()
        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(withServices: nil)
        connectionState = .scanning
    }
    
    /// Bluetooth 디바이스 스캔을 중지합니다.
    public func stopScanning() {
        centralManager.stopScan()
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }
    
    /// 지정된 디바이스에 연결을 시도합니다.
    ///
    /// - Parameter device: 연결할 BluetoothDevice
    public func connect(to device: BluetoothDevice) {
        guard centralManager.state == .poweredOn else {
            log("Cannot connect: Bluetooth not available")
            connectionState = .failed(BluetoothKitError.bluetoothUnavailable)
            return
        }
        
        stopScanning()
        connectionState = .connecting(device.name)
        centralManager.connect(device.peripheral, options: nil)
    }
    
    /// 현재 연결된 디바이스와의 연결을 해제합니다.
    public func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    /// 자동 재연결 기능을 활성화하거나 비활성화합니다.
    ///
    /// - Parameter enabled: 자동 재연결 활성화 여부
    public func enableAutoReconnect(_ enabled: Bool) {
        isAutoReconnectEnabled = enabled
        
        if enabled {
            // auto-reconnect가 활성화되고 마지막 연결된 디바이스가 있으며,
            // 현재 연결이 끊어진 상태라면, 재연결을 시도합니다
            if let lastPeripheralId = lastConnectedPeripheralIdentifier,
               !isConnected,
               centralManager.state == .poweredOn {
                
                // 검색된 디바이스에서 peripheral을 찾거나 검색을 시도합니다
                if let peripheral = discoveredDevices.first(where: { $0.peripheral.identifier == lastPeripheralId })?.peripheral {
                    connectionState = .reconnecting(peripheral.name ?? "Unknown Device")
                    centralManager.connect(peripheral, options: nil)
                } else {
                    // peripheral이 검색된 디바이스에 없다면, 검색을 시도합니다
                    let peripherals = centralManager.retrievePeripherals(withIdentifiers: [lastPeripheralId])
                    if let peripheral = peripherals.first {
                        connectionState = .reconnecting(peripheral.name ?? "Unknown Device")
                        centralManager.connect(peripheral, options: nil)
                    }
                }
            }
        } else {
            // auto-reconnect가 비활성화되면, 진행 중인 재연결 시도를 취소합니다
            if case .reconnecting(_) = connectionState {
                // 재연결을 시도 중인 peripheral을 찾아서 연결을 취소합니다
                if let lastPeripheralId = lastConnectedPeripheralIdentifier {
                    let peripherals = centralManager.retrievePeripherals(withIdentifiers: [lastPeripheralId])
                    if let peripheral = peripherals.first {
                        centralManager.cancelPeripheralConnection(peripheral)
                    }
                }
                connectionState = .disconnected
            }
            log("Auto-reconnect disabled - all automatic reconnection attempts will be blocked")
        }
    }
    
    // MARK: - Private Methods
    
    private func handleDeviceDiscovered(_ peripheral: CBPeripheral, rssi: NSNumber) {
        let name = peripheral.name ?? ""
        guard name.hasPrefix(configuration.deviceNamePrefix) else { return }
        
        // 디바이스가 이미 존재하는지 확인합니다
        if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            let device = BluetoothDevice(peripheral: peripheral, name: name)
            discoveredDevices.append(device)
            
            notifyDeviceDiscovered(device)
        }
    }
    
    private func handleConnectionSuccess(_ peripheral: CBPeripheral) {
        // 이 연결이 허용되는지 확인합니다
        // auto-reconnect가 비활성화되어 있고 사용자가 시작한 연결이 아니라면, 취소합니다
        if case .reconnecting = connectionState, !isAutoReconnectEnabled {
            centralManager.cancelPeripheralConnection(peripheral)
            connectionState = .disconnected
            return
        }
        
        connectedPeripheral = peripheral
        lastConnectedPeripheralIdentifier = peripheral.identifier
        
        let deviceName = peripheral.name ?? "Unknown Device"
        connectionState = .connected(deviceName)
        
        // 서비스 검색을 시작합니다
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        
        if let device = discoveredDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
            notifyDeviceConnected(device)
        }
    }
    
    private func handleConnectionFailure(_ peripheral: CBPeripheral, error: Error?) {
        let errorMessage = error?.localizedDescription ?? "Unknown error"
        connectionState = .failed(BluetoothKitError.connectionFailed(errorMessage))
        
        log("Connection failed: \(errorMessage)")
    }
    
    private func handleDisconnection(_ peripheral: CBPeripheral, error: Error?) {
        let deviceName = peripheral.name ?? "Unknown Device"
        
        if connectedPeripheral?.identifier == peripheral.identifier {
            connectedPeripheral = nil
        }
        
        // auto-reconnection을 처리합니다
        if !isAutoReconnectEnabled {
            connectionState = .disconnected
        } else {
            connectionState = .reconnecting(deviceName)
            centralManager.connect(peripheral, options: nil)
        }
        
        if let device = discoveredDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
            notifyDeviceDisconnected(device, error: error)
        }
    }
    
    private func handleCharacteristicUpdate(_ characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, error == nil else {
            log("Characteristic update error: \(error?.localizedDescription ?? "Unknown")")
            return
        }
        
        do {
            switch characteristic.uuid {
            case SensorUUID.eegNotifyChar:
                let readings = try dataParser.parseEEGData(data)
                for reading in readings {
                    notifySensorData(reading) { [weak self] data in
                        self?.sensorDataDelegate?.didReceiveEEGData(data)
                    }
                }
                
            case SensorUUID.ppgChar:
                let readings = try dataParser.parsePPGData(data)
                for reading in readings {
                    notifySensorData(reading) { [weak self] data in
                        self?.sensorDataDelegate?.didReceivePPGData(data)
                    }
                }
                
            case SensorUUID.accelChar:
                let readings = try dataParser.parseAccelerometerData(data)
                for reading in readings {
                    notifySensorData(reading) { [weak self] data in
                        self?.sensorDataDelegate?.didReceiveAccelerometerData(data)
                    }
                }
                
            case SensorUUID.batteryChar:
                let reading = try dataParser.parseBatteryData(data)
                notifySensorData(reading) { [weak self] data in
                    self?.sensorDataDelegate?.didReceiveBatteryData(data)
                }
                
            default:
                log("Received data from unknown characteristic: \(characteristic.uuid)")
            }
        } catch {
            log("Data parsing error: \(error)")
        }
    }
    
    private func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        logger.log(message, file: file, function: function, line: line)
    }
    
    // MARK: - Private Helper Methods
    
    private func notifyStateChange(_ state: ConnectionState) {
        if Thread.isMainThread {
            delegate?.bluetoothManager(self, didUpdateState: state)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.bluetoothManager(self, didUpdateState: state)
            }
        }
    }
    
    private func notifyDeviceDiscovered(_ device: BluetoothDevice) {
        if Thread.isMainThread {
            delegate?.bluetoothManager(self, didDiscoverDevice: device)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.bluetoothManager(self, didDiscoverDevice: device)
            }
        }
    }
    
    private func notifyDeviceConnected(_ device: BluetoothDevice) {
        if Thread.isMainThread {
            delegate?.bluetoothManager(self, didConnectToDevice: device)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.bluetoothManager(self, didConnectToDevice: device)
            }
        }
    }
    
    private func notifyDeviceDisconnected(_ device: BluetoothDevice, error: Error?) {
        if Thread.isMainThread {
            delegate?.bluetoothManager(self, didDisconnectFromDevice: device, error: error)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.bluetoothManager(self, didDisconnectFromDevice: device, error: error)
            }
        }
    }
    
    private func notifySensorData<T: Sendable>(_ data: T, callback: @escaping @Sendable (T) -> Void) {
        if Thread.isMainThread {
            callback(data)
        } else {
            DispatchQueue.main.async {
                callback(data)
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    
    /// Central Manager의 상태가 변경되었을 때 호출됩니다.
    ///
    /// Bluetooth가 켜지거나 꺼지는 등의 상태 변화를 처리하며,
    /// 연결 상태를 적절히 업데이트합니다.
    ///
    /// - Parameter central: 상태가 변경된 Central Manager
    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .failed(let error) = connectionState,
               error.localizedDescription == BluetoothKitError.bluetoothUnavailable.localizedDescription {
                connectionState = .disconnected
            }
            
        case .poweredOff:
            connectionState = .failed(BluetoothKitError.bluetoothUnavailable)
            
        case .unauthorized:
            connectionState = .failed(BluetoothKitError.bluetoothUnavailable)
            
        case .unsupported:
            connectionState = .failed(BluetoothKitError.bluetoothUnavailable)
            
        default:
            connectionState = .failed(BluetoothKitError.bluetoothUnavailable)
        }
    }
    
    /// 새로운 BLE 디바이스가 발견되었을 때 호출됩니다.
    ///
    /// 설정된 디바이스 이름 필터에 맞는 디바이스를 찾아
    /// 발견된 디바이스 목록에 추가합니다.
    ///
    /// - Parameters:
    ///   - central: 디바이스를 발견한 Central Manager
    ///   - peripheral: 발견된 BLE 페리페럴
    ///   - advertisementData: 광고 데이터
    ///   - RSSI: 신호 강도 (dBm)
    internal func centralManager(_ central: CBCentralManager,
                              didDiscover peripheral: CBPeripheral,
                              advertisementData: [String : Any],
                              rssi RSSI: NSNumber) {
        handleDeviceDiscovered(peripheral, rssi: RSSI)
    }
    
    /// 디바이스에 성공적으로 연결되었을 때 호출됩니다.
    ///
    /// 연결 후 서비스 검색을 시작하고 연결 상태를 업데이트합니다.
    ///
    /// - Parameters:
    ///   - central: 연결을 수행한 Central Manager
    ///   - peripheral: 연결된 페리페럴
    internal func centralManager(_ central: CBCentralManager,
                              didConnect peripheral: CBPeripheral) {
        handleConnectionSuccess(peripheral)
    }
    
    /// 디바이스 연결에 실패했을 때 호출됩니다.
    ///
    /// 연결 실패 원인을 로그에 기록하고 연결 상태를 실패로 업데이트합니다.
    ///
    /// - Parameters:
    ///   - central: 연결을 시도한 Central Manager
    ///   - peripheral: 연결에 실패한 페리페럴
    ///   - error: 연결 실패 원인
    internal func centralManager(_ central: CBCentralManager,
                              didFailToConnect peripheral: CBPeripheral,
                              error: Error?) {
        handleConnectionFailure(peripheral, error: error)
    }
    
    /// 디바이스와의 연결이 해제되었을 때 호출됩니다.
    ///
    /// 자동 재연결이 활성화된 경우 재연결을 시도하고,
    /// 그렇지 않으면 연결 상태를 해제됨으로 업데이트합니다.
    ///
    /// - Parameters:
    ///   - central: 연결 해제를 감지한 Central Manager
    ///   - peripheral: 연결이 해제된 페리페럴
    ///   - error: 연결 해제 원인 (자발적 해제인 경우 nil)
    internal func centralManager(_ central: CBCentralManager,
                              didDisconnectPeripheral peripheral: CBPeripheral,
                              error: Error?) {
        handleDisconnection(peripheral, error: error)
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    /// 페리페럴의 서비스가 발견되었을 때 호출됩니다.
    ///
    /// 발견된 각 서비스에 대해 특성(Characteristics) 검색을 시작합니다.
    ///
    /// - Parameters:
    ///   - peripheral: 서비스가 발견된 페리페럴
    ///   - error: 서비스 검색 중 발생한 오류
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    /// 서비스의 특성들이 발견되었을 때 호출됩니다.
    ///
    /// 센서 데이터 수신을 위해 필요한 특성들에 대해 알림을 활성화합니다.
    ///
    /// - Parameters:
    ///   - peripheral: 특성이 발견된 페리페럴
    ///   - service: 특성을 포함하는 서비스
    ///   - error: 특성 검색 중 발생한 오류
    internal func peripheral(_ peripheral: CBPeripheral,
                          didDiscoverCharacteristicsFor service: CBService,
                          error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if SensorUUID.allSensorCharacteristics.contains(characteristic.uuid) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    /// 특성의 값이 업데이트되었을 때 호출됩니다.
    ///
    /// 수신된 데이터를 센서 타입에 따라 파싱하고 델리게이트에 전달합니다.
    ///
    /// - Parameters:
    ///   - peripheral: 값이 업데이트된 페리페럴
    ///   - characteristic: 값이 업데이트된 특성
    ///   - error: 값 읽기 중 발생한 오류
    internal func peripheral(_ peripheral: CBPeripheral,
                          didUpdateValueFor characteristic: CBCharacteristic,
                          error: Error?) {
        handleCharacteristicUpdate(characteristic, error: error)
    }
} 