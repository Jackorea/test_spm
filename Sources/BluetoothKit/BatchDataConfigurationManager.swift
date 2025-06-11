import Foundation
import Combine

/// 배치 데이터 수집 설정을 관리하는 비즈니스 로직 클래스
/// UI 프레임워크에 의존하지 않는 순수한 비즈니스 로직을 제공합니다.
public class BatchDataConfigurationManager {
    
    // MARK: - Types
    
    public enum CollectionMode: String, CaseIterable {
        case sampleCount = "샘플 수"
        case duration = "시간 (초)"
        
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
    
    /// 유효성 검사 범위 정의
    private struct ValidationRange {
        static let sampleCount = 1...100000
        static let duration = 1...3600
    }
    
    // MARK: - Published Properties (Combine을 사용한 반응형 프로그래밍)
    
    @Published public var selectedCollectionMode: CollectionMode = .sampleCount
    @Published public var selectedSensors: Set<SensorType> = [.eeg, .ppg, .accelerometer]
    @Published public var isConfigured = false
    
    /// 센서별 설정을 관리하는 Dictionary
    @Published private var sensorConfigurations: [SensorType: SensorConfiguration] = [:]
    
    // MARK: - Dependencies
    
    private let bluetoothKit: BluetoothKit
    private var batchDelegate: BatchDataConsoleLogger?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public init(bluetoothKit: BluetoothKit) {
        self.bluetoothKit = bluetoothKit
        initializeDefaultConfigurations()
        setupReactiveBindings()
    }
    
    // MARK: - Public Configuration Methods
    
    public func applyInitialConfiguration() {
        guard !selectedSensors.isEmpty else { return }
        
        setupBatchDelegate()
        configureAllSensors()
        isConfigured = true
    }
    
    public func removeConfiguration() {
        bluetoothKit.disableAllDataCollection()
        batchDelegate?.updateSelectedSensors(Set<SensorType>())
        bluetoothKit.batchDataDelegate = nil
        batchDelegate = nil
        isConfigured = false
        print("❌ 배치 데이터 수집 설정 해제")
    }
    
    public func updateSensorSelection(_ sensors: Set<SensorType>) {
        selectedSensors = sensors
    }
    
    public func updateCollectionMode(_ mode: CollectionMode) {
        selectedCollectionMode = mode
    }
    
    // MARK: - Sensor Configuration Access
    
    /// 특정 센서의 샘플 수를 반환
    public func getSampleCount(for sensor: SensorType) -> Int {
        return sensorConfigurations[sensor]?.sampleCount ?? SensorConfiguration.defaultConfiguration(for: sensor).sampleCount
    }
    
    /// 특정 센서의 시간(초)을 반환
    public func getDuration(for sensor: SensorType) -> Int {
        return sensorConfigurations[sensor]?.duration ?? SensorConfiguration.defaultConfiguration(for: sensor).duration
    }
    
    /// 특정 센서의 샘플 수 텍스트를 반환
    public func getSampleCountText(for sensor: SensorType) -> String {
        return sensorConfigurations[sensor]?.sampleCountText ?? "\(getSampleCount(for: sensor))"
    }
    
    /// 특정 센서의 시간 텍스트를 반환
    public func getDurationText(for sensor: SensorType) -> String {
        return sensorConfigurations[sensor]?.durationText ?? "\(getDuration(for: sensor))"
    }
    
    /// 특정 센서의 샘플 수를 설정
    public func setSampleCount(_ value: Int, for sensor: SensorType) {
        ensureConfigurationExists(for: sensor)
        sensorConfigurations[sensor]?.sampleCount = value
        sensorConfigurations[sensor]?.sampleCountText = "\(value)"
    }
    
    /// 특정 센서의 시간을 설정
    public func setDuration(_ value: Int, for sensor: SensorType) {
        ensureConfigurationExists(for: sensor)
        sensorConfigurations[sensor]?.duration = value
        sensorConfigurations[sensor]?.durationText = "\(value)"
    }
    
    /// 특정 센서의 샘플 수 텍스트를 설정
    public func setSampleCountText(_ text: String, for sensor: SensorType) {
        ensureConfigurationExists(for: sensor)
        sensorConfigurations[sensor]?.sampleCountText = text
    }
    
    /// 특정 센서의 시간 텍스트를 설정
    public func setDurationText(_ text: String, for sensor: SensorType) {
        ensureConfigurationExists(for: sensor)
        sensorConfigurations[sensor]?.durationText = text
    }
    
    // MARK: - Validation Methods
    
    /// 샘플 수 유효성 검사
    public func validateSampleCount(_ text: String, for sensor: SensorType) -> ValidationResult {
        return validateValue(text, for: sensor, valueType: .sampleCount, range: ValidationRange.sampleCount)
    }
    
