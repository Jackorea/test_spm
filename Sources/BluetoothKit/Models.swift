import Foundation
import CoreBluetooth

// MARK: - Device Models

/// Bluetooth 디바이스를 나타내는 구조체입니다.
///
/// 스캔 중 발견된 Bluetooth Low Energy (BLE) 디바이스의 정보를 담고 있습니다.
/// 이 구조체는 연결 대상 디바이스를 식별하고 연결 작업에 사용됩니다.
///
/// ## 예시
///
/// ```swift
/// // 특정 디바이스 연결
/// if let device = bluetoothKit.discoveredDevices.first(where: { $0.name.contains("LinkBand") }) {
///     bluetoothKit.connect(to: device)
/// }
/// ```
public struct BluetoothDevice: @unchecked Sendable {
    /// Core Bluetooth 페리페럴 객체입니다.
    ///
    /// 실제 BLE 통신을 위해 사용되는 CBPeripheral 인스턴스입니다.
    /// 연결, 서비스 검색, 특성 읽기/쓰기 등의 작업에 사용됩니다.
    /// SDK 내부에서만 접근 가능합니다.
    internal let peripheral: CBPeripheral
    
    /// 디바이스의 표시 이름입니다.
    ///
    /// BLE 광고에서 가져온 디바이스 이름 또는 사용자 정의 이름입니다.
    /// 일반적으로 "LXB-" 접두사를 가진 형태입니다.
    public let name: String
    
    /// 새로운 BluetoothDevice 인스턴스를 생성합니다.
    ///
    /// - Parameters:
    ///   - peripheral: Core Bluetooth peripheral
    ///   - name: 디바이스 이름
    internal init(peripheral: CBPeripheral, name: String) {
        self.peripheral = peripheral
        self.name = name
    }
    
    /// 두 BluetoothDevice가 동일한지 비교합니다.
    ///
    /// 페리페럴의 식별자를 기준으로 동등성을 판단합니다.
    internal static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        return lhs.peripheral.identifier == rhs.peripheral.identifier
    }
}

// MARK: - Sensor Data Models

/// EEG(뇌전도) 센서 읽기값을 나타내는 구조체입니다.
///
/// 이 구조체는 2채널 EEG 데이터와 관련 메타데이터를 포함합니다.
/// 전압 값은 마이크로볼트(µV) 단위로 표현되며, 원시 ADC 값도 함께 제공됩니다.
///
/// ## 예시
///
/// ```swift
/// let eegReading = EEGReading(
///     channel1: 15.3,
///     channel2: -8.7,
///     ch1Raw: 125043,
///     ch2Raw: -67834,
///     leadOff: false
/// )
/// ```
public struct EEGReading: Sendable {
    /// 채널 1의 EEG 전압값 (마이크로볼트 단위)
    ///
    /// 첫 번째 EEG 전극에서 측정된 전압입니다.
    public let channel1: Double  // µV
    
    /// 채널 2의 EEG 전압값 (마이크로볼트 단위)
    ///
    /// 두 번째 EEG 전극에서 측정된 전압입니다.
    public let channel2: Double  // µV
    
    /// 채널 1의 원시 ADC 값입니다.
    ///
    /// 아날로그-디지털 변환기에서 직접 얻은 24비트 정수값입니다.
    /// 디버깅이나 고급 신호 처리에 사용될 수 있습니다.
    public let ch1Raw: Int32     // Raw ADC value for channel 1
    
    /// 채널 2의 원시 ADC 값입니다.
    ///
    /// 아날로그-디지털 변환기에서 직접 얻은 24비트 정수값입니다.
    /// 디버깅이나 고급 신호 처리에 사용될 수 있습니다.
    public let ch2Raw: Int32     // Raw ADC value for channel 2
    
    /// 전극 연결 해제 상태를 나타냅니다.
    ///
    /// `true`일 때 전극이 피부에서 분리되었거나 접촉이 불량함을 의미합니다.
    public let leadOff: Bool
    
    /// 데이터가 측정된 시간입니다.
    public let timestamp: Date
    
    /// 새로운 EEGReading 인스턴스를 생성합니다.
    ///
    /// - Parameters:
    ///   - channel1: 채널 1 전압값 (µV)
    ///   - channel2: 채널 2 전압값 (µV)
    ///   - ch1Raw: 채널 1 원시 ADC 값
    ///   - ch2Raw: 채널 2 원시 ADC 값
    ///   - leadOff: 전극 연결 해제 상태
    ///   - timestamp: 측정 시간 (기본값: 현재 시간)
    public init(channel1: Double, channel2: Double, ch1Raw: Int32, ch2Raw: Int32, leadOff: Bool, timestamp: Date = Date()) {
        self.channel1 = channel1
        self.channel2 = channel2
        self.ch1Raw = ch1Raw
        self.ch2Raw = ch2Raw
        self.leadOff = leadOff
        self.timestamp = timestamp
    }
}

