// lib/screen/consultation/consultation_detail_pane_web.dart
// ===================================================================
// 상담 상세 (Web) - 공통 Pane (접수리스트/상담리스트 동일 사용)
// - 수정1차: 상담상세 UI를 단일화(중복 구현 제거 목적)
// - Scaffold/AppBar 없음 (HomeScreenWeb 메인컨텐츠 내부 렌더링 전용)
// - 데이터 소스: receptions/{docId} (배정건만 상담으로 취급)
// ===================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ConsultationDetailPaneWeb extends StatefulWidget {
  final String receptionDocId;
  final VoidCallback onBack; // 리스트로 돌아가기
  final VoidCallback? onEdit; // 수정 화면으로 이동(선택)

  const ConsultationDetailPaneWeb({
    super.key,
    required this.receptionDocId,
    required this.onBack,
    this.onEdit,
  });

  @override
  State<ConsultationDetailPaneWeb> createState() => _ConsultationDetailPaneWebState();
}

class _ConsultationDetailPaneWebState extends State<ConsultationDetailPaneWeb> {
  // ===== 공통 스타일(접수/상담 동일 유지) =====
  static const double _pagePadding = 24.0;
  static const double _cardRadius = 16.0;
  static const Color _borderColor = Color(0xFFE5E7EB); // 연한 그레이

  final DateFormat _df = DateFormat('yyyy-MM-dd (E)', 'ko_KR');
  final DateFormat _dtf = DateFormat('yyyy-MM-dd (E) HH:mm', 'ko_KR');

  DocumentReference<Map<String, dynamic>> get _docRef =>
      FirebaseFirestore.instance.collection('receptions').doc(widget.receptionDocId);

  // ---------- helpers ----------
  String _s(dynamic v) => (v ?? '').toString().trim();

