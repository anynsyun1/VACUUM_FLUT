// lib/models/vacuum_record.dart
class VacuumRecord {
  final int? lotid; // 새로 INSERT할 때는 null일 수 있음
  final String lotname;
  final String pkck; // "PAK" / "CHUCK"
  final int vacpSel;
  final double vacpSt;
  final double vacpSp;
  final double vacpDiff;
  final int duration; // sec
  final String result; // "pass" / "fail"
  final DateTime stmpdate;

  VacuumRecord({
    this.lotid,
    required this.lotname,
    required this.pkck,
    required this.vacpSel,
    required this.vacpSt,
    required this.vacpSp,
    required this.vacpDiff,
    required this.duration,
    required this.result,
    required this.stmpdate,
  });

  factory VacuumRecord.fromMap(Map<String, Object?> m) {
   final rawDate = m['stmpdate'];

    final String dateStr = (rawDate == null || rawDate.toString().isEmpty)
      ? DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ')
      : rawDate.toString();

    return VacuumRecord(
      lotid: (m['lotid'] as num?)?.toInt(),
      lotname: (m['lotname'] ?? '').toString(),
      pkck: (m['pkck'] ?? '').toString(),
      vacpSel: (m['vacp_sel'] as num?)?.toInt() ?? 0,
      vacpSt: (m['vacp_st'] as num?)?.toDouble() ?? 0.0,
      vacpSp: (m['vacp_sp'] as num?)?.toDouble() ?? 0.0,
      vacpDiff: (m['vacp_diff'] as num?)?.toDouble() ?? 0.0,
      duration: (m['duration'] as num?)?.toInt() ?? 0,
      result: (m['result'] ?? '').toString(),
      stmpdate: DateTime.parse(dateStr.replaceFirst(' ', 'T')),
    );
  }


  Map<String, Object?> toMap() {
    // Qt와 동일한 포맷: "yyyy-MM-dd hh:mm:ss"
    final y = stmpdate.year.toString().padLeft(4, '0');
    final m = stmpdate.month.toString().padLeft(2, '0');
    final d = stmpdate.day.toString().padLeft(2, '0');
    final hh = stmpdate.hour.toString().padLeft(2, '0');
    final mm = stmpdate.minute.toString().padLeft(2, '0');
    final ss = stmpdate.second.toString().padLeft(2, '0');
    final stmpStr = '$y-$m-$d $hh:$mm:$ss';

    return {
      if (lotid != null) 'lotid': lotid,
      'lotname': lotname,
      'pkck': pkck,
      'vacp_sel': vacpSel,
      'vacp_st': vacpSt,
      'vacp_sp': vacpSp,
      'vacp_diff': vacpDiff,
      'duration': duration,
      'result': result,
      'stmpdate': stmpStr,
    };
  }
}
