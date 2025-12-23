// lib/screen/reception/reception_timeline_screen_web.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReceptionTimelineItem {
  final DateTime date;
  final String title;
  final String? description;

  ReceptionTimelineItem({
    required this.date,
    required this.title,
    this.description,
  });
}

class ReceptionTimelineScreenWeb extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onBack;
  final VoidCallback? onDetail;

  const ReceptionTimelineScreenWeb({
    super.key,
    required this.data,
    required this.onBack,
    this.onDetail,
  });

  String _s(dynamic v) => (v ?? '').toString();

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    try {
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      if (v.toString().contains('Timestamp(')) {
        final raw = v.toString();
        final sec =
        int.tryParse(raw.split('seconds=')[1].split(',').first.trim());
        return DateTime.fromMillisecondsSinceEpoch((sec ?? 0) * 1000);
      }
      if (v is Map && v.containsKey('_seconds')) {
        return DateTime.fromMillisecondsSinceEpoch(
          (v['_seconds'] as int) * 1000,
        );
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

  List<ReceptionTimelineItem> _buildTimeline() {
    final List<ReceptionTimelineItem> items = [];

    final createdAt = _asDate(data['createdAt']);
    if (createdAt != null) {
      items.add(
        ReceptionTimelineItem(
          date: createdAt,
          title: '접수 등록',
          description: '접수가 시스템에 등록되었습니다.',
        ),
      );
    }

    final resDate = _asDate(data['reservationDateTime']);
    if (resDate != null) {
      items.add(
        ReceptionTimelineItem(
          date: resDate,
          title: '상담 예약',
          description:
          '상담방법: ${_s(data['consultMethod']).isEmpty ? '미지정' : _s(data['consultMethod'])}',
        ),
      );
    }

    final start = _asDate(data['constructStart']);
    final end = _asDate(data['constructEnd']);
    if (start != null || end != null) {
      items.add(
        ReceptionTimelineItem(
          date: start ?? end!,
          title: '시공 예정',
          description:
          '${_fmt(start, onlyDate: true)} ~ ${_fmt(end, onlyDate: true)}',
        ),
      );
    }

    final moveIn = _asDate(data['moveInDate']);
    if (moveIn != null) {
      items.add(
        ReceptionTimelineItem(
          date: moveIn,
          title: '입주 예정',
          description: _fmt(moveIn, onlyDate: true),
        ),
      );
    }

    final updatedAt = _asDate(data['updatedAt']);
    if (updatedAt != null) {
      items.add(
        ReceptionTimelineItem(
          date: updatedAt,
          title: '마지막 수정',
          description: '상담/시공 정보가 수정되었습니다.',
        ),
      );
    }

    final rounds = data['consultRounds'];
    if (rounds is List) {
      for (int i = 0; i < rounds.length; i++) {
        final r = rounds[i];
        if (r is Map) {
          final dt = _asDate(r['dateTime']);
          final method = _s(r['method']);
          if (dt != null) {
            items.add(
              ReceptionTimelineItem(
                date: dt,
                title: '${i + 1}차 상담',
                description:
                method.isEmpty ? null : '상담방법: $method',
              ),
            );
          }
        }
      }
    }

    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  Widget _buildTimelineList() {
    final items = _buildTimeline();
    if (items.isEmpty) {
      return const Center(child: Text('타임라인 정보가 없습니다.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(items.length, (i) {
        final e = items[i];
        final isLast = i == items.length - 1;

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
                      color:
                      isLast ? const Color(0xFF6366F1) : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 40,
                      color: const Color(0xFFE5E7EB),
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
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (e.description != null &&
                        e.description!.trim().isNotEmpty)
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
    _s(data['project']).isEmpty ? '상담 타임라인' : '상담 타임라인 - ${_s(data['project'])}';

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 10,
                      color: Color(0x16000000),
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: _buildTimelineList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onBack,
                  child: const Text('목록으로'),
                ),
                const SizedBox(width: 8),
                if (onDetail != null)
                  FilledButton(
                    onPressed: onDetail,
                    child: const Text('상세보기'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
