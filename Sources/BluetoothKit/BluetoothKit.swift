import Foundation
import CoreBluetooth

// MARK: - BluetoothKit Main Interface

/// LinkBand 센서에서 데이터를 읽고 연결을 관리하는 메인 클래스입니다.
///
/// 이 클래스는 Bluetooth Low Energy를 통해 LinkBand 디바이스와 통신하며,
/// EEG, PPG, 가속도계, 배터리 데이터를 실시간으로 수신합니다.
/// SwiftUI의 `@ObservableObject`로 구현되어 UI와 자동으로 동기화됩니다.
///
/// ## 기본 사용법
///
/// ```swift
/// @StateObject private var bluetoothKit = BluetoothKit()
///
/// // 1. 디바이스 스캔
/// bluetoothKit.startScanning()
///
/// // 2. 디바이스 연결
/// if let device = bluetoothKit.discoveredDevices.first {
///     bluetoothKit.connect(to: device)
/// }
///
/// // 3. 데이터 기록
/// bluetoothKit.startRecording()
///
/// // 4. 센서 데이터 접근
/// if let eeg = bluetoothKit.latestEEGReading {
///     print("EEG: \(eeg.channel1)µV, \(eeg.channel2)µV")
/// }
/// ```
@available(iOS 13.0, macOS 10.15, *)
public class BluetoothKit: ObservableObject, @unchecked Sendable {
    
    // MARK: - Public Properties
    
    /// 스캔 중 발견된 Bluetooth 디바이스 목록.
    ///
    /// 이 배열은 스캔 중 새 디바이스가 발견될 때 자동으로 업데이트됩니다.
    /// 디바이스는 설정된 디바이스 이름 접두사로 필터링됩니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 발견된 디바이스 목록 표시
    /// ForEach(bluetoothKit.discoveredDevices, id: \.id) { device in
    ///     Button(device.name) {
    ///         bluetoothKit.connect(to: device)
    ///     }
    /// }
    ///
    /// // 특정 디바이스 연결
    /// if let targetDevice = bluetoothKit.discoveredDevices.first(where: { $0.name.contains("LinkBand") }) {
    ///     bluetoothKit.connect(to: targetDevice)
    /// }
    /// ```
    @Published public var discoveredDevices: [BluetoothDevice] = []
    
    /// 현재 연결 상태의 사용자 친화적인 설명.
    ///
    /// 연결 상태를 사용자에게 표시하기 위한 한국어 문자열입니다:
    /// - "연결 안됨": 활성 연결 없음
    /// - "스캔 중...": 현재 디바이스 스캔 중  
    /// - "[디바이스명]에 연결 중...": 디바이스 연결 시도 중
    /// - "[디바이스명]에 연결됨": 디바이스에 성공적으로 연결됨
    /// - "[디바이스명]에 재연결 중...": 연결 해제 후 재연결 시도 중
    /// - "실패: [오류 메시지]": 연결 또는 작업 실패
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 상태바에 연결 상태 표시
    /// Text("상태: \(bluetoothKit.connectionStatusDescription)")
    ///     .foregroundColor(bluetoothKit.isConnected ? .green : .gray)
    ///
    /// // 연결 완료 감지
    /// if bluetoothKit.connectionStatusDescription.contains("연결됨") {
    ///     // 연결 완료 후 자동 작업 실행
    ///     bluetoothKit.startRecording()
    /// }
    /// ```
    @Published public var connectionStatusDescription: String = "연결 안됨"
    
    /// 라이브러리가 현재 디바이스를 스캔 중인지 여부.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 스캔 상태에 따른 UI 표시
    /// if bluetoothKit.isScanning {
    ///     Button("중지") { bluetoothKit.stopScanning() }
    /// } else {
    ///     Button("스캔 시작") { bluetoothKit.startScanning() }
    /// }
    /// ```
    @Published public var isScanning: Bool = false
    
    /// 데이터 기록이 현재 활성화되어 있는지 여부.
    ///
    /// `true`일 때, 수신된 모든 센서 데이터가 파일에 저장됩니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 기록 상태 확인
    /// if bluetoothKit.isRecording {
    ///     print("현재 기록 중...")
    /// }
    ///
    /// // SwiftUI에서 기록 버튼
    /// Button(bluetoothKit.isRecording ? "기록 중지" : "기록 시작") {
    ///     if bluetoothKit.isRecording {
    ///         bluetoothKit.stopRecording()
    ///     } else {
    ///         bluetoothKit.startRecording()
    ///     }
    /// }
    /// ```
    @Published public var isRecording: Bool = false
    