/// PPG(광전 용적 맥파) 센서 읽기값을 나타내는 구조체입니다.
///
/// PPG는 심박수와 혈류량 모니터링에 사용되는 광학 센서입니다.
/// 적색(Red)과 적외선(IR) LED를 사용하여 혈액의 산소 포화도와
/// 심박수를 측정할 수 있습니다.
///
/// ## 예시
///
/// ```swift
/// let ppgReading = PPGReading(
///     red: 125043,
///     ir: 134567
/// )
/// ```
public struct PPGReading: Sendable {
    /// 적색 LED에서 반사된 빛의 강도를 측정한 값입니다.
    public let red: Int
    
    /// 적외선 LED에서 반사된 빛의 강도를 측정한 값입니다.
    public let ir: Int
    
    /// 데이터가 측정된 시간입니다.
    public let timestamp: Date
    
    /// 새로운 PPGReading 인스턴스를 생성합니다.
    ///
    /// - Parameters:
    ///   - red: 적색 LED 측정값
    ///   - ir: 적외선 LED 측정값
    ///   - timestamp: 측정 시간 (기본값: 현재 시간)
    public init(red: Int, ir: Int, timestamp: Date = Date()) {
        self.red = red
        self.ir = ir
        self.timestamp = timestamp
    }
}

/// 3축 가속도계 센서 읽기값을 나타내는 구조체입니다.
///
/// 이 구조체는 디바이스의 움직임과 방향을 감지하기 위한
/// X, Y, Z축의 가속도 데이터를 포함합니다.
///
/// ## 예시
///
/// ```swift
/// let accelReading = AccelerometerReading(
///     x: 1024,   //
///     y: 0,      //
///     z: 0       //
/// )
/// ```
public struct AccelerometerReading: Sendable {
    /// X축 가속도 값입니다.
    ///
    /// 디바이스의 좌우 방향 가속도를 나타냅니다.
    public let x: Int16
    
    /// Y축 가속도 값입니다.
    ///
    /// 디바이스의 전후 방향 가속도를 나타냅니다.
    public let y: Int16
    
    /// Z축 가속도 값입니다.
    ///
    /// 디바이스의 상하 방향 가속도를 나타냅니다.
    public let z: Int16
    
    /// 데이터가 측정된 시간입니다.
    public let timestamp: Date
    
    /// 새로운 AccelerometerReading 인스턴스를 생성합니다.
    ///
    /// - Parameters:
    ///   - x: X축 가속도값
    ///   - y: Y축 가속도값
    ///   - z: Z축 가속도값
    ///   - timestamp: 측정 시간 (기본값: 현재 시간)
    public init(x: Int16, y: Int16, z: Int16, timestamp: Date = Date()) {
        self.x = x
        self.y = y
        self.z = z
        self.timestamp = timestamp
    }
}

/// 디바이스 배터리 상태를 나타내는 구조체입니다.
///
/// 연결된 센서 디바이스의 배터리 잔량을 백분율로 제공합니다.
///
/// ## 예시
///
/// ```swift
/// let batteryReading = BatteryReading(level: 85)
/// print("배터리 잔량: \(batteryReading.level)%")
/// ```
public struct BatteryReading: Sendable {
    /// 배터리 잔량 백분율입니다.
    ///
    /// 0%에서 100% 사이의 값으로 배터리 충전 상태를 나타냅니다.
    /// 0은 완전 방전, 100은 완전 충전을 의미합니다.
    public let level: UInt8  // 0-100%
    
    /// 데이터가 측정된 시간입니다.
    public let timestamp: Date
    
    /// 새로운 BatteryReading 인스턴스를 생성합니다.
    ///
    /// - Parameters:
    ///   - level: 배터리 잔량 (0-100%)
    ///   - timestamp: 측정 시간 (기본값: 현재 시간)
    public init(level: UInt8, timestamp: Date = Date()) {
        self.level = level
        self.timestamp = timestamp
    }
}

// MARK: - Connection State

