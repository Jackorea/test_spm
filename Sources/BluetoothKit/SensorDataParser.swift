import Foundation
import CoreBluetooth

// MARK: - SensorDataParser (Pure Business Logic)

/// 센서 데이터 패킷을 구조화된 읽기값으로 파싱하는 순수 비즈니스 로직 클래스입니다.
///
/// 이 클래스는 UI 프레임워크와 완전히 독립적으로 작동하며, Bluetooth 센서로부터 수신된
/// 바이너리 데이터를 구조화된 Swift 타입으로 변환합니다. 모든 파싱 매개변수는
/// `SensorConfiguration`을 통해 설정 가능하여 다양한 센서 하드웨어를 지원합니다.
/// 
/// **주요 특징:**
/// - UI 프레임워크 의존성 없음 (순수 비즈니스 로직)
/// - 바이너리 데이터 파싱 전문화
/// - 설정 가능한 센서 매개변수 지원
/// - 엄격한 데이터 검증 및 오류 처리
/// - 타임스탬프 처리 및 샘플링 레이트 계산
/// - 멀티 샘플 패킷 지원
///
/// **지원 센서 타입:**
/// - EEG (뇌전도): 2채널, 24비트 해상도, lead-off 감지
/// - PPG (광전 용적 맥파): Red/IR LED, 심박수 모니터링용
/// - 가속도계: 3축, 모션 감지용
/// - 배터리: 배터리 레벨 모니터링
///
/// **사용법:**
/// ```swift
/// let parser = SensorDataParser(configuration: .default)
/// let eegReadings = try parser.parseEEGData(rawData)
/// let ppgReadings = try parser.parsePPGData(rawData)
/// ```
internal class SensorDataParser: @unchecked Sendable {
    private let configuration: SensorConfiguration
    