    /// auto-reconnection이 현재 활성화되어 있는지 여부.
    ///
    /// `true`일 때, 연결이 끊어지면 라이브러리가 자동으로 재연결을 시도합니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 자동 재연결 토글
    /// Toggle("자동 재연결", isOn: $bluetoothKit.isAutoReconnectEnabled)
    ///
    /// // 설정에 따른 UI 표시
    /// if bluetoothKit.isAutoReconnectEnabled {
    ///     Image(systemName: "arrow.triangle.2.circlepath")
    ///         .foregroundColor(.blue)
    /// }
    /// ```
    @Published public var isAutoReconnectEnabled: Bool = true
    
    // 최신 센서 읽기값
    
    /// 가장 최근의 EEG (뇌전도) 읽기값.
    ///
    /// 마이크로볼트(µV) 단위의 2채널 뇌 활동 데이터와 lead-off 상태를 포함합니다.
    /// 아직 EEG 데이터를 받지 못한 경우 `nil`입니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // EEG 데이터 표시
    /// if let eeg = bluetoothKit.latestEEGReading {
    ///     Text("EEG: \(eeg.channel1)µV / \(eeg.channel2)µV")
    ///     Text("Lead-off: \(eeg.leadOff ? "감지됨" : "정상")")
    /// } else {
    ///     Text("EEG 데이터 없음")
    /// }
    /// ```
    @Published public var latestEEGReading: EEGReading?
    
    /// 가장 최근의 PPG (광전 용적 맥파) 읽기값.
    ///
    /// 심박수 모니터링을 위한 적색 및 적외선 LED 값을 포함합니다.
    /// 아직 PPG 데이터를 받지 못한 경우 `nil`입니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // PPG 데이터 표시
    /// if let ppg = bluetoothKit.latestPPGReading {
    ///     VStack {
    ///         Text("Red: \(ppg.red)")
    ///         Text("IR: \(ppg.infrared)")
    ///         Text("심박수 계산 가능")
    ///     }
    /// } else {
    ///     Text("PPG 데이터 대기 중...")
    /// }
    /// ```
    @Published public var latestPPGReading: PPGReading?
    
    /// 가장 최근의 가속도계 읽기값.
    ///
    /// 모션 감지를 위한 3축 가속도 데이터를 포함합니다.
    /// 아직 가속도계 데이터를 받지 못한 경우 `nil`입니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 가속도계 데이터 표시
    /// if let accel = bluetoothKit.latestAccelerometerReading {
    ///     HStack {
    ///         Text("X: \(String(format: "%.2f", accel.x))")
    ///         Text("Y: \(String(format: "%.2f", accel.y))")
    ///         Text("Z: \(String(format: "%.2f", accel.z))")
    ///     }
    /// }
    /// ```
    @Published public var latestAccelerometerReading: AccelerometerReading?
    
    /// 가장 최근의 배터리 레벨 읽기값.
    ///
    /// 연결된 디바이스의 배터리 백분율(0-100%)을 포함합니다.
    /// 아직 배터리 데이터를 받지 못한 경우 `nil`입니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 배터리 상태 표시
    /// if let battery = bluetoothKit.latestBatteryReading {
    ///     HStack {
    ///         Image(systemName: "battery.25")
    ///         Text("\(Int(battery.percentage))%")
    ///     }
    ///     .foregroundColor(battery.percentage < 20 ? .red : .primary)
    /// }
    /// ```
    @Published public var latestBatteryReading: BatteryReading?
    
    /// 기록된 데이터 파일 목록.
    ///
    /// 기록이 완료되면 자동으로 업데이트됩니다.
    /// 각 기록 세션은 여러 CSV 파일(센서 타입당 하나)을 생성합니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 기록된 파일 목록 표시
    /// List(bluetoothKit.recordedFiles, id: \.self) { file in
    ///     Text(file.lastPathComponent)
    /// }
    ///
    /// // 파일 개수 표시
    /// Text("저장된 파일: \(bluetoothKit.recordedFiles.count)개")
    /// ```
    @Published public var recordedFiles: [URL] = []
    
