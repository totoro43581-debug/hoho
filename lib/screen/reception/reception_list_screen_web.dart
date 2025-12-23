import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hoho/widget/web_list_scaffold.dart'; // ✅ 수정2차: 공통 리스트 프레임
import 'package:hoho/widget/web_common_button.dart';
import 'package:hoho/service/soft_delete_service.dart';

class ReceptionListScreen extends StatefulWidget {
  final VoidCallback? onRegisterTap;
  final void Function(String receptionId)? onEditTap;
  final void Function(Map<String, dynamic> data)? onDetailTap;

  const ReceptionListScreen({
    super.key,
    this.onRegisterTap,
    this.onEditTap,
    this.onDetailTap,
  });

  @override
  State<ReceptionListScreen> createState() => _ReceptionListScreenState();
}

class _ReceptionListScreenState extends State<ReceptionListScreen> {
  // ==========================
  // 수정2차: WebListScaffold 적용
  // - 갯수(10/25/50/100) + 팝업 화이트
  // - 가로 반응형 스크롤 공통화
  // ==========================

  final Set<String> _selectedDocs = {};
  int _limit = 25;
  String _query = '';

  String formatTimestamp(dynamic value) {
    if (value == null) return '-';
    try {
      if (value is Timestamp) {
        return DateFormat('yy-MM-dd HH:mm').format(value.toDate());
      } else if (value is String) {
        try {
          final dt = DateTime.parse(value);
          return DateFormat('yy-MM-dd HH:mm').format(dt);
        } catch (_) {
          final parsed = DateFormat('yyyy-MM-dd HH:mm').parseStrict(value);
          return DateFormat('yy-MM-dd HH:mm').format(parsed);
        }
      }
    } catch (_) {}
    return '-';
  }

