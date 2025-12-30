// flutter_app/lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'native/vacuum_backend.dart';

void main() {
  runApp(const VacuumDemoApp());
}

class VacuumDemoApp extends StatelessWidget {
  const VacuumDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vacuum FFI Demo',
      debugShowCheckedModeBanner: false,
      home: const VacuumHomePage(),
    );
  }
}

class VacuumHomePage extends StatefulWidget {
  const VacuumHomePage({super.key});

  @override
  State<VacuumHomePage> createState() => _VacuumHomePageState();
}

class _VacuumHomePageState extends State<VacuumHomePage> {
  // 🔹 C++ FFI 백엔드
  late final VacuumNative backend;

  // 주기적으로 vacuum_step() 호출용 타이머
  Timer? _timer;

  // 현재 압력 / PASS 상태
  double _pressure = 0.0;
  bool _pass = true;

  // 시간 / 압력 모드 (Dropdown에서 선택)
  int _timeMode = 2;      // 2: 5분 예제
  int _pressureMode = 65; // 65 kPa 예제

  @override
  void initState() {
    super.initState();

    // C++ 라이브러리 로드 + 초기화
    backend = VacuumNative();
    backend.vacuumInit();

    // 초기 모드 설정을 C++ 쪽에도 전달
    backend.vacuumSetTimeMode(_timeMode);
    backend.vacuumSetPressureMode(_pressureMode);
  }

  /// START 버튼: 진공 시작 + 타이머로 주기적 step
  void _startVac() {
    // 현재 설정을 C++에 전달
    backend.vacuumSetTimeMode(_timeMode);
    backend.vacuumSetPressureMode(_pressureMode);
    backend.vacuumStart();

    // 이전 타이머 있으면 정리
    _timer?.cancel();

    // 200ms마다 C++에서 step + pressure 읽어오기
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      backend.vacuumStep();

      final p = backend.vacuumGetLastPressure();
      final pass = backend.vacuumGetLastPass() == 1;

      setState(() {
        _pressure = p;
        _pass = pass;
      });
    });
  }

  /// STOP 버튼: 타이머만 멈춤 (C++쪽 stop 함수는 나중에 추가 가능)
  void _stopVac() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _pass ? 'PASS' : 'FAIL';
    final statusColor = _pass ? Colors.green : Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vacuum FFI Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ====== 설정 영역 ======
            Row(
              children: [
                const Text('Time Mode:'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _timeMode,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('수동')),
                    DropdownMenuItem(value: 2, child: Text('5분')),
                    DropdownMenuItem(value: 3, child: Text('3분')),
                    DropdownMenuItem(value: 4, child: Text('2분')),
                    DropdownMenuItem(value: 5, child: Text('30초')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _timeMode = v);
                    backend.vacuumSetTimeMode(v);
                  },
                ),
                const SizedBox(width: 24),
                const Text('Pressure:'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _pressureMode,
                  items: const [
                    DropdownMenuItem(value: 62, child: Text('62 kPa')),
                    DropdownMenuItem(value: 65, child: Text('65 kPa')),
                    DropdownMenuItem(value: 80, child: Text('80 kPa')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _pressureMode = v);
                    backend.vacuumSetPressureMode(v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ====== 현재 상태 표시 ======
            Card(
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Pressure: ${_pressure.toStringAsFixed(2)} kPa',
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Result: $statusText',
                      style: TextStyle(
                        fontSize: 24,
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ====== START / STOP 버튼 ======
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _startVac,
                  child: const Text('START'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _stopVac,
                  child: const Text('STOP'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
