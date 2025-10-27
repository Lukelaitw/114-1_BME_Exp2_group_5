import 'package:flutter/material.dart';
import 'bluetooth_manager.dart';
import 'connection_page.dart';
import 'data_page.dart';
import 'ecg_viewer_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arduino 藍牙連接',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final BluetoothManager _bluetoothManager = BluetoothManager();

  @override
  void dispose() {
    _bluetoothManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ConnectionPage(
            bluetoothManager: _bluetoothManager,
            onConnected: () {
              setState(() {
                _currentIndex = 1; // 切換到數據頁面
              });
            },
          ),
          DataPage(bluetoothManager: _bluetoothManager),
          EcgViewerPage(bluetoothManager: _bluetoothManager),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: '藍牙連接',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.data_usage),
            label: '數據顯示',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'ECG圖表',
          ),
        ],
      ),
    );
  }
}

