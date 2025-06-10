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
    
    // File writers - using a serial queue for thread safety
    private let fileQueue = DispatchQueue(label: "com.bluetoothkit.filewriter", qos: .utility)
    private var eegCsvWriter: FileWriter?
    private var ppgCsvWriter: FileWriter?
    private var accelCsvWriter: FileWriter?
    private var rawDataWriter: FileWriter?
    
    // Raw data storage for JSON - protected by main actor
    private var rawDataDict: [String: Any] = [:]
    
    // File URLs
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
    public func startRecording() {
        guard recordingState == .idle else {
            let error = BluetoothKitError.recordingFailed("Already recording")
            log("Failed to start recording: Already recording")
            notifyRecordingError(error)
            return
        }
        
        do {
            try setupRecordingFiles()
            recordingState = .recording
            
            let startDate = Date()
            notifyRecordingStarted(at: startDate)
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
            
            let endDate = Date()
            let savedFiles = currentRecordingFiles
            notifyRecordingStopped(at: endDate, savedFiles: savedFiles)
        } catch {
            recordingState = .idle
            notifyRecordingError(error)
            log("Failed to stop recording: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Recording Methods
    
    /// EEG 데이터를 기록합니다.
    ///
    /// - Parameter readings: 기록할 EEG 읽기값 배열
    public func recordEEGData(_ readings: [EEGReading]) {
        guard isRecording else { return }
        
        for reading in readings {
            // Add to raw data dict
            appendToRawDataDict("eegChannel1", value: reading.channel1)
            appendToRawDataDict("eegChannel2", value: reading.channel2)
            appendToRawDataDict("eegLeadOff", value: reading.leadOff ? 1 : 0)
            
            // Write to CSV
            if let writer = eegCsvWriter {
                let timestamp = reading.timestamp.timeIntervalSince1970
                let line = "\(timestamp),\(reading.ch1Raw),\(reading.ch2Raw),\(reading.channel1),\(reading.channel2),\(reading.leadOff ? 1 : 0)\n"
                writer.write(line)
            }
        }
    }
    
    /// PPG 데이터를 기록합니다.
    ///
    /// - Parameter readings: 기록할 PPG 읽기값 배열
    public func recordPPGData(_ readings: [PPGReading]) {
        guard isRecording else { return }
        
        for reading in readings {
            // Add to raw data dict
            appendToRawDataDict("ppgRed", value: reading.red)
            appendToRawDataDict("ppgIr", value: reading.ir)
            
            // Write to CSV
            if let writer = ppgCsvWriter {
                let timestamp = reading.timestamp.timeIntervalSince1970
                let line = "\(timestamp),\(reading.red),\(reading.ir)\n"
                writer.write(line)
            }
        }
    }
    
    /// 가속도계 데이터를 기록합니다.
    ///
    /// - Parameter readings: 기록할 가속도계 읽기값 배열
    public func recordAccelerometerData(_ readings: [AccelerometerReading]) {
        guard isRecording else { return }
        
        for reading in readings {
            // Add to raw data dict
            appendToRawDataDict("accelX", value: Int(reading.x))
            appendToRawDataDict("accelY", value: Int(reading.y))
            appendToRawDataDict("accelZ", value: Int(reading.z))
            
            // Write to CSV
            if let writer = accelCsvWriter {
                let timestamp = reading.timestamp.timeIntervalSince1970
                let line = "\(timestamp),\(reading.x),\(reading.y),\(reading.z)\n"
                writer.write(line)
            }
        }
    }
    
    /// 배터리 데이터를 기록합니다.
    ///
    /// - Parameter reading: 기록할 배터리 읽기값
    public func recordBatteryData(_ reading: BatteryReading) {
        guard isRecording else { return }
        
        // Battery data is not typically recorded in bulk, just noted
    }
    
    // MARK: - Private Methods
    
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestampString = dateFormatter.string(from: Date())
        
        currentRecordingFiles = []
        
        // Setup JSON file
        let rawDataURL = recordingsDirectory.appendingPathComponent("raw_data_\(timestampString).json")
        try setupJSONFile(at: rawDataURL)
        
        // Setup CSV files
        let csvTimestampString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        
        try setupEEGCSVFile(timestamp: csvTimestampString)
        try setupPPGCSVFile(timestamp: csvTimestampString)
        try setupAccelCSVFile(timestamp: csvTimestampString)
        
        initializeRawDataDict()
    }
    
    private func setupJSONFile(at url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw BluetoothKitError.fileOperationFailed("Could not create JSON file")
        }
        rawDataWriter = FileWriter(fileHandle: handle)
        currentRecordingFiles.append(url)
    }
    
    private func setupEEGCSVFile(timestamp: String) throws {
        let eegCsvURL = recordingsDirectory.appendingPathComponent("eeg_data_\(timestamp).csv")
        FileManager.default.createFile(atPath: eegCsvURL.path, contents: nil, attributes: nil)
        guard let handle = try? FileHandle(forWritingTo: eegCsvURL) else {
            throw BluetoothKitError.fileOperationFailed("Could not create EEG CSV file")
        }
        let writer = FileWriter(fileHandle: handle)
        writer.write("timestamp,ch1Raw,ch2Raw,ch1uV,ch2uV,leadOff\n")
        eegCsvWriter = writer
        currentRecordingFiles.append(eegCsvURL)
    }
    
    private func setupPPGCSVFile(timestamp: String) throws {
        let ppgCsvURL = recordingsDirectory.appendingPathComponent("ppg_data_\(timestamp).csv")
        FileManager.default.createFile(atPath: ppgCsvURL.path, contents: nil, attributes: nil)
        guard let handle = try? FileHandle(forWritingTo: ppgCsvURL) else {
            throw BluetoothKitError.fileOperationFailed("Could not create PPG CSV file")
        }
        let writer = FileWriter(fileHandle: handle)
        writer.write("timestamp,red,ir\n")
        ppgCsvWriter = writer
        currentRecordingFiles.append(ppgCsvURL)
    }
    
    private func setupAccelCSVFile(timestamp: String) throws {
        let accelCsvURL = recordingsDirectory.appendingPathComponent("accel_data_\(timestamp).csv")
        FileManager.default.createFile(atPath: accelCsvURL.path, contents: nil, attributes: nil)
        guard let handle = try? FileHandle(forWritingTo: accelCsvURL) else {
            throw BluetoothKitError.fileOperationFailed("Could not create Accelerometer CSV file")
        }
        let writer = FileWriter(fileHandle: handle)
        writer.write("timestamp,x,y,z\n")
        accelCsvWriter = writer
        currentRecordingFiles.append(accelCsvURL)
    }
    
    private func appendToRawDataDict<T>(_ key: String, value: T) {
        if var array = rawDataDict[key] as? [T] {
            array.append(value)
            rawDataDict[key] = array
        }
    }
    
    private func finalizeRecording() throws {
        // Save JSON file
        if let handle = rawDataWriter?.fileHandle {
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
            
            if #available(iOS 13.0, macOS 10.15, *) {
                try? handle.close()
            }
        }
        
        // Close all CSV files
        if #available(iOS 13.0, macOS 10.15, *) {
            try? eegCsvWriter?.fileHandle.close()
            try? ppgCsvWriter?.fileHandle.close()
            try? accelCsvWriter?.fileHandle.close()
        }
        
        // Reset writers
        rawDataWriter = nil
        eegCsvWriter = nil
        ppgCsvWriter = nil
        accelCsvWriter = nil
    }
    
    private func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        logger.log(message, file: file, function: function, line: line)
    }
    
    // MARK: - Private Helper Methods for Safe Delegate Calls
    
    private func notifyRecordingStarted(at date: Date) {
        if Thread.isMainThread {
            delegate?.dataRecorder(self, didStartRecording: date)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.dataRecorder(self, didStartRecording: date)
            }
        }
    }
    
    private func notifyRecordingStopped(at date: Date, savedFiles: [URL]) {
        if Thread.isMainThread {
            delegate?.dataRecorder(self, didStopRecording: date, savedFiles: savedFiles)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.dataRecorder(self, didStopRecording: date, savedFiles: savedFiles)
            }
        }
    }
    
    private func notifyRecordingError(_ error: Error) {
        if Thread.isMainThread {
            delegate?.dataRecorder(self, didFailWithError: error)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.dataRecorder(self, didFailWithError: error)
            }
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