    /// Bluetooth가 현재 비활성화되어 있는지 여부.
    ///
    /// Bluetooth가 꺼지면 자동으로 `true`로 설정됩니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // Bluetooth 상태 경고 표시
    /// if bluetoothKit.isBluetoothDisabled {
    ///     Text("⚠️ Bluetooth를 활성화해주세요")
    ///         .foregroundColor(.red)
    /// }
    ///
    /// // 스캔 버튼 비활성화
    /// Button("스캔 시작") { }
    ///     .disabled(bluetoothKit.isBluetoothDisabled)
    /// ```
    @Published public var isBluetoothDisabled: Bool = false
    
    // MARK: - Batch Data Collection
    
    /// 배치 단위로 센서 데이터를 수신하는 델리게이트.
    ///
    /// 설정된 시간 간격이나 샘플 개수에 따라 센서 데이터를 배치로 받을 수 있습니다.
    /// 개별 샘플 대신 배치로 처리하면 성능이 향상되고 더 효율적인 데이터 분석이 가능합니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// class DataProcessor: SensorBatchDataDelegate {
    ///     func didReceiveEEGBatch(_ readings: [EEGReading]) {
    ///         print("EEG 배치: \(readings.count)개 샘플")
    ///     }
    /// }
    ///
    /// bluetoothKit.batchDataDelegate = DataProcessor()
    /// bluetoothKit.setDataCollection(timeInterval: 0.5, for: .eeg)
    /// ```
    public weak var batchDataDelegate: SensorBatchDataDelegate?
    
    // MARK: - Internal Properties
    
    /// 내부 연결 상태 (SDK 내부 사용만).
    internal var connectionState: ConnectionState = .disconnected
    
    // MARK: - Batch Data Collection (Internal)
    
    /// 각 센서별 데이터 수집 설정
    private var dataCollectionConfigs: [SensorType: DataCollectionConfig] = [:]
    
    /// 센서별 데이터 버퍼
    private var eegBuffer: [EEGReading] = []
    private var ppgBuffer: [PPGReading] = []
    private var accelerometerBuffer: [AccelerometerReading] = []
    
    // MARK: - Private Components
    
    private let bluetoothManager: BluetoothManager
    private let dataRecorder: DataRecorder
    private let configuration: SensorConfiguration
    private let logger: InternalLogger
    
    // MARK: - Initialization
    
    /// 새로운 BluetoothKit 인스턴스를 생성합니다.
    /// 
    /// 기본 설정으로 초기화되며, 바로 사용할 수 있습니다.
    ///
    /// ## 예시
    /// ```swift
    /// let bluetoothKit = BluetoothKit()
    /// bluetoothKit.startScanning()
    /// ```
    public init() {
        self.configuration = .default
        self.logger = InternalLogger(isEnabled: false)  // 프로덕션 최적화
        self.bluetoothManager = BluetoothManager(configuration: configuration, logger: logger)
        self.dataRecorder = DataRecorder(logger: logger)
        
        // 기본값: auto-reconnect 활성화 (대부분의 경우 유용함)
        self.isAutoReconnectEnabled = true
        
        setupDelegates()
        updateRecordedFiles()
        
        // BluetoothManager에 초기 auto-reconnect 설정 전달
        bluetoothManager.enableAutoReconnect(true)
    }
    
    // MARK: - Public Interface
    
    /// Bluetooth 디바이스 스캔을 시작합니다.
    ///
    /// ## 예시
    /// ```swift
    /// bluetoothKit.startScanning()
    /// ```
    public func startScanning() {
        bluetoothManager.startScanning()
    }
    
    /// Bluetooth 디바이스 스캔을 중지합니다.
    ///
    /// ## 예시
    /// ```swift
    /// bluetoothKit.stopScanning()
    /// ```
    public func stopScanning() {
        bluetoothManager.stopScanning()
    }
    
    /// 특정 Bluetooth 디바이스에 연결합니다.
    ///
    /// - Parameter device: 연결할 디바이스
    ///
    /// ## 예시
    /// ```swift
    /// if let device = bluetoothKit.discoveredDevices.first(where: { $0.name.contains("LinkBand") }) {
    ///     bluetoothKit.connect(to: device)
    /// }
    /// ```
    public func connect(to device: BluetoothDevice) {
        bluetoothManager.connect(to: device)
    }
    
