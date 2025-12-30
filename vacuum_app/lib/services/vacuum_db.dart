// lib/services/vacuum_db.dart
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/vacuum_record.dart';

class VacuumDB {
  static final VacuumDB instance = VacuumDB._internal();
  Database? _db;

  VacuumDB._internal();

  Future<void> open() async {
    if (_db != null) return;


    // 실제 Qt에서 사용하던 vacuums.db 경로와 동일하게 맞추기
    String dbFilePath ='';
        //'/home/nsyun/mnt/development/engr/Programming/SERA_VACU/SERA_VACUUM/DATA/vacuums.db';

    if (Platform.isWindows) {
        
      dbFilePath = 'C:\DATA\\vacuums.db';
      if (!File(dbFilePath).existsSync()) {
        //throw Exception("vacuums.db 파일을 찾을 수 없습니다: $dbFilePath");
        dbFilePath = 'C:\\VACUUM\\VACUUM_FLUT\\DATA\\vacuums.db';
        if (!File(dbFilePath).existsSync()) {
          throw Exception("vacuums.db 파일을 찾을 수 없습니다: $dbFilePath");
        }
      } 
    } else if (Platform.isLinux) {
      dbFilePath = '/home/nsyun/mnt/development/engr/Programming/SERA_VACU/SERA_VACUUM/DATA/vacuums.db';
      if (!File(dbFilePath).existsSync()) {
        dbFilePath = '/home/nsyun/mnt/development/engr/Programming/SERA_VACU/VACUUM_FLUT/DATA/vacuums.db';
        if (!File(dbFilePath).existsSync()) {
          throw Exception("vacuums.db 파일을 찾을 수 없습니다: $dbFilePath");
        }
      }
    } else {
      throw Exception("지원하지 않는 플랫폼입니다.");
    }

    _db = await databaseFactory.openDatabase(dbFilePath);
  }

  String _fmtDateForSql(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  /// 날짜/결과로 검색 (DataManagementPage 에서 사용)
  Future<List<VacuumRecord>> queryRecords({
    DateTime? from,
    DateTime? to,
    String? result, // "PASS" | "FAIL" | null
  }) async {
    await open();
    final db = _db!;

    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add("stmpdate >= ?");
      args.add(_fmtDateForSql(from));
    }
    if (to != null) {
      where.add("stmpdate <= ?");
      args.add(_fmtDateForSql(to));
    }
    if (result != null && result.isNotEmpty) {
      where.add("LOWER(result) = LOWER(?)");
      args.add(result);
    }

    final whereClause = where.isEmpty ? "" : "WHERE ${where.join(' AND ')}";

    final rows = await db.rawQuery("""
      SELECT * FROM vacuums
      $whereClause
      ORDER BY lotid DESC
    """, args);

    return rows.map((m) => VacuumRecord.fromMap(m)).toList();
  }

  /// 전체 레코드 (필요하면 사용)
  Future<List<VacuumRecord>> queryAllRecords() async {
    await open();
    final db = _db!;
    final rows = await db.query(
      'vacuums',
      orderBy: 'lotid DESC',
    );
    return rows.map((m) => VacuumRecord.fromMap(m)).toList();
  }

  /// 🔹 메인 화면에서 "최근 5개" 같이 가져올 때 쓰는 함수

  Future<List<VacuumRecord>> queryLatest({required int limit}) async {
    await open();
    final db = _db!;
    // lotid DESC 로 가져온 뒤, 역순으로 돌려서 화면에는 오래된게 위, 최신이 아래로 보이게
    final rows = await db.query(
      'vacuums',
      orderBy: 'lotid DESC',
      limit: limit,
    );

    final desc = rows.map((m) => VacuumRecord.fromMap(m)).toList();
    return desc.reversed.toList();
  }

  /// 🔹 측정 끝난 후 1건 INSERT (Qt 의 addItem() 과 대응)
  Future<int> insertRecord(VacuumRecord record) async {
    await open();
    final db = _db!;

    final map = record.toMap();
    // lotid (PK, AUTOINCREMENT)는 직접 넣지 않음
    map.remove('lotid');

    return db.insert('vacuums', map);
  }
}