  DateTime _pickCreatedAt(Map<String, dynamic> data) {
    final tsCandidates = [
      data['createdAtTs'],
      data['createdAt'],
      data['reservationDate']
    ];
    for (final v in tsCandidates) {
      if (v is Timestamp) return v.toDate();
    }
    final strCandidates = [
      data['createdAtIso'],
      data['createdAt'],
      data['reservationDateTime']
    ];
    for (final v in strCandidates) {
      if (v is String && v.trim().isNotEmpty) {
        try {
          return DateTime.parse(v);
        } catch (_) {}
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _toggleSelection(String docId, bool selected) {
    setState(() {
      if (selected) {
        _selectedDocs.add(docId);
      } else {
        _selectedDocs.remove(docId);
      }
    });
  }

// ==========================
// 수정3차(누적): 실삭제(delete) 금지 → 소프트삭제로 전환
// ==========================
  Future<void> _deleteSelectedDocs() async {
    for (final docId in _selectedDocs) {
      await SoftDeleteService.softDelete(
          collection: 'receptions', docId: docId);
    }
    setState(() => _selectedDocs.clear());
  }

  bool _matchQuery(Map<String, dynamic> data) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;

    String s(dynamic v) => (v ?? '').toString().toLowerCase();
    final candidates = <String>[
      s(data['project']),
      s(data['projectName']),
      s(data['customerName']),
      s(data['phone1']),
      s(data['address1']),
      s(data['address2']),
      s(data['addressDetail']),
      s(data['branch']),
    ];
    return candidates.any((v) => v.contains(q));
  }

  @override
  Widget build(BuildContext context) {
    return WebListScaffold(
      limit: _limit,
      onLimitChanged: (v) => setState(() => _limit = v),
      searchHint: '검색',
      onSearchChanged: (v) => setState(() => _query = v),

      // ✅ 접수는 삭제/등록 둘 다 있음
      onDeleteTap: _selectedDocs.isEmpty ? null : _deleteSelectedDocs,

      showRegisterButton: true,
      onRegisterTap: () => widget.onRegisterTap?.call(),

      childTable: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('receptions')
            .where('isDeleted', isEqualTo: false)
            .snapshots(includeMetadataChanges: true),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('오류 발생'));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final rawDocs = snapshot.data!.docs.toList();

          // 클라이언트 정렬 보강(키 폴백)
          rawDocs.sort((a, b) {
            final A = _pickCreatedAt(a.data() as Map<String, dynamic>);
            final B = _pickCreatedAt(b.data() as Map<String, dynamic>);
            return B.compareTo(A);
          });

          // ============================================================
          // 수정4차(누적): 검색 → limit 순서 클라이언트 처리
          // ============================================================

          // 검색 필터 (전체)
          final filteredAll = rawDocs
              .where((d) => _matchQuery(d.data() as Map<String, dynamic>))
              .toList();

          // 화면 표시용(limit 적용)
          final filtered = filteredAll.take(_limit).toList();

          final total = filteredAll.length;

          return DataTable(
            headingRowColor:
                MaterialStateColor.resolveWith((_) => Colors.grey[200]!),
            columns: const [
              DataColumn(label: Text('')),
              DataColumn(label: Text('번호')),
              DataColumn(label: Text('지점')),
              DataColumn(label: Text('공실여부')),
              DataColumn(label: Text('상담예약일')),
              DataColumn(label: Text('상담방법')),
              DataColumn(label: Text('접수일자')),
              DataColumn(label: Text('접수유형')),
              DataColumn(label: Text('프로젝트명')),
              DataColumn(label: Text('동/호수')),
              DataColumn(label: Text('평수')),
              DataColumn(label: Text('고객명')),
              DataColumn(label: Text('연락처')),
              DataColumn(label: Text('상담/계약')),
              DataColumn(label: Text('관리')),
            ],
            rows: List.generate(filtered.length, (index) {
              final doc = filtered[index];
              final data = doc.data() as Map<String, dynamic>;
              final isSelected = _selectedDocs.contains(doc.id);
              String s(dynamic v) => (v ?? '').toString();

              final rowData = <String, dynamic>{
                ...data,
                'id': data['id'] ?? doc.id
              };

              void goDetail() => widget.onDetailTap?.call(rowData);

              return DataRow(
                selected: isSelected,
                cells: [
                  DataCell(
                    Checkbox(
                      value: isSelected,
                      onChanged: (value) =>
                          _toggleSelection(doc.id, value ?? false),
                    ),
                  ),
                  DataCell(Text('${total - index}'), onTap: goDetail),
                  DataCell(Text(s(data['branch'])), onTap: goDetail),
                  DataCell(Text(s(data['emptyStatus'])), onTap: goDetail),
                  DataCell(
                      Text(formatTimestamp(data['reservationDate'] ??
                          data['reservationDateTime'])),
                      onTap: goDetail),
                  DataCell(Text(s(data['consultMethod'])), onTap: goDetail),
                  DataCell(
                      Text(DateFormat('yy-MM-dd HH:mm')
                          .format(_pickCreatedAt(data))),
                      onTap: goDetail),
                  DataCell(
                      Text(s(data['receptionSource'] ?? data['receptionType'])),
                      onTap: goDetail),
                  DataCell(Text(s(data['project'] ?? data['projectName'])),
                      onTap: goDetail),
                  DataCell(Text(s(data['address2'] ?? data['addressDetail'])),
                      onTap: goDetail),
                  DataCell(Text(s(data['area'])), onTap: goDetail),
                  DataCell(Text(s(data['customerName'])), onTap: goDetail),
                  DataCell(Text(s(data['phone1'])), onTap: goDetail),
                  DataCell(
                      Text(s(data['managerName'] ??
                          data['manager'] ??
                          data['assigneeManagerName'] ??
                          data['managerId'] ??
                          '—')),
                      onTap: goDetail),
// ============================================================
// 수정3차(누적): 접수 리스트 행 '수정' 버튼 공통 버튼(WebCommonButton) 적용
// ============================================================
                  DataCell(
                    WebCommonButton.pill(
                      text: '수정',
                      onPressed: () => widget.onEditTap?.call(doc.id),
                      minWidth: 60,
                      height: 30,
                    ),
                  ),
                ],
              );
            }),
          );
        },
      ),
    );
  }
}