    /// 현재 연결된 디바이스에서 연결을 해제합니다.
    ///
    /// ## 예시
    /// ```swift
    /// bluetoothKit.disconnect()
    /// ```
    public func disconnect() {
        if isRecording {
            stopRecording()
        }
        bluetoothManager.disconnect()
    }
    
    /// 센서 데이터를 파일로 기록하기 시작합니다.
    ///
    /// ## 예시
    /// ```swift
    /// bluetoothKit.startRecording()
    /// ```
    public func startRecording() {
        dataRecorder.startRecording()
    }
    
    /// 센서 데이터 기록을 중지합니다.
    ///
    /// ## 예시
    /// ```swift
    /// bluetoothKit.stopRecording()
    /// ```
    public func stopRecording() {
        dataRecorder.stopRecording()
    }
    
    /// 기록이 저장되는 디렉토리를 가져옵니다.
    ///
    /// - Returns: CSV 및 JSON 파일이 저장되는 documents 디렉토리의 URL.
    ///
    /// 기록된 파일에 프로그래밍적으로 접근하거나 공유 기능을 위해 사용하세요.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 기록 디렉토리 경로 표시
    /// Text("저장 위치: \(bluetoothKit.recordingsDirectory.path)")
    ///
    /// // 파일 공유
    /// let activityViewController = UIActivityViewController(
    ///     activityItems: [bluetoothKit.recordingsDirectory],
    ///     applicationActivities: nil
    /// )
    /// ```
    public var recordingsDirectory: URL {
        return dataRecorder.recordingsDirectory
    }
    
    /// 현재 디바이스에 연결되어 있는지 확인합니다.
    ///
    /// - Returns: 디바이스가 연결되어 데이터 스트리밍 준비가 되었으면 `true`.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 연결 상태에 따른 UI 표시
    /// Circle()
    ///     .fill(bluetoothKit.isConnected ? Color.green : Color.red)
    ///     .frame(width: 10, height: 10)
    ///
    /// // 연결 상태에 따른 버튼 활성화
    /// Button("기록 시작") { }
    ///     .disabled(!bluetoothKit.isConnected)
    /// ```
    public var isConnected: Bool {
        return bluetoothManager.isConnected
    }
    
    /// auto-reconnection을 활성화하거나 비활성화합니다.
    ///
    /// - Parameter enabled: 연결이 끊어졌을 때 자동으로 재연결할지 여부.
    ///
    /// 활성화되면, 연결이 예기치 않게 끊어졌을 때(사용자 작업이 아닌 경우)
    /// 라이브러리가 자동으로 마지막에 연결된 디바이스에 재연결을 시도합니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // 견고한 연결을 위해 auto-reconnect 활성화
    /// bluetoothKit.setAutoReconnect(enabled: true)
    /// 
    /// // 수동 연결 제어를 위해 비활성화
    /// bluetoothKit.setAutoReconnect(enabled: false)
    /// ```
    public func setAutoReconnect(enabled: Bool) {
        isAutoReconnectEnabled = enabled
        bluetoothManager.enableAutoReconnect(enabled)
    }
    
    // MARK: - Batch Data Collection API
    
    /// 시간 간격을 기준으로 배치 데이터 수집을 설정합니다.
    ///
    /// 지정된 시간마다 해당 센서의 데이터를 배치로 수집하여 델리게이트에 전달합니다.
    /// 시간 간격은 센서의 샘플링 레이트에 따라 적절한 샘플 개수로 자동 변환됩니다.
    ///
    /// - Parameters:
    ///   - timeInterval: 배치 수집 간격 (초 단위, 0.04 ~ 10.0초)
    ///   - sensorType: 설정할 센서 타입
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // EEG 데이터를 0.5초마다 배치로 수집 (125개 샘플)
    /// bluetoothKit.setDataCollection(timeInterval: 0.5, for: .eeg)
    ///
    /// // PPG 데이터를 1초마다 배치로 수집 (50개 샘플)
    /// bluetoothKit.setDataCollection(timeInterval: 1.0, for: .ppg)
    ///
    /// // 가속도계 데이터를 2초마다 배치로 수집 (60개 샘플)
    /// bluetoothKit.setDataCollection(timeInterval: 2.0, for: .accelerometer)
    /// ```
    public func setDataCollection(timeInterval: TimeInterval, for sensorType: SensorType) {
        let config = DataCollectionConfig(sensorType: sensorType, timeInterval: timeInterval)
        dataCollectionConfigs[sensorType] = config
        clearBuffer(for: sensorType)
    }
    
