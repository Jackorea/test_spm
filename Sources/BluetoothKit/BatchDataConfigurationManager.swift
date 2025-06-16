import Foundation
import Combine

/// 배치 데이터 수집 설정을 관리하는 비즈니스 로직 클래스
/// UI 프레임워크에 의존하지 않는 순수한 비즈니스 로직을 제공합니다.
public class BatchDataConfigurationManager {
    
    // MARK: - Types
    
    public enum CollectionMode: String, CaseIterable {
        case sampleCount = "샘플 수"
        case duration = "초단위"
        case minuteDuration = "분단위"
        
        public var displayName: String { rawValue }
    }
    
    /// 센서 설정을 관리하는 구조체
    public struct SensorConfiguration {
        public var sampleCount: Int
        public var duration: Int
        public var sampleCountText: String
        public var durationText: String
        
        public init(sampleCount: Int, duration: Int) {
            self.sampleCount = sampleCount
            self.duration = duration
            self.sampleCountText = "\(sampleCount)"
            self.durationText = "\(duration)"
        }
        
        /// 기본값 설정
        public static func defaultConfiguration(for sensorType: SensorType) -> SensorConfiguration {
            switch sensorType {
            case .eeg:
                return SensorConfiguration(sampleCount: 250, duration: 1)
            case .ppg:
                return SensorConfiguration(sampleCount: 50, duration: 1)
            case .accelerometer:
                return SensorConfiguration(sampleCount: 30, duration: 1)
            case .battery:
                return SensorConfiguration(sampleCount: 1, duration: 60)
            }
        }
    }
    
    /// 유효성 검사 결과
    public struct ValidationResult {
        public let isValid: Bool
        public let message: String?
        
        public init(isValid: Bool, message: String? = nil) {
            self.isValid = isValid
            self.message = message
        }
    }
    
    /// 설정 변경 타입 (단순화)
    public enum ConfigurationChangeType {
        case sensorSelection(Set<SensorType>)
        case sampleCount(Int, SensorType)
        case duration(Int, SensorType)
    }
    
    // MARK: - Published Properties
    
    @Published public var selectedCollectionMode: CollectionMode = .sampleCount
    @Published public var selectedSensors: Set<SensorType> = [.eeg, .ppg, .accelerometer]
    @Published public var isMonitoringActive = false
    
    // 경고 팝업 관련 상태
    @Published public var showRecordingChangeWarning = false
    @Published public var pendingConfigurationChange: ConfigurationChangeType?
    @Published public var pendingSensorSelection: Set<SensorType>? // 하위 호환성
    
    /// 센서별 설정을 관리하는 Dictionary
    @Published private var sensorConfigurations: [SensorType: SensorConfiguration] = [:]
    
    // MARK: - Dependencies
    
    private let bluetoothKit: BluetoothKit
    private var batchDelegate: BatchDataConsoleLogger?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    
    private enum ValidationRange {
        static let sampleCount = 1...100000
        static let duration = 1...3600
    }
    
    public enum ValueType {
        case sampleCount
        case duration
    }
    
    // MARK: - Initialization
    
    public init(bluetoothKit: BluetoothKit) {
        self.bluetoothKit = bluetoothKit
        self.initializeDefaultConfigurations()
        self.setupReactiveBindings()
    }
    
    // MARK: - Public Configuration Methods
    
    public func startMonitoring() {
        guard !selectedSensors.isEmpty else { return }
        
        setupBatchDelegate()
        configureAllSensors()
        bluetoothKit.enableMonitoring()
        isMonitoringActive = true
    }
    
    public func stopMonitoring() {
        bluetoothKit.disableAllDataCollection()
        bluetoothKit.disableMonitoring()
        batchDelegate?.updateSelectedSensors(Set<SensorType>())
        bluetoothKit.batchDataDelegate = nil
        batchDelegate = nil
        isMonitoringActive = false
    }
    
    public func updateSensorSelection(_ sensors: Set<SensorType>) {
        if checkRecordingAndWarn(for: .sensorSelection(sensors)) { return }
        applySensorSelection(sensors)
    }
    
    public func updateCollectionMode(_ mode: CollectionMode) {
        selectedCollectionMode = mode
    }
    
    // MARK: - Configuration Access (통합된 getter/setter)
    
    public func getValue(for sensor: SensorType, type: ValueType) -> Int {
        let config = sensorConfigurations[sensor] ?? SensorConfiguration.defaultConfiguration(for: sensor)
        return type == .sampleCount ? config.sampleCount : config.duration
    }
    
    public func getValueText(for sensor: SensorType, type: ValueType) -> String {
        let config = sensorConfigurations[sensor] ?? SensorConfiguration.defaultConfiguration(for: sensor)
        return type == .sampleCount ? config.sampleCountText : config.durationText
    }
    