/// Bluetooth 연결의 현재 상태를 나타내는 열거형입니다.
///
/// 이 열거형은 연결 프로세스의 다양한 단계를 추적하며,
/// 사용자 인터페이스에서 적절한 상태 표시를 제공합니다.
/// 
/// **⚠️ 중요: 이 상태들은 SDK에서 자동으로 관리됩니다.**
/// **사용자가 직접 생성하지 마세요. 읽기 전용으로만 사용하세요.**
///
/// ## 사용 예시
///
/// ```swift
/// // ✅ 올바른 사용법 - 상태 읽기
/// switch bluetoothKit.connectionState {
/// case .disconnected:
///     showDisconnectedUI()
/// case .connected(let deviceName):
///     showConnectedUI(for: deviceName)
/// default:
///     break
/// }
/// 
/// // ❌ 잘못된 사용법 - 직접 생성하지 마세요
/// // bluetoothKit.connectionState = .connected("FakeDevice")
/// ```
public enum ConnectionState: Sendable, Equatable {
    /// 어떤 디바이스에도 연결되지 않은 상태입니다.
    case disconnected
    
    /// 현재 디바이스를 스캔하고 있는 상태입니다.
    case scanning
    
    /// 특정 디바이스에 연결을 시도하고 있는 상태입니다.
    ///
    /// - Parameter deviceName: 연결을 시도하는 디바이스의 이름
    case connecting(String)
    
    /// 특정 디바이스에 성공적으로 연결된 상태입니다.
    ///
    /// - Parameter deviceName: 연결된 디바이스의 이름
    case connected(String)
    
    /// 연결이 끊어진 후 자동으로 재연결을 시도하고 있는 상태입니다.
    ///
    /// - Parameter deviceName: 재연결을 시도하는 디바이스의 이름
    case reconnecting(String)
    
    /// 연결 또는 작업이 실패한 상태입니다.
    ///
    /// - Parameter error: 실패 원인을 나타내는 오류
    case failed(Error)
    
    /// 연결 상태의 사용자 친화적인 한국어 설명입니다.
    public var description: String {
        switch self {
        case .disconnected:
            return "연결 안됨"
        case .scanning:
            return "스캔 중..."
        case .connecting(let deviceName):
            return "\(deviceName)에 연결 중..."
        case .connected(let deviceName):
            return "\(deviceName)에 연결됨"
        case .reconnecting(let deviceName):
            return "\(deviceName)에 재연결 중..."
        case .failed(let error):
            return "실패: \(error.localizedDescription)"
        }
    }
    
    // 수동 Equatable 구현
    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected), (.scanning, .scanning):
            return true
        case (.connecting(let lhsName), .connecting(let rhsName)):
            return lhsName == rhsName
        case (.connected(let lhsName), .connected(let rhsName)):
            return lhsName == rhsName
        case (.reconnecting(let lhsName), .reconnecting(let rhsName)):
            return lhsName == rhsName
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Recording State

/// 데이터 기록의 현재 상태를 나타내는 열거형입니다.
///
/// 이 열거형은 센서 데이터의 파일 기록 상태를 추적합니다.
/// 기록 시작과 종료 상태를 구분하여
/// 사용자 인터페이스와 내부 로직에서 활용됩니다.
///
/// **⚠️ 중요: 이 상태들은 SDK에서 자동으로 관리됩니다.**
/// **사용자가 직접 생성하지 마세요. 읽기 전용으로만 사용하세요.**
///
/// ## 사용 예시
///
/// ```swift
/// // ✅ 올바른 사용법 - 상태 확인
/// if bluetoothKit.isRecording {
///     showRecordingIndicator()
/// }
/// 
/// // ❌ 잘못된 사용법 - 직접 상태 생성하지 마세요
/// // let fakeState = RecordingState.recording
/// ```
internal enum RecordingState: Sendable {
    /// 기록이 비활성화된 유휴 상태입니다.
    case idle
    
    /// 현재 데이터를 기록하고 있는 상태입니다.
    case recording
    
    /// 현재 기록 중인지 여부를 나타내는 편의 속성입니다.
    internal var isRecording: Bool {
        return self == .recording
    }
}

// MARK: - Sensor Configuration (Internal)

/// 센서의 내부 설정을 관리하는 구조체입니다.
///
/// LXB- 디바이스에 특화되어 있으며, 모든 설정값이 고정되어 있습니다.
/// 사용자가 직접 수정할 필요가 없는 내부 하드웨어 파라미터들을 포함합니다.
internal struct SensorConfiguration: Sendable {
    
    /// LXB- 디바이스 이름 접두사 (고정값)
    internal let deviceNamePrefix: String = "LXB-"
    
    // MARK: - Sampling Rates (Fixed Values)
    
    /// EEG 샘플링 레이트 (Hz) - 고정값
    internal let eegSampleRate: Double = 250.0
    
    /// PPG 샘플링 레이트 (Hz) - 고정값
    internal let ppgSampleRate: Double = 50.0
    
    /// 가속도계 샘플링 레이트 (Hz) - 고정값
    internal let accelerometerSampleRate: Double = 30.0
    
    // MARK: - Hardware Parameters (Fixed Values)
    