    /// 샘플 개수를 기준으로 배치 데이터 수집을 설정합니다.
    ///
    /// 지정된 개수의 샘플이 누적되면 배치로 수집하여 델리게이트에 전달합니다.
    /// 정확한 샘플 개수 제어가 필요한 신호 처리나 분석에 유용합니다.
    ///
    /// - Parameters:
    ///   - sampleCount: 배치당 샘플 개수 (1 ~ 각 센서별 최대값)
    ///   - sensorType: 설정할 센서 타입
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // EEG 데이터를 100개씩 배치로 수집
    /// bluetoothKit.setDataCollection(sampleCount: 100, for: .eeg)
    ///
    /// // PPG 데이터를 25개씩 배치로 수집
    /// bluetoothKit.setDataCollection(sampleCount: 25, for: .ppg)
    ///
    /// // 가속도계 데이터를 15개씩 배치로 수집
    /// bluetoothKit.setDataCollection(sampleCount: 15, for: .accelerometer)
    /// ```
    public func setDataCollection(sampleCount: Int, for sensorType: SensorType) {
        let config = DataCollectionConfig(sensorType: sensorType, sampleCount: sampleCount)
        dataCollectionConfigs[sensorType] = config
        clearBuffer(for: sensorType)
    }
    
    /// 특정 센서의 배치 데이터 수집을 비활성화합니다.
    ///
    /// 해당 센서는 기본 동작(latest* 프로퍼티 업데이트)만 수행하고
    /// 배치 델리게이트 호출은 중단됩니다.
    ///
    /// - Parameter sensorType: 비활성화할 센서 타입
    ///
    /// ## 예시
    ///
    /// ```swift
    /// // EEG 배치 수집 중단
    /// bluetoothKit.disableDataCollection(for: .eeg)
    /// ```
    public func disableDataCollection(for sensorType: SensorType) {
        dataCollectionConfigs.removeValue(forKey: sensorType)
        clearBuffer(for: sensorType)
    }
    
    /// 모든 센서의 배치 데이터 수집을 비활성화합니다.
    ///
    /// ## 예시
    ///
    /// ```swift
    /// bluetoothKit.disableAllDataCollection()
    /// ```
    public func disableAllDataCollection() {
        dataCollectionConfigs.removeAll()
        clearAllBuffers()
    }
    
    // MARK: - Private Setup
    
    /// 센서별 버퍼를 초기화합니다.
    private func clearBuffer(for sensorType: SensorType) {
        switch sensorType {
        case .eeg:
            eegBuffer.removeAll()
        case .ppg:
            ppgBuffer.removeAll()
        case .accelerometer:
            accelerometerBuffer.removeAll()
        case .battery:
            break // 배터리는 버퍼 없음
        }
    }
    
    /// 모든 센서 버퍼를 초기화합니다.
    private func clearAllBuffers() {
        eegBuffer.removeAll()
        ppgBuffer.removeAll()
        accelerometerBuffer.removeAll()
    }
    
    /// EEG 데이터를 버퍼에 추가하고 배치 조건을 확인합니다.
    private func addToEEGBuffer(_ reading: EEGReading) {
        guard let config = dataCollectionConfigs[.eeg] else { return }
        
        eegBuffer.append(reading)
        
        if eegBuffer.count >= config.targetSampleCount {
            let batch = Array(eegBuffer.prefix(config.targetSampleCount))
            eegBuffer.removeFirst(config.targetSampleCount)
            
            DispatchQueue.main.async { [weak self] in
                self?.batchDataDelegate?.didReceiveEEGBatch(batch)
            }
        }
    }
    
    /// PPG 데이터를 버퍼에 추가하고 배치 조건을 확인합니다.
    private func addToPPGBuffer(_ reading: PPGReading) {
        guard let config = dataCollectionConfigs[.ppg] else { return }
        
        ppgBuffer.append(reading)
        
        if ppgBuffer.count >= config.targetSampleCount {
            let batch = Array(ppgBuffer.prefix(config.targetSampleCount))
            ppgBuffer.removeFirst(config.targetSampleCount)
            
            DispatchQueue.main.async { [weak self] in
                self?.batchDataDelegate?.didReceivePPGBatch(batch)
            }
        }
    }
    
