import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// =====================================================================
/// 타임라인용 모델
/// =====================================================================
class TimelineItem {
  final DateTime date;
  final String title;
  final String? description;

  TimelineItem({
    required this.date,
    required this.title,
    this.description,
  });
}

/// =====================================================================
/// 상담 상세 페이지 (웹)
///  - 메인 컨텐츠 카드 안에서만 렌더링 (내부 카드 없음 - 수정1차)
///  - 타임라인은 팝업(Dialog)에서만 표시 (onTimeline 콜백 사용 안 함 - 수정2차)
///  - 섹션 순서: 기본정보 → 주소정보 → 상담정보 → 시공및일정 → 상담메모 → 담당자정보 (수정3차)
/// =====================================================================
class ReceptionDetailScreenWeb extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onBack;
  final void Function(String id)? onEdit;
  final void Function(Map<String, dynamic> data)? onTimeline; // 현재는 호출 안 함

  const ReceptionDetailScreenWeb({
    super.key,
    required this.data,
    required this.onBack,
    this.onEdit,
    this.onTimeline,
  });

  String _s(dynamic v) => (v ?? '').toString();

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;

    try {
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v);
      }

      // Timestamp(seconds=...) 문자열 대응
      final str = v.toString();
      if (str.contains('seconds=')) {
        final secStr = str.split('seconds=')[1].split(',').first.trim();
        final sec = int.tryParse(secStr);
        if (sec != null) {
          return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
        }
      }

      // Firestore Timestamp json map {_seconds: , _nanoseconds: }
      if (v is Map && v['_seconds'] is int) {
        return DateTime.fromMillisecondsSinceEpoch(v['_seconds'] * 1000);
      }
    } catch (_) {}

    return null;
  }

  String _fmt(dynamic v, {bool onlyDate = false}) {
    final dt = _asDate(v);
    if (dt == null) return '-';

    return onlyDate
        ? DateFormat('yyyy-MM-dd').format(dt)
        : DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  // ---------------- UI 공통 위젯 ----------------
  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF374151),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {int maxLines = 4}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              softWrap: true,
              maxLines: maxLines,
              style: const TextStyle(
                  fontSize: 13,
                  height: 1.25
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendar(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const Icon(Icons.calendar_month, size: 18, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ---------------- 타임라인 데이터 빌드 ----------------
  List<TimelineItem> _buildTimelineItems() {
    final List<TimelineItem> items = [];

    // 1) 시공 예정
    final start = _asDate(data['constructStart']);
    final end = _asDate(data['constructEnd']);
    if (start != null || end != null) {
      items.add(
        TimelineItem(
          date: start ?? end!,
          title: '시공 예정',
          description:
          '${_fmt(start, onlyDate: true)} ~ ${_fmt(end, onlyDate: true)}',
        ),
      );
    }

    // 2) 접수 등록
    final createdAt = _asDate(data['createdAt'] ?? data['createdAtTs']);
    if (createdAt != null) {
      items.add(
        TimelineItem(
          date: createdAt,
          title: '접수 등록',
          description: '접수 정보가 시스템에 등록되었습니다.',
        ),
      );
    }

    // 3) 상담 예약
    final resDate = _asDate(data['reservationDateTime']);
    if (resDate != null) {
      items.add(
        TimelineItem(
          date: resDate,
          title: '상담 예약',
          description:
          '상담방법: ${_s(data['consultMethod']).isEmpty ? '미지정' : _s(data['consultMethod'])}',
        ),
      );
    }

    // 4) 입주 예정
    final moveIn = _asDate(data['moveInDate']);
    if (moveIn != null) {
      items.add(
        TimelineItem(
          date: moveIn,
          title: '입주 예정',
          description: _fmt(moveIn, onlyDate: true),
        ),
      );
    }

    // 5) 마지막 수정
    final updatedAt = _asDate(data['updatedAt']);
    if (updatedAt != null) {
      items.add(
        TimelineItem(
          date: updatedAt,
          title: '마지막 수정',
          description: '상담/시공 정보가 수정되었습니다.',
        ),
      );
    }

    // 6) 상담 차수(consultRounds)
    final rounds = data['consultRounds'];
    if (rounds is List) {
      for (int i = 0; i < rounds.length; i++) {
        final r = rounds[i];
        if (r is Map) {
          final dt = _asDate(r['dateTime']);
          final method = _s(r['method']);
          if (dt != null) {
            items.add(
              TimelineItem(
                date: dt,
                title: '${i + 1}차 상담',
                description: method.isEmpty ? null : '상담방법: $method',
              ),
            );
          }
        }
      }
    }

    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  // ---------------- 타임라인 그리기 (팝업에서 사용) ----------------
  Widget _buildTimelineWidget() {
    final items = _buildTimelineItems();
    if (items.isEmpty) {
      return const Center(
        child: Text(
          '타임라인 정보가 없습니다.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '타임라인',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Column(
          children: List.generate(items.length, (i) {
            final e = items[i];
            final last = i == items.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  child: Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: last ? Colors.indigo : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (!last)
                        Container(
                          width: 2,
                          height: 40,
                          color: Colors.grey.shade300,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(e.date),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          e.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (e.description != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              e.description!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  // ---------------- 타임라인 Dialog (팝업 전용) ----------------
  void _showTimelineDialog(BuildContext context) {
    // onTimeline 콜백은 더 이상 호출하지 않고, 팝업만 표시 (수정2차)
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: Colors.white, // 배경색
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '상담 타임라인',
                    style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildTimelineWidget(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('닫기'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------- 레이아웃(상세 내용) ----------------
  @override
  Widget build(BuildContext context) {
    final id = _s(data['id']);

    return LayoutBuilder(
      builder: (context, cons) {
        final wide = cons.maxWidth > 950;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // 상단 타이틀은 이미 제거하셨으면 이 부분도 주석 처리 가능
            // const Text(
            //   '상담 상세내용',
            //   style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            // ),
            // const SizedBox(height: 20),

            // 상세 내용: 내부 카드 없음
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: wide ? _twoColumn() : _oneColumn(),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 하단 버튼 (목록 / 수정 / 타임라인 보기)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 타임라인 보기 버튼도 테두리 있는 버튼으로 변경
                OutlinedButton(
                  onPressed: () => _showTimelineDialog(context),
                  child: const Text('타임라인 보기'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onBack,
                  child: const Text('목록으로'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onEdit != null ? () => onEdit!(id) : null,
                  child: const Text('수정하기'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ------------ 컬럼 분리 ------------
  Widget _twoColumn() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _leftColumn()),
        const SizedBox(width: 60),
        Expanded(child: _rightColumn()),
      ],
    );
  }

  Widget _oneColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _leftColumn(),
        const SizedBox(height: 24),
        _rightColumn(),
      ],
    );
  }

  // LEFT 컬럼: 기본 정보 + 주소 정보
  Widget _leftColumn() {
    return Column(
      children: [
        _sectionHeader('기본 정보'),
        _row('접수유형',
            _s(data['receptionSource'] ?? data['receptionType'])),
        _row('유형', _s(data['type'])),
        _row('지점', _s(data['branch'])),
        _row('공실여부', _s(data['emptyStatus'])),
        _row('평수', _s(data['area'])),
        _row('고객명', _s(data['customerName'])),
        _row('연락처', _s(data['phone1'])),
        _row('부연락처', _s(data['phone2'])),

        _sectionHeader('주소 정보'),
        _row('프로젝트명', _s(data['project'])),
        _row(
          '주소',
          '${_s(data['address1'])}\n${_s(data['address2'])}',
          maxLines: 6,
        ),

        // ===== 시공 및 일정 =====
        _sectionHeader('시공 및 일정'),
        _calendar(
          '시공예정일',
          '${_fmt(data['constructStart'], onlyDate: true)} ~ ${_fmt(data['constructEnd'], onlyDate: true)}',
        ),
        _calendar('입주예정일', _fmt(data['moveInDate'], onlyDate: true)),
      ],
    );
  }

  // RIGHT 컬럼: 상담 정보 → 시공 및 일정 → 상담 메모 → 담당자 정보
  Widget _rightColumn() {
    return Column(
      children: [
        // ===== 상담 정보 (시공 일정보다 위로 이동 - 수정3차) =====
        _sectionHeader('상담 정보'),
        _row('상담방법', _s(data['consultMethod'])),
        _calendar('상담예약일', _fmt(data['reservationDateTime'])),
        _calendar('접수일자', _fmt(data['createdAt'] ?? data['createdAtTs'])),

        // ===== 상담 메모 =====
        _sectionHeader('상담 메모'),
        _row('메모', _s(data['memo']), maxLines: 999),

        // ===== 담당자 정보 =====
        _sectionHeader('담당자 정보'),
        _row('상담/계약담당자', _s(data['managerName'])),
        _row('현장정담당자', _s(data['siteMainName'])),
        _row('현장부담당자', _s(data['siteSubName'])),
        _row('디자이너', _s(data['designerName'])),
      ],
    );
  }
}