    internal let eegVoltageReference: Double = 4.033
    internal let eegGain: Double = 12.0
    internal let eegResolution: Double = 8388607 // 2^23 - 1
    internal let microVoltMultiplier: Double = 1e6
    internal let timestampDivisor: Double = 32.768
    internal let millisecondsToSeconds: Double = 1000.0
    internal let eegPacketSize: Int = 179
    internal let ppgPacketSize: Int = 172
    internal let eegSampleSize: Int = 7
    internal let ppgSampleSize: Int = 6
    
    /// LXB- 디바이스용 기본 설정을 생성합니다.
    internal init() {
        // 모든 값이 고정 상수로 정의되어 있음
    }
    
    /// 일반적인 사용을 위한 기본 설정.
    internal static let `default` = SensorConfiguration()
}

// MARK: - Sensor UUIDs (Internal)

/// Bluetooth 서비스 및 특성 UUID를 포함하는 내부 구조체입니다.
///
/// 이 UUID들은 센서 통신을 위한 Bluetooth Low Energy GATT 프로파일을 정의합니다.
/// 사용되는 센서 하드웨어에 특화되어 있으며 다른 디바이스 제조업체의 경우
/// 업데이트가 필요할 수 있습니다.
internal struct SensorUUID {
    // MARK: - EEG Service
    
    /// EEG 서비스 UUID (알림 및 쓰기 작업을 위한 공유 서비스)
    static var eegService: CBUUID { CBUUID(string: "df7b5d95-3afe-00a1-084c-b50895ef4f95") }
    
    /// EEG 알림 특성 UUID (데이터 수신용)
    static var eegNotifyChar: CBUUID { CBUUID(string: "00ab4d15-66b4-0d8a-824f-8d6f8966c6e5") }
    
    /// EEG 쓰기 특성 UUID (명령 전송용)
    static var eegWriteChar: CBUUID { CBUUID(string: "0065cacb-9e52-21bf-a849-99a80d83830e") }

    // MARK: - PPG Service
    
    /// PPG 서비스 UUID
    static var ppgService: CBUUID { CBUUID(string: "1cc50ec0-6967-9d84-a243-c2267f924d1f") }
    
    /// PPG 특성 UUID (광전 용적 맥파 데이터 수신용)
    static var ppgChar: CBUUID { CBUUID(string: "6c739642-23ba-818b-2045-bfe8970263f6") }

    // MARK: - Accelerometer Service
    
    /// 가속도계 서비스 UUID
    static var accelService: CBUUID { CBUUID(string: "75c276c3-8f97-20bc-a143-b354244886d4") }
    
    /// 가속도계 특성 UUID (모션 데이터 수신용)
    static var accelChar: CBUUID { CBUUID(string: "d3d46a35-4394-e9aa-5a43-e7921120aaed") }

    // MARK: - Battery Service
    
    /// 표준 Bluetooth SIG Battery Service UUID
    static var batteryService: CBUUID { CBUUID(string: "0000180f-0000-1000-8000-00805f9b34fb") }
    
    /// 표준 Bluetooth SIG Battery Level Characteristic UUID
    static var batteryChar: CBUUID { CBUUID(string: "00002a19-0000-1000-8000-00805f9b34fb") }
    
    // MARK: - Convenience Collections
    
    /// 쉬운 반복을 위한 모든 센서 특성 UUID
    static var allSensorCharacteristics: [CBUUID] {
        [eegNotifyChar, ppgChar, accelChar, batteryChar]
    }
}

// MARK: - Logging System

/// 내부 로깅을 위한 간단한 로거입니다.
internal struct InternalLogger {
    let isEnabled: Bool
    
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        print("[\(timestamp)] [\(fileName):\(line)] \(message)")
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Protocols

/// 센서 데이터 수신을 처리하는 델리게이트 프로토콜입니다.
///
/// 이 프로토콜을 구현하여 BluetoothKit에서 수신되는
/// 각종 센서 데이터에 대한 사용자 정의 처리 로직을 제공할 수 있습니다.
/// 실시간 데이터 처리나 커스텀 분석에 유용합니다.
///
/// ## 예시
///
/// ```swift
/// class DataProcessor: SensorDataDelegate {
///     func didReceiveEEGData(_ reading: EEGReading) {
///         // EEG 데이터 처리 로직
///         processEEGSignal(reading.channel1, reading.channel2)
///     }
///     
///     func didReceivePPGData(_ reading: PPGReading) {
///         // PPG 데이터로부터 심박수 계산
///         calculateHeartRate(red: reading.red, ir: reading.ir)
///     }
/// }
/// ```
internal protocol SensorDataDelegate: AnyObject, Sendable {
    /// EEG 데이터가 수신되었을 때 호출됩니다.
    ///
    /// - Parameter reading: 수신된 EEG 읽기값
    func didReceiveEEGData(_ reading: EEGReading)
    
