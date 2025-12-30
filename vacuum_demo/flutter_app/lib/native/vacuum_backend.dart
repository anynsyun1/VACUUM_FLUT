// lib/native/vacuum_backend.dart
import 'dart:ffi';
import 'dart:io';

typedef _VoidC = Void Function();
typedef _VoidD = void Function();

typedef _SetModeC = Void Function(Int32);
typedef _SetModeD = void Function(int);

typedef _GetPressureC = Float Function();
typedef _GetPressureD = double Function();

typedef _GetPassC = Int32 Function();
typedef _GetPassD = int Function();

class VacuumNative {
  late final DynamicLibrary _lib;

  late final _VoidD vacuumInit;
  late final _SetModeD vacuumSetTimeMode;
  late final _SetModeD vacuumSetPressureMode;
  late final _VoidD vacuumStart;
  late final _VoidD vacuumStep;
  late final _GetPressureD vacuumGetLastPressure;
  late final _GetPassD vacuumGetLastPass;

  VacuumNative() {
    _lib = _openLib();

    vacuumInit = _lib
        .lookup<NativeFunction<_VoidC>>('vacuum_init')
        .asFunction();

    vacuumSetTimeMode = _lib
        .lookup<NativeFunction<_SetModeC>>('vacuum_set_time_mode')
        .asFunction();

    vacuumSetPressureMode = _lib
        .lookup<NativeFunction<_SetModeC>>('vacuum_set_pressure_mode')
        .asFunction();

    vacuumStart = _lib
        .lookup<NativeFunction<_VoidC>>('vacuum_start')
        .asFunction();

    vacuumStep = _lib
        .lookup<NativeFunction<_VoidC>>('vacuum_step')
        .asFunction();

    vacuumGetLastPressure = _lib
        .lookup<NativeFunction<_GetPressureC>>('vacuum_get_last_pressure')
        .asFunction();

    vacuumGetLastPass = _lib
        .lookup<NativeFunction<_GetPassC>>('vacuum_get_last_pass')
        .asFunction();
  }

  DynamicLibrary _openLib() {
    if (Platform.isLinux) {
      return DynamicLibrary.open('/home/nsyun/mnt/development/engr/Programming/SERA_VACU/VACUUM_FLUT/vacuum_demo/cpp_backend/build/libvacuum_backend.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('vacuum_backend.dll');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libvacuum_backend.dylib');
    }
    throw UnsupportedError('Unsupported platform');
  }
}