    /// 시간 유효성 검사
    public func validateDuration(_ text: String, for sensor: SensorType) -> ValidationResult {
        return validateValue(text, for: sensor, valueType: .duration, range: ValidationRange.duration)
    }
    
    // MARK: - Helper Methods
    
    public func getExpectedTime(for sensor: SensorType, sampleCount: Int) -> Double {
        return sensor.expectedTime(for: sampleCount)
    }
    
    public func getExpectedSamples(for sensor: SensorType, duration: Int) -> Int {
        return sensor.expectedSamples(for: TimeInterval(duration))
    }
    
    /// 모든 센서 설정을 기본값으로 리셋
    public func resetToDefaults() {
        initializeDefaultConfigurations()
    }
    
    /// 설정 상태 요약 반환
    public func getConfigurationSummary() -> String {
        let mode = selectedCollectionMode.displayName
        let sensors = selectedSensors.map { $0.displayName }.joined(separator: ", ")
        return "모드: \(mode), 센서: \(sensors)"
    }
    
    /// 특정 센서가 선택되었는지 확인
    public func isSensorSelected(_ sensor: SensorType) -> Bool {
        return selectedSensors.contains(sensor)
    }
    
    // MARK: - Private Methods
    
    private enum ValueType {
        case sampleCount
        case duration
    }
    
    /// 기본 설정 초기화
    private func initializeDefaultConfigurations() {
        for sensorType in SensorType.allCases {
            sensorConfigurations[sensorType] = SensorConfiguration.defaultConfiguration(for: sensorType)
        }
    }
    
    /// 반응형 바인딩 설정
    private func setupReactiveBindings() {
        // 설정이 변경될 때마다 자동으로 적용
        Publishers.CombineLatest(
            $selectedCollectionMode,
            $selectedSensors
        )
        .dropFirst() // 초기값 무시
        .sink { [weak self] _, _ in
            if self?.isConfigured == true {
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
    
    /// 값 유효성 검사 및 업데이트
    private func validateValue(_ text: String, for sensor: SensorType, valueType: ValueType, range: ClosedRange<Int>) -> ValidationResult {
        guard let value = Int(text), value > 0 else {
            if !text.isEmpty {
                return ValidationResult(isValid: false, message: "유효한 숫자를 입력해주세요")
            }
            return ValidationResult(isValid: false)
        }
        
        let clampedValue = max(range.lowerBound, min(value, range.upperBound))
        
        switch valueType {
        case .sampleCount:
            updateSampleCount(clampedValue, for: sensor, originalValue: value)
        case .duration:
            updateDuration(clampedValue, for: sensor, originalValue: value)
        }
        
        return ValidationResult(isValid: true)
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
                configureSensor(sensorType, isInitial: true)
            } else {
                bluetoothKit.disableDataCollection(for: sensorType)
                print("🚫 초기 비활성화: \(sensorType.displayName) - 데이터 수집 제외")
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
    private func configureSensor(_ sensor: SensorType, isInitial: Bool = false) {
        let prefix = isInitial ? "🔧 초기 설정" : "🔄 자동 변경"
        
        switch selectedCollectionMode {
        case .sampleCount:
            let sampleCount = getSampleCount(for: sensor)
            bluetoothKit.setDataCollection(sampleCount: sampleCount, for: sensor)
            
            let expectedTime = getExpectedTime(for: sensor, sampleCount: sampleCount)
            print("\(prefix): \(sensor.displayName) - \(sampleCount)개 샘플마다 배치 수신")
            print("   → \(sensor.displayName): \(sampleCount)개 샘플 = 약 \(String(format: "%.1f", expectedTime))초")
            
        case .duration:
            let duration = getDuration(for: sensor)
            bluetoothKit.setDataCollection(timeInterval: TimeInterval(duration), for: sensor)
            
            let expectedSamples = getExpectedSamples(for: sensor, duration: duration)
            print("\(prefix): \(sensor.displayName) - \(duration)초마다 배치 수신")
            print("   → \(sensor.displayName): \(duration)초마다 약 \(expectedSamples)개 샘플 예상")
        }
    }
    
    /// 샘플 수 업데이트
    private func updateSampleCount(_ value: Int, for sensor: SensorType, originalValue: Int) {
        ensureConfigurationExists(for: sensor)
        sensorConfigurations[sensor]?.sampleCount = value
        if value != originalValue {
            sensorConfigurations[sensor]?.sampleCountText = "\(value)"
        }
    }
    
    /// 시간 업데이트
    private func updateDuration(_ value: Int, for sensor: SensorType, originalValue: Int) {
        ensureConfigurationExists(for: sensor)
        sensorConfigurations[sensor]?.duration = value
        if value != originalValue {
            sensorConfigurations[sensor]?.durationText = "\(value)"
        }
    }
} 