    public func setValue(_ value: Int, for sensor: SensorType, type: ValueType) {
        let changeType: ConfigurationChangeType = type == .sampleCount ? 
            .sampleCount(value, sensor) : .duration(value, sensor)
        
        if checkRecordingAndWarn(for: changeType) { return }
        updateSensorConfiguration(for: sensor, value: value, type: type)
    }
    
    public func setValueText(_ text: String, for sensor: SensorType, type: ValueType) {
        ensureConfigurationExists(for: sensor)
        if type == .sampleCount {
            sensorConfigurations[sensor]?.sampleCountText = text
        } else {
            sensorConfigurations[sensor]?.durationText = text
        }
    }
    
    // MARK: - Legacy Getters/Setters (하위 호환성)
    
    public func getSampleCount(for sensor: SensorType) -> Int {
        return getValue(for: sensor, type: .sampleCount)
    }
    
    public func getDuration(for sensor: SensorType) -> Int {
        return getValue(for: sensor, type: .duration)
    }
    
    public func getSampleCountText(for sensor: SensorType) -> String {
        return getValueText(for: sensor, type: .sampleCount)
    }
    
    public func getDurationText(for sensor: SensorType) -> String {
        return getValueText(for: sensor, type: .duration)
    }
    
    public func setSampleCount(_ value: Int, for sensor: SensorType) {
        setValue(value, for: sensor, type: .sampleCount)
    }
    
    public func setDuration(_ value: Int, for sensor: SensorType) {
        setValue(value, for: sensor, type: .duration)
    }
    
    public func setSampleCountText(_ text: String, for sensor: SensorType) {
        setValueText(text, for: sensor, type: .sampleCount)
    }
    
    public func setDurationText(_ text: String, for sensor: SensorType) {
        setValueText(text, for: sensor, type: .duration)
    }
    
    // MARK: - Validation Methods (통합)
    
    public func validateValue(_ text: String, for sensor: SensorType, type: ValueType) -> ValidationResult {
        guard let value = Int(text), value > 0 else {
            if !text.isEmpty {
                return ValidationResult(isValid: false, message: "유효한 숫자를 입력해주세요")
            }
            return ValidationResult(isValid: false)
        }
        
        let range = type == .sampleCount ? ValidationRange.sampleCount : ValidationRange.duration
        let clampedValue = max(range.lowerBound, min(value, range.upperBound))
        updateSensorConfiguration(for: sensor, value: clampedValue, type: type)
        return ValidationResult(isValid: true)
    }
    
    public func validateSampleCount(_ text: String, for sensor: SensorType) -> ValidationResult {
        return validateValue(text, for: sensor, type: .sampleCount)
    }
    
    public func validateDuration(_ text: String, for sensor: SensorType) -> ValidationResult {
        return validateValue(text, for: sensor, type: .duration)
    }
    
    // MARK: - Warning Dialog Methods
    
    public func confirmSensorChangeWithRecordingStop() {
        guard let pendingChange = pendingConfigurationChange else { return }
        
        print("✅ 사용자 확인: 기록 중지 후 설정 변경")
        bluetoothKit.stopRecording()
        applyConfigurationChange(pendingChange)
        clearPendingChanges()
    }
    
    public func cancelSensorChange() {
        print("❌ 사용자 취소: 설정 변경 취소")
        clearPendingChanges()
    }
    
    // MARK: - Helper Methods
    
    public func getExpectedTime(for sensor: SensorType, sampleCount: Int) -> Double {
        return sensor.expectedTime(for: sampleCount)
    }
    
    public func getExpectedSamples(for sensor: SensorType, duration: Int) -> Int {
        return sensor.expectedSamples(for: TimeInterval(duration))
    }
    
    public func resetToDefaults() {
        initializeDefaultConfigurations()
    }
    
    public func getConfigurationSummary() -> String {
        let mode = selectedCollectionMode.displayName
        let sensors = selectedSensors.map { $0.displayName }.joined(separator: ", ")
        return "모드: \(mode), 센서: \(sensors)"
    }
    
    public func isSensorSelected(_ sensor: SensorType) -> Bool {
        return selectedSensors.contains(sensor)
    }
    
    // MARK: - Private Methods
    
    /// 기록 중인지 확인하고 필요한 경우 경고 표시 (통합된 체크 로직)
    private func checkRecordingAndWarn(for change: ConfigurationChangeType) -> Bool {
        if isMonitoringActive && bluetoothKit.isRecording {
            print("⚠️ 기록 중 설정 변경 시도 감지")
            pendingConfigurationChange = change
            if case .sensorSelection(let sensors) = change {
                pendingSensorSelection = sensors // 하위 호환성
            }
            showRecordingChangeWarning = true
            return true
        }
        return false
    }
    
