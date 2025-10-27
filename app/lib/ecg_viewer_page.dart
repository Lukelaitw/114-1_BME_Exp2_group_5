import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'bluetooth_manager.dart';

class EcgViewerPage extends StatefulWidget {
  final BluetoothManager bluetoothManager;
  
  const EcgViewerPage({
    super.key,
    required this.bluetoothManager,
  });

  @override
  State<EcgViewerPage> createState() => _EcgViewerPageState();
}

class _EcgViewerPageState extends State<EcgViewerPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  List<double> _ecgData = [];
  int _bpm = 40;
  Timer? _dataTimer;
  final Random _random = Random();
  StreamSubscription<String>? _bluetoothSubscription;
  String _lastBluetoothData = '';

  // 心率估算的實例變數
  double _lastVoltage = 0;
  int _peakCount = 0;
  int _lastPeakTime = 0;
  
  // Arduino數據處理相關
  List<double> _rawAdcData = [];
  List<double> _filteredData = [];
  double _latestAdcValue = 0;
  double _latestVoltage = 0;
  bool _isReceivingArduinoData = false;
  DateTime? _lastDataTime;
  int _dataPointCount = 0;
  
  // ECG圖表控制變數
  double _zoomLevel = 1.0;
  bool _isZoomed = false;
  double _scrollOffset = 0.0; // 水平滾動偏移量

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController);
    _animationController.repeat();
    _startDataGeneration();
    _startBluetoothListening();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _dataTimer?.cancel();
    _bluetoothSubscription?.cancel();
    super.dispose();
  }

  void _startDataGeneration() {
    _dataTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        _generateEcgData();
      });
    });
  }

  void _startBluetoothListening() {
    _bluetoothSubscription = widget.bluetoothManager.dataStream.listen((data) {
      setState(() {
        _lastBluetoothData = data;
        _processBluetoothData(data);
      });
    });
  }

  void _processBluetoothData(String data) {
    // 處理ADC數據
    if (data.startsWith('ADC_DATA:')) {
      try {
        String adcData = data.substring(9); // 移除 'ADC_DATA:' 前綴
        List<String> parts = adcData.split(',');
        if (parts.length >= 2) {
          int adcValue = int.parse(parts[0]);
          double voltage = double.parse(parts[1]);
          
          setState(() {
            _latestAdcValue = adcValue.toDouble();
            _latestVoltage = voltage;
            _lastDataTime = DateTime.now();
            _isReceivingArduinoData = true;
            _dataPointCount++;
            
            // 保存原始ADC數據
            _rawAdcData.add(adcValue.toDouble());
            if (_rawAdcData.length > 300) {
              _rawAdcData.removeAt(0);
            }
            
            // 將ADC值轉換為適合ECG顯示的範圍
            // ADC值範圍: 0-1023, 轉換為 -2.5 到 2.5 的範圍
            double normalizedValue = (adcValue - 512) / 1023.0 * 5.0;
            
            // 應用簡單的移動平均濾波
            double filteredValue = _applyMovingAverageFilter(normalizedValue);
            
            _ecgData.add(filteredValue);
            _filteredData.add(filteredValue);
            
            // 限制數據長度
            if (_ecgData.length > 300) {
              _ecgData.removeAt(0);
            }
            if (_filteredData.length > 300) {
              _filteredData.removeAt(0);
            }
            
            // 根據電壓變化估算心率 (改進的峰值檢測)
            _estimateBpmFromVoltage(voltage);
          });
          
          print('處理ADC數據: ADC=$adcValue, 電壓=${voltage}V, 標準化值=${(adcValue - 512) / 1023.0 * 5.0}');
        }
      } catch (e) {
        print('處理ADC數據時出錯: $e');
      }
    }
    // 處理系統狀態
    else if (data.startsWith('SYSTEM_STATUS:')) {
      print('ECG頁面收到系統狀態: $data');
    }
    // 處理ADC傳輸狀態
    else if (data.startsWith('ADC_TRANSMISSION:')) {
      print('ECG頁面收到ADC傳輸狀態: $data');
    }
    // 處理心跳
    else if (data.startsWith('HEARTBEAT:')) {
      print('ECG頁面收到心跳: $data');
    }
    // 嘗試從其他數據中提取數值
    else {
      try {
        RegExp numberPattern = RegExp(r'(\d+(?:\.\d+)?)');
        Match? match = numberPattern.firstMatch(data);
        
        if (match != null) {
          double value = double.parse(match.group(1)!);
          
          // 如果數據看起來像心率 (30-200 範圍)
          if (value >= 30 && value <= 200) {
            _bpm = value.round();
          }
          
          // 如果數據看起來像 ECG 數值，添加到波形數據
          if (value >= -5 && value <= 5) {
            _ecgData.add(value);
            if (_ecgData.length > 200) {
              _ecgData.removeAt(0);
            }
          }
        }
      } catch (e) {
        print('處理藍牙數據時出錯: $e');
      }
    }
  }

  // 移動平均濾波器
  double _applyMovingAverageFilter(double newValue) {
    if (_filteredData.isEmpty) {
      return newValue;
    }
    
    // 使用最近5個值的移動平均
    int windowSize = 5;
    if (_filteredData.length < windowSize) {
      return newValue;
    }
    
    double sum = 0;
    for (int i = _filteredData.length - windowSize; i < _filteredData.length; i++) {
      sum += _filteredData[i];
    }
    return (sum + newValue) / (windowSize + 1);
  }

  void _estimateBpmFromVoltage(double voltage) {
    // 改進的心率估算：基於電壓變化頻率
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    
    // 檢測峰值 (改進的上升/下降檢測)
    if (voltage > _lastVoltage + 0.1 && _lastVoltage > 0) { // 增加閾值避免噪聲
      _peakCount++;
      if (currentTime - _lastPeakTime > 300) { // 至少300ms間隔
        _lastPeakTime = currentTime;
        // 計算BPM (基於峰值間隔)
        if (_peakCount > 2) {
          int timeDiff = currentTime - _lastPeakTime;
          if (timeDiff > 0) {
            int estimatedBpm = (60000 / timeDiff).round();
            if (estimatedBpm >= 30 && estimatedBpm <= 200) {
              setState(() {
                _bpm = estimatedBpm;
              });
            }
          }
        }
      }
    }
    
    _lastVoltage = voltage;
  }

  void _generateEcgData() {
    // 如果有藍牙數據，優先使用藍牙數據
    if (_ecgData.isNotEmpty) {
      return; // 使用藍牙數據，不生成模擬數據
    }
    
    // 如果沒有藍牙數據，生成模擬 ECG 數據
    double time = DateTime.now().millisecondsSinceEpoch / 1000.0;
    
    // 基礎心率 (BPM 轉換為頻率)
    double heartRate = _bpm / 60.0;
    
    // 生成 ECG 波形
    double ecgValue = 0;
    
    // QRS 複合波 (主要心跳)
    double qrsPhase = (time * heartRate * 2 * pi) % (2 * pi);
    if (qrsPhase < 0.1) {
      ecgValue += 2.0 * sin(qrsPhase * 10 * pi);
    }
    
    // P 波
    double pPhase = (time * heartRate * 2 * pi) % (2 * pi);
    if (pPhase > 0.2 && pPhase < 0.4) {
      ecgValue += 0.5 * sin((pPhase - 0.2) * 5 * pi);
    }
    
    // T 波
    double tPhase = (time * heartRate * 2 * pi) % (2 * pi);
    if (tPhase > 0.6 && tPhase < 0.8) {
      ecgValue += 0.3 * sin((tPhase - 0.6) * 5 * pi);
    }
    
    // 添加一些隨機噪聲
    ecgValue += (_random.nextDouble() - 0.5) * 0.1;
    
    _ecgData.add(ecgValue);
    
    // 保持數據長度在合理範圍內
    if (_ecgData.length > 200) {
      _ecgData.removeAt(0);
    }
  }

  void _updateBpm(int newBpm) {
    setState(() {
      _bpm = newBpm;
    });
  }

  // 清空ECG數據
  void _clearEcgData() {
    setState(() {
      _ecgData.clear();
      _rawAdcData.clear();
      _filteredData.clear();
      _dataPointCount = 0;
      _isReceivingArduinoData = false;
      _lastDataTime = null;
    });
  }

  // 縮放ECG圖表
  void _zoomIn() {
    setState(() {
      _zoomLevel = (_zoomLevel * 1.5).clamp(0.5, 5.0);
      _isZoomed = _zoomLevel != 1.0;
      // 當放大時，自動滾動到最新數據
      if (_ecgData.isNotEmpty) {
        _scrollOffset = (_ecgData.length * _zoomLevel - 300).clamp(0.0, double.infinity);
      }
    });
  }

  void _zoomOut() {
    setState(() {
      _zoomLevel = (_zoomLevel / 1.5).clamp(0.5, 5.0);
      _isZoomed = _zoomLevel != 1.0;
      // 當縮小時，調整滾動位置
      _scrollOffset = (_scrollOffset / 1.5).clamp(0.0, double.infinity);
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomLevel = 1.0;
      _isZoomed = false;
      _scrollOffset = 0.0;
    });
  }

  // 滾動控制
  void _scrollLeft() {
    setState(() {
      _scrollOffset = (_scrollOffset - 50).clamp(0.0, double.infinity);
    });
  }

  void _scrollRight() {
    setState(() {
      if (_ecgData.isNotEmpty) {
        double maxOffset = (_ecgData.length * _zoomLevel - 300).clamp(0.0, double.infinity);
        _scrollOffset = (_scrollOffset + 50).clamp(0.0, maxOffset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ECG & BPM Viewer'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('設定心率'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('目前心率: $_bpm BPM'),
                      Slider(
                        value: _bpm.toDouble(),
                        min: 30,
                        max: 120,
                        divisions: 90,
                        onChanged: (value) {
                          _updateBpm(value.round());
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('確定'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Arduino數據狀態和BPM顯示
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Arduino數據狀態
                    if (_isReceivingArduinoData) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[300]!),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.radio_button_checked, color: Colors.green, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  '正在接收Arduino數據',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[800],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildDataInfo('ADC值', '${_latestAdcValue.round()}', Icons.signal_cellular_alt),
                                _buildDataInfo('電壓', '${_latestVoltage.toStringAsFixed(3)}V', Icons.electrical_services),
                                _buildDataInfo('數據點', '$_dataPointCount', Icons.analytics),
                              ],
                            ),
                            if (_lastDataTime != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '最後更新: ${_lastDataTime!.hour.toString().padLeft(2, '0')}:${_lastDataTime!.minute.toString().padLeft(2, '0')}:${_lastDataTime!.second.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // BPM顯示
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'BPM',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            Icon(
                              widget.bluetoothManager.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                              color: widget.bluetoothManager.isConnected ? Colors.blue : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.bluetoothManager.isConnected ? '藍牙已連接' : '藍牙未連接',
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.bluetoothManager.isConnected ? Colors.blue : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_bpm',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getBpmStatus(_bpm),
                      style: TextStyle(
                        fontSize: 16,
                        color: _getBpmColor(_bpm),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_isReceivingArduinoData) ...[
                      const SizedBox(height: 8),
                      Text(
                        '基於Arduino數據計算',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // ECG 波形顯示
            SizedBox(
              height: 450, // 增加高度
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ECG/EMG',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: [
                              if (_isReceivingArduinoData) ...[
                                Icon(Icons.radio_button_checked, color: Colors.green, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  'Arduino數據',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ] else ...[
                                Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '模擬數據',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 圖表控制按鈕
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 縮放控制
                          Row(
                            children: [
                              IconButton(
                                onPressed: _zoomOut,
                                icon: const Icon(Icons.zoom_out),
                                tooltip: '縮小',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.grey[100],
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${(_zoomLevel * 100).toInt()}%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: _zoomIn,
                                icon: const Icon(Icons.zoom_in),
                                tooltip: '放大',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.grey[100],
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                              if (_isZoomed) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  onPressed: _resetZoom,
                                  icon: const Icon(Icons.refresh),
                                  tooltip: '重置縮放',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.orange[100],
                                    foregroundColor: Colors.orange[700],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // 清空按鈕
                          ElevatedButton.icon(
                            onPressed: _clearEcgData,
                            icon: const Icon(Icons.clear_all, size: 16),
                            label: const Text('清空圖表'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[100],
                              foregroundColor: Colors.red[700],
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                      // 滾動控制按鈕
                      if (_isZoomed) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _scrollLeft,
                              icon: const Icon(Icons.arrow_back_ios),
                              tooltip: '向左滾動',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.blue[100],
                                foregroundColor: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '滾動查看歷史數據',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _scrollRight,
                              icon: const Icon(Icons.arrow_forward_ios),
                              tooltip: '向右滾動',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.blue[100],
                                foregroundColor: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_isReceivingArduinoData) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildChartInfo('原始ADC', '${_rawAdcData.isNotEmpty ? _rawAdcData.last.round() : 0}'),
                            _buildChartInfo('標準化值', '${_ecgData.isNotEmpty ? _ecgData.last.toStringAsFixed(2) : '0.00'}'),
                            _buildChartInfo('數據點數', '${_ecgData.length}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(8), // 增加外邊距
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[50],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16), // 增加內邊距
                            child: CustomPaint(
                              painter: EcgPainter(_ecgData, _isReceivingArduinoData, _zoomLevel, _scrollOffset),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // ADC控制按鈕
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'ADC控制',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              bool success = await widget.bluetoothManager.sendData('START_ADC');
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已發送開始ADC指令')),
                                );
                              }
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('開始ADC'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              bool success = await widget.bluetoothManager.sendData('STOP_ADC');
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已發送停止ADC指令')),
                                );
                              }
                            },
                            icon: const Icon(Icons.stop),
                            label: const Text('停止ADC'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 模擬控制按鈕
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _bpm = 40;
                      });
                    },
                    icon: const Icon(Icons.favorite),
                    label: const Text('正常心率 (40)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _bpm = 80;
                      });
                    },
                    icon: const Icon(Icons.favorite_border),
                    label: const Text('標準心率 (80)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getBpmStatus(int bpm) {
    if (bpm < 60) return '心率偏低';
    if (bpm > 100) return '心率偏高';
    return '心率正常';
  }

  Color _getBpmColor(int bpm) {
    if (bpm < 60) return Colors.blue;
    if (bpm > 100) return Colors.red;
    return Colors.green;
  }
  
  // 構建數據信息顯示
  Widget _buildDataInfo(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }
  
  // 構建圖表信息顯示
  Widget _buildChartInfo(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class EcgPainter extends CustomPainter {
  final List<double> data;
  final bool isArduinoData;
  final double zoomLevel;
  final double scrollOffset;
  
  EcgPainter(this.data, [this.isArduinoData = false, this.zoomLevel = 1.0, this.scrollOffset = 0.0]);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // 根據數據來源選擇顏色
    final paint = Paint()
      ..color = isArduinoData ? Colors.green : Colors.blue
      ..strokeWidth = isArduinoData ? 2.5 : 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    
    // 計算縮放比例
    double maxValue = data.reduce((a, b) => a > b ? a : b);
    double minValue = data.reduce((a, b) => a < b ? a : b);
    double range = maxValue - minValue;
    
    if (range == 0) range = 1;
    
    // 調試信息
    print('ECG繪製調試: 數據點數=${data.length}, 最大值=$maxValue, 最小值=$minValue, 範圍=$range');
    
    // 應用縮放級別 - 橫軸放大時縱軸縮小
    double scaleY = (size.height / range) / (zoomLevel * 0.5); // 縱軸縮小，但保持最小可見性
    double scaleX = (size.width / data.length) * zoomLevel; // 橫軸放大
    
    // 如果數據範圍太小，使用固定縮放
    if (range < 0.1) {
      scaleY = size.height / 2; // 使用固定縮放
      print('使用固定縮放，範圍太小: $range');
    }
    
    // 確保縱軸縮放不會太小
    if (scaleY < 10) scaleY = 10;
    
    // 繪製網格
    _drawGrid(canvas, size);
    
    // 繪製 ECG 波形 - 支援滾動
    int startIndex = (scrollOffset / scaleX).round().clamp(0, data.length);
    int endIndex = ((scrollOffset + size.width) / scaleX).round().clamp(0, data.length);
    
    // 確保至少繪製一些數據點
    if (startIndex >= endIndex) {
      startIndex = 0;
      endIndex = data.length;
    }
    
    for (int i = startIndex; i < endIndex; i++) {
      double x = i * scaleX - scrollOffset;
      double y = size.height / 2 - ((data[i] - minValue) * scaleY); // 以中心為基準
      
      if (i == startIndex) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, paint);
    
    // 如果是Arduino數據，添加實時指示器
    if (isArduinoData && data.isNotEmpty) {
      _drawRealTimeIndicator(canvas, size, data.last, maxValue, minValue, range);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 0.5;

    // 繪製水平網格線
    for (int i = 0; i <= 10; i++) {
      double y = size.height * i / 10;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }
    
    // 繪製垂直網格線
    for (int i = 0; i <= 20; i++) {
      double x = size.width * i / 20;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }
  }
  
  void _drawRealTimeIndicator(Canvas canvas, Size size, double lastValue, double maxValue, double minValue, double range) {
    // 繪製實時數據指示器
    final indicatorPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    final dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    // 計算最後一個數據點的位置，確保不超出邊界
    double x = (size.width - 20).clamp(10.0, size.width - 10); // 確保有足夠的邊距
    double y = (size.height / 2 - ((lastValue - minValue) / range * size.height / 2)).clamp(10.0, size.height - 10);
    
    // 繪製垂直線，確保不超出邊界
    canvas.drawLine(
      Offset(x, 5),
      Offset(x, size.height - 5),
      indicatorPaint,
    );
    
    // 繪製數據點
    canvas.drawCircle(Offset(x, y), 3, dotPaint);
    
    // 繪製數值標籤，確保不超出邊界
    final textPainter = TextPainter(
      text: TextSpan(
        text: lastValue.toStringAsFixed(2),
        style: TextStyle(
          color: Colors.red,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    // 計算文字位置，確保不超出邊界
    double textX = (x - textPainter.width / 2).clamp(5, size.width - textPainter.width - 5);
    double textY = (y - 15).clamp(5, size.height - textPainter.height - 5);
    
    textPainter.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(covariant EcgPainter oldDelegate) {
    return oldDelegate.data != data || 
           oldDelegate.isArduinoData != isArduinoData ||
           oldDelegate.zoomLevel != zoomLevel ||
           oldDelegate.scrollOffset != scrollOffset;
  }
}