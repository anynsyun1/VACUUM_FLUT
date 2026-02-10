// lib/native/vacuum_backend.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';


/// C struct VacuumMeasureResult 와 동일한 메모리 레이아웃
///
/// C++ 쪽 구조체는 반드시 다음과 같은 순서여야 합니다:
/// struct VacuumMeasureResult {
///   float pressure;
///   float startPressure;
///   float stopPressure;
///   float diffPressure;
///   int   pass;
///   int   stop;
///   int   ok;
/// };
final class VacuumMeasureResultNative extends Struct {
  @Float()
  external double pressure;

  @Float()
  external double startPressure;

  @Float()
  external double stopPressure;

  @Float()
  external double diffPressure;

  @Int32()
  external int pass;

  @Int32()
  external int stop;

  @Int32()
  external int ok;
}

/// Flutter 쪽에서 쓰기 편한 Dart 데이터 클래스
class VacuumMeasureResult {
  final double pressure;
  final double startPressure;
  final double stopPressure;
  final double diffPressure;
  final bool pass;
  final bool stop;
  final bool ok;

  const VacuumMeasureResult({
    required this.pressure,
    required this.startPressure,
    required this.stopPressure,
    required this.diffPressure,
    required this.pass,
    required this.stop,
    required this.ok,
  });
}

/// ───── C 함수 시그니처들 ─────

typedef _VoidC = Void Function();
typedef _VoidD = void Function();

typedef _SetModeC = Void Function(Int32);
typedef _SetModeD = void Function(int);

typedef _ConnectC = Int32 Function(Pointer<Utf8>);
typedef _ConnectD = int Function(Pointer<Utf8>);

typedef _DisconnectC = Void Function();
typedef _DisconnectD = void Function();

typedef _IsConnectedC = Int32 Function();
typedef _IsConnectedD = int Function();

typedef _GetPressureC = Float Function();
typedef _GetPressureD = double Function();

typedef _GetPassC = Int32 Function();
typedef _GetPassD = int Function();

typedef _ListPortsC = Int32 Function(Pointer<Utf8>, Int32);
typedef _ListPortsD = int Function(Pointer<Utf8>, int);

typedef _DebugMeasureC = Float Function(Int32);
typedef _DebugMeasureD = double Function(int);

typedef _DebugMeasure2C = Float Function(Int32, Int32);
typedef _DebugMeasure2D = double Function(int, int);

typedef _MeasureDecideC = VacuumMeasureResultNative Function(Int32, Int32);
typedef _MeasureDecideD = VacuumMeasureResultNative Function(int, int);

class VacuumNative {
  late final DynamicLibrary _lib;

  late final _VoidD _vacuumInit;
  late final _SetModeD _vacuumSetTimeMode;
  late final _SetModeD _vacuumSetPressureMode;
  late final _VoidD _vacuumStart;
  late final _VoidD _vacuumStep;
  late final _GetPressureD _vacuumGetLastPressure;
  late final _GetPassD _vacuumGetLastPass;

  late final _ConnectD _vacuumConnect;
  late final _DisconnectD _vacuumDisconnect;
  late final _IsConnectedD _vacuumIsConnected;
  late final _ListPortsD _vacuumListPorts;

  late final _DebugMeasureD _vacuumDebugMeasureOnce;
  late final _DebugMeasure2D _vacuumDebugMeasureOnce2;

  // struct 반환 함수
  late final _MeasureDecideD _vacuumMeasureDecide;

  VacuumNative() {
    _lib = _openLib();

    _vacuumInit =
        _lib.lookup<NativeFunction<_VoidC>>('vacuum_init').asFunction();

    _vacuumSetTimeMode = _lib
        .lookup<NativeFunction<_SetModeC>>('vacuum_set_time_mode')
        .asFunction();

    _vacuumSetPressureMode = _lib
        .lookup<NativeFunction<_SetModeC>>('vacuum_set_pressure_mode')
        .asFunction();

    _vacuumStart =
        _lib.lookup<NativeFunction<_VoidC>>('vacuum_start').asFunction();

    _vacuumStep =
        _lib.lookup<NativeFunction<_VoidC>>('vacuum_step').asFunction();

    _vacuumGetLastPressure = _lib
        .lookup<NativeFunction<_GetPressureC>>('vacuum_get_last_pressure')
        .asFunction();

    _vacuumGetLastPass = _lib
        .lookup<NativeFunction<_GetPassC>>('vacuum_get_last_pass')
        .asFunction();

    _vacuumConnect =
        _lib.lookup<NativeFunction<_ConnectC>>('vacuum_connect').asFunction();

    _vacuumDisconnect = _lib
        .lookup<NativeFunction<_DisconnectC>>('vacuum_disconnect')
        .asFunction();

    _vacuumIsConnected = _lib
        .lookup<NativeFunction<_IsConnectedC>>('vacuum_is_connected')
        .asFunction();

    _vacuumListPorts = _lib
        .lookup<NativeFunction<_ListPortsC>>('vacuum_list_ports')
        .asFunction();

    _vacuumDebugMeasureOnce = _lib
        .lookup<NativeFunction<_DebugMeasureC>>('vacuum_debug_measure_once')
        .asFunction();

    _vacuumDebugMeasureOnce2 = _lib
        .lookup<NativeFunction<_DebugMeasure2C>>('vacuum_debug_measure_once2')
        .asFunction();

    _vacuumMeasureDecide = _lib.lookupFunction<
        _MeasureDecideC,
        _MeasureDecideD>('vacuum_measure_decide');
  }