    /// 설정 변경 적용 (통합된 적용 로직)
    private func applyConfigurationChange(_ change: ConfigurationChangeType) {
        switch change {
        case .sensorSelection(let sensors):
            applySensorSelection(sensors)
        case .sampleCount(let value, let sensor):
            updateSensorConfiguration(for: sensor, value: value, type: .sampleCount)
        case .duration(let value, let sensor):
            updateSensorConfiguration(for: sensor, value: value, type: .duration)
        }
    }
    
    /// 펜딩 상태 정리
    private func clearPendingChanges() {
        pendingConfigurationChange = nil
        pendingSensorSelection = nil
        showRecordingChangeWarning = false
    }
    
    /// 센서 선택 적용
    private func applySensorSelection(_ sensors: Set<SensorType>) {
        selectedSensors = sensors
        print("🔄 센서 선택 업데이트: \(sensors.map { $0.displayName }.joined(separator: ", "))")
        
        if isMonitoringActive {
            batchDelegate?.updateSelectedSensors(selectedSensors)
            print("📝 콘솔 출력 센서 즉시 업데이트: \(selectedSensors.map { $0.displayName }.joined(separator: ", "))")
            reconfigureSensorsForSelection()
        }
    }
    
    /// 센서 설정 업데이트 (통합된 업데이트 로직)
    private func updateSensorConfiguration(for sensor: SensorType, value: Int, type: ValueType) {
        ensureConfigurationExists(for: sensor)
        
        switch type {
        case .sampleCount:
            sensorConfigurations[sensor]?.sampleCount = value
            sensorConfigurations[sensor]?.sampleCountText = "\(value)"
        case .duration:
            sensorConfigurations[sensor]?.duration = value
            sensorConfigurations[sensor]?.durationText = "\(value)"
        }
        
        if isMonitoringActive && selectedSensors.contains(sensor) {
            configureSensor(sensor)
            let typeText = type == .sampleCount ? "샘플 수" : "시간 설정"
            let unitText = type == .sampleCount ? "개 샘플" : "초"
            print("🔄 \(typeText) 변경 적용: \(sensor.displayName) - \(value)\(unitText)")
        }
    }
    
    /// 기본 설정 초기화
    private func initializeDefaultConfigurations() {
        for sensorType in SensorType.allCases {
            sensorConfigurations[sensorType] = SensorConfiguration.defaultConfiguration(for: sensorType)
        }
    }
    
    /// 반응형 바인딩 설정
    private func setupReactiveBindings() {
        Publishers.CombineLatest($selectedCollectionMode, $selectedSensors)
            .dropFirst()
            .sink { [weak self] _, _ in
                if self?.isMonitoringActive == true {
                    self?.applyChanges()
                }
            }
            .store(in: &cancellables)
    }
    
    /// 센서 설정이 존재하는지 확인하고 없으면 생성
    private func ensureConfigurationExists(for sensor: SensorType) {
        if sensorConfigurations[sensor] == nil {
            sensorConfigurations[sensor] = SensorConfiguration.defaultConfiguration(for: sensor)
        }
    }
    
    /// 배치 델리게이트 설정
    private func setupBatchDelegate() {
        if batchDelegate == nil {
            batchDelegate = BatchDataConsoleLogger()
            bluetoothKit.batchDataDelegate = batchDelegate
        }
        batchDelegate?.updateSelectedSensors(selectedSensors)
    }
    
    /// 모든 센서 설정 적용
    private func configureAllSensors() {
        for sensorType in SensorType.allCases {
            if selectedSensors.contains(sensorType) {
                configureSensor(sensorType)
            } else {
                bluetoothKit.disableDataCollection(for: sensorType)
            }
        }
    }
    
    /// 변경사항 적용
    private func applyChanges() {
        setupBatchDelegate()
        
        if bluetoothKit.isRecording {
            bluetoothKit.updateRecordingSensors()
        }
        
        configureAllSensors()
    }
    
    /// 특정 센서 설정
    private func configureSensor(_ sensor: SensorType) {
        switch selectedCollectionMode {
        case .sampleCount:
            let sampleCount = getSampleCount(for: sensor)
            bluetoothKit.setDataCollection(sampleCount: sampleCount, for: sensor)
            
        case .duration:
            let duration = getDuration(for: sensor)
            bluetoothKit.setDataCollection(timeInterval: TimeInterval(duration), for: sensor)
            
        case .minuteDuration:
            let duration = getDuration(for: sensor)
            bluetoothKit.setDataCollection(timeInterval: TimeInterval(duration * 60), for: sensor)
        }
    }
    
    /// 센서 선택 변경에 따라 BluetoothKit의 데이터 수집을 재설정
    private func reconfigureSensorsForSelection() {
        for sensorType in SensorType.allCases {
            if selectedSensors.contains(sensorType) {
                configureSensor(sensorType)
            } else {
                bluetoothKit.disableDataCollection(for: sensorType)
            }
        }
    }
} 
