// lib/screen/common/recycle_bin_screen_web.dart
// ===================================================================
// RecycleBinScreenWeb (휴지통)
// - 수정1차: 접수/상담 소프트삭제 데이터 조회 + 복원 UI
// - 수정2차: WebListScaffold + WebCommonButton 스타일 통일
// ===================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:hoho/widget/web_list_scaffold.dart';
import 'package:hoho/widget/web_common_button.dart';
import 'package:hoho/service/soft_delete_service.dart';

class RecycleBinScreenWeb extends StatefulWidget {
  final VoidCallback onBack;
  const RecycleBinScreenWeb({super.key, required this.onBack});

  @override
  State<RecycleBinScreenWeb> createState() => _RecycleBinScreenWebState();
}

class _RecycleBinScreenWebState extends State<RecycleBinScreenWeb> {
  int _limit = 25;
  String _query = '';

  // 0=접수, 1=상담
  int _tab = 0;

  String _collection() => _tab == 0 ? 'receptions' : 'consultations';

  String _title() => _tab == 0 ? '휴지통 - 접수' : '휴지통 - 상담';

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
      s(data['branch']),
      s(data['managerName']),
      s(data['manager']),
    ];
    return candidates.any((v) => v.contains(q));
  }

  String _fmtTs(dynamic v) {
    if (v == null) return '-';
    try {
      if (v is Timestamp) {
        return DateFormat('yy-MM-dd HH:mm').format(v.toDate());
      }
    } catch (_) {}
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 상단 타이틀 + 탭 + 뒤로
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Text(_title(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 14),

              // 탭 (접수/상담)
              ToggleButtons(
                isSelected: [_tab == 0, _tab == 1],
                onPressed: (i) => setState(() => _tab = i),
                borderRadius: BorderRadius.circular(10),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Text('접수')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Text('상담')),
                ],
              ),

              const Spacer(),
              WebCommonButton.pill(text: '목록으로', onPressed: widget.onBack),
            ],
          ),
        ),
        const Divider(height: 1),

        // 리스트 프레임
        Expanded(
          child: WebListScaffold(
            limit: _limit,
            onLimitChanged: (v) => setState(() => _limit = v),
            searchHint: '검색',
            onSearchChanged: (v) => setState(() => _query = v),

            // 휴지통은 삭제 버튼은 숨김(복원만 제공)
            showDeleteButton: false,
            showRegisterButton: false,

            childTable: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(_collection())
                  .where('isDeleted', isEqualTo: true)
                  .orderBy('deletedAt', descending: true)
                  .limit(_limit)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('오류 발생'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data!.docs.toList();
                final filtered = docs.where((d) => _matchQuery(d.data() as Map<String, dynamic>)).toList();

                return DataTable(
                  headingRowColor: MaterialStateColor.resolveWith((_) => Colors.grey[200]!),
                  columns: const [
                    DataColumn(label: Text('삭제일')),
                    DataColumn(label: Text('프로젝트명')),
                    DataColumn(label: Text('고객명')),
                    DataColumn(label: Text('연락처')),
                    DataColumn(label: Text('담당자')),
                    DataColumn(label: Text('복원')),
                  ],
                  rows: filtered.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    String s(dynamic v) => (v ?? '').toString();

                    return DataRow(
                      cells: [
                        DataCell(Text(_fmtTs(data['deletedAt']))),
                        DataCell(Text(s(data['project'] ?? data['projectName']))),
                        DataCell(Text(s(data['customerName']))),
                        DataCell(Text(s(data['phone1']))),
                        DataCell(Text(s(data['managerName'] ?? data['manager'] ?? '—'))),
                        DataCell(
                          WebCommonButton.pill(
                            text: '복원',
                            onPressed: () async {
                              await SoftDeleteService.restore(collection: _collection(), docId: doc.id);
                            },
                            minWidth: 72,
                            height: 30,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
