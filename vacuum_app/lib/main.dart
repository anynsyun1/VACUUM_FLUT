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
  double _currentStartP = 0.0; // 시작 압력
  double _currentStopP = 0.0; // 종료 압력
  double _currentDiff = 0.0; // ΔP
  bool _currentPass = true;
  bool _currentStopFlag = false;
  int _currentDurationSec = 0; // 패널/테이블용 지속시간(초 단위 표시용)

  // 차트 오프셋 (C++ STARTOFFSET과 맞춰서 사용)
  // counter 는 0.5초마다 1 증가하므로, (초 * _div) = tick 수
  int _chartOffsetTicks = 0;

  // C++ cpp_backend 와 동일: averaging 구간 tick 수
  static const int _maxAvgTicks = 5;

  int _timeCounter = 0; // C++ measureAndDecide()에 넘기는 카운터
  final int _div = 2; // 0.5초 간격(500ms)일 때 counter 2개 = 1초

  int _startOffsetSecForChannel(int channel) {
    // C++ cpp_backend 기준과 동기화 필요
    // channel 1: VAC (PAK)
    // channel 2: CHK (CHUCK)
    if (channel == 1) return 18;
    if (channel == 2) return 7;
    return 7;
  }

  // 어떤 버튼으로 시작했는지 (VAC / CHK 에 따라 PAK / CHUCK)
  String _currentPkck = 'PAK';

  // 차트 데이터 (ΔP vs time)
  final List<FlSpot> _spots = [];
  double _elapsedSec = 0; // offset 이후 경과시간 (차트/패널/DB용)

  // 자동 모드에서 이번 런의 목표 시간(초)
  double _runMaxXSec = 300;

  // 측정 시작 시점의 시간 모드(중간에 UI에서 바뀌어도 런에 영향 없게 고정)
  String _runTimeMode = 'MANUAL';

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

  bool _blinkOn = false;
  Timer? _blinkTimer;

  ButtonStyle _mainButtonStyle(bool enabled) {
    return ElevatedButton.styleFrom(
      backgroundColor: enabled ? Colors.blue : null,
      foregroundColor: enabled ? Colors.white : null,
      disabledBackgroundColor: Colors.grey[400],
      disabledForegroundColor: Colors.grey[800],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _blinkWrapper({required bool active, required Widget child}) {
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
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 10,
    ),
    double fontSize = 16,
    bool isRunning = false,
    double? fixedHeight, // ✅ 높이 고정 옵션
    Color? disabledForegroundColor,
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
                padding: WidgetStateProperty.all(padding),
                minimumSize: fixedHeight == null
                    ? null
                    : WidgetStateProperty.all(Size.fromHeight(fixedHeight)),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) return null;
                  return Colors.blue;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return disabledForegroundColor;
                  }
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
                      color: enabled ? Colors.white : disabledForegroundColor,
                    ),
                  ),
                  const SizedBox(width: 8), // ✅ 간격도 항상 유지
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: enabled ? null : disabledForegroundColor,
                      ),
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
          _portStatusText = _connected
              ? 'CONNECTED: $_selectedPort'
              : 'PORT: $_selectedPort';
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
      _portStatusText = ok
          ? 'CONNECTED: $_selectedPort'
          : 'CONNECT FAILED (${_selectedPort!})';
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
    final mode = _isMeasuring ? _runTimeMode : _selectedTime;
    switch (mode) {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('코드DATA를 먼저 입력하세요.')));
      return;
    }

    // C++ 백엔드에 현재 모드 전달
    _backend.configureModes(_timeModeValue(), _selectedKpa);
    _backend.start();

    // 차트/표시 오프셋을 채널별 STARTOFFSET(초)에 맞춰 동기화
    // C++ 로직: counter <= STARTOFFSET*DIV 는 offset 구간,
    // 그 다음 MAXAVG tick 동안 평균을 내므로 차트는 STARTOFFSET*DIV + MAXAVG 이후부터가 자연스러움
    final startOffsetSec = _startOffsetSecForChannel(channel);
    _chartOffsetTicks = (startOffsetSec * _div) + _maxAvgTicks;
    _runMaxXSec = _chartMaxX();
    _runTimeMode = _selectedTime;
    debugPrint(
      'measure start: channel=$channel startOffsetSec=$startOffsetSec '
      'div=$_div maxAvgTicks=$_maxAvgTicks chartOffsetTicks=$_chartOffsetTicks',
    );

    _resetMeasureStateForNewRun(pkck);

    setState(() {
      _isMeasuring = true;
    });

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

      // offset 이후의 시간 (차트/TIME/DB용)
      double nextElapsedSec;
      if (_timeCounter >= _chartOffsetTicks) {
        nextElapsedSec = (_timeCounter - _chartOffsetTicks) / _div;
      } else {
        nextElapsedSec = 0;
      }

      // 자동 모드에서는 선택 시간(maxX)을 넘기지 않도록 클램프 + 즉시 정지
      final bool shouldStopByTime =
          _runTimeMode != 'MANUAL' && nextElapsedSec >= _runMaxXSec;
      if (shouldStopByTime) {
        nextElapsedSec = _runMaxXSec;
      }

      setState(() {
        // 🔹 측정 결과 적용
        _currentStartP = res.startPressure;
        _currentStopP = res.stopPressure;
        _currentDiff = res.diffPressure;
        _currentPass = res.pass;
        _currentStopFlag = res.stop;

        _elapsedSec = nextElapsedSec;

        // 패널/테이블에서 쓸 정수 초
        _currentDurationSec = _elapsedSec.floor();

        // 🔹 차트는 offset 이후부터만 찍기
        if (_timeCounter >= _chartOffsetTicks) {
          // 자동 모드에서는 maxX 범위를 넘는 점을 추가하지 않음
          if (_runTimeMode == 'MANUAL' || _elapsedSec <= _runMaxXSec) {
            if (_runTimeMode != 'MANUAL' && shouldStopByTime) {
              // 마지막 점이 이미 maxX라면 중복 추가 방지
              if (_spots.isEmpty || _spots.last.x != _runMaxXSec) {
                _spots.add(FlSpot(_runMaxXSec, res.diffPressure));
              }
            } else {
              _spots.add(FlSpot(_elapsedSec, res.diffPressure));
            }
          }

          // MANUAL 모드일 경우 300초 슬라이딩 윈도우
          if (_runTimeMode == 'MANUAL' && _elapsedSec > 300) {
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
          _runTimeMode != 'MANUAL' && !res.pass; // 자동 모드에서 FAIL 시 정지

      if (shouldStopByFlag || shouldStopByFail || shouldStopByTime) {
        debugPrint(
          'Stop condition: stopFlag=$shouldStopByFlag, failStop=$shouldStopByFail, '
          'timeStop=$shouldStopByTime, elapsed=${nextElapsedSec.toStringAsFixed(1)}',
        );
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
      _blinkOn = false;
      _measureMode = MeasureMode.none;
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

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DataManagementPage()));

    if (!mounted) return;
    setState(() {
      _isDataManagementMode = false;
    });
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final maxX = _isMeasuring ? _runMaxXSec : _chartMaxX();

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
                                  fontSize: 28,
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

                        // Port 선택(/dev/ttyUSB*) ~ 30초 SET 영역(차트/상태창 제외)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black, width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // COM + CONNECT / DISCONNECT / DATA MANAGEMENT 버튼들
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
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
                                      SizedBox(
                                        width: 170,
                                        child: _buildBlueButton(
                                          label: _connecting
                                              ? 'CONNECTING...'
                                              : 'CONNECT',
                                          onPressed:
                                              (_selectedPort != null &&
                                                  !_connected &&
                                                  !_connecting)
                                              ? _connect
                                              : null,
                                          fontSize: 16,
                                        ),
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
                                        onPressed: _connected
                                            ? _disconnect
                                            : null,
                                        child: const Text(
                                          'DISCONNECT',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
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
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                                                  DataCell(
                                                    Text('${r.vacpSel}'),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      r.vacpSt.toStringAsFixed(
                                                        1,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      r.vacpSp.toStringAsFixed(
                                                        1,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      r.vacpDiff
                                                          .toStringAsFixed(2),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text('${r.duration}'),
                                                  ),
                                                  DataCell(Text(r.result)),
                                                  DataCell(
                                                    Text(
                                                      r.stmpdate
                                                          .toIso8601String()
                                                          .substring(0, 19),
                                                    ),
                                                  ),
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
                                                          border:
                                                              InputBorder.none,
                                                        ),
                                                    onChanged: (_) {
                                                      setState(
                                                        () {},
                                                      ); // 버튼 활성화 갱신
                                                    },
                                                  ),
                                                ),
                                                DataCell(Text(_currentPkck)),
                                                DataCell(Text('$_selectedKpa')),
                                                DataCell(
                                                  Text(
                                                    _currentStartP
                                                        .toStringAsFixed(1),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    _currentStopP
                                                        .toStringAsFixed(1),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    _currentDiff
                                                        .toStringAsFixed(2),
                                                  ),
                                                ),
                                                // 여기만 현재 측정의 시간(_currentDurationSec) 사용
                                                DataCell(
                                                  Text('$_currentDurationSec'),
                                                ),
                                                DataCell(
                                                  Text(
                                                    _currentPass
                                                        ? 'PASS'
                                                        : 'FAIL',
                                                  ),
                                                ),
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
                                        active:
                                            _isMeasuring &&
                                            _currentPkck == 'PAK',
                                        child: _buildBlueButton(
                                          label: 'VAC',
                                          onPressed: _vacButtonsEnabled
                                              ? _onVacPressed
                                              : null,
                                          padding: const EdgeInsets.all(12),
                                          fontSize: 22,
                                          disabledForegroundColor:
                                              Colors.black87,
                                          isRunning:
                                              _isMeasuring &&
                                              _measureMode ==
                                                  MeasureMode.vac, // ? ??? ??
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _blinkWrapper(
                                        active:
                                            _isMeasuring &&
                                            _currentPkck == 'CHUCK',
                                        child: _buildBlueButton(
                                          label: 'CHK',
                                          onPressed: _vacButtonsEnabled
                                              ? _onChkPressed
                                              : null,
                                          padding: const EdgeInsets.all(12),
                                          fontSize: 22,
                                          disabledForegroundColor:
                                              Colors.black87,
                                          isRunning:
                                              _isMeasuring &&
                                              _measureMode ==
                                                  MeasureMode.chk, // ? ??? ??
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildBlueButton(
                                        label: 'STOP(SAVE)',
                                        onPressed: _stopEnabled
                                            ? _onStopPressed
                                            : null,
                                        padding: const EdgeInsets.all(12),
                                        fontSize: 22,
                                        disabledForegroundColor: Colors.black87,
                                        isRunning:
                                            _isMeasuring, // STOP? ????? ??? ???? ??? true
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
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _buildTimeCheckbox(
                                                  "수동 SET",
                                                  'MANUAL',
                                                ),
                                                _buildTimeCheckbox(
                                                  "5분 SET",
                                                  '5M',
                                                ),
                                                _buildTimeCheckbox(
                                                  "3분 SET",
                                                  '3M',
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _buildTimeCheckbox(
                                                  "2분 SET",
                                                  '2M',
                                                ),
                                                _buildTimeCheckbox(
                                                  "30초 SET",
                                                  '30S',
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // KPA 묶음
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // _buildKpaCheckbox("62 KPA", 62),
                                          Container(
                                            decoration: const BoxDecoration(
                                              border: Border(
                                                left: BorderSide(
                                                  color: Colors.black26,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                            padding:
                                                const EdgeInsets.only(left: 8),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _buildKpaCheckbox(
                                                  "65 KPA",
                                                  65,
                                                ),
                                                _buildKpaCheckbox(
                                                  "80 KPA",
                                                  80,
                                                ),
                                              ],
                                            ),
                                          ),
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
                            color: Colors.blue,
                          ),
                          child: const Center(
                            child: Text(
                              "ONSEMI 2호기",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
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
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            "VACUUM",
                                            style: TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "STATE: $_selectedKpa KPA",
                                            style: const TextStyle(
                                              fontSize: 18,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            "TIME: ${_timeLabelForStatus()}",
                                            style: const TextStyle(
                                              fontSize: 18,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            "START: ${_currentStartP.toStringAsFixed(1)} KPA",
                                            style: const TextStyle(
                                              fontSize: 18,
                                            ),
                                          ),
                                          Text(
                                            "STOP:  ${_currentStopP.toStringAsFixed(1)} KPA",
                                            style: const TextStyle(
                                              fontSize: 18,
                                            ),
                                          ),
                                          Text(
                                            "ΔP: ${_currentDiff.toStringAsFixed(2)} KPA",
                                            style: const TextStyle(
                                              fontSize: 18,
                                            ),
                                          ),
                                          Text(
                                            "TIME: ${_elapsedSec.toStringAsFixed(1)}s",
                                            style: const TextStyle(
                                              fontSize: 18,
                                            ),
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
                                                  color: Colors.orange,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
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
        style: const TextStyle(fontSize: 20, color: Colors.black87),
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
        style: const TextStyle(fontSize: 22, color: Colors.black87),
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

  static const double _ucl = 1.0; // UCL
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