    /// PPG 데이터가 수신되었을 때 호출됩니다.
    ///
    /// - Parameter reading: 수신된 PPG 읽기값
    func didReceivePPGData(_ reading: PPGReading)
    
    /// 가속도계 데이터가 수신되었을 때 호출됩니다.
    ///
    /// - Parameter reading: 수신된 가속도계 읽기값
    func didReceiveAccelerometerData(_ reading: AccelerometerReading)
    
    /// 배터리 데이터가 수신되었을 때 호출됩니다.
    ///
    /// - Parameter reading: 수신된 배터리 읽기값
    func didReceiveBatteryData(_ reading: BatteryReading)
}

/// Bluetooth 연결 상태 변화를 처리하는 델리게이트 프로토콜입니다.
///
/// BluetoothManager의 연결 이벤트를 모니터링하고
/// 사용자 정의 로직을 실행할 수 있도록 합니다.
/// 연결 상태에 따른 UI 업데이트나 알림 처리에 유용합니다.
///
/// ## 예시
///
/// ```swift
/// class ConnectionHandler: BluetoothManagerDelegate {
///     func bluetoothManager(_ manager: AnyObject, didConnectToDevice device: BluetoothDevice) {
///         showConnectionSuccessMessage(device.name)
///     }
///     
///     func bluetoothManager(_ manager: AnyObject, didDisconnectFromDevice device: BluetoothDevice, error: Error?) {
///         if let error = error {
///             handleConnectionError(error)
///         }
///     }
/// }
/// ```
internal protocol BluetoothManagerDelegate: AnyObject, Sendable {
    /// Bluetooth 연결 상태가 변경되었을 때 호출됩니다.
    ///
    /// - Parameters:
    ///   - manager: 상태 변경을 보고하는 BluetoothManager
    ///   - state: 새로운 연결 상태
    func bluetoothManager(_ manager: AnyObject, didUpdateState state: ConnectionState)
    
    /// 새로운 디바이스가 발견되었을 때 호출됩니다.
    ///
    /// - Parameters:
    ///   - manager: 디바이스를 발견한 BluetoothManager
    ///   - device: 발견된 디바이스 정보
    func bluetoothManager(_ manager: AnyObject, didDiscoverDevice device: BluetoothDevice)
    
    /// 디바이스에 성공적으로 연결되었을 때 호출됩니다.
    ///
    /// - Parameters:
    ///   - manager: 연결을 수행한 BluetoothManager
    ///   - device: 연결된 디바이스 정보
    func bluetoothManager(_ manager: AnyObject, didConnectToDevice device: BluetoothDevice)
    
    /// 디바이스와의 연결이 해제되었을 때 호출됩니다.
    ///
    /// - Parameters:
    ///   - manager: 연결 해제를 보고하는 BluetoothManager
    ///   - device: 연결이 해제된 디바이스 정보
    ///   - error: 연결 해제 원인 (자발적 해제인 경우 nil)
    func bluetoothManager(_ manager: AnyObject, didDisconnectFromDevice device: BluetoothDevice, error: Error?)
}

/// 데이터 기록 이벤트를 처리하는 델리게이트 프로토콜입니다.
///
/// DataRecorder의 기록 시작, 종료, 오류 이벤트를 모니터링하여
/// 사용자에게 적절한 피드백을 제공할 수 있습니다.
/// 기록 상태에 따른 UI 업데이트나 파일 관리에 유용합니다.
///
/// ## 예시
///
/// ```swift
/// class RecordingHandler: DataRecorderDelegate {
///     func dataRecorder(_ recorder: AnyObject, didStartRecording at: Date) {
///         updateUIForRecordingStart()
///     }
///     
///     func dataRecorder(_ recorder: AnyObject, didStopRecording at: Date, savedFiles: [URL]) {
///         showRecordingComplete(fileCount: savedFiles.count)
///     }
/// }
/// ```
internal protocol DataRecorderDelegate: AnyObject, Sendable {
    /// 데이터 기록이 시작되었을 때 호출됩니다.
    ///
    /// - Parameters:
    ///   - recorder: 기록을 시작한 DataRecorder
    ///   - at: 기록 시작 시간
    func dataRecorder(_ recorder: AnyObject, didStartRecording at: Date)
    
    /// 데이터 기록이 완료되었을 때 호출됩니다.
    ///
    /// - Parameters:
    ///   - recorder: 기록을 완료한 DataRecorder
    ///   - at: 기록 완료 시간
    ///   - savedFiles: 저장된 파일들의 URL 목록
    func dataRecorder(_ recorder: AnyObject, didStopRecording at: Date, savedFiles: [URL])
    
