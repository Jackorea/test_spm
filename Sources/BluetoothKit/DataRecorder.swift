import Foundation

// MARK: - Data Recorder

/// 센서 데이터를 CSV 파일로 기록하고 관리하는 클래스입니다.
///
/// 이 클래스는 실시간으로 수신되는 센서 데이터를 백그라운드에서 
/// 효율적으로 CSV 파일에 저장합니다. BluetoothKit의 내부 구현체로 사용됩니다.
internal class DataRecorder: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// 데이터 기록 이벤트를 처리하는 델리게이트입니다.
    public weak var delegate: DataRecorderDelegate?
    
    private var recordingState: RecordingState = .idle
    private let logger: InternalLogger
    private var selectedSensorTypes: Set<SensorType> = []
    
    // Unified file writers using a serial queue for thread safety
    private let fileQueue = DispatchQueue(label: "com.bluetoothkit.filewriter", qos: .utility)
    private var csvWriters: [SensorType: FileWriter] = [:]
    private var rawDataWriter: FileWriter?
    
    // Raw data storage for JSON - protected by main actor
    private var rawDataDict: [String: Any] = [:]
    private var currentRecordingFiles: [URL] = []
    
    // MARK: - Initialization
    
    /// 새로운 DataRecorder 인스턴스를 생성합니다.
    ///
    /// - Parameter logger: 로깅을 위한 내부 로거 (기본값: 비활성화)
    public init(logger: InternalLogger = InternalLogger(isEnabled: false)) {
        self.logger = logger
        initializeRawDataDict()
    }
    
    deinit {
        if recordingState.isRecording {
            stopRecording()
        }
    }
    
    // MARK: - Public Interface
    
    /// 현재 데이터 기록 중인지 여부를 나타냅니다.
    public var isRecording: Bool {
        return recordingState.isRecording
    }
    
    /// 기록된 파일들이 저장되는 디렉토리 URL을 반환합니다.
    public var recordingsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    /// 기록된 파일들의 URL 목록을 반환합니다.
    ///
    /// - Returns: 문서 디렉토리에 저장된 모든 기록 파일들의 URL 배열
    public func getRecordedFiles() -> [URL] {
        return (try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
    }
    
    /// 센서 데이터 기록을 시작합니다.
    ///
    /// 이미 기록 중인 경우 오류를 발생시킵니다.
    /// 기록 파일들(CSV, JSON)을 생성하고 기록 상태로 전환합니다.
    /// 
    /// - Parameter selectedSensors: 기록할 센서 타입들의 집합
    public func startRecording(with selectedSensors: Set<SensorType> = [.eeg, .ppg, .accelerometer]) {
        guard recordingState == .idle else {
            let error = BluetoothKitError.recordingFailed("Already recording")
            log("Failed to start recording: Already recording")
            notifyRecordingError(error)
            return
        }
        
        selectedSensorTypes = selectedSensors
        
        do {
            try setupRecordingFiles()
            recordingState = .recording
            notifyRecordingStarted(at: Date())
        } catch {
            notifyRecordingError(error)
            log("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    /// 센서 데이터 기록을 중지합니다.
    ///
    /// 기록 중이 아닌 경우 아무 작업도 수행하지 않습니다.
    /// 모든 파일을 정리하고 기록 완료 이벤트를 발생시킵니다.
    public func stopRecording() {
        guard recordingState == .recording else { return }
        
        do {
            try finalizeRecording()
            recordingState = .idle
            notifyRecordingStopped(at: Date(), savedFiles: currentRecordingFiles)
        } catch {
            recordingState = .idle
            notifyRecordingError(error)
            log("Failed to stop recording: \(error.localizedDescription)")
        }
    }
    
    /// 기록 중에 선택된 센서를 업데이트합니다.
    ///
    /// 기록 중이 아닌 경우 아무 작업도 수행하지 않습니다.
    /// 새로 선택된 센서만 향후 데이터가 기록됩니다.
    ///
    /// - Parameter selectedSensors: 기록할 센서 타입들의 집합
    public func updateSelectedSensors(_ selectedSensors: Set<SensorType>) {
        selectedSensorTypes = selectedSensors
    }
    
    /// 센서 타입을 문자열로 변환하는 헬퍼 메서드
    private func sensorTypeToString(_ sensorType: SensorType) -> String {
        switch sensorType {
        case .eeg: return "EEG"
        case .ppg: return "PPG"
        case .accelerometer: return "ACC"
        case .battery: return "배터리"
        }
    }
    
    // MARK: - Unified Data Recording Methods
    
    /// EEG 데이터를 기록합니다.
    ///
    /// - Parameter readings: 기록할 EEG 읽기값 배열
    public func recordEEGData(_ readings: [EEGReading]) {
        guard canRecord(.eeg) else { return }
        
        for reading in readings {
            recordSensorData(
                sensorType: .eeg,
                timestamp: reading.timestamp,
                csvData: [reading.ch1Raw, reading.ch2Raw, reading.channel1, reading.channel2, reading.leadOff ? 1 : 0],
                rawDataEntries: [
                    ("eegChannel1", reading.channel1),
                    ("eegChannel2", reading.channel2),
                    ("eegLeadOff", reading.leadOff ? 1 : 0)
                ]
            )
        }
    }
    
    /// PPG 데이터를 기록합니다.
    ///
    /// - Parameter readings: 기록할 PPG 읽기값 배열
    public func recordPPGData(_ readings: [PPGReading]) {
        guard canRecord(.ppg) else { return }
        
        for reading in readings {
            recordSensorData(
                sensorType: .ppg,
                timestamp: reading.timestamp,
                csvData: [reading.red, reading.ir],
                rawDataEntries: [
                    ("ppgRed", reading.red),
                    ("ppgIr", reading.ir)
                ]
            )
        }
    }
    
    /// 가속도계 데이터를 기록합니다.
    ///
    /// - Parameter readings: 기록할 가속도계 읽기값 배열
    public func recordAccelerometerData(_ readings: [AccelerometerReading]) {
        guard canRecord(.accelerometer) else { return }
        
        for reading in readings {
            recordSensorData(
                sensorType: .accelerometer,
                timestamp: reading.timestamp,
                csvData: [reading.x, reading.y, reading.z],
                rawDataEntries: [
                    ("accelX", Int(reading.x)),
                    ("accelY", Int(reading.y)),
                    ("accelZ", Int(reading.z))
                ]
            )
        }
    }
    
    /// 배터리 데이터를 기록합니다.
    ///
    /// - Parameter reading: 기록할 배터리 읽기값
    public func recordBatteryData(_ reading: BatteryReading) {
        guard isRecording else { return }
        // Battery data is not typically recorded in bulk files
    }
    
    // MARK: - Private Unified Helpers
    
    private func canRecord(_ sensorType: SensorType) -> Bool {
        return isRecording && selectedSensorTypes.contains(sensorType)
    }
    
    private func recordSensorData<T>(
        sensorType: SensorType,
        timestamp: Date,
        csvData: [T],
        rawDataEntries: [(String, Any)]
    ) {
        // Add to raw data dict
        for (key, value) in rawDataEntries {
            appendToRawDataDict(key, value: value)
        }
        
        // Write to CSV
        if let writer = csvWriters[sensorType] {
            let timestampValue = timestamp.timeIntervalSince1970
            let csvStringValues = [String(timestampValue)] + csvData.map { String(describing: $0) }
            let line = csvStringValues.joined(separator: ",") + "\n"
            writer.write(line)
        }
    }
    
    private func initializeRawDataDict() {
        rawDataDict = [
            "timestamp": [Double](),
            "eegChannel1": [Double](),
            "eegChannel2": [Double](),
            "eegLeadOff": [Int](),
            "ppgRed": [Int](),
            "ppgIr": [Int](),
            "accelX": [Int](),
            "accelY": [Int](),
            "accelZ": [Int]()
        ]
    }
    
    private func setupRecordingFiles() throws {
        let timestamp = createTimestamp()
        currentRecordingFiles = []
        csvWriters = [:]
        
        // Setup JSON file
        try setupJSONFile(timestamp: timestamp)
        
        // Setup CSV files for selected sensors
        for sensorType in selectedSensorTypes {
            try setupCSVFile(for: sensorType, timestamp: timestamp)
        }
        
        initializeRawDataDict()
    }
    
    private func createTimestamp() -> String {
        return DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
    
    private func setupJSONFile(timestamp: String) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let jsonTimestamp = dateFormatter.string(from: Date())
        
        let rawDataURL = recordingsDirectory.appendingPathComponent("raw_data_\(jsonTimestamp).json")
        try createFileWriter(at: rawDataURL) { writer in
            rawDataWriter = writer
        }
    }
    
    private func setupCSVFile(for sensorType: SensorType, timestamp: String) throws {
        let filename = "\(sensorType.csvFileName)_\(timestamp).csv"
        let csvURL = recordingsDirectory.appendingPathComponent(filename)
        
        try createFileWriter(at: csvURL) { writer in
            writer.write(sensorType.csvHeader)
            csvWriters[sensorType] = writer
        }
    }
    
    private func createFileWriter(at url: URL, setup: (FileWriter) throws -> Void) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw BluetoothKitError.fileOperationFailed("Could not create file at \(url.path)")
        }
        
        let writer = FileWriter(fileHandle: handle)
        try setup(writer)
        currentRecordingFiles.append(url)
    }
    
    private func appendToRawDataDict<T>(_ key: String, value: T) {
        if var array = rawDataDict[key] as? [T] {
            array.append(value)
            rawDataDict[key] = array
        }
    }
    
    private func finalizeRecording() throws {
        // Save JSON file
        try saveJSONFile()
        
        // Close all file handles
        closeAllWriters()
    }
    
    private func saveJSONFile() throws {
        guard let handle = rawDataWriter?.fileHandle else { return }
        
        let encodableData = SensorDataJSON(
            timestamp: rawDataDict["timestamp"] as? [Double] ?? [],
            eegChannel1: rawDataDict["eegChannel1"] as? [Double] ?? [],
            eegChannel2: rawDataDict["eegChannel2"] as? [Double] ?? [],
            eegLeadOff: rawDataDict["eegLeadOff"] as? [Int] ?? [],
            ppgRed: rawDataDict["ppgRed"] as? [Int] ?? [],
            ppgIr: rawDataDict["ppgIr"] as? [Int] ?? [],
            accelX: rawDataDict["accelX"] as? [Int] ?? [],
            accelY: rawDataDict["accelY"] as? [Int] ?? [],
            accelZ: rawDataDict["accelZ"] as? [Int] ?? []
        )
        
        do {
            let jsonData = try JSONEncoder().encode(encodableData)
            handle.seek(toFileOffset: 0)
            handle.write(jsonData)
        } catch {
            throw BluetoothKitError.fileOperationFailed("Failed to encode JSON: \(error)")
        }
    }
    
    private func closeAllWriters() {
        if #available(iOS 13.0, macOS 10.15, *) {
            try? rawDataWriter?.fileHandle.close()
            csvWriters.values.forEach { try? $0.fileHandle.close() }
        }
        
        rawDataWriter = nil
        csvWriters.removeAll()
    }
    
    private func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        logger.log(message, file: file, function: function, line: line)
    }
    
    // MARK: - Unified Notification Methods
    
    private func notifyOnMainThread(_ action: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
    
    private func notifyRecordingStarted(at date: Date) {
        notifyOnMainThread { [weak self] in
            guard let self = self else { return }
            self.delegate?.dataRecorder(self, didStartRecording: date)
        }
    }
    
    private func notifyRecordingStopped(at date: Date, savedFiles: [URL]) {
        notifyOnMainThread { [weak self] in
            guard let self = self else { return }
            self.delegate?.dataRecorder(self, didStopRecording: date, savedFiles: savedFiles)
        }
    }
    
    private func notifyRecordingError(_ error: Error) {
        notifyOnMainThread { [weak self] in
            guard let self = self else { return }
            self.delegate?.dataRecorder(self, didFailWithError: error)
        }
    }
}

// MARK: - SensorType Extensions

private extension SensorType {
    var csvFileName: String {
        switch self {
        case .eeg: return "eeg_data"
        case .ppg: return "ppg_data"
        case .accelerometer: return "accel_data"
        case .battery: return "battery_data"
        }
    }
    
    var csvHeader: String {
        switch self {
        case .eeg: return "timestamp,ch1Raw,ch2Raw,ch1uV,ch2uV,leadOff\n"
        case .ppg: return "timestamp,red,ir\n"
        case .accelerometer: return "timestamp,x,y,z\n"
        case .battery: return "timestamp,level\n"
        }
    }
}

// MARK: - File Writer Helper

private class FileWriter {
    let fileHandle: FileHandle
    
    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }
    
    func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
}

// MARK: - JSON Data Structure

private struct SensorDataJSON: Encodable {
    let timestamp: [Double]
    let eegChannel1: [Double]
    let eegChannel2: [Double]
    let eegLeadOff: [Int]
    let ppgRed: [Int]
    let ppgIr: [Int]
    let accelX: [Int]
    let accelY: [Int]
    let accelZ: [Int]
} 
