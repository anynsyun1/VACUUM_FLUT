
// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pages/data_management_page.dart';
import 'native/vacuum_backend.dart';
import 'models/vacuum_record.dart';
import 'services/vacuum_db.dart';

enum MeasureMode { none, vac, chk }


void main() {
  // Linux / Windows 에서 SQLite FFI 초기화
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const VacuumApp());
}

class VacuumApp extends StatelessWidget {
  const VacuumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SERA VACUUM',
      debugShowCheckedModeBanner: false,
      home: const VacuumScreen(),
    );
  }
}

/// ─────────────────────────────────────────
///  VACUUM 메인 화면
/// ─────────────────────────────────────────
class VacuumScreen extends StatefulWidget {
  const VacuumScreen({super.key});

  @override
  State<VacuumScreen> createState() => _VacuumScreenState();
}

class _VacuumScreenState extends State<VacuumScreen> 
  with SingleTickerProviderStateMixin {
  // 🔹 C++ 백엔드
  late final VacuumNative _backend;

  // 시리얼 포트 관련 상태
  List<String> _ports = [];
  String? _selectedPort;
  bool _connected = false;
  bool _connecting = false;
  String _portStatusText = 'DISCONNECTED';

  final FocusNode _lotFocusNode = FocusNode();

  // 시간 SET 그룹 : MANUAL, 5M, 3M, 2M, 30S
  String _selectedTime = 'MANUAL';

  // KPA 그룹 : 62, 65, 80
  int _selectedKpa = 65;

  // 데이터 관리 모드: true이면 VAC/CHK/STOP 비활성화
  bool _isDataManagementMode = false;

  // 테이블용 최근 레코드 (DB에서 가져온 5개 정도)
  List<VacuumRecord> _recentRecords = [];

  // 새 레코드용 코드DATA 입력 필드
  final TextEditingController _lotController = TextEditingController();

  // 실시간 상태값 (VACUUM 패널)
  double _currentPressure = 0.0; // 마지막 측정 압력(현재 압력)
  double _currentStartP = 0.0; // 시작 압력
  double _currentStopP = 0.0; // 종료 압력
  double _currentDiff = 0.0; // ΔP
  bool _currentPass = true;
  bool _currentStopFlag = false;
  int _currentDurationSec = 0; // 패널/테이블용 지속시간(초 단위 표시용)

  // 차트 오프셋 (STARTOFFSET과 맞춰서 사용)
  static const int _chartOffsetTicks = 20; // timer tick 20개(=10초) 이후부터 그래프

  int _timeCounter = 0; // C++ measureAndDecide()에 넘기는 카운터
  final int _div = 2; // 0.5초 간격(500ms)일 때 counter 2개 = 1초

  // 어떤 버튼으로 시작했는지 (VAC / CHK 에 따라 PAK / CHUCK)
  String _currentPkck = 'PAK';

  // 차트 데이터 (ΔP vs time)
  final List<FlSpot> _spots = [];
  double _elapsedSec = 0; // offset 이후 경과시간 (차트/패널/DB용)

  Timer? _vacTimer;
  bool _isMeasuring = false;

  bool get _hasLotCode => _lotController.text.trim().isNotEmpty;

  bool get _basicButtonsEnabled =>
      !_isDataManagementMode && _connected && _hasLotCode;

  bool get _vacButtonsEnabled => _basicButtonsEnabled && !_isMeasuring;
  bool get _stopEnabled => _basicButtonsEnabled && _isMeasuring;

  // 차트 Y 범위 (ΔP)
  static const double _minDiff = -5.0;
  static const double _maxDiff = 5.0;

  late final AnimationController _blinkCtrl;
  MeasureMode _measureMode = MeasureMode.none;
  int _measureChannel = 0;


  bool _blinkOn = false;
  Timer? _blinkTimer;

    //  VAC/CHK 
  String? _activeJob; // 'VAC' | 'CHK' | null

  ButtonStyle _blueEnabledButtonStyle() {
    return ButtonStyle(
      backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (states.contains(MaterialState.disabled)) return null; // ?? disabled ??
        return Colors.blue; // enabled? ??
      }),
      foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (states.contains(MaterialState.disabled)) return null; // ?? disabled ??
        return Colors.white; // enabled? ?? ??
      }),
    );
  }

  ButtonStyle _mainButtonStyle(bool enabled) {
    return ElevatedButton.styleFrom(
      backgroundColor: enabled ? Colors.blue : null,
      foregroundColor: enabled ? Colors.white : null,
      disabledBackgroundColor: Colors.grey[300],
      disabledForegroundColor: Colors.grey[600],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _blinkWrapper({
    required bool active,
    required Widget child,
  }) {
    const double bw = 3; // 항상 같은 두께 유지
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        border: Border.all(
          color: (active && _blinkOn) ? Colors.blue : Colors.transparent,
          width: bw,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _buildBlueButton({
    required String label,
    required VoidCallback? onPressed,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    double fontSize = 16,
    bool isRunning = false,
    double? fixedHeight, // ✅ 높이 고정 옵션
  }) {
    final enabled = onPressed != null;

    return AnimatedBuilder(
      animation: _blinkCtrl,
      builder: (context, _) {
        final showBorder = isRunning && (_blinkCtrl.value > 0.5);
        final borderColor = showBorder ? Colors.blue : Colors.transparent;

        final iconSize = fontSize + 2;

        return Container(
          // ✅ 테두리는 항상 같은 두께로 유지 (색만 변경)
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: SizedBox(
            height: fixedHeight, // ✅ Row 높이 고정
            child: ElevatedButton(
              onPressed: onPressed,
              style: ButtonStyle(
                padding: MaterialStateProperty.all(padding),
                minimumSize: fixedHeight == null
                    ? null
                    : MaterialStateProperty.all(Size.fromHeight(fixedHeight)),
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                backgroundColor: MaterialStateProperty.resolveWith((states) {
                  if (states.contains(MaterialState.disabled)) return null;
                  return Colors.blue;
                }),
                foregroundColor: MaterialStateProperty.resolveWith((states) {
                  if (states.contains(MaterialState.disabled)) return null;
                  return Colors.white;
                }),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ 아이콘 “자리”는 항상 확보 (Opacity로만 보이게/숨기게)
                  Opacity(
                    opacity: isRunning ? 1.0 : 0.0,
                    child: Icon(
                      Icons.autorenew,
                      size: iconSize,
                      color: enabled ? Colors.white : null,
                    ),
                  ),
                  const SizedBox(width: 8), // ✅ 간격도 항상 유지
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _backend = VacuumNative();
    _backend.init();
    _refreshPorts();
  }

  @override
  void dispose() {
    _vacTimer?.cancel();
    _lotController.dispose();
    _lotFocusNode.dispose();
    _blinkCtrl.dispose();  
    super.dispose();
  }

  // ───────────────────────── 포트 처리 ─────────────────────────

  void _refreshPorts() {
    try {
      final ports = _backend.listPorts();
      setState(() {
        _ports = ports;
        if (_ports.isNotEmpty) {
          _selectedPort ??= _ports.first;
          _portStatusText =
              _connected ? 'CONNECTED: $_selectedPort' : 'PORT: $_selectedPort';
        } else {
          _selectedPort = null;
          _portStatusText = 'NO PORT FOUND';
        }
      });
    } catch (e) {
      setState(() {
        _ports = [];
        _selectedPort = null;
        _portStatusText = 'PORT ERROR: $e';
      });
    }
  }

  Future<void> _loadRecentFromDB() async {
    try {
      final list = await VacuumDB.instance.queryLatest(limit: 5);
      // DB에서는 lotid DESC(최신 → 오래된) 으로 가져오고,
      // 화면에는 오래된 게 위, 최신이 아래로 보이도록 reverse
      setState(() {
        _recentRecords = list.reversed.toList();
      });
    } catch (e) {
      debugPrint('DB load error: $e');
    }
  }

  Future<void> _connect() async {
    if (_selectedPort == null || _connecting || _connected) return;

    setState(() {
      _connecting = true;
      _portStatusText = 'CONNECTING...';
    });

    final ok = _backend.connect(_selectedPort!);

    setState(() {
      _connected = ok;
      _connecting = false;
      _portStatusText =
          ok ? 'CONNECTED: $_selectedPort' : 'CONNECT FAILED (${_selectedPort!})';
    });

    if (ok) {
      await _loadRecentFromDB();
      _lotController.clear();
      setState(() {}); // 버튼 활성화 상태 갱신
    }
  }

  void _disconnect() {
    if (!_connected) return;
    _vacTimer?.cancel();
    _vacTimer = null;
    _blinkCtrl.stop(); 
    _isMeasuring = false;
    _measureMode = MeasureMode.none;
    _backend.disconnect();
    setState(() {
      _connected = false;
      _portStatusText = 'DISCONNECTED';
      _isMeasuring = false;
      _activeJob = null;
    });
  }

  // ───────────────────────── 시간 / 압력 모드 ─────────────────────────

  int _timeModeValue() {
    switch (_selectedTime) {
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

  String _timeLabelForStatus() {
    switch (_selectedTime) {
      case '5M':
        return '5분(300)';
      case '3M':
        return '3분(180)';
      case '2M':
        return '2분(120)';
      case '30S':
        return '30초(30)';
      case 'MANUAL':
      default:
        return '수동';
    }
  }

  double _chartMaxX() {
    switch (_selectedTime) {
      case '30S':
        return 30;
      case '2M':
        return 120;
      case '3M':
        return 180;
      case '5M':
        return 300;
      case 'MANUAL':
      default:
        return 300;
    }
  }

  void _resetMeasureStateForNewRun(String pkck) {
    _spots.clear();
    _elapsedSec = 0;
    _timeCounter = 0;
    _currentPkck = pkck;

    // 새 측정을 시작할 때만 상태를 초기화
    _currentStartP = 0;
    _currentStopP = 0;
    _currentDiff = 0;
    _currentStopFlag = false;
    _currentDurationSec = 0;

    _currentPressure = 0;
    _currentPass = true;
    setState(() {
      _isMeasuring = true;
    });
    _blinkCtrl.repeat(reverse: true); 

  }

  // ───────────────────────── VAC / CHK / STOP ─────────────────────────

  void _startMeasure(int channel, String pkck) {
    if (!_vacButtonsEnabled) return;
    if (!_backend.isConnected()) return;

    if (!_hasLotCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('코드DATA를 먼저 입력하세요.')),
      );
      return;
    }

    // C++ 백엔드에 현재 모드 전달
    _backend.configureModes(_timeModeValue(), _selectedKpa);
    _backend.start();

    _resetMeasureStateForNewRun(pkck);

    setState(() {
      _isMeasuring = true;
      _activeJob = (channel == 1) ? 'VAC' : 'CHK'; 
    });

    _measureChannel = channel;
    _measureMode = (channel == 1) ? MeasureMode.vac : MeasureMode.chk;

    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {
        _blinkOn = !_blinkOn;
      });
    });

    _vacTimer?.cancel();
    _vacTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _timeCounter += 1; // 0.5초마다 1씩 증가

      final res = _backend.measureAndDecide(channel, _timeCounter);
      if (!res.ok) {
        debugPrint('measureAndDecide failed');
        return;
      }

      setState(() {
        // 🔹 측정 결과 적용
        _currentPressure = res.pressure;
        _currentStartP = res.startPressure;
        _currentStopP = res.stopPressure;
        _currentDiff = res.diffPressure;
        _currentPass = res.pass;
        _currentStopFlag = res.stop;

        // 🔹 offset 이후의 시간 (차트/TIME/DB용)
        if (_timeCounter > _chartOffsetTicks) {
          _elapsedSec = (_timeCounter - _chartOffsetTicks) / _div;
        } else {
          _elapsedSec = 0;
        }

        // 패널/테이블에서 쓸 정수 초
        _currentDurationSec = _elapsedSec.floor();

        // 🔹 차트는 offset 이후부터만 찍기
        if (_timeCounter > _chartOffsetTicks) {
          _spots.add(FlSpot(_elapsedSec, res.diffPressure));

          // MANUAL 모드일 경우 300초 슬라이딩 윈도우
          if (_selectedTime == 'MANUAL' && _elapsedSec > 300) {
            final shift = _elapsedSec - 300;

            for (int i = 0; i < _spots.length; i++) {
              final s = _spots[i];
              _spots[i] = FlSpot(s.x - shift, s.y);
            }

            _elapsedSec -= shift;
            _spots.removeWhere((s) => s.x < 0);
          }
        }
      });

      // ✅ 정지 조건
      final shouldStopByFlag = res.stop;
      final shouldStopByFail =
          _selectedTime != 'MANUAL' && !res.pass; // 자동 모드에서 FAIL 시 정지

      if (shouldStopByFlag || shouldStopByFail) {
        debugPrint(
            'Stop condition: stopFlag=$shouldStopByFlag, failStop=$shouldStopByFail');
        _finishMeasurementAndSave();
      }
    });
  }

  void _finishMeasurementAndSave({bool aborted = false}) async {
    _blinkTimer?.cancel();
    _blinkTimer = null;

    _vacTimer?.cancel();
    _vacTimer = null;
    _blinkCtrl.stop();

    if (aborted) {
      setState(() {
        _currentPass = false;
      });
    }

    setState(() {
      _isMeasuring = false;
      _activeJob = null; 
      _blinkOn = false;
      _measureMode = MeasureMode.none;
      _measureChannel = 0;
    });

    final lotname = _lotController.text.trim();
    if (lotname.isEmpty) return;

    final int durSec = _elapsedSec.floor();
    final bool finalPass = (!aborted && durSec > 0) ? _currentPass : false;

    final record = VacuumRecord(
      lotid: null,
      lotname: lotname,
      pkck: _currentPkck,
      vacpSel: _selectedKpa,
      vacpSt: double.parse(_currentStartP.toStringAsFixed(1)),
      vacpSp: double.parse(_currentStopP.toStringAsFixed(1)),
      vacpDiff: double.parse(_currentDiff.toStringAsFixed(2)),
      duration: durSec,
      result: finalPass ? 'PASS' : 'FAIL',
      stmpdate: DateTime.now(),
    );

    try {
      await VacuumDB.instance.insertRecord(record);
      await _loadRecentFromDB();

      // ? ???? ??
      _lotController.clear();

      // ?? ????? ??? ?? ??
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _lotFocusNode.requestFocus();
        }
      });

      setState(() {});
    } catch (e) {
      debugPrint('Insert record error: $e');
    }
  }

  void _onVacPressed() {
    _startMeasure(1, 'PAK'); // 채널 1 = VAC, 구분 PAK
  }

  void _onChkPressed() {
    _startMeasure(2, 'CHUCK'); // 채널 2 = CHK, 구분 CHUCK
  }

  void _onStopPressed() {
    if (!_stopEnabled) return;
    // 수동 STOP → 지금까지 결과로 저장
    _finishMeasurementAndSave(aborted: true);
  }

  // ───────────────────────── Data Management ─────────────────────────

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

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final maxX = _chartMaxX();

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

                        // COM + CONNECT / DISCONNECT / DATA MANAGEMENT 버튼들
                        Row(
                          children: [
                            // 포트 선택 + 새로고침
                            DropdownButton<String>(
                              value: _selectedPort,
                              hint: const Text('NO PORT'),
                              items: _ports
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                setState(() {
                                  _selectedPort = v;
                                  if (v != null) {
                                    _portStatusText = _connected
                                        ? 'CONNECTED: $v'
                                        : 'PORT: $v';
                                  }
                                });
                              },
                            ),
                            IconButton(
                              onPressed: _refreshPorts,
                              icon: const Icon(Icons.refresh),
                              tooltip: '포트 새로고침',
                            ),
                            const SizedBox(width: 20),

                            // CONNECT
                            /*
                            ElevatedButton(
                              style: _blueEnabledButtonStyle(),
                              onPressed: (_selectedPort != null &&
                                      !_connected &&
                                      !_connecting)
                                  ? _connect
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Text(
                                  _connecting ? 'CONNECTING...' : 'CONNECT',
                                ),
                              ),
                            ),
                            */
                            /*
                            ElevatedButton(
                              style: _mainButtonStyle(!_connected && !_connecting),
                              onPressed: (!_connected && !_connecting) ? _connect : null,
                              child: const Text('CONNECT'),
                            ),
                            const SizedBox(width: 12),
                            */
                            _buildBlueButton(
                              label: _connecting ? 'CONNECTING...' : 'CONNECT',
                              onPressed: (_selectedPort != null && !_connected && !_connecting) ? _connect : null,
                              fontSize: 14,
                            ),

                            /*
                            _buildBlueButton(
                              label: 'DISCONNECT',
                              onPressed: _connected ? _disconnect : null,
                              fontSize: 14,
                            ),
                            */

                            // DISCONNECT
                            /*
                            ElevatedButton(
                              style: _blueEnabledButtonStyle(),
                              onPressed: _connected ? _disconnect : null,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Text('DISCONNECT'),
                              ),
                            ),
                            */

                            ElevatedButton(
                              style: _mainButtonStyle(_connected),
                              onPressed: _connected ? _disconnect : null,
                              child: const Text('DISCONNECT'),
                            ),
                            const SizedBox(width: 12),

                            // DATA MANAGEMENT 버튼
                            ElevatedButton(
                              onPressed: _isDataManagementMode
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
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _portStatusText,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),

                        // 데이터 테이블
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.black, width: 1),
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
                                    DataColumn(label: Text("지속시간")),
                                    DataColumn(label: Text("결과")),
                                    DataColumn(label: Text("날짜-시간")),
                                  ],
                                  rows: [
                                    // ✅ 기존 레코드: 각 레코드의 duration 사용
                                    ..._recentRecords.map((r) {
                                      return DataRow(
                                        cells: [
                                          DataCell(Text(r.lotname)),
                                          DataCell(Text(r.pkck)),
                                          DataCell(Text('${r.vacpSel}')),
                                          DataCell(Text(
                                              r.vacpSt.toStringAsFixed(1))),
                                          DataCell(Text(
                                              r.vacpSp.toStringAsFixed(1))),
                                          DataCell(Text(
                                              r.vacpDiff.toStringAsFixed(2))),
                                          DataCell(Text('${r.duration}')),
                                          DataCell(Text(r.result)),
                                          DataCell(Text(r.stmpdate
                                              .toIso8601String()
                                              .substring(0, 19))),
                                        ],
                                      );
                                    }),

                                    // ✅ 새 레코드 입력용 마지막 한 줄
                                    DataRow(
                                      cells: [
                                        DataCell(
                                          TextField(
                                            controller: _lotController,
                                            focusNode: _lotFocusNode, //
                                            decoration:
                                                const InputDecoration(
                                              isDense: true,
                                              border: InputBorder.none,
                                            ),
                                            onChanged: (_) {
                                              setState(() {}); // 버튼 활성화 갱신
                                            },
                                          ),
                                        ),
                                        DataCell(
                                          Text(_currentPkck),
                                        ),
                                        DataCell(Text('$_selectedKpa')),
                                        DataCell(Text(
                                            _currentStartP.toStringAsFixed(1))),
                                        DataCell(Text(
                                            _currentStopP.toStringAsFixed(1))),
                                        DataCell(Text(
                                            _currentDiff.toStringAsFixed(2))),
                                        // 여기만 현재 측정의 시간(_currentDurationSec) 사용
                                        DataCell(
                                            Text('$_currentDurationSec')),
                                        DataCell(Text(
                                            _currentPass ? 'PASS' : 'FAIL')),
                                        DataCell(
                                          Text(
                                            DateTime.now()
                                                .toIso8601String()
                                                .substring(0, 19),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
                              child: _blinkWrapper(
                                active: _isMeasuring && _currentPkck == 'PAK',
                                child: _buildBlueButton(
                                  label: 'VAC',
                                  onPressed: _vacButtonsEnabled ? _onVacPressed : null,
                                  padding: const EdgeInsets.all(12),
                                  fontSize: 22,
                                  isRunning: _isMeasuring && _measureMode == MeasureMode.vac, // ? ??? ??
                                ),
                                /*
                                child: ElevatedButton(
                                  style: _mainButtonStyle(_vacButtonsEnabled),
                                  onPressed: _vacButtonsEnabled ? _onVacPressed : null,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_isMeasuring && _currentPkck == 'PAK')
                                        const Icon(Icons.play_arrow, size: 24),
                                      const SizedBox(width: 4),
                                      const Text("VAC", style: TextStyle(fontSize: 22)),
                                    ],
                                  ),
                                ),
                                */
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _blinkWrapper(
                                active: _isMeasuring && _currentPkck == 'CHUCK',
                                child: _buildBlueButton(
                                  label: 'CHK',
                                  onPressed: _vacButtonsEnabled ? _onChkPressed : null,
                                  padding: const EdgeInsets.all(12),
                                  fontSize: 22,
                                  isRunning: _isMeasuring && _measureMode == MeasureMode.chk, // ? ??? ??
                                ),
                                /*
                                child: ElevatedButton(
                                  style: _mainButtonStyle(_vacButtonsEnabled),
                                  onPressed: _vacButtonsEnabled ? _onChkPressed : null,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_isMeasuring && _currentPkck == 'CHUCK')
                                        const Icon(Icons.play_arrow, size: 24),
                                      const SizedBox(width: 4),
                                      const Text("CHK", style: TextStyle(fontSize: 22)),
                                    ],
                                  ),
                                ),
                                */
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildBlueButton(
                                label: 'STOP(SAVE)',
                                onPressed: _stopEnabled ? _onStopPressed : null,
                                padding: const EdgeInsets.all(12),
                                fontSize: 22,
                                isRunning: _isMeasuring, // STOP? ????? ??? ???? ??? true
                              ),
                              /*
                              child: ElevatedButton(
                                style: _mainButtonStyle(_stopEnabled),
                                onPressed: _stopEnabled ? _onStopPressed : null,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text("STOP(SAVE)", style: TextStyle(fontSize: 22)),
                                ),
                              ),
                              */
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
                                  // _buildKpaCheckbox("62 KPA", 62),
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
                          child: VacuumPressureChartContainer(
                            spots: _spots,
                            maxX: maxX,
                            minY: _minDiff,
                            maxY: _maxDiff,
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "VACUUM",
                                    style: TextStyle(fontSize: 26),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "STATE: $_selectedKpa KPA",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "TIME: ${_timeLabelForStatus()}",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "START: ${_currentStartP.toStringAsFixed(1)} KPA",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  Text(
                                    "STOP:  ${_currentStopP.toStringAsFixed(1)} KPA",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  Text(
                                    "ΔP: ${_currentDiff.toStringAsFixed(2)} KPA",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  Text(
                                    "TIME: ${_elapsedSec.toStringAsFixed(1)}s",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _currentPass
                                        ? "RESULT: PASS"
                                        : "RESULT: FAIL",
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: _currentPass
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                  if (_currentStopFlag)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Text(
                                        "(측정 종료 조건 만족)",
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.orange),
                                      ),
                                    ),
                                ],
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
      onChanged: (_) {
        setState(() {
          _selectedTime = value;
        });
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
      onChanged: (_) {
        setState(() {
          _selectedKpa = value;
        });
      },
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

/// ─────────────────────────────────────────
///  차트 컨테이너
/// ─────────────────────────────────────────
class VacuumPressureChartContainer extends StatelessWidget {
  final List<FlSpot> spots;
  final double maxX;
  final double minY;
  final double maxY;

  static const double _lclValue = -1.0;

  const VacuumPressureChartContainer({
    super.key,
    required this.spots,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue, width: 2),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            "Vacuum Pressure Change (ΔP)",
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: VacuumPressureChart(
              spots: spots,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────
///  차트 위젯
/// ─────────────────────────────────────────
class VacuumPressureChart extends StatelessWidget {
  final List<FlSpot> spots;
  final double maxX;
  final double minY;
  final double maxY;

  static const double _ucl = 1.0;  // UCL
  static const double _lcl = -1.0; // LCL

  const VacuumPressureChart({
    super.key,
    required this.spots,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,

        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: _ucl,
              color: Colors.orange, // UCL ? ?
              strokeWidth: 2,
              dashArray: [6, 4], // ??(??? ?? ??)
            ),
            HorizontalLine(
              y: _lcl,
              color: Colors.orange, // LCL ? ?
              strokeWidth: 2,
              dashArray: [6, 4],
            ),
          ],
        ),

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
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: false,
            barWidth: 2,
            spots: spots.isEmpty ? const [FlSpot(0, 0)] : spots,
            //dotData: FlDotData(show: true),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final outOfSpec = (spot.y < _lcl) || (spot.y > _ucl);
    
                return FlDotCirclePainter(
                  radius: 3,
                  color: outOfSpec ? Colors.red : Colors.blue, // ???? ??
                  strokeWidth: 0,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