    /// 데이터 기록 중 오류가 발생했을 때 호출됩니다.
    ///
    /// - Parameters:
    ///   - recorder: 오류가 발생한 DataRecorder
    ///   - error: 발생한 오류 정보
    func dataRecorder(_ recorder: AnyObject, didFailWithError error: Error)
}

// MARK: - Errors

/// BluetoothKit에서 발생할 수 있는 오류들을 정의하는 열거형입니다.
///
/// 각 오류는 구체적인 실패 원인을 나타내며,
/// 사용자에게 적절한 오류 메시지를 제공하는 데 사용됩니다.
/// 모든 오류는 현지화된 설명을 제공합니다.
///
/// **⚠️ 중요: 이 오류들은 SDK에서 자동으로 생성됩니다.**
/// **사용자가 직접 생성하지 마세요. catch 블록에서만 처리하세요.**
///
/// ## 사용 예시
///
/// ```swift
/// // ✅ 올바른 사용법 - 오류 처리
/// switch bluetoothKit.connectionState {
/// case .failed(let error):
///     if error.localizedDescription.contains("Bluetooth is not available") {
///         showBluetoothOffAlert()
///     } else {
///         showGenericError(error.localizedDescription)
///     }
/// default:
///     break
/// }
/// 
/// // ❌ 잘못된 사용법 - 직접 오류 생성하지 마세요
/// // let fakeError = BluetoothKitError.connectionFailed("fake")
/// ```
internal enum BluetoothKitError: LocalizedError, Sendable, Equatable {
    /// Bluetooth가 비활성화되어 있거나 사용할 수 없는 상태입니다.
    case bluetoothUnavailable
    
    /// 요청된 디바이스를 찾을 수 없습니다.
    case deviceNotFound
    
    /// 디바이스 연결에 실패했습니다.
    ///
    /// - Parameter reason: 연결 실패 원인에 대한 상세 설명
    case connectionFailed(String)
    
    /// 수신된 데이터의 파싱에 실패했습니다.
    ///
    /// - Parameter reason: 파싱 실패 원인에 대한 상세 설명
    case dataParsingFailed(String)
    
    /// 데이터 기록에 실패했습니다.
    ///
    /// - Parameter reason: 기록 실패 원인에 대한 상세 설명
    case recordingFailed(String)
    
    /// 파일 작업에 실패했습니다.
    ///
    /// - Parameter reason: 파일 작업 실패 원인에 대한 상세 설명
    case fileOperationFailed(String)
    
    /// 오류에 대한 현지화된 설명을 제공합니다.
    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is not available"
        case .deviceNotFound:
            return "Device not found"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .dataParsingFailed(let reason):
            return "Data parsing failed: \(reason)"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .fileOperationFailed(let reason):
            return "File operation failed: \(reason)"
        }
    }
    
    // 수동 Equatable 구현
    public static func == (lhs: BluetoothKitError, rhs: BluetoothKitError) -> Bool {
        switch (lhs, rhs) {
        case (.bluetoothUnavailable, .bluetoothUnavailable), (.deviceNotFound, .deviceNotFound):
            return true
        case (.connectionFailed(let lhsReason), .connectionFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.dataParsingFailed(let lhsReason), .dataParsingFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.recordingFailed(let lhsReason), .recordingFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.fileOperationFailed(let lhsReason), .fileOperationFailed(let rhsReason)):
            return lhsReason == rhsReason
        default:
            return false
        }
    }
}

// MARK: - Public Data Collection API

/// 센서 타입을 나타내는 열거형입니다.
///
/// 각 센서의 특성과 샘플링 레이트가 다르므로 타입별로 구분하여 처리합니다.
public enum SensorType: String, CaseIterable, Sendable {
    case eeg = "EEG"
    case ppg = "PPG" 
    case accelerometer = "Accelerometer"
    case battery = "Battery"
    
    /// 각 센서의 샘플링 레이트를 반환합니다.
    public var sampleRate: Double {
        switch self {
        case .eeg: return 250.0
        case .ppg: return 50.0
        case .accelerometer: return 30.0
        case .battery: return 1.0 / 60.0  // 1분마다
        }
    }
    
    /// UI에서 표시하기 위한 짧은 이름을 반환합니다.
    public var displayName: String {
        switch self {
        case .eeg: return "EEG"
        case .ppg: return "PPG"
        case .accelerometer: return "ACC"
        case .battery: return "배터리"
        }
    }
    
    /// UI에서 표시하기 위한 이모지를 반환합니다.
    public var emoji: String {
        switch self {
        case .eeg: return "🧠"
        case .ppg: return "❤️"
        case .accelerometer: return "🏃"
        case .battery: return "🔋"
        }
    }
    