    internal init(configuration: SensorConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - EEG Data Parsing
    
    /// Parses raw EEG data packets into structured readings.
    ///
    /// - Parameter data: Raw binary data from EEG characteristic
    /// - Returns: Array of EEG readings extracted from the packet
    /// - Throws: `BluetoothKitError.dataParsingFailed` if packet format is invalid
    internal func parseEEGData(_ data: Data) throws -> [EEGReading] {
        let bytes = [UInt8](data)
        
        // Check minimum packet size (header + at least one sample)
        let headerSize = 4
        guard bytes.count >= headerSize + configuration.eegSampleSize else {
            throw BluetoothKitError.dataParsingFailed("EEG packet too short: \(bytes.count) bytes (minimum: \(headerSize + configuration.eegSampleSize))")
        }
        
        // Calculate actual number of samples available
        let dataWithoutHeader = bytes.count - headerSize
        let actualSampleCount = dataWithoutHeader / configuration.eegSampleSize
        let expectedSampleCount = (configuration.eegPacketSize - headerSize) / configuration.eegSampleSize
        
        // Log if packet size differs from expected
        if bytes.count != configuration.eegPacketSize {
            print("⚠️ EEG packet size: \(bytes.count) bytes (expected: \(configuration.eegPacketSize)), processing \(actualSampleCount) samples (expected: \(expectedSampleCount))")
        }
        
        // Extract timestamp from packet header
        let timeRaw = UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
        var timestamp = Double(timeRaw) / configuration.timestampDivisor / configuration.millisecondsToSeconds
        
        var readings: [EEGReading] = []
        
        // Parse only the available samples
        for sampleIndex in 0..<actualSampleCount {
            let i = headerSize + (sampleIndex * configuration.eegSampleSize)
            
            // Ensure we don't exceed array bounds
            guard i + configuration.eegSampleSize <= bytes.count else {
                print("⚠️ EEG sample \(sampleIndex + 1) incomplete, skipping remaining samples")
                break
            }
            
            // lead-off (1 byte) - sensor connection status
            let leadOffRaw = bytes[i]
            let leadOffNormalized = leadOffRaw > 0  // true if any lead is disconnected
            
            // CH1: 3 bytes (Big Endian)
            var ch1Raw = Int32(bytes[i+1]) << 16 | Int32(bytes[i+2]) << 8 | Int32(bytes[i+3])
            
            // CH2: 3 bytes (Big Endian)  
            var ch2Raw = Int32(bytes[i+4]) << 16 | Int32(bytes[i+5]) << 8 | Int32(bytes[i+6])
            
            // Handle 24-bit signed values (MSB sign extension)
            if (ch1Raw & 0x800000) != 0 {
                ch1Raw -= 0x1000000
            }
            if (ch2Raw & 0x800000) != 0 {
                ch2Raw -= 0x1000000
            }
            
            // Convert to voltage using configuration parameters
            let ch1uV = Double(ch1Raw) * configuration.eegVoltageReference / configuration.eegGain / configuration.eegResolution * configuration.microVoltMultiplier
            let ch2uV = Double(ch2Raw) * configuration.eegVoltageReference / configuration.eegGain / configuration.eegResolution * configuration.microVoltMultiplier
            
            let reading = EEGReading(
                channel1: ch1uV,
                channel2: ch2uV,
                ch1Raw: ch1Raw,
                ch2Raw: ch2Raw,
                leadOff: leadOffNormalized,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
            
            readings.append(reading)
            
            // Increment timestamp for next sample
            timestamp += 1.0 / configuration.eegSampleRate
        }
        
        return readings
    }
    
    // MARK: - PPG Data Parsing
    
    /// Parses raw PPG data packets into structured readings.
    ///
    /// - Parameter data: Raw binary data from PPG characteristic
    /// - Returns: Array of PPG readings extracted from the packet
    /// - Throws: `BluetoothKitError.dataParsingFailed` if packet format is invalid
    internal func parsePPGData(_ data: Data) throws -> [PPGReading] {
        let bytes = [UInt8](data)
        
        // Check minimum packet size (header + at least one sample)
        let headerSize = 4
        guard bytes.count >= headerSize + configuration.ppgSampleSize else {
            throw BluetoothKitError.dataParsingFailed("PPG packet too short: \(bytes.count) bytes (minimum: \(headerSize + configuration.ppgSampleSize))")
        }
        
        // Calculate actual number of samples available
        let dataWithoutHeader = bytes.count - headerSize
        let actualSampleCount = dataWithoutHeader / configuration.ppgSampleSize
        let expectedSampleCount = (configuration.ppgPacketSize - headerSize) / configuration.ppgSampleSize
        
        // Log if packet size differs from expected
        if bytes.count != configuration.ppgPacketSize {
            print("⚠️ PPG packet size: \(bytes.count) bytes (expected: \(configuration.ppgPacketSize)), processing \(actualSampleCount) samples (expected: \(expectedSampleCount))")
        }

        // Extract timestamp from packet header
        let timeRaw = UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
        var timestamp = Double(timeRaw) / configuration.timestampDivisor / configuration.millisecondsToSeconds

        var readings: [PPGReading] = []

        // Parse only the available samples
        for sampleIndex in 0..<actualSampleCount {
            let i = headerSize + (sampleIndex * configuration.ppgSampleSize)
            
            // Ensure we don't exceed array bounds
            guard i + configuration.ppgSampleSize <= bytes.count else {
                print("⚠️ PPG sample \(sampleIndex + 1) incomplete, skipping remaining samples")
                break
            }
            
            let red = Int(bytes[i]) << 16 | Int(bytes[i+1]) << 8 | Int(bytes[i+2])
            let ir  = Int(bytes[i+3]) << 16 | Int(bytes[i+4]) << 8 | Int(bytes[i+5])
            
            let reading = PPGReading(
                red: red,
                ir: ir,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
            
            readings.append(reading)
            
            // Increment timestamp for next sample
            timestamp += 1.0 / configuration.ppgSampleRate
        }
        
        return readings
    }
    
    // MARK: - Accelerometer Data Parsing
    
    /// Parses raw accelerometer data packets into structured readings.
    ///
    /// - Parameter data: Raw binary data from accelerometer characteristic
    /// - Returns: Array of accelerometer readings extracted from the packet
    /// - Throws: `BluetoothKitError.dataParsingFailed` if packet format is invalid
    internal func parseAccelerometerData(_ data: Data) throws -> [AccelerometerReading] {
        let bytes = [UInt8](data)
        
        let headerSize = 4
        let sampleSize = 6
        
        guard bytes.count >= headerSize + sampleSize else {
            throw BluetoothKitError.dataParsingFailed("ACCEL packet too short: \(bytes.count) bytes")
        }
        
        // Extract timestamp from packet header
        let timeRaw = UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
        var timestamp = Double(timeRaw) / configuration.timestampDivisor / configuration.millisecondsToSeconds

        let dataWithoutHeaderCount = bytes.count - headerSize
        guard dataWithoutHeaderCount >= sampleSize else {
            throw BluetoothKitError.dataParsingFailed("ACCEL packet has header but not enough data for one sample")
        }
        
        let sampleCount = dataWithoutHeaderCount / sampleSize
        var readings: [AccelerometerReading] = []

        for i in 0..<sampleCount {
            let baseInFullPacket = headerSize + (i * sampleSize)
            // Use odd-numbered bytes as per hardware specification
            let x = Int16(bytes[baseInFullPacket + 1])  // data[i+1]
            let y = Int16(bytes[baseInFullPacket + 3])  // data[i+3] 
            let z = Int16(bytes[baseInFullPacket + 5])  // data[i+5]
            
            let reading = AccelerometerReading(
                x: x,
                y: y,
                z: z,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
            
            readings.append(reading)
            
            // Increment timestamp for next sample
            timestamp += 1.0 / configuration.accelerometerSampleRate
        }
        
        return readings
    }
    
    // MARK: - Battery Data Parsing
    
    /// Parses raw battery data into a structured reading.
    ///
    /// - Parameter data: Raw binary data from battery characteristic
    /// - Returns: Battery reading with current level
    /// - Throws: `BluetoothKitError.dataParsingFailed` if data is invalid
    internal func parseBatteryData(_ data: Data) throws -> BatteryReading {
        guard let level = data.first else {
            throw BluetoothKitError.dataParsingFailed("Battery data is empty")
        }
        
        return BatteryReading(level: level)
    }
} 