    /// 가속도계 데이터를 버퍼에 추가하고 배치 조건을 확인합니다.
    private func addToAccelerometerBuffer(_ reading: AccelerometerReading) {
        guard let config = dataCollectionConfigs[.accelerometer] else { return }
        
        accelerometerBuffer.append(reading)
        
        if accelerometerBuffer.count >= config.targetSampleCount {
            let batch = Array(accelerometerBuffer.prefix(config.targetSampleCount))
            accelerometerBuffer.removeFirst(config.targetSampleCount)
            
            DispatchQueue.main.async { [weak self] in
                self?.batchDataDelegate?.didReceiveAccelerometerBatch(batch)
            }
        }
    }
    
    private func setupDelegates() {
        bluetoothManager.delegate = self
        bluetoothManager.sensorDataDelegate = self
        dataRecorder.delegate = self
    }
    
    private func updateRecordedFiles() {
        recordedFiles = dataRecorder.getRecordedFiles()
    }
}

// MARK: - BluetoothManagerDelegate

@available(iOS 13.0, macOS 10.15, *)
extension BluetoothKit: BluetoothManagerDelegate {
    
    internal func bluetoothManager(_ manager: AnyObject, didUpdateState state: ConnectionState) {
        connectionState = state
        connectionStatusDescription = state.description
        isScanning = bluetoothManager.isScanning
        
        if case .failed(let error) = state,
           error.localizedDescription.contains("Bluetooth is not available") {
            isBluetoothDisabled = true
        } else {
            isBluetoothDisabled = false
        }
    }
    
    internal func bluetoothManager(_ manager: AnyObject, didDiscoverDevice device: BluetoothDevice) {
        if !discoveredDevices.contains(where: { $0.peripheral.identifier == device.peripheral.identifier }) {
            discoveredDevices.append(device)
        }
    }
    
    internal func bluetoothManager(_ manager: AnyObject, didConnectToDevice device: BluetoothDevice) {
        // 연결 성공 로그 제거
    }
    
    internal func bluetoothManager(_ manager: AnyObject, didDisconnectFromDevice device: BluetoothDevice, error: Error?) {
        if let error = error {
            log("Disconnected from \(device.name) with error: \(error.localizedDescription)")
        }
        // 정상 연결 해제는 로그하지 않음
    }
}

// MARK: - SensorDataDelegate

@available(iOS 13.0, macOS 10.15, *)
extension BluetoothKit: SensorDataDelegate {
    
    internal func didReceiveEEGData(_ reading: EEGReading) {
        latestEEGReading = reading
        
        if isRecording {
            dataRecorder.recordEEGData([reading])
        }
        
        addToEEGBuffer(reading)
    }
    
    internal func didReceivePPGData(_ reading: PPGReading) {
        latestPPGReading = reading
        
        if isRecording {
            dataRecorder.recordPPGData([reading])
        }
        
        addToPPGBuffer(reading)
    }
    
    internal func didReceiveAccelerometerData(_ reading: AccelerometerReading) {
        latestAccelerometerReading = reading
        
        if isRecording {
            dataRecorder.recordAccelerometerData([reading])
        }
        
        addToAccelerometerBuffer(reading)
    }
    
    internal func didReceiveBatteryData(_ reading: BatteryReading) {
        latestBatteryReading = reading
        
        if isRecording {
            dataRecorder.recordBatteryData(reading)
        }
        
        // 배터리는 배치가 아닌 개별 업데이트로 처리
        DispatchQueue.main.async { [weak self] in
            self?.batchDataDelegate?.didReceiveBatteryUpdate(reading)
        }
    }
}

// MARK: - DataRecorderDelegate

@available(iOS 13.0, macOS 10.15, *)
extension BluetoothKit: DataRecorderDelegate {
    
    internal func dataRecorder(_ recorder: AnyObject, didStartRecording at: Date) {
        isRecording = true
    }
    
    internal func dataRecorder(_ recorder: AnyObject, didStopRecording at: Date, savedFiles: [URL]) {
        isRecording = false
        recordedFiles = savedFiles
    }
    
    internal func dataRecorder(_ recorder: AnyObject, didFailWithError error: Error) {
        isRecording = false
        log("Recording failed: \(error.localizedDescription)")
    }
    
    // MARK: - Private Logging
    
    private func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        logger.log(message, file: file, function: function, line: line)
    }
} 