    /// UI에서 표시하기 위한 색상을 반환합니다.
    public var color: String {
        switch self {
        case .eeg: return "blue"
        case .ppg: return "red"
        case .accelerometer: return "green"
        case .battery: return "orange"
        }
    }
    
    /// 주어진 샘플 수에 대한 예상 시간을 계산합니다.
    public func expectedTime(for sampleCount: Int) -> Double {
        return Double(sampleCount) / sampleRate
    }
    
    /// 주어진 시간에 대한 예상 샘플 수를 계산합니다.
    public func expectedSamples(for duration: TimeInterval) -> Int {
        return Int(duration * sampleRate)
    }
}

/// 배치 단위로 센서 데이터를 수신하는 델리게이트 프로토콜입니다.
///
/// 사용자가 설정한 시간 간격이나 샘플 개수에 따라 센서 데이터를 배치로 받을 수 있습니다.
/// 실시간 개별 샘플 대신 원하는 크기의 데이터 배치를 받아 처리할 수 있어 성능이 향상됩니다.
///
/// ## 예시
///
/// ```swift
/// class MyDataProcessor: SensorBatchDataDelegate {
///     func didReceiveEEGBatch(_ readings: [EEGReading]) {
///         print("EEG 배치 수신: \(readings.count)개 샘플")
///         // FFT, 필터링 등 배치 처리
///         processEEGBatch(readings)
///     }
///     
///     func didReceivePPGBatch(_ readings: [PPGReading]) {
///         print("PPG 배치 수신: \(readings.count)개 샘플")
///         // 심박수 계산
///         calculateHeartRate(from: readings)
///     }
/// }
/// 
/// // 설정
/// bluetoothKit.batchDataDelegate = MyDataProcessor()
/// bluetoothKit.setDataCollection(timeInterval: 0.5, for: .eeg)  // 0.5초마다
/// bluetoothKit.setDataCollection(sampleCount: 25, for: .ppg)    // 25개씩
/// ```
public protocol SensorBatchDataDelegate: AnyObject {
    /// EEG 데이터 배치가 수신되었을 때 호출됩니다.
    ///
    /// - Parameter readings: 설정된 크기의 EEG 읽기값 배열
    func didReceiveEEGBatch(_ readings: [EEGReading])
    
    /// PPG 데이터 배치가 수신되었을 때 호출됩니다.
    ///
    /// - Parameter readings: 설정된 크기의 PPG 읽기값 배열
    func didReceivePPGBatch(_ readings: [PPGReading])
    
    /// 가속도계 데이터 배치가 수신되었을 때 호출됩니다.
    ///
    /// - Parameter readings: 설정된 크기의 가속도계 읽기값 배열
    func didReceiveAccelerometerBatch(_ readings: [AccelerometerReading])
    
    /// 배터리 데이터가 업데이트되었을 때 호출됩니다.
    ///
    /// 배터리는 배치가 아닌 개별 업데이트로 처리됩니다.
    ///
    /// - Parameter reading: 최신 배터리 읽기값
    func didReceiveBatteryUpdate(_ reading: BatteryReading)
}

/// 데이터 수집 설정을 관리하는 내부 구조체입니다.
internal struct DataCollectionConfig {
    let sensorType: SensorType
    let targetSampleCount: Int
    
    init(sensorType: SensorType, sampleCount: Int) {
        self.sensorType = sensorType
        self.targetSampleCount = max(1, sampleCount)  // 최소 1개만 보장
    }
    
    init(sensorType: SensorType, timeInterval: TimeInterval) {
        self.sensorType = sensorType
        let sampleCount = Int(max(0.001, timeInterval) * sensorType.sampleRate)  // 최소 1ms
        self.targetSampleCount = max(1, sampleCount)
    }
}

// MARK: - Default Console Logger Implementation

/// 배치 센서 데이터를 콘솔에 출력하는 기본 구현체입니다.
///
/// SDK 사용자가 빠르게 데이터 모니터링을 시작할 수 있도록 제공되는 유틸리티 클래스입니다.
/// 실제 프로덕션에서는 이를 참고하여 커스텀 델리게이트를 구현하는 것을 권장합니다.
///
/// ## 사용 예시
///
/// ```swift
/// let bluetoothKit = BluetoothKit()
/// let consoleLogger = BatchDataConsoleLogger()
/// 
/// // 선택된 센서만 콘솔에 출력하도록 설정
/// consoleLogger.updateSelectedSensors([.eeg, .ppg])
/// bluetoothKit.batchDataDelegate = consoleLogger
/// 
/// // 배치 데이터 수집 설정
/// bluetoothKit.setDataCollection(sampleCount: 100, for: .eeg)
/// ```
public class BatchDataConsoleLogger: SensorBatchDataDelegate {
    private var batchCount: [String: Int] = [:]
    private let startTime = Date()
    private var _selectedSensors: Set<SensorType> = []
    
