import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothManager {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  StreamController<String> _dataController = StreamController<String>.broadcast();
  bool _isConnected = false;
  String _deviceName = '';

  // Getters
  bool get isConnected => _isConnected;
  String get deviceName => _deviceName;
  Stream<String> get dataStream => _dataController.stream;

  // 請求藍牙權限
  Future<bool> requestPermissions() async {
    try {
      // 檢查藍牙狀態
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      print('請求藍牙權限時出錯: $e');
      return false;
    }
  }

  // 檢查藍牙是否開啟
  Future<bool> isBluetoothEnabled() async {
    try {
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      print('檢查藍牙狀態時出錯: $e');
      return false;
    }
  }

  // 掃描所有藍牙設備
  Future<List<BluetoothDevice>> scanForDevices({String? deviceNameFilter}) async {
    try {
      List<BluetoothDevice> devices = [];
      
      print('🔍 開始掃描所有藍牙設備...');
      
      // 停止之前的掃描
      await FlutterBluePlus.stopScan();
      
      // 開始掃描，增加掃描時間
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withServices: [],
      );

      // 監聽掃描結果，設定超時
      StreamSubscription<List<ScanResult>>? subscription;
      final completer = Completer<List<BluetoothDevice>>();
      
      subscription = FlutterBluePlus.scanResults.listen((results) {
        print('📡 掃描結果: ${results.length} 個設備');
        
        for (ScanResult result in results) {
          BluetoothDevice device = result.device;
          String deviceName = device.platformName;
          
          print('🔍 發現設備: $deviceName (${device.remoteId})');
          
          // 如果指定了設備名稱過濾器，則過濾設備
          if (deviceNameFilter != null && deviceNameFilter.isNotEmpty) {
            if (deviceName.toLowerCase().contains(deviceNameFilter.toLowerCase())) {
              if (!devices.any((d) => d.remoteId == device.remoteId)) {
                devices.add(device);
                print('✅ 添加過濾設備: $deviceName');
              }
            }
          } else {
            // 顯示所有設備，包括沒有名稱的
            if (!devices.any((d) => d.remoteId == device.remoteId)) {
              devices.add(device);
              print('✅ 添加設備: ${deviceName.isEmpty ? "未知設備" : deviceName}');
            }
          }
        }
      });

      // 設定超時
      Timer(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          FlutterBluePlus.stopScan();
          completer.complete(devices);
        }
      });

      // 等待掃描完成
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      
      subscription?.cancel();
      await FlutterBluePlus.stopScan();
      
      print('📱 掃描完成，找到 ${devices.length} 個設備');
      return devices;
    } catch (e) {
      print('❌ 掃描藍牙設備時出錯: $e');
      await FlutterBluePlus.stopScan();
      return [];
    }
  }

  // 掃描 HM-10 BLE 設備
  Future<List<BluetoothDevice>> scanForHM10Devices() async {
    try {
      List<BluetoothDevice> devices = [];
      
      print('🔍 開始掃描 HM-10 BLE 設備...');
      
      // 停止之前的掃描
      await FlutterBluePlus.stopScan();
      
      // 開始掃描 BLE 設備，增加掃描時間
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15), // 增加掃描時間
        withServices: [],
      );

      // 監聽掃描結果
      StreamSubscription<List<ScanResult>>? subscription;
      final completer = Completer<List<BluetoothDevice>>();
      
      subscription = FlutterBluePlus.scanResults.listen((results) {
        print('📡 掃描結果: ${results.length} 個設備');
        
        for (ScanResult result in results) {
          BluetoothDevice device = result.device;
          String deviceName = device.platformName;
          
          print('🔍 發現設備: $deviceName (${device.remoteId})');
          
          // 更寬鬆的過濾條件，包含更多可能的設備名稱
          String lowerName = deviceName.toLowerCase();
          if (lowerName.contains('hm-10') || 
              lowerName.contains('hm10') ||
              lowerName.contains('arduino_ecg') ||
              lowerName.contains('arduino') ||
              lowerName.contains('ble') ||
              lowerName.contains('esp32') ||
              lowerName.contains('esp8266') ||
              lowerName.contains('cc2541') || // HM-10 的晶片型號
              lowerName.contains('cc2540') ||
              deviceName.isEmpty || // 包含沒有名稱的設備
              lowerName.contains('unknown')) {
            
            if (!devices.any((d) => d.remoteId == device.remoteId)) {
              devices.add(device);
              print('✅ 添加設備: $deviceName');
            }
          }
        }
      });

      // 設定掃描超時
      Timer(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          FlutterBluePlus.stopScan();
          completer.complete(devices);
        }
      });

      // 等待掃描完成
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      
      subscription?.cancel();
      await FlutterBluePlus.stopScan();
      
      print('📱 掃描完成，找到 ${devices.length} 個設備');
      return devices;
    } catch (e) {
      print('❌ 掃描 HM-10 設備時出錯: $e');
      await FlutterBluePlus.stopScan();
      return [];
    }
  }

  // 獲取已配對的設備
  Future<List<BluetoothDevice>> getPairedDevices({String? deviceNameFilter}) async {
    try {
      // 獲取已連接的設備
      List<BluetoothDevice> devices = await FlutterBluePlus.connectedDevices;
      
      // 如果指定了設備名稱過濾器，則過濾設備
      if (deviceNameFilter != null && deviceNameFilter.isNotEmpty) {
        devices = devices.where((device) => 
          device.platformName.toLowerCase().contains(deviceNameFilter.toLowerCase())
        ).toList();
      }
      
      return devices;
    } catch (e) {
      print('獲取已配對設備時出錯: $e');
      return [];
    }
  }

  // 連接到設備
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _connectedDevice = device;
      
      // 連接到設備
      await device.connect();
      
      // 發現服務
      List<BluetoothService> services = await device.discoverServices();
      
      // 尋找可用的特徵值
      BluetoothCharacteristic? writeCharacteristic;
      BluetoothCharacteristic? readCharacteristic;
      
      for (BluetoothService service in services) {
        print('🔍 發現服務: ${service.uuid}');
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          print('🔍 發現特徵值: ${characteristic.uuid}');
          print('🔍 特徵值屬性: ${characteristic.properties.toString()}');
          
          // 檢查是否可寫入
          if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
            writeCharacteristic = characteristic;
            print('✅ 找到寫入特徵值: ${characteristic.uuid}');
          }
          
          // 檢查是否可讀取或通知
          if (characteristic.properties.read || 
              characteristic.properties.notify || 
              characteristic.properties.indicate) {
            readCharacteristic = characteristic;
            print('✅ 找到讀取特徵值: ${characteristic.uuid}');
          }
        }
      }
      
      // 優先使用讀取特徵值，如果沒有則使用寫入特徵值
      _characteristic = readCharacteristic ?? writeCharacteristic;

      if (_characteristic != null) {
        // 設置通知（如果支持）
        if (_characteristic!.properties.notify || _characteristic!.properties.indicate) {
          try {
            await _characteristic!.setNotifyValue(true);
            print('✅ 已啟用通知');
          } catch (e) {
            print('⚠️ 無法啟用通知: $e');
          }
        }
        
        // 監聽數據
        _characteristic!.lastValueStream.listen((data) {
          String dataString = String.fromCharCodes(data);
          
          // 在命令行中顯示接收到的原始數據
          print('=' * 60);
          print('📡 [藍牙接收] Arduino 數據');
          print('=' * 60);
          print('⏰ 時間: ${DateTime.now().toString().substring(11, 19)}');
          print('📊 原始字節: [${data.map((b) => b.toString()).join(', ')}]');
          print('📝 字符串: "$dataString"');
          print('📏 數據長度: ${dataString.length} 字符');
          print('=' * 60);
          
          // 處理接收到的數據
          _processReceivedData(dataString);
        });

        _isConnected = true;
        _deviceName = device.platformName;
        print('✅ 藍牙連接成功: $_deviceName');
        return true;
      } else {
        print('未找到可用的特徵值');
        return false;
      }
    } catch (e) {
      print('連接設備時出錯: $e');
      _isConnected = false;
      return false;
    }
  }

  // 發送數據
  Future<bool> sendData(String data) async {
    if (!_isConnected || _characteristic == null) {
      print('❌ 設備未連接或特徵值不可用');
      return false;
    }

    try {
      List<int> bytes = data.codeUnits;
      
      // 在命令行中顯示發送的數據
      print('=' * 60);
      print('📤 [藍牙發送] 到 Arduino');
      print('=' * 60);
      print('⏰ 時間: ${DateTime.now().toString().substring(11, 19)}');
      print('📝 發送內容: "$data"');
      print('📊 字節數組: [${bytes.join(', ')}]');
      print('📏 數據長度: ${data.length} 字符');
      print('=' * 60);
      
      // 檢查特徵值是否支持寫入
      if (!_characteristic!.properties.write && !_characteristic!.properties.writeWithoutResponse) {
        print('❌ 特徵值不支持寫入操作');
        return false;
      }
      
      // 根據特徵值屬性選擇寫入方式
      if (_characteristic!.properties.write) {
        await _characteristic!.write(bytes);
      } else {
        await _characteristic!.write(bytes, withoutResponse: true);
      }
      
      print('✅ 數據發送成功');
      return true;
    } catch (e) {
      print('❌ 發送數據時出錯: $e');
      // 嘗試重新連接
      if (_connectedDevice != null) {
        print('🔄 嘗試重新連接...');
        await disconnect();
        await Future.delayed(const Duration(seconds: 1));
        return await connectToDevice(_connectedDevice!);
      }
      return false;
    }
  }

  // 斷開連接
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
      _isConnected = false;
      _deviceName = '';
      _connectedDevice = null;
      _characteristic = null;
    } catch (e) {
      print('斷開連接時出錯: $e');
    }
  }

  // 處理接收到的數據
  void _processReceivedData(String data) {
    // 清理數據
    String cleanData = data.trim();
    if (cleanData.isEmpty) return;
    
    // 處理 HM-10 的 AT 指令回應（忽略）
    if (cleanData == 'OK' || 
        cleanData == 'OK+CONN' || 
        cleanData == 'OK+CONNF' ||
        cleanData.startsWith('+') ||
        cleanData.startsWith('AT')) {
      print('📡 收到 HM-10 狀態回應: $cleanData');
      return;
    }
    
    // 檢查是否是完整的數據行
    if (cleanData.contains('\n') || cleanData.contains('\r')) {
      // 分割多行數據
      List<String> lines = cleanData.split(RegExp(r'[\n\r]+'));
      for (String line in lines) {
        line = line.trim();
        if (line.isNotEmpty && 
            line != 'OK' && 
            !line.startsWith('+') && 
            !line.startsWith('AT')) {
          print('📤 發送數據到 UI: $line');
          _dataController.add(line);
        }
      }
    } else {
      // 單行數據
      if (cleanData != 'OK' && 
          !cleanData.startsWith('+') && 
          !cleanData.startsWith('AT')) {
        print('📤 發送數據到 UI: $cleanData');
        _dataController.add(cleanData);
      }
    }
  }

  // 發送測試指令
  Future<bool> sendTestCommand() async {
    return await sendData('PING');
  }

  // 發送心跳測試
  Future<bool> sendHeartbeat() async {
    return await sendData('HELLO');
  }

  // 釋放資源
  void dispose() {
    _dataController.close();
    disconnect();
  }
}