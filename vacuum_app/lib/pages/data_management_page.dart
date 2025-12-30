import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/vacuum_record.dart';
import '../services/vacuum_db.dart';

/// DB에 저장된 vacuums 테이블을
/// - 날짜(from/to) 필터
/// - PASS/FAIL 필터
/// - LOT/PK/CK 텍스트 검색
/// - CSV Export
/// 하는 화면
class DataManagementPage extends StatefulWidget {
  const DataManagementPage({super.key});

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  /// DB에서 읽어온 전체 데이터
  List<VacuumRecord> _allRecords = [];

  /// 필터가 적용된 결과
  List<VacuumRecord> _filteredRecords = [];

  /// 날짜 필터
  DateTime? _fromDate;
  DateTime? _toDate;

  /// PASS / FAIL 필터(null이면 전체)
  String? _resultFilter; // "pass" | "fail"

  /// LOT/PK/CK 검색 키워드
  String _keyword = "";

  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllRecords();

    // 검색창 리스너 등록
    _searchController.addListener(() {
      _keyword = _searchController.text;
      _applyFilters();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────
  //  DB에서 전체 레코드 읽어오기
  // ─────────────────────────────────
  Future<void> _loadAllRecords() async {
    try {
      final records = await VacuumDB.instance.queryAllRecords();
      setState(() {
        _allRecords = records;
        _filteredRecords = records;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('DB 로딩 오류: $e')),
      );
    }
  }

  // ─────────────────────────────────
  //  날짜/결과/검색어 전체 필터 적용
  // ─────────────────────────────────
  void _applyFilters() {
    List<VacuumRecord> list = List.of(_allRecords);

    // 1) 날짜 필터
    if (_fromDate != null) {
      list = list.where((r) => !r.stmpdate.isBefore(_fromDate!)).toList();
    }
    if (_toDate != null) {
      // _toDate 의 23:59:59 까지 포함되도록
      final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
      list = list.where((r) => !r.stmpdate.isAfter(to)).toList();
    }

    // 2) PASS/FAIL 필터
    if (_resultFilter != null && _resultFilter!.isNotEmpty) {
      final lower = _resultFilter!.toLowerCase();
      list = list.where((r) => r.result.toLowerCase() == lower).toList();
    }

    // 3) LOT / PK/CK 키워드 검색
    if (_keyword.trim().isNotEmpty) {
      final kw = _keyword.toLowerCase();
      list = list.where((r) {
        return r.lotname.toLowerCase().contains(kw) ||
            r.pkck.toLowerCase().contains(kw);
      }).toList();
    }

    setState(() {
      _filteredRecords = list;
    });
  }

  // ─────────────────────────────────
  //  날짜 선택
  // ─────────────────────────────────
  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      _applyFilters();
    }
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _toDate = picked);
      _applyFilters();
    }
  }

  // ─────────────────────────────────
  //  CSV Export
  // ─────────────────────────────────
  Future<void> _exportCsv() async {
    if (_filteredRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('엑셀로 저장할 데이터가 없습니다.')),
      );
      return;
    }

    // CSV 헤더 + 각 레코드
    final rows = <List<dynamic>>[
      [
        "lotid",
        "lotname",
        "pkck",
        "vacp_sel",
        "vacp_st",
        "vacp_sp",
        "vacp_diff",
        "duration",
        "result",
        "stmpdate",
      ],
      ..._filteredRecords.map((r) => [
            r.lotid,
            r.lotname,
            r.pkck,
            r.vacpSel,
            r.vacpSt,
            r.vacpSp,
            r.vacpDiff,
            r.duration,
            r.result,
            _formatDate(r.stmpdate),
          ]),
    ];

    final csv = const ListToCsvConverter().convert(rows);

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'CSV Export',
      fileName: 'vacuum_export.csv',
    );

    if (savePath == null) return;

    await File(savePath).writeAsString(csv);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV 저장 완료!')),
    );
  }

  // Qt 스타일: yyyy-MM-dd hh:mm:ss
  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  // ─────────────────────────────────
  //  UI
  // ─────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Management'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Column(
        children: [
          // 상단 필터 영역
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _pickFromDate,
                      child: Text(
                        _fromDate == null
                            ? 'From'
                            : _fromDate!.toIso8601String().substring(0, 10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _pickToDate,
                      child: Text(
                        _toDate == null
                            ? 'To'
                            : _toDate!.toIso8601String().substring(0, 10),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // PASS/FAIL 필터
                    DropdownButton<String>(
                      value: _resultFilter,
                      hint: const Text('결과'),
                      items: const [
                        DropdownMenuItem(value: 'pass', child: Text('PASS')),
                        DropdownMenuItem(value: 'fail', child: Text('FAIL')),
                      ],
                      onChanged: (v) {
                        setState(() => _resultFilter = v);
                        _applyFilters();
                      },
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _exportCsv,
                      child: const Text('CSV Export'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // LOT / PK/CK 검색
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search LOT / PAK / CHUCK ...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 리스트 영역
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRecords.isEmpty
                    ? const Center(child: Text('검색된 결과가 없습니다.'))
                    : ListView.builder(
                        itemCount: _filteredRecords.length,
                        itemBuilder: (context, index) {
                          final r = _filteredRecords[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            child: ListTile(
                              title: Text('${r.lotname} (${r.pkck})'),
                              subtitle: Text(
                                'Sel:${r.vacpSel}  '
                                'Start:${r.vacpSt.toStringAsFixed(1)}  '
                                'End:${r.vacpSp.toStringAsFixed(1)}  '
                                'Diff:${r.vacpDiff.toStringAsFixed(1)}  '
                                'Time:${r.duration}s  '
                                'Result:${r.result.toUpperCase()}',
                              ),
                              trailing: Text(_formatDate(r.stmpdate)),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
