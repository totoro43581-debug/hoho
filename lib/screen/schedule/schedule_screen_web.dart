// lib/screen/schedule/schedule_screen_web.dart
// ===================================================================
// 통합일정 (Web) - 1차(UI 골격)
// - 목표A: 스크린샷 스타일의 "좌측 필터 + 월 캘린더 보드" UI 재현
// - 데이터A: Firestore 기존 컬렉션 기반(1차는 receptions 중심, 클라이언트 필터)
// - 수정1차:
//   1) 좌측 필터 패널(역할/공간/지점 + 접기 섹션) UI 구성
//   2) 월 이동/오늘 버튼 + 월/주/일/목록 토글(1차는 월만 활성)
//   3) 캘린더 6주 그리드 + 일정 카드(색상점/시간/타이틀) 렌더링
//   4) 수평/수직 스크롤 안정화(웹용)
// ===================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ScheduleScreenWeb extends StatefulWidget {
  const ScheduleScreenWeb({super.key});

  @override
  State<ScheduleScreenWeb> createState() => _ScheduleScreenWebState();
}

class _ScheduleScreenWebState extends State<ScheduleScreenWeb> {
  // ===========================
  // UI 상태(좌측 필터)
  // ===========================
  String _roleTab = '전체'; // 전체/미팅/시공/디자이너/지원
  String _spaceTab = '전체'; // 전체/주거/상업
  String _branchTab = '전체'; // 전체/수성/월성

  bool _foldProject = false;
  bool _foldManager = false;
  bool _foldCommon = false;

  // ===========================
  // 캘린더 상태
  // ===========================
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  // ===========================
  // 스타일(스크린샷 다크톤)
  // ===========================
  static const Color _bg = Color(0xFF1E1F21);
  static const Color _panel = Color(0xFF242628);
  static const Color _line = Color(0xFF34373A);
  static const Color _text = Color(0xFFEDEDED);
  static const Color _muted = Color(0xFFB9B9B9);
  static const Color _accent = Color(0xFF2DD4BF); // 필터 선택 느낌
  static const Color _chip = Color(0xFF2A2C2F);

  // ===========================
  // 데이터 모델
  // ===========================
  String s(dynamic v) => (v ?? '').toString();

  Color _parseHex(String? hex) {
    if (hex == null) return Colors.white30;
    final h = hex.trim();
    if (h.isEmpty) return Colors.white30;
    try {
      final v = h.startsWith('#') ? h.replaceFirst('#', '0xff') : '0xff$h';
      return Color(int.parse(v));
    } catch (_) {
      return Colors.white30;
    }
  }

  DateTime? _pickEventDate(Map<String, dynamic> data) {
    // 1차: 가능한 후보들을 최대한 폭넓게 읽어서 "표시"부터 되게 함
    // - reservationDateTime: 문자열("yyyy-MM-dd HH:mm") 또는 Timestamp
    // - consultReservedAt: Timestamp
    // - moveInDate / constructionDate 등 (있으면 2차에서 확정 필드로 재정의)
    final v = data['reservationDateTime'] ?? data['consultReservedAt'] ?? data['reservedAt'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) {
      // "yyyy-MM-dd HH:mm" 또는 ISO 모두 시도
      try {
        return DateTime.parse(v);
      } catch (_) {}
      try {
        return DateFormat('yyyy-MM-dd HH:mm').parseStrict(v);
      } catch (_) {}
      try {
        return DateFormat('yyyy.MM.dd HH:mm').parseStrict(v);
      } catch (_) {}
    }
    return null;
  }

  String _formatTime(DateTime dt) {
    // 오전/오후 HH시 mm분 느낌(스크린샷 근접)
    final a = dt.hour < 12 ? '오전' : '오후';
    int h = dt.hour % 12;
    if (h == 0) h = 12;
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$a $h:${mm}';
  }

  String _eventTitle(Map<String, dynamic> d) {
    // 1차: 최대한 자연스럽게
    final type = s(d['consultType'] ?? d['type'] ?? d['receptionType']).trim();
    final addr = s(d['address'] ?? d['address1'] ?? d['addr1']).trim();
    final proj = s(d['projectName'] ?? d['project'] ?? d['title']).trim();
    final name = s(d['customerName'] ?? d['name']).trim();

    final head = type.isEmpty ? '' : '[$type] ';
    final body = proj.isNotEmpty ? proj : (addr.isNotEmpty ? addr : name);
    return (head + body).trim().isEmpty ? '(제목 없음)' : (head + body).trim();
  }

