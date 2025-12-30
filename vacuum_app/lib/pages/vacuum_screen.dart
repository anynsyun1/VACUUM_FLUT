import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'native/vacuum_backend.dart';
import 'pages/data_management_page.dart';

/// VACUUM 메인 화면
class VacuumScreen extends StatefulWidget {
  const VacuumScreen({super.key});

  @override
  State<VacuumScreen> createState() => _VacuumScreenState();
}

class _VacuumScreenState extends State<VacuumScreen> {
  // 시간 SET 그룹 (MANUAL, 5M, 3M, 2M, 30S)
  String _selectedTime = 'MANUAL';

  // 압력 선택 (62 / 65 / 80)
  int _selectedKpa = 65;

  // Data Management 모드 여부
  bool _isDataManagementMode = false;

  // C++ 백엔드 (FFI)
  late final VacuumNative backend;

  // 포트 관련 상태
  List<String> _ports = [];
  String? _selectedPort;
  bool _connected = false;

  // 측정 중 여부 (VAC / CHK 진행 중)
  bool _measuring = false;

  // 진공 측정 상태
  Timer? _timer;
  double _pressure = 0.0;
  bool _pass = true;
  int _stepIndex = 0;

  // 실시간 압력 / 결과
  final double _currentPressure = 0.0;
  final bool _currentPass = true;

  // 차트용 데이터
  final List<FlSpot> _spots = [];
  final double _elapsedSec = 0;

  Timer? _vacTimer;

  // 차트용 데이터 (x: step index, y: 압력 변화)
  final List<FlSpot> _chartSpots = [];

  @override
  void initState() {
    super.initState();
    backend = VacuumNative();
    backend.vacuumInit();

    // 초기 모드 C++에도 전달
    backend.vacuumSetTimeMode(_mapTimeModeToCode(_selectedTime));
    backend.vacuumSetPressureMode(_selectedKpa);

    _refreshPorts();
    _connected = backend.isConnected();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ======================== 공통 ========================

  /// Data Management 화면 열기
  Future<void> _openDataManagement() async {
    setState(() {
      _isDataManagementMode = true;
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DataManagementPage(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _isDataManagementMode = false;
    });
  }

  /// 포트 목록 새로고침 (C++에서 가져오기)
  Future<void> _refreshPorts() async {
    final ports = backend.listPorts();
    setState(() {
      _ports = ports;
      if (ports.isNotEmpty) {
        // 기존 선택 유지, 없으면 첫 번째 선택
        if (_selectedPort == null || !_ports.contains(_selectedPort)) {
          _selectedPort = ports.first;
        }
      } else {
        _selectedPort = null;
        _connected = false;
      }
    });
  }

  /// 선택된 포트로 연결
  void _onConnect() {
    if (_selectedPort == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연결할 포트를 선택하세요.')),
      );
      return;
    }

    final ok = backend.connect(_selectedPort!);
    setState(() {
      _connected = ok;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '$_selectedPort 연결 성공' : '$_selectedPort 연결 실패',
        ),
      ),
    );
  }

  /// 연결 해제
  void _onDisconnect() {
    backend.disconnect();
    setState(() {
      _connected = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('연결 해제됨')),
    );
  }

  /// 시간 모드 → C++ backend 코드 매핑
  int _mapTimeModeToCode(String mode) {
    switch (mode) {
      case '5M':
        return 2;
      case '3M':
        return 3;
      case '2M':
        return 4;
      case '30S':
        return 5;
      case 'MANUAL':
      default:
        return 1;
    }
  }

  // ======================== VAC / CHK / STOP ========================

  /// VAC 버튼 눌렀을 때 : C++측에서 진공 시작 + 주기적으로 step 호출
  void _onStartVac() {
    if (!_connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 장비를 CONNECT 하세요.')),
      );
      return;
    }
    if (_measuring) return;

    // 시간 / 압력 설정을 C++에 전달
    backend.vacuumSetTimeMode(_mapTimeModeToCode(_selectedTime));
    backend.vacuumSetPressureMode(_selectedKpa);

    // 시퀀스 시작
    backend.vacuumStart();