    // Thread-safe access to selectedSensors using concurrent queue
    private let sensorAccessQueue = DispatchQueue(label: "com.bluetoothkit.sensorsAccess", attributes: .concurrent)
    
    private var selectedSensors: Set<SensorType> {
        get {
            return sensorAccessQueue.sync {
                return _selectedSensors
            }
        }
        set {
            sensorAccessQueue.async(flags: .barrier) {
                self._selectedSensors = newValue
            }
        }
    }
    
    /// 새로운 BatchDataConsoleLogger 인스턴스를 생성합니다.
    public init() {}
    
    /// 선택된 센서를 업데이트하는 메서드
    ///
    /// 설정된 센서의 데이터만 콘솔에 출력됩니다.
    /// 빈 세트를 전달하면 모든 출력이 중지됩니다.
    ///
    /// - Parameter sensors: 콘솔에 출력할 센서 타입들의 집합
    public func updateSelectedSensors(_ sensors: Set<SensorType>) {
        selectedSensors = sensors
        print("📝 콘솔 출력 설정 업데이트: \(sensors.map { sensorTypeToString($0) }.joined(separator: ", "))")
    }
    
    private func sensorTypeToString(_ sensorType: SensorType) -> String {
        switch sensorType {
        case .eeg: return "EEG"
        case .ppg: return "PPG"
        case .accelerometer: return "ACC"
        case .battery: return "배터리"
        }
    }
    
    public func didReceiveEEGBatch(_ readings: [EEGReading]) {
        // EEG가 선택된 센서에 포함되어 있을 때만 출력
        guard selectedSensors.contains(.eeg) else { return }
        
        let count = (batchCount["EEG"] ?? 0) + 1
        batchCount["EEG"] = count
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("🧠 EEG 배치 #\(count) 수신 - \(readings.count)개 샘플 (경과: \(String(format: "%.1f", elapsed))초)")
        
        // 모든 EEG 샘플 출력 (순서: ch1raw, ch2raw, ch1, ch2, leadOff)
        for (index, reading) in readings.enumerated() {
            print("   📊 샘플 #\(index + 1): CH1_RAW=\(reading.ch1Raw), CH2_RAW=\(reading.ch2Raw), CH1=\(String(format: "%.1f", reading.channel1))µV, CH2=\(String(format: "%.1f", reading.channel2))µV, LEAD_OFF=\(reading.leadOff ? "접촉안됨" : "접촉됨")")
        }
        print("") // 배치 간 구분을 위한 빈 줄
    }
    
    public func didReceivePPGBatch(_ readings: [PPGReading]) {
        // PPG가 선택된 센서에 포함되어 있을 때만 출력
        guard selectedSensors.contains(.ppg) else { return }
        
        let count = (batchCount["PPG"] ?? 0) + 1
        batchCount["PPG"] = count
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("❤️ PPG 배치 #\(count) 수신 - \(readings.count)개 샘플 (경과: \(String(format: "%.1f", elapsed))초)")
        
        // 모든 PPG 샘플 출력
        for (index, reading) in readings.enumerated() {
            print("   📊 샘플 #\(index + 1): RED=\(reading.red), IR=\(reading.ir)")
        }
        print("") // 배치 간 구분을 위한 빈 줄
    }
    
    public func didReceiveAccelerometerBatch(_ readings: [AccelerometerReading]) {
        // 가속도계가 선택된 센서에 포함되어 있을 때만 출력
        guard selectedSensors.contains(.accelerometer) else { return }
        
        let count = (batchCount["ACCEL"] ?? 0) + 1
        batchCount["ACCEL"] = count
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("🏃 ACC 배치 #\(count) 수신 - \(readings.count)개 샘플 (경과: \(String(format: "%.1f", elapsed))초)")
        
        // 모든 ACC 샘플 출력
        for (index, reading) in readings.enumerated() {
            print("   📊 샘플 #\(index + 1): X=\(reading.x), Y=\(reading.y), Z=\(reading.z)")
        }
        print("") // 배치 간 구분을 위한 빈 줄
    }
    
    public func didReceiveBatteryUpdate(_ reading: BatteryReading) {
        // 배터리가 선택된 센서에 포함되어 있을 때만 출력
        guard selectedSensors.contains(.battery) else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("🔋 배터리 업데이트 - \(reading.level)% (경과: \(String(format: "%.1f", elapsed))초)")
        print("") // 다른 로그와 구분을 위한 빈 줄
    }
} 