  Color _eventDotColor(Map<String, dynamic> d) {
    final hex = (d['managerColor'] ?? d['color'] ?? d['assignedManagerColor'])?.toString();
    return _parseHex(hex);
  }

  // ===========================
  // 달력 계산(6주 x 7일)
  // ===========================
  List<DateTime> _buildMonthCells(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final weekday = first.weekday % 7; // Sun=0
    final start = first.subtract(Duration(days: weekday));
    return List.generate(42, (i) => DateTime(start.year, start.month, start.day + i));
  }

  void _prevMonth() {
    setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
  }

  void _nextMonth() {
    setState(() => _month = DateTime(_month.year, _month.month + 1, 1));
  }

  void _today() {
    final now = DateTime.now();
    setState(() => _month = DateTime(now.year, now.month, 1));
  }

  // ===========================
  // 좌측 필터 UI
  // ===========================
  Widget _segButton(String text, String selected, ValueChanged<String> onTap) {
    final active = text == selected;
    return InkWell(
      onTap: () => setState(() => onTap(text)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? _chip : Colors.transparent,
          border: Border.all(color: active ? _accent : _line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: active ? _accent : _muted,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _segRow(List<String> items, String selected, ValueChanged<String> onTap) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((t) => _segButton(t, selected, onTap)).toList(),
    );
  }

  Widget _foldHeader(String title, bool folded, VoidCallback onToggle) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(title, style: const TextStyle(color: _text, fontWeight: FontWeight.w800)),
            const Spacer(),
            Icon(folded ? Icons.add : Icons.remove, color: _muted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _leftPanel() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: _panel,
        border: Border(right: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('통합일정', style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),

          // 역할/업무 탭
          _segRow(const ['전체', '미팅', '시공', '디자이너', '지원'], _roleTab, (v) => _roleTab = v),
          const SizedBox(height: 12),

          // 공간/지점
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF202225),
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('공간', style: TextStyle(color: _muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _segRow(const ['전체', '주거', '상업'], _spaceTab, (v) => _spaceTab = v),
                const SizedBox(height: 10),
                const Text('지점', style: TextStyle(color: _muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _segRow(const ['전체', '수성', '월성'], _branchTab, (v) => _branchTab = v),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 접기 섹션들(1차는 UI만)
          _foldHeader('프로젝트', _foldProject, () => setState(() => _foldProject = !_foldProject)),
          if (!_foldProject) ...[
            const SizedBox(height: 8),
            _miniListPlaceholder('프로젝트 항목(2차)'),
          ],
          const SizedBox(height: 10),

          _foldHeader('매니저', _foldManager, () => setState(() => _foldManager = !_foldManager)),
          if (!_foldManager) ...[
            const SizedBox(height: 8),
            _miniListPlaceholder('매니저 항목(2차)'),
          ],
          const SizedBox(height: 10),

          _foldHeader('공용', _foldCommon, () => setState(() => _foldCommon = !_foldCommon)),
          if (!_foldCommon) ...[
            const SizedBox(height: 8),
            _miniListPlaceholder('공용 항목(2차)'),
          ],

          const SizedBox(height: 12),

          // 오늘상담(1차 UI)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF202225),
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('오늘상담', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                Text('• (1차) 오늘 목록은 2차에서 연결합니다.', style: TextStyle(color: _muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniListPlaceholder(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF202225),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(color: _muted)),
    );
  }

  // ===========================
  // 메인 헤더/범례
  // ===========================
  Widget _legendDot(Color c) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black26)),
    );
  }

  Widget _legendItem(Color dot, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _legendDot(dot),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _topHeader() {
    final title = DateFormat('yyyy년 M월').format(_month);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          // 좌: 이동 버튼
          _iconBtn(Icons.chevron_left, _prevMonth),
          const SizedBox(width: 6),
          _iconBtn(Icons.chevron_right, _nextMonth),
          const SizedBox(width: 10),
          _pillBtn('오늘', _today),

          const Spacer(),

          // 중앙 타이틀
          Text(title, style: const TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w900)),

          const Spacer(),

          // 우: 월/주/일/목록 토글(1차는 월만)
          Row(
            children: [
              _toggle('월', true),
              _toggle('주', false),
              _toggle('일', false),
              _toggle('일정목록', false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF202225),
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: _muted, size: 18),
      ),
    );
  }

  Widget _pillBtn(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF202225),
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(text, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _toggle(String text, bool active) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: active ? _chip : const Color(0xFF202225),
        border: Border.all(color: active ? _accent : _line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: active ? _accent : _muted,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _legendRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text('※ 시공항목 체크여부 확인:', style: TextStyle(color: _muted, fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(width: 12),
            _legendItem(const Color(0xFF6B7280), '아직 체크 안함'),
            const SizedBox(width: 10),
            _legendItem(const Color(0xFF22C55E), '시공전 체크완료'),
            const SizedBox(width: 10),
            _legendItem(const Color(0xFF10B981), '시공후 체크완료'),
            const SizedBox(width: 10),
            _legendItem(const Color(0xFF059669), '모두 체크 완료'),
            const SizedBox(width: 14),
            _legendItem(const Color(0xFFEF4444), '시공전 확인요망'),
            const SizedBox(width: 10),
            _legendItem(const Color(0xFFDC2626), '시공후 확인요망'),
            const SizedBox(width: 10),
            _legendItem(const Color(0xFFB91C1C), '시공진행 모두 확인요망'),
          ],
        ),
      ),
    );
  }

  // ===========================
  // 메인 캘린더 그리드
  // ===========================
  Widget _weekdayHeader() {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF202225), border: Border.all(color: _line)),
      child: Row(
        children: List.generate(7, (i) {
          return Expanded(
            child: Container(
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: i == 6 ? Colors.transparent : _line))),
              child: Text(days[i], style: const TextStyle(color: _muted, fontWeight: FontWeight.w800)),
            ),
          );
        }),
      ),
    );
  }

  bool _inMonth(DateTime d) => d.month == _month.month && d.year == _month.year;

  // 1차: 데이터가 없어도 UI를 확인할 수 있도록 “더미” 2~3개 제공(필터/정합성은 2차)
  List<_ScheduleItem> _dummyItemsForDay(DateTime day) {
    if (!_inMonth(day)) return const [];
    if (day.day % 11 != 0) return const [];
    return [
      _ScheduleItem(
        when: DateTime(day.year, day.month, day.day, 10, 0),
        title: '[상담] 대구 수성구 샘플 일정',
        dot: const Color(0xFF7C4DFF),
      ),
      _ScheduleItem(
        when: DateTime(day.year, day.month, day.day, 13, 30),
        title: '[실측] 현장 점검',
        dot: const Color(0xFF22C55E),
      ),
    ];
  }

  // Firestore -> ScheduleItem 변환(1차는 receptions 중심)
  List<_ScheduleItem> _mapDocsToItems(List<QueryDocumentSnapshot> docs) {
    final items = <_ScheduleItem>[];

    for (final doc in docs) {
      final d = (doc.data() as Map<String, dynamic>);
      final dt = _pickEventDate(d);
      if (dt == null) continue;

      // 1차 UI: 좌측 탭 필터는 “있으면 적용” (필드 없으면 통과)
      if (_roleTab != '전체') {
        final roleGuess = s(d['scheduleType'] ?? d['roleType'] ?? d['category']);
        if (roleGuess.isNotEmpty && !roleGuess.contains(_roleTab)) {
          // 필드가 있을 때만 필터링
          continue;
        }
      }
      if (_spaceTab != '전체') {
        final space = s(d['spaceType'] ?? d['spaceAuth'] ?? d['space']).toLowerCase();
        if (space.isNotEmpty) {
          final want = _spaceTab == '주거' ? '주거' : '상업';
          if (!space.contains(want)) continue;
        }
      }
      if (_branchTab != '전체') {
        final branch = s(d['branch'] ?? d['branchAuth'] ?? d['simpleRegion']).toLowerCase();
        if (branch.isNotEmpty) {
          final want = _branchTab.toLowerCase();
          if (!branch.contains(want)) continue;
        }
      }

      items.add(_ScheduleItem(
        when: dt,
        title: '${_formatTime(dt)} ${_eventTitle(d)}',
        dot: _eventDotColor(d),
      ));
    }

    // 시간순 정렬
    items.sort((a, b) => a.when.compareTo(b.when));
    return items;
  }

  Map<String, List<_ScheduleItem>> _groupByDay(List<_ScheduleItem> items) {
    final map = <String, List<_ScheduleItem>>{};
    for (final it in items) {
      final key = DateFormat('yyyy-MM-dd').format(DateTime(it.when.year, it.when.month, it.when.day));
      map.putIfAbsent(key, () => []);
      map[key]!.add(it);
    }
    return map;
  }

  Widget _calendarGrid(AsyncSnapshot<QuerySnapshot> snap) {
    final cells = _buildMonthCells(_month);

    final firestoreItems = snap.hasData ? _mapDocsToItems(snap.data!.docs) : <_ScheduleItem>[];
    // 1차: 더미를 섞어서 UI가 항상 보이게
    final allItems = <_ScheduleItem>[
      ...firestoreItems,
      ...cells.expand(_dummyItemsForDay),
    ];
    final byDay = _groupByDay(allItems);

    return Column(
      children: [
        _weekdayHeader(),
        const SizedBox(height: 0),

        // 6주 그리드
        Expanded(
          child: Scrollbar(
            controller: _vCtrl,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _vCtrl,
              child: Column(
                children: List.generate(6, (week) {
                  final rowDays = cells.sublist(week * 7, week * 7 + 7);
                  return Row(
                    children: rowDays.map((day) {
                      final key = DateFormat('yyyy-MM-dd').format(day);
                      final list = byDay[key] ?? const <_ScheduleItem>[];
                      final dim = _inMonth(day) ? 1.0 : 0.45;

                      return Expanded(
                        child: Container(
                          height: 155, // 스크린샷처럼 "많이 쌓이는" 느낌을 위해 고정 높이
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1D1F),
                            border: Border(
                              right: BorderSide(color: _line),
                              bottom: BorderSide(color: _line),
                            ),
                          ),
                          child: Opacity(
                            opacity: dim,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 날짜
                                  Row(
                                    children: [
                                      Text(
                                        '${day.day}',
                                        style: TextStyle(
                                          color: _inMonth(day) ? _text : _muted,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const Spacer(),
                                    ],
                                  ),
                                  const SizedBox(height: 6),

                                  // 일정 리스트(셀 내부 스크롤)
                                  Expanded(
                                    child: Scrollbar(
                                      controller: ScrollController(),
                                      thumbVisibility: false,
                                      child: ListView.builder(
                                        itemCount: list.length,
                                        padding: EdgeInsets.zero,
                                        itemBuilder: (context, i) {
                                          final it = list[i];
                                          return _scheduleLine(it);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scheduleLine(_ScheduleItem it) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: it.dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              it.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _text, fontSize: 11.8, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: Row(
        children: [
          _leftPanel(),

          // 우측 메인
          Expanded(
            child: Column(
              children: [
                _topHeader(),
                _legendRow(),
                const Divider(height: 1, color: _line),

                Expanded(
                  child: Scrollbar(
                    controller: _hCtrl,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _hCtrl,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        // 넓을수록 보드가 넓게(스크린샷 느낌)
                        width: MediaQuery.of(context).size.width - 280,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF202225),
                              border: Border.all(color: _line),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: StreamBuilder<QuerySnapshot>(
                              // ✅ 데이터A: 1차는 receptions 중심(인덱스/타입 혼재 방지 위해 orderBy 없이)
                              stream: FirebaseFirestore.instance
                                  .collection('receptions')
                                  .limit(500)
                                  .snapshots(),
                              builder: (context, snap) {
                                if (snap.hasError) {
                                  return Center(
                                    child: Text(
                                      '오류 발생: ${snap.error}',
                                      style: const TextStyle(color: _muted),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }
                                if (!snap.hasData) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                return _calendarGrid(snap);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleItem {
  final DateTime when;
  final String title;
  final Color dot;

  const _ScheduleItem({
    required this.when,
    required this.title,
    required this.dot,
  });
}
