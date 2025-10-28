# BME Lab 2 - Arduino Bluetooth ECG/EMG Monitoring System

## Project Overview

This is a Bluetooth ECG (Electrocardiogram) and EMG (Electromyography) monitoring system based on Flutter and Arduino, designed for biomedical engineering experiments. The system can collect, transmit, and display ECG/EMG signals in real-time, providing heart rate monitoring functionality.

## Technical Architecture

### Hardware Components
- **Arduino Uno** - Main controller
- **HM-10 Bluetooth Module** - Wireless communication
- **ECG Sensor** - Heart signal acquisition
- **ADC Converter** - Analog to digital conversion

### Software Technologies
- **Flutter** - Cross-platform mobile application development
- **Dart** - Programming language
- **Arduino C++** - Embedded system programming
- **Bluetooth BLE** - Wireless communication protocol

## Project Structure

```
114-1_BME_Exp2_group_5/
├── app/                          # Flutter application
│   ├── lib/                      # Dart source code
│   │   ├── main.dart            # Main program entry
│   │   ├── bluetooth_manager.dart    # Bluetooth management
│   │   ├── connection_page.dart      # Connection page
│   │   ├── data_page.dart            # Data monitoring page
│   │   └── ecg_viewer_page.dart      # ECG chart page
│   ├── android/                 # Android platform configuration
│   ├── ios/                     # iOS platform configuration
│   └── pubspec.yaml             # Dependency management
├── bluetooth/                    # Arduino code
│   └── bmelab/
│       └── bmelab.ino           # Arduino main program
└── README.md                    # Project documentation
```

## Main Features

### Bluetooth Connection Management
- Automatic scanning and pairing of Bluetooth devices
- Support for HM-10 BLE module
- Real-time connection status monitoring
- Automatic reconnection mechanism

### Real-time Data Monitoring
- Real-time ADC data reception
- Voltage value conversion and display
- System status monitoring
- Command control interface

### ECG Waveform Display
- Real-time ECG waveform rendering
- Automatic heart rate calculation
- Chart zooming and scrolling
- Data filtering and processing

### Arduino Control
- START_ADC - Start data transmission
- STOP_ADC - Stop data transmission
- STATUS - Query system status
- HELLO - Communication test

## Communication Protocol

### Arduino Command Format
```
START_ADC    # Start ADC data transmission
STOP_ADC     # Stop ADC data transmission
STATUS       # Query system status
HELLO        # Communication test
```

### Data Format
```
ADC_DATA:value,voltage          # ADC data
SYSTEM_STATUS:status            # System status
ADC_TRANSMISSION:status         # Transmission status
HEARTBEAT:status               # Heartbeat status
```

## Installation and Usage

### Requirements
- Flutter SDK 3.0+
- Arduino IDE
- Android Studio / Xcode
- HM-10 Bluetooth module

### Arduino Setup
1. Upload `bluetooth/bmelab/bmelab.ino` to Arduino
2. Connect HM-10 Bluetooth module to Arduino
3. Connect ECG sensor to pin A0

### Flutter Application Setup
1. Navigate to `app` directory
2. Install dependencies: `flutter pub get`
3. Run application: `flutter run`

### Usage Steps
1. Launch Flutter application
2. Scan and connect to Arduino device
3. Send `START_ADC` command to start data transmission
4. Monitor real-time data in data page
5. View waveform charts in ECG page

## Key Features

### Intelligent Signal Processing
- Moving average filter
- Automatic heart rate detection algorithm
- Real-time data normalization

### User-friendly Interface
- Material Design 3 interface
- Three-page navigation structure
- Real-time status indicators
- Detailed debugging information

### Complete Error Handling
- Automatic retry on connection failure
- Data validation and error prompts
- Exception state recovery mechanism

## Development Team

**Group 5** - 114-1 BME Lab 2
- Designed for biomedical engineering experiments
- National Taiwan University Department of Biomedical Engineering

## Version History

- **v1.0.0** - Initial version with basic functionality
- **v1.0.1** - Optimized Bluetooth connection stability
- **v1.0.2** - Improved ECG signal processing algorithms

## License

This project is for academic research purposes only.

## Contact Information

For questions or suggestions, please contact the development team.

---

*Last updated: October 2025*