  DynamicLibrary _openLib() {
    if (Platform.isLinux) {
      final cwd = Directory.current.path;

      // Prefer local dev builds (so changes in cpp_backend are reflected in the app).
      // Typical run cwd is the flutter project root, but we also try workspace-root style.
      final candidates = <String>[
        '$cwd/../vacuum_demo/cpp_backend/build/libvacuum_backend.so',
        '$cwd/../vacuum_demo/cpp_backend/linuxbuild/libvacuum_backend.so',
        '$cwd/vacuum_demo/cpp_backend/build/libvacuum_backend.so',
        '$cwd/vacuum_demo/cpp_backend/linuxbuild/libvacuum_backend.so',
      ];

      for (final path in candidates) {
        if (File(path).existsSync()) {
          return DynamicLibrary.open(path);
        }
      }

      // fallback: system search path / executable directory
      return DynamicLibrary.open('libvacuum_backend.so');
    }

    if (Platform.isWindows) {
      // 1️⃣ 배포 시 가장 일반적: 실행 중인 exe 디렉토리 (같은 폴더에 DLL 배치)
      final exeDir = File(Platform.resolvedExecutable).parent.path;

      final candidates = <String>[
        '$exeDir\\vacuum_backend.dll',
        '${Directory.current.path}\\vacuum_backend.dll',
        // 2️⃣ 개발 환경 fallback (특정 PC 경로에만 존재할 수 있음)
        r'C:\\VACUUM\\VACUUM_FLUT\\vacuum_demo\\cpp_backend\\build\\Release\\vacuum_backend.dll',
      ];

      for (final path in candidates) {
        if (File(path).existsSync()) {
          return DynamicLibrary.open(path);
        }
      }

      throw Exception('vacuum_backend.dll not found');
    }

    if (Platform.isMacOS) {
      return DynamicLibrary.open('libvacuum_backend.dylib');
    }

    throw UnsupportedError('Unsupported platform');
  }


  // ───────── High-level wrapper ─────────

  void init() => _vacuumInit();

  void configureModes(int timeMode, int pressureKpa) {
    _vacuumSetTimeMode(timeMode);
    _vacuumSetPressureMode(pressureKpa);
  }

  void start() => _vacuumStart();
  void step() => _vacuumStep();

  double getLastPressure() => _vacuumGetLastPressure();
  bool getLastPass() => _vacuumGetLastPass() == 1;

  List<String> listPorts() {
    const bufSize = 2048;
    final buf = calloc<Uint8>(bufSize).cast<Utf8>();
    try {
      final count = _vacuumListPorts(buf, bufSize);
      if (count <= 0) return [];
      final joined = buf.toDartString();
      return joined
          .split(';')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } finally {
      calloc.free(buf);
    }
  }

  bool connect(String portName) {
    final ptr = portName.toNativeUtf8();
    final result = _vacuumConnect(ptr);
    malloc.free(ptr);
    return result == 1;
  }

  void disconnect() => _vacuumDisconnect();

  bool isConnected() => _vacuumIsConnected() == 1;

  double debugMeasureOnce(int channel) {
    return _vacuumDebugMeasureOnce(channel);
  }

  double debugMeasureOnce2(int channel, int timeCounter) {
    return _vacuumDebugMeasureOnce2(channel, timeCounter);
  }

  /// channel, counter 를 넣으면 C++ measureAndDecide 결과 전체를 받아옴
  VacuumMeasureResult measureAndDecide(int channel, int counter) {
    final r = _vacuumMeasureDecide(channel, counter);
    return VacuumMeasureResult(
      pressure: r.pressure,
      startPressure: r.startPressure,
      stopPressure: r.stopPressure,
      diffPressure: r.diffPressure,
      pass: r.pass != 0,
      stop: r.stop != 0,
      ok: r.ok != 0,
    );
  }
}
