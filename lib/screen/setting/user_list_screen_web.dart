import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hoho/widget/web_list_scaffold.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';


class UserListScreenWeb extends StatefulWidget {
  final VoidCallback onBack;
  final void Function(String userId)? onEditTap;

  const UserListScreenWeb({
    super.key,
    required this.onBack,
    this.onEditTap,
  });

  @override
  State<UserListScreenWeb> createState() => _UserListScreenWebState();
}

class _UserListScreenWebState extends State<UserListScreenWeb> {
  // ============================================================
  // 수정1차
  // - WebListScaffold 공통 리스트 UI 적용
  // - 사용자 리스트 컬럼 표준화
  // - 가로 반응형 스크롤 기본
  // ============================================================
  // ============================================================
  // 수정2차
  // - 권한/역할 옆에 매니저 색상 표시
  // ============================================================
  // ============================================================
  // 수정3차
  // - "사용자 리스트 안나옴" 원인 제거:
  //   1) orderBy('createdAt') 제거(문서 타입 혼재 시 쿼리 에러 방지)
  //   2) 클라이언트 정렬로 대체(타입 섞여도 안전)
  //   3) snapshot.hasError 시 에러 메시지 화면에 출력(원인 즉시 확인)
  //   4) 색상 필드 폴백: managerColor 없으면 color 사용
  // ============================================================

  Color _parseManagerColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.grey;
    try {
      final v = hex.startsWith('#') ? hex.replaceFirst('#', '0xff') : '0xff$hex';
      return Color(int.parse(v));
    } catch (_) {
      return Colors.grey;
    }
  }

  String s(dynamic v) => (v ?? '').toString();

  // ✅ 수정3차: createdAt 정렬용 (Timestamp/String 모두 대응)
  DateTime _pickCreatedAt(Map<String, dynamic> data) {
    final v = data['createdAt'];

    if (v is Timestamp) return v.toDate();
    if (v is String && v.trim().isNotEmpty) {
      try {
        return DateTime.parse(v);
      } catch (_) {}
      // 혹시 "yyyy-MM-dd HH:mm" 형태면 파싱 시도
      try {
        return DateFormat('yyyy-MM-dd HH:mm').parseStrict(v);
      } catch (_) {}
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Widget _roleWithColorChip(Map<String, dynamic> data) {
    final role = s(data['role']);
    // ✅ 수정3차: managerColor 없으면 color 폴백
    final colorHex = (data['managerColor'] ?? data['color'])?.toString();

    return Row(
      children: [
        Text(role),
        const SizedBox(width: 6),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _parseManagerColor(colorHex),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  int _limit = 25;
  String _query = '';

  String formatDate(dynamic v) {
    if (v == null) return '-';
    if (v is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm').format(v.toDate());
    }
    if (v is String && v.isNotEmpty) {
      try {
        return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(v));
      } catch (_) {}
    }
    return '-';
  }

  bool _matchQuery(Map<String, dynamic> data) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;

    return [
      s(data['name']),
      s(data['email']),
      s(data['phone']),
      s(data['role']),
    ].any((v) => v.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    return WebListScaffold(
      limit: _limit,
      onLimitChanged: (v) => setState(() => _limit = v),
      searchHint: '이름/이메일 검색',
      onSearchChanged: (v) => setState(() => _query = v),

      // 사용자 리스트는 삭제 없음
      onDeleteTap: null,
      showRegisterButton: false,

      childTable: StreamBuilder<QuerySnapshot>(
        // ✅ 수정3차: orderBy 제거(타입 혼재/결측으로 인한 쿼리 에러 방지)
        stream: FirebaseFirestore.instance
            .collection('users')
            .limit(_limit)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final pid = Firebase.app().options.projectId;
            final uid = FirebaseAuth.instance.currentUser?.uid;
            return Center(
              child: Text(
                '오류 발생: ${snapshot.error}\nprojectId: $pid\nuid: $uid',
                textAlign: TextAlign.center,
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rawDocs = snapshot.data!.docs.toList();

          // ✅ 수정3차: createdAt 기반 클라이언트 정렬(내림차순)
          rawDocs.sort((a, b) {
            final A = _pickCreatedAt(a.data() as Map<String, dynamic>);
            final B = _pickCreatedAt(b.data() as Map<String, dynamic>);
            return B.compareTo(A);
          });

          final docs = rawDocs
              .where((d) => _matchQuery(d.data() as Map<String, dynamic>))
              .toList();

          if (docs.isEmpty) {
            return const Center(child: Text('표시할 사용자 데이터가 없습니다.'));
          }

          return DataTable(
            headingRowColor: MaterialStateColor.resolveWith((_) => Colors.grey[200]!),
            columns: const [
              DataColumn(label: Text('이름')),
              DataColumn(label: Text('이메일')),
              DataColumn(label: Text('연락처')),
              DataColumn(label: Text('권한/역할')),
              DataColumn(label: Text('최근로그인')),
              DataColumn(label: Text('등록일')),
              DataColumn(label: Text('수정')),
            ],
            rows: List.generate(docs.length, (index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              return DataRow(
                cells: [
                  DataCell(Text(s(data['name']))),
                  DataCell(Text(s(data['email']))),
                  DataCell(Text(s(data['phone']))),
                  DataCell(_roleWithColorChip(data)),
                  DataCell(Text(formatDate(data['lastLoginAt']))),
                  DataCell(Text(formatDate(data['createdAt']))),
                  DataCell(
                    TextButton(
                      onPressed: () => widget.onEditTap?.call(doc.id),
                      child: const Text('수정'),
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