    _timer?.cancel();
    _stepIndex = 0;
    _chartSpots.clear();
    setState(() {
      _measuring = true;
    });

    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      backend.vacuumStep();
      final p = backend.vacuumGetLastPressure();
      final pass = backend.vacuumGetLastPass() == 1;

      setState(() {
        _pressure = p;
        _pass = pass;

        // 간단한 차트: 압력 변화(현재압 - 설정압력)를 y값으로 사용
        final diff = _pressure - _selectedKpa;
        if (_chartSpots.length < 300) {
          _chartSpots.add(FlSpot(_stepIndex.toDouble(), diff));
        }
        _stepIndex++;
      });
    });
  }

  /// CHK 버튼: 우선 VAC과 같은 동작 (나중에 필요시 따로 분리 가능)
  void _onStartChk() => _onStartVac();

  /// STOP(SAVE) 버튼: 시퀀스 정지 (DB 저장은 추후 실제 로직과 연동)
  void _onStop() {
    if (!_measuring) return;

    _timer?.cancel();
    _timer = null;

    setState(() {
      _measuring = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('측정을 중지했습니다. (저장 로직은 추후 연동 예정)')),
    );
  }

  // ======================== UI ========================

  @override
  Widget build(BuildContext context) {
    final statusText = _pass ? 'PASS' : 'FAIL';
    final statusColor = _pass ? Colors.green : Colors.red;

    // 시간 모드 텍스트
    String timeModeText;
    switch (_selectedTime) {
      case '5M':
        timeModeText = '5분(300)';
        break;
      case '3M':
        timeModeText = '3분(180)';
        break;
      case '2M':
        timeModeText = '2분(120)';
        break;
      case '30S':
        timeModeText = '30초(30)';
        break;
      case 'MANUAL':
      default:
        timeModeText = '수동(MANUAL)';
        break;
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red, width: 1),
            ),
            child: Row(
              children: [
                // ============================ LEFT SIDE ============================ //
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 제목
                        Center(
                          child: Column(
                            children: const [
                              Text(
                                'ONSEMI WAFER PAK',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text('(제품코드, 단위: KPA , SEC)'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(height: 2, color: Colors.blue),
                        const SizedBox(height: 12),

                        // COM / 포트 선택 + CONNECT / DISCONNECT / DATA MANAGEMENT
                        Row(
                          children: [
                            const Text(
                              'PORT',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: _selectedPort,
                              hint: const Text('No Port'),
                              items: _ports
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _measuring
                                  ? null
                                  : (v) {
                                      setState(() {
                                        _selectedPort = v;
                                      });
                                    },
                            ),
                            IconButton(
                              onPressed: _measuring ? null : _refreshPorts,
                              icon: const Icon(Icons.refresh),
                              tooltip: '포트 새로고침',
                            ),
                            const SizedBox(width: 20),
                            ElevatedButton(
                              onPressed: (!_connected && !_measuring)
                                  ? _onConnect
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _connected
                                    ? Colors.grey
                                    : Colors.blue,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Text('CONNECT'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: (_connected && !_measuring)
                                  ? _onDisconnect
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _connected
                                    ? Colors.red
                                    : Colors.grey,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Text('DISCONNECT'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // DATA MANAGEMENT 버튼
                            ElevatedButton(
                              onPressed: _isDataManagementMode
                                      || _measuring
                                  ? null
                                  : _openDataManagement,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                backgroundColor: _isDataManagementMode
                                    ? Colors.orange[200]
                                    : Colors.orange,
                              ),
                              child: const Text(
                                'DATA MANAGEMENT',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 데이터 테이블 (샘플 / 나중에 DB 연동해도 됨)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.black,
                                width: 1,
                              ),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  headingRowHeight: 40,
                                  columns: const [
                                    DataColumn(label: Text("코드DATA")),
                                    DataColumn(label: Text("구분")),
                                    DataColumn(label: Text("선택압력")),
                                    DataColumn(label: Text("시작압력")),
                                    DataColumn(label: Text("종료압력")),
                                    DataColumn(label: Text("압력변화")),
                                    DataColumn(label: Text("결과")),
                                    DataColumn(label: Text("날짜-시간")),
                                  ],
                                  rows: List.generate(
                                    7,
                                    (i) => DataRow(
                                      cells: [
                                        DataCell(Text("Z12345$i")),
                                        const DataCell(Text("PAK")),
                                        DataCell(Text("$_selectedKpa")),
                                        DataCell(
                                          Text(
                                            (_pressure + 1.2)
                                                .toStringAsFixed(1),
                                          ),
                                        ),
                                        DataCell(
                                          Text(_pressure.toStringAsFixed(1)),
                                        ),
                                        const DataCell(Text("1.0")),
                                        DataCell(Text(statusText)),
                                        const DataCell(
                                          Text("2024-10-10 12:12"),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // VAC / CHK / STOP(SAVE) 버튼들
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isDataManagementMode
                                        || !_connected
                                    ? null
                                    : _onStartVac,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _measuring
                                      ? Colors.green[300]
                                      : Colors.green,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    "VAC",
                                    style: TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isDataManagementMode
                                        || !_connected
                                    ? null
                                    : _onStartChk,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _measuring
                                      ? Colors.blue[300]
                                      : Colors.blue,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    "CHK",
                                    style: TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    _isDataManagementMode || !_measuring
                                        ? null
                                        : _onStop,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      _measuring ? Colors.red : Colors.grey,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    "STOP(SAVE)",
                                    style: TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 시간 SET + KPA SET 그룹
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 시간 SET 묶음
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildTimeCheckbox("수동 SET", 'MANUAL'),
                                  _buildTimeCheckbox("5분 SET", '5M'),
                                  _buildTimeCheckbox("3분 SET", '3M'),
                                  _buildTimeCheckbox("2분 SET", '2M'),
                                  _buildTimeCheckbox("30초 SET", '30S'),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // KPA 묶음
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildKpaCheckbox("62 KPA", 62),
                                  _buildKpaCheckbox("65 KPA", 65),
                                  _buildKpaCheckbox("80 KPA", 80),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text("□ 30초 사용시는 테스트에서만 적용됩니다"),
                      ],
                    ),
                  ),
                ),

                // ============================ RIGHT SIDE ============================ //
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        // 윗 제목: ONSEMI 1호기
                        Container(
                          height: 40,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue, width: 2),
                          ),
                          child: const Center(
                            child: Text(
                              "ONSEMI 1호기",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 그래프
                        Expanded(
                          flex: 3,
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blue, width: 2),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  "Vacuum Pressure Change",
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: VacuumPressureChart(
                                    spots: _chartSpots,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // VACUUM 상태
                        Expanded(
                          flex: 2,
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blue, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                "VACUUM\n"
                                "PRESSURE: ${_pressure.toStringAsFixed(2)} KPA\n"
                                "TIME: $timeModeText\n"
                                "RESULT: $statusText",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ====== helper widgets for checkbox groups ======

  Widget _buildTimeCheckbox(String label, String value) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 16),
      ),
      value: _selectedTime == value,
      onChanged: _measuring
          ? null
          : (_) {
              setState(() {
                _selectedTime = value;
              });
              // C++에도 반영
              backend.vacuumSetTimeMode(_mapTimeModeToCode(value));
            },
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildKpaCheckbox(String label, int value) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 18),
      ),
      value: _selectedKpa == value,
      onChanged: _measuring
          ? null
          : (_) {
              setState(() {
                _selectedKpa = value;
              });
              backend.vacuumSetPressureMode(value);
            },
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

/// ─────────────────────────────────────────
///  차트 위젯
///   - x: 0 ~ 300
///   - y: 대략 -5 ~ +5 (압력 차이 기준)
/// ─────────────────────────────────────────
class VacuumPressureChart extends StatelessWidget {
  final List<FlSpot> spots;

  const VacuumPressureChart({
    super.key,
    required this.spots,
  });

  @override
  Widget build(BuildContext context) {
    final data = spots.isEmpty
        ? const [
            FlSpot(0, 0),
            FlSpot(60, 0),
            FlSpot(120, -1),
            FlSpot(180, -2),
            FlSpot(240, -3),
            FlSpot(300, -3),
          ]
        : spots;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 300,
        minY: -5,
        maxY: 5,
        gridData: FlGridData(show: true),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(),
            bottom: BorderSide(),
            right: BorderSide(),
            top: BorderSide(),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
            ),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: false,
            barWidth: 2,
            spots: data,
            dotData: FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
