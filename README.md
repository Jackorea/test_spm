# IOS_link_band_sdk

# BluetoothKit SDK

[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)
[![Platform](https://img.shields.io/badge/platform-iOS%2013.0%2B%20%7C%20macOS%2010.15%2B-lightgrey.svg)](https://developer.apple.com/documentation/)
[![Swift](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)

BluetoothKit은 생체의학 센서 디바이스와의 Bluetooth Low Energy (BLE) 통신을 위한 Swift SDK입니다. EEG(뇌전도), PPG(광전 용적 맥파), 가속도계, 배터리 센서 데이터의 실시간 수집과 기록을 지원합니다.

## ✨ 주요 기능

- **🔍 디바이스 검색**: 설정 가능한 이름 필터를 통한 BLE 디바이스 자동 검색
- **📡 실시간 데이터**: EEG, PPG, 가속도계, 배터리 센서 데이터 실시간 스트리밍
- **💾 데이터 기록**: CSV 및 JSON 형식으로 센서 데이터 자동 저장
- **🔄 자동 재연결**: 예기치 않은 연결 해제 시 자동 재연결 기능
- **📱 SwiftUI 지원**: @ObservableObject 기반 반응형 UI 지원
- **⚡ 동시성 안전**: Swift 6.1 Sendable 프로토콜 완전 지원

## 📖 문서화

완전한 API 문서는 [docs/ios-jazzy](docs/ios-jazzy/index.html)에서 확인할 수 있습니다.
- **100% 문서화 커버리지**
- **Apple 스타일 테마**
- **상세한 사용 예시와 설명**

## 🏗️ 아키텍처

- **BluetoothKit**: 메인 API 클래스
- **BluetoothManager**: BLE 연결 및 디바이스 관리
- **DataRecorder**: 센서 데이터 파일 기록
- **Models**: 센서 데이터 모델 및 구성
- **SensorDataParser**: 센서 데이터 파싱

## 🛠️ 기술 스택

- **Swift 6.1+**
- **iOS 13.0+ / macOS 10.15+**
- **Core Bluetooth Framework**
- **Swift Package Manager**
- **Jazzy Documentation**
# test_spm
