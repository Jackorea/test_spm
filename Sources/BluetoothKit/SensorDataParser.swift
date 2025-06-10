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
    
    // MARK: - EEG Data Parsing
    
    /// Parses raw EEG data packets into structured readings.
    ///
    /// - Parameter data: Raw binary data from EEG characteristic
    /// - Returns: Array of EEG readings extracted from the packet
    /// - Throws: `BluetoothKitError.dataParsingFailed` if packet format is invalid
    internal func parseEEGData(_ data: Data) throws -> [EEGReading] {
        let bytes = [UInt8](data)
        
        // Validate packet size using configuration
        guard bytes.count == configuration.eegPacketSize else {
            throw BluetoothKitError.dataParsingFailed("EEG packet length invalid: \(bytes.count) bytes (expected \(configuration.eegPacketSize))")
        }
        
        // Extract timestamp from packet header
        let timeRaw = UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
        var timestamp = Double(timeRaw) / configuration.timestampDivisor / configuration.millisecondsToSeconds
        
        var readings: [EEGReading] = []
        
        // Parse samples using configuration parameters
        let headerSize = 4
        for i in stride(from: headerSize, to: configuration.eegPacketSize, by: configuration.eegSampleSize) {
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
        guard bytes.count == configuration.ppgPacketSize else {
            throw BluetoothKitError.dataParsingFailed("PPG packet length invalid: \(bytes.count) bytes (expected \(configuration.ppgPacketSize))")
        }

        // Extract timestamp from packet header
        let timeRaw = UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
        var timestamp = Double(timeRaw) / configuration.timestampDivisor / configuration.millisecondsToSeconds

        var readings: [PPGReading] = []

        let headerSize = 4
        for i in stride(from: headerSize, to: configuration.ppgPacketSize, by: configuration.ppgSampleSize) {
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