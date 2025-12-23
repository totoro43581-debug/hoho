// lib/screen/consultation/consultation_list_screen_web.dart
// ===================================================================
// 상담 리스트 (Web)
// - (기존 주석 유지 가정)
// - 수정3차(누적):
//   1) 접수/상담 리스트 UI 완전 동일화: 체크박스 컬럼 추가
//   2) 삭제 버튼 동일 노출 + 선택 없으면 비활성
//   3) "전체" 텍스트 제거(공통 스캐폴드 수정2차 반영)
//   4) 갯수 10/25/50/100 실제 limit 적용
//
// ✅ 수정4차:
//   - 수정버튼 제외 클릭 = 상세(onDetailTap)
//   - 수정버튼만 수정(onEditTap)
// ===================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hoho/widget/web_list_scaffold.dart';
import 'package:hoho/widget/web_common_button.dart';
import 'package:hoho/service/soft_delete_service.dart';

class ConsultationListScreenWeb extends StatefulWidget {
  final VoidCallback? onRegisterTap; // 호환용(사용 안함)
  final void Function(String docId)? onEditTap;

  // ✅ 수정4차: 상세 진입 콜백
  final void Function(Map<String, dynamic> rowData)? onDetailTap;

  const ConsultationListScreenWeb({
    super.key,
    this.onRegisterTap,
    this.onEditTap,
    this.onDetailTap,
  });

  @override
  State<ConsultationListScreenWeb> createState() => _ConsultationListScreenWebState();
}

class _ConsultationListScreenWebState extends State<ConsultationListScreenWeb> {
  static const String kCollection = 'receptions';

  final Set<String> _selectedDocs = {};

  int _limit = 25;
  String _query = '';

  String _s(dynamic v) => (v ?? '').toString();

  DateTime _pickCreatedAt(Map<String, dynamic> data) {
    final tsCandidates = [
      data['createdAtTs'],
      data['createdAt'],
      data['reservationDate'],
      data['updatedAt'],
    ];
    for (final v in tsCandidates) {
      if (v is Timestamp) return v.toDate();
    }

    final strCandidates = [
      data['createdAtIso'],
      data['createdAt'],
      data['reservationDateTime'],
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

  bool _isAssigned(Map<String, dynamic> data) {
    final candidates = [
      data['managerName'],
      data['manager'],
      data['assigneeManagerName'],
      data['assigneeName'],
      data['assignedManagerName'],
      data['managerId'],
      data['assigneeId'],
      data['assignedManagerId'],
    ];
    for (final v in candidates) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s != '-' && s != '—') return true;
    }
    return false;
  }

  String _assignedText(Map<String, dynamic> data) {
    return _s(
      data['managerName'] ??
          data['manager'] ??
          data['assigneeManagerName'] ??
          data['assigneeName'] ??
          data['assignedManagerName'] ??
          data['managerId'] ??
          data['assigneeId'] ??
          '—',
    );
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
      _assignedText(data).toLowerCase(),
    ];
    return candidates.any((v) => v.contains(q));
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

  Future<void> _deleteSelectedDocs() async {
    final batch = FirebaseFirestore.instance.batch();
    final col = FirebaseFirestore.instance.collection(kCollection);
    for (final docId in _selectedDocs) {
      batch.delete(col.doc(docId));
    }
    await batch.commit();
    setState(() => _selectedDocs.clear());
  }

  @override
  Widget build(BuildContext context) {
    return WebListScaffold(
      limit: _limit,
      onLimitChanged: (v) => setState(() => _limit = v),
      searchHint: '검색',
      onSearchChanged: (v) => setState(() => _query = v),

      onDeleteTap: _selectedDocs.isEmpty ? null : _deleteSelectedDocs,

      showRegisterButton: false,
      onRegisterTap: null,

      childTable: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection(kCollection)
            .where('isDeleted', isEqualTo: false)
            .limit(_limit)
            .snapshots(includeMetadataChanges: true),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('오류 발생: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs.toList();

          docs.sort((a, b) {
            final A = _pickCreatedAt(a.data() as Map<String, dynamic>);
            final B = _pickCreatedAt(b.data() as Map<String, dynamic>);
            return B.compareTo(A);
          });

          final assigned = docs
              .where((d) => _isAssigned(d.data() as Map<String, dynamic>))
              .where((d) => _matchQuery(d.data() as Map<String, dynamic>))
              .toList();

          final total = assigned.length;

          if (assigned.isEmpty) {
            return const Center(child: Text('표시할 상담(배정) 데이터가 없습니다.'));
          }

          return DataTable(
            headingRowColor: MaterialStateColor.resolveWith((_) => Colors.grey[200]!),
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
            rows: List.generate(assigned.length, (index) {
              final doc = assigned[index];
              final data = doc.data() as Map<String, dynamic>;
              final isSelected = _selectedDocs.contains(doc.id);

              // ✅ 상세 진입용 rowData (id 포함)
              final rowData = <String, dynamic>{
                ...data,
                'id': doc.id,
              };

              // ✅ 수정4차: 수정 버튼만 edit
              void goEdit() => widget.onEditTap?.call(doc.id);

              // ✅ 수정4차: 나머지 클릭은 detail
              void goDetail() => widget.onDetailTap?.call(rowData);

              return DataRow(
                selected: isSelected,
                cells: [
                  DataCell(
                    Checkbox(
                      value: isSelected,
                      onChanged: (v) => _toggleSelection(doc.id, v ?? false),
                    ),
                  ),

                  // ===== 여기부터 전부 onTap: goDetail =====
                  DataCell(Text('${total - index}'), onTap: goDetail),
                  DataCell(Text(_s(data['branch'])), onTap: goDetail),
                  DataCell(Text(_s(data['emptyStatus'])), onTap: goDetail),
                  DataCell(Text(formatTimestamp(data['reservationDate'] ?? data['reservationDateTime'])), onTap: goDetail),
                  DataCell(Text(_s(data['consultMethod'])), onTap: goDetail),
                  DataCell(Text(DateFormat('yy-MM-dd HH:mm').format(_pickCreatedAt(data))), onTap: goDetail),
                  DataCell(Text(_s(data['receptionSource'] ?? data['receptionType'])), onTap: goDetail),
                  DataCell(Text(_s(data['project'] ?? data['projectName'])), onTap: goDetail),
                  DataCell(Text(_s(data['address2'] ?? data['addressDetail'])), onTap: goDetail),
                  DataCell(Text(_s(data['area'])), onTap: goDetail),
                  DataCell(Text(_s(data['customerName'])), onTap: goDetail),
                  DataCell(Text(_s(data['phone1'])), onTap: goDetail),
                  DataCell(Text(_assignedText(data)), onTap: goDetail),

                  // ===== 관리 컬럼: 수정 버튼만 goEdit =====
                  DataCell(
                    WebCommonButton.pill(
                      text: '수정',
                      onPressed: goEdit,
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
