import Foundation
import CoreBluetooth

// MARK: - Sensor Data Parser (Internal)

/// Internal class responsible for parsing raw sensor data packets into structured readings.
///
/// This parser handles binary data from Bluetooth sensors and converts it into
/// structured Swift types. All parsing parameters are configurable through
/// `SensorConfiguration` to support different sensor hardware.
internal class SensorDataParser: @unchecked Sendable {
    private let configuration: SensorConfiguration
    
    internal init(configuration: SensorConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Parsing Configuration
    
    private struct ParsingParams {
        let sensorName: String
        let sampleSize: Int
        let expectedPacketSize: Int
        let sampleRate: Double
    }
    
    private var eegParams: ParsingParams {
        ParsingParams(
            sensorName: "EEG",
            sampleSize: configuration.eegSampleSize,
            expectedPacketSize: configuration.eegPacketSize,
            sampleRate: configuration.eegSampleRate
        )
    }
    
    private var ppgParams: ParsingParams {
        ParsingParams(
            sensorName: "PPG",
            sampleSize: configuration.ppgSampleSize,
            expectedPacketSize: configuration.ppgPacketSize,
            sampleRate: configuration.ppgSampleRate
        )
    }
    
    private var accelParams: ParsingParams {
        ParsingParams(
            sensorName: "ACCEL",
            sampleSize: 6, // Fixed accelerometer sample size
            expectedPacketSize: 0, // Not used for accelerometer
            sampleRate: configuration.accelerometerSampleRate
        )
    }
    
    // MARK: - Common Parsing Helpers
    
    private struct ParsedPacketHeader {
        let timestamp: Double
        let actualSampleCount: Int
    }
    
    private func parsePacketHeader(
        from bytes: [UInt8],
        params: ParsingParams,
        headerSize: Int = 4
    ) throws -> ParsedPacketHeader {
        // Validate minimum packet size
        guard bytes.count >= headerSize + params.sampleSize else {
            throw BluetoothKitError.dataParsingFailed(
                "\(params.sensorName) packet too short: \(bytes.count) bytes (minimum: \(headerSize + params.sampleSize))"
            )
        }
        
        // Calculate actual sample count
        let dataWithoutHeader = bytes.count - headerSize
        let actualSampleCount = dataWithoutHeader / params.sampleSize
        
        // Log packet size warnings for EEG/PPG only
        if params.expectedPacketSize > 0 && bytes.count != params.expectedPacketSize {
            let expectedSampleCount = (params.expectedPacketSize - headerSize) / params.sampleSize
            print("⚠️ \(params.sensorName) packet size: \(bytes.count) bytes (expected: \(params.expectedPacketSize)), processing \(actualSampleCount) samples (expected: \(expectedSampleCount))")
        }
        
        // Extract timestamp from packet header (Little Endian)
        let timeRaw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let timestamp = Double(timeRaw) / configuration.timestampDivisor / configuration.millisecondsToSeconds
        
        return ParsedPacketHeader(timestamp: timestamp, actualSampleCount: actualSampleCount)
    }
    
    private func validateSampleBounds(
        sampleIndex: Int,
        sampleSize: Int,
        headerSize: Int,
        bytesCount: Int,
        sensorName: String
    ) -> Bool {
        let i = headerSize + (sampleIndex * sampleSize)
        guard i + sampleSize <= bytesCount else {
            print("⚠️ \(sensorName) sample \(sampleIndex + 1) incomplete, skipping remaining samples")
            return false
        }
        return true
    }
    
    private func parse24BitSigned(_ byte1: UInt8, _ byte2: UInt8, _ byte3: UInt8) -> Int32 {
        var value = Int32(byte1) << 16 | Int32(byte2) << 8 | Int32(byte3)
        // Handle 24-bit signed values (MSB sign extension)
        if (value & 0x800000) != 0 {
            value -= 0x1000000
        }
        return value
    }
    
    // MARK: - EEG Data Parsing
    
    /// Parses raw EEG data packets into structured readings.
    ///
    /// - Parameter data: Raw binary data from EEG characteristic
    /// - Returns: Array of EEG readings extracted from the packet
    /// - Throws: `BluetoothKitError.dataParsingFailed` if packet format is invalid
    internal func parseEEGData(_ data: Data) throws -> [EEGReading] {
        let bytes = [UInt8](data)
        let params = eegParams
        let headerSize = 4
        
        let header = try parsePacketHeader(from: bytes, params: params, headerSize: headerSize)
        var timestamp = header.timestamp
        var readings: [EEGReading] = []
        
        for sampleIndex in 0..<header.actualSampleCount {
            guard validateSampleBounds(
                sampleIndex: sampleIndex,
                sampleSize: params.sampleSize,
                headerSize: headerSize,
                bytesCount: bytes.count,
                sensorName: params.sensorName
            ) else { break }
            
            let i = headerSize + (sampleIndex * params.sampleSize)
            
            // Parse EEG-specific data
            let leadOffRaw = bytes[i]
            let leadOffNormalized = leadOffRaw > 0
            
            let ch1Raw = parse24BitSigned(bytes[i+1], bytes[i+2], bytes[i+3])
            let ch2Raw = parse24BitSigned(bytes[i+4], bytes[i+5], bytes[i+6])
            
            // Convert to voltage
            let voltageConversionFactor = configuration.eegVoltageReference / configuration.eegGain / configuration.eegResolution * configuration.microVoltMultiplier
            let ch1uV = Double(ch1Raw) * voltageConversionFactor
            let ch2uV = Double(ch2Raw) * voltageConversionFactor
            
            let reading = EEGReading(
                channel1: ch1uV,
                channel2: ch2uV,
                ch1Raw: ch1Raw,
                ch2Raw: ch2Raw,
                leadOff: leadOffNormalized,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
            
            readings.append(reading)
            timestamp += 1.0 / params.sampleRate
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
        let params = ppgParams
        let headerSize = 4
        
        let header = try parsePacketHeader(from: bytes, params: params, headerSize: headerSize)
        var timestamp = header.timestamp
        var readings: [PPGReading] = []
        
        for sampleIndex in 0..<header.actualSampleCount {
            guard validateSampleBounds(
                sampleIndex: sampleIndex,
                sampleSize: params.sampleSize,
                headerSize: headerSize,
                bytesCount: bytes.count,
                sensorName: params.sensorName
            ) else { break }
            
            let i = headerSize + (sampleIndex * params.sampleSize)
            
            // Parse PPG data (24-bit values, Big Endian)
            let red = Int(bytes[i]) << 16 | Int(bytes[i+1]) << 8 | Int(bytes[i+2])
            let ir = Int(bytes[i+3]) << 16 | Int(bytes[i+4]) << 8 | Int(bytes[i+5])
            
            let reading = PPGReading(
                red: red,
                ir: ir,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
            
            readings.append(reading)
            timestamp += 1.0 / params.sampleRate
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
        let params = accelParams
        let headerSize = 4
        
        guard bytes.count >= headerSize + params.sampleSize else {
            throw BluetoothKitError.dataParsingFailed("ACCEL packet too short: \(bytes.count) bytes")
        }
        
        // Extract timestamp and calculate sample count
        let timeRaw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        var timestamp = Double(timeRaw) / configuration.timestampDivisor / configuration.millisecondsToSeconds
        
        let dataWithoutHeaderCount = bytes.count - headerSize
        let sampleCount = dataWithoutHeaderCount / params.sampleSize
        var readings: [AccelerometerReading] = []
        
        for i in 0..<sampleCount {
            let baseIndex = headerSize + (i * params.sampleSize)
            
            // Use odd-numbered bytes as per hardware specification
            let x = Int16(bytes[baseIndex + 1])
            let y = Int16(bytes[baseIndex + 3])
            let z = Int16(bytes[baseIndex + 5])
            
            let reading = AccelerometerReading(
                x: x,
                y: y,
                z: z,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
            
            readings.append(reading)
            timestamp += 1.0 / params.sampleRate
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