  // Firestore Timestamp / String / int 모두 대응 (프로젝트 중간에 형식 바뀌는 경우가 많아서 방어)
  DateTime? _toDate(dynamic v) {
    try {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) {
        // "2025-10-10 12:30" 같은 텍스트 저장도 대비
        final t = DateTime.tryParse(v);
        return t;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // 상담예약일시: 프로젝트 내 여러 키가 존재할 수 있어 폴백 처리
  DateTime? _readConsultReservationDate(Map<String, dynamic> data) {
    // ✅ 우선순위: reservationDateTime(권장) -> reservationAt -> reservationText(문자열)
    final dt = _toDate(data['reservationDateTime']) ??
        _toDate(data['reservationAt']) ??
        _toDate(data['consultReservationAt']);
    if (dt != null) return dt;

    // 문자열로 저장된 경우
    final text = _s(data['reservation']) // 예: reservationController.text
        .ifEmpty(_s(data['reservationText']))
        .ifEmpty(_s(data['reservationDateTimeText']));
    if (text.isEmpty) return null;

    // 문자열 파싱은 포맷이 들쑥날쑥할 수 있어 표시만 하고 날짜는 null로 처리 가능
    return null;
  }

  String _readConsultReservationText(Map<String, dynamic> data) {
    final dt = _readConsultReservationDate(data);
    if (dt != null) return _dtf.format(dt);

    final text = _s(data['reservation'])
        .ifEmpty(_s(data['reservationText']))
        .ifEmpty(_s(data['reservationDateTimeText']));
    return text;
  }

  // 상담담당자 표기 (users 문서 id / 이름 저장 방식 혼재 대비)
  String _readAssignedName(Map<String, dynamic> data) {
    // 프로젝트에서 쓰던 키들 폴백
    final name = _s(data['assignedUserName'])
        .ifEmpty(_s(data['assignedManagerName']))
        .ifEmpty(_s(data['consultantName']))
        .ifEmpty(_s(data['assignedToName']));
    if (name.isNotEmpty) return name;

    // id만 있는 경우
    final id = _s(data['assignedUserId'])
        .ifEmpty(_s(data['assignedManagerId']))
        .ifEmpty(_s(data['assignedTo']));
    return id.isNotEmpty ? '담당자ID: $id' : '';
  }

  // 상담상태
  String _readStatus(Map<String, dynamic> data) {
    return _s(data['consultStatus'])
        .ifEmpty(_s(data['status']))
        .ifEmpty('대기');
  }

  // 상담방법
  String _readMethod(Map<String, dynamic> data) {
    return _s(data['consultMethod'])
        .ifEmpty(_s(data['consultType']))
        .ifEmpty(_s(data['method']));
  }

  // 공통 카드
  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }

  // 공통 타이틀 행
  Widget _titleRow(String title, {Widget? right}) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (right != null) right,
      ],
    );
  }

  // 공통 정보 라인
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(value.isEmpty ? '-' : value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // 상담 로그(타임라인) - subcollection 이름은 프로젝트마다 달라질 수 있어 일단 consultationsLogs로 고정
  // 필요 시 여기만 키 바꾸면, 접수/상담 어디서 열어도 동일 동작
  Stream<QuerySnapshot<Map<String, dynamic>>> _logStream() {
    return _docRef
        .collection('consultationLogs') // ✅ 수정1차: 상담로그 subcollection명
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> _updateStatus(String nextStatus) async {
    await _docRef.update({
      'consultStatus': nextStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 로그도 남기고 싶으면(권장) - 필요 없으면 아래 블록 삭제 가능
    await _docRef.collection('consultationLogs').add({
      'type': 'STATUS',
      'message': '상태 변경: $nextStatus',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(_pagePadding),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _titleRow('상담 상세', right: _topButtons(context)),
                  const SizedBox(height: 12),
                  Text('불러오기 오류: ${snap.error}'),
                ],
              ),
            );
          }
          if (!snap.hasData) {
            return _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _titleRow('상담 상세', right: _topButtons(context)),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ),
            );
          }

          final doc = snap.data!;
          final data = doc.data() ?? {};

          // 기본 정보
          final customerName = _s(data['customerName']);
          final phone = _s(data['phone1']).ifEmpty(_s(data['customerPhone']));
          final simpleArea = _s(data['simpleArea']).ifEmpty(_s(data['regionSimple']));
          final addr1 = _s(data['address1']).ifEmpty(_s(data['address']));
          final addr2 = _s(data['address2']).ifEmpty(_s(data['addressDetail']));
          final projectName = _s(data['projectName']);
          final pyeong = _s(data['pyeong']).ifEmpty(_s(data['areaPyeong']));
          final vacant = _s(data['vacant']).ifEmpty(_s(data['isVacant']));
          final receptionType = _s(data['receptionType']);
          final type = _s(data['type']);

          // 상담 정보
          final consultStatus = _readStatus(data);
          final consultMethod = _readMethod(data);
          final consultReservation = _readConsultReservationText(data);
          final assignedName = _readAssignedName(data);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 상단 헤더(리스트와 동일한 톤)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _titleRow('상담 상세', right: _topButtons(context)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip('상태', consultStatus),
                        _chip('방법', consultMethod),
                        _chip('담당', assignedName.isEmpty ? '-' : assignedName),
                        _chip('예약', consultReservation.isEmpty ? '-' : consultReservation),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 기본 정보 카드
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _titleRow('기본 정보'),
                    const SizedBox(height: 8),
                    _infoRow('고객명', customerName),
                    _infoRow('연락처', phone),
                    _infoRow('간편지역', simpleArea),
                    _infoRow('주소', addr1),
                    _infoRow('상세주소', addr2),
                    _infoRow('프로젝트명', projectName),
                    _infoRow('평수', pyeong),
                    _infoRow('공실여부', vacant),
                    _infoRow('접수유형', receptionType),
                    _infoRow('유형', type),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 상담 정보 카드
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _titleRow('상담 정보'),
                    const SizedBox(height: 8),
                    _infoRow('상담상태', consultStatus),
                    _infoRow('상담방법', consultMethod),
                    _infoRow('상담예약일시', consultReservation),
                    _infoRow('상담담당자', assignedName),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _actionButton('상담완료', onTap: () => _updateStatus('상담완료')),
                        const SizedBox(width: 8),
                        _actionButton('보류', onTap: () => _updateStatus('보류')),
                        const SizedBox(width: 8),
                        _actionButton('대기', onTap: () => _updateStatus('대기')),
                        const Spacer(),
                        if (widget.onEdit != null) _primaryButton('수정', onTap: widget.onEdit!),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 타임라인
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _titleRow('상담 히스토리'),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _logStream(),
                      builder: (context, logSnap) {
                        if (logSnap.hasError) {
                          return Text('로그 오류: ${logSnap.error}');
                        }
                        if (!logSnap.hasData) {
                          return const LinearProgressIndicator();
                        }
                        final logs = logSnap.data!.docs;
                        if (logs.isEmpty) {
                          return const Text('기록이 없습니다.');
                        }
                        return Column(
                          children: logs.map((d) {
                            final m = d.data();
                            final msg = _s(m['message']);
                            final createdAt = _toDate(m['createdAt']);
                            final timeText = createdAt == null ? '-' : _dtf.format(createdAt);
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: _borderColor),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(timeText, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                                  const SizedBox(height: 6),
                                  Text(msg.isEmpty ? '-' : msg, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===== 상단 버튼(뒤로/수정) =====
  Widget _topButtons(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: widget.onBack,
          child: const Text('목록으로'),
        ),
        if (widget.onEdit != null) ...[
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: widget.onEdit,
            child: const Text('수정'),
          ),
        ],
      ],
    );
  }

  // ===== 칩 =====
  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Color(0xFF6B7280))),
          Text(value.isEmpty ? '-' : value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ===== 버튼 =====
  Widget _actionButton(String text, {required VoidCallback onTap}) {
    return OutlinedButton(onPressed: onTap, child: Text(text));
  }

  Widget _primaryButton(String text, {required VoidCallback onTap}) {
    return ElevatedButton(onPressed: onTap, child: Text(text));
  }
}

// ===== String extension (빈 문자열 폴백용) =====
extension _StringFallback on String {
  String ifEmpty(String other) => trim().isEmpty ? other : this;
}
