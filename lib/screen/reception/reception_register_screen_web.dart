// lib/screen/reception/reception_register_screen_web.dart
// ============================================================================
// ReceptionRegisterScreenWeb — 접수 등록 & 수정(웹 전용)
// - 등록폼에는 '상담 차수' 섹션 미표시
// - 수정폼에는 '상담 차수' 섹션 표시(1차 + 차수 추가 UI)
// - 담당자 드롭다운(상담/계약담당자, 현장 정담당자, 현장 부담당자, 디자이너)은
//   Firestore users 컬렉션 연동. 드롭다운 value = String(id) 로 통일하여
//   재진입(수정 화면) 시 DropdownButton의 value 매칭 에러를 방지.
// ============================================================================

import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ----------------------------------------------------------------------------
// (A) 가벼운 사용자 뷰모델: 드롭다운은 문자열 id만 value로 사용
// ----------------------------------------------------------------------------
class _UserLite {
  final String id;
  final String name;
  final String? email;
  const _UserLite({required this.id, required this.name, this.email});
}

// ----------------------------------------------------------------------------
// (B) 상담 차수(수정폼 전용) 모델
// consultRounds: [{ "dateTime": ISO8601, "method": "전화상담" }, ...]
// ----------------------------------------------------------------------------
class _ConsultRound {
  DateTime date;
  String method;

  _ConsultRound({required this.date, required this.method});

  Map<String, dynamic> toMap() => {
        'dateTime': date.toIso8601String(),
        'method': method,
      };

  static _ConsultRound? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final ds = (raw['dateTime'] ?? '').toString();
      final ms = (raw['method'] ?? '').toString();
      if (ds.isEmpty || ms.isEmpty) return null;
      return _ConsultRound(date: DateTime.parse(ds), method: ms);
    } catch (_) {
      return null;
    }
  }
}

/// 드롭다운에 쓰는 사용자 옵션 (문서 밖, top-level)
class UserOption {
  final String id; // users 문서 id (또는 uid)
  final String name; // 표시용 이름
  final String? email; // (있으면 저장)

  const UserOption({required this.id, required this.name, this.email});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (email != null) 'email': email,
      };

  static UserOption? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    final name = (raw['name'] ?? '').toString();
    if (id.isEmpty || name.isEmpty) return null;
    return UserOption(
        id: id, name: name, email: (raw['email'] ?? '').toString());
  }
}

// 간단 월 더하기/빼기
DateTime _addMonths(DateTime base, int add) {
  final y = base.year + ((base.month - 1 + add) ~/ 12);
  final m = ((base.month - 1 + add) % 12) + 1;
  return DateTime(y, m, 1);
}

class ReceptionRegisterScreenWeb extends StatefulWidget {
  final VoidCallback onCancel;
  final void Function(Map<String, dynamic> data)? onSubmit;

  /// 편집할 문서 id (null => 신규 등록)
  final String? editingDocId;

  const ReceptionRegisterScreenWeb({
    super.key,
    required this.onCancel,
    this.onSubmit,
    this.editingDocId,
  });

  @override
  State<ReceptionRegisterScreenWeb> createState() =>
      _ReceptionRegisterScreenWebState();
}

class _ReceptionRegisterScreenWebState
    extends State<ReceptionRegisterScreenWeb> {
  // == 편집 모드 여부
  bool get _isEdit => widget.editingDocId != null;

  // == 카카오 콜백 접근용 별칭
  TextEditingController get _address1Controller => _addr1;
  TextEditingController get _address2Controller => _addr2;
  TextEditingController get _projectNameController => _project;

  // setState 지연 적용(마우스 트래커 경고 회피)
  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) super.setState(fn);
    });
  }

  // ===== 컨트롤러 & 상태 =====
  String? _receptionSource;
  String? _type;
  final TextEditingController _phone1 = TextEditingController();
  final TextEditingController _phone2 = TextEditingController();
  String? _region;
  String? _branch = '미지정';
  final TextEditingController _project = TextEditingController();

  // 주소
  final TextEditingController _addr1 = TextEditingController();
  final TextEditingController _addr2 = TextEditingController();

  // 평수
  final TextEditingController _area = TextEditingController();

  // 공실여부
  String? _emptyStatus;

  // 일정
  DateTimeRange? _constructRange; // 시공예정일(기간)
  DateTime? _moveInDate; // 입주예정일(단일)

  // 상담예약(날짜+시간)
  DateTime? _reservationDate;
  int _reservationHour = 14;
  int _reservationMinute = 30;

  // 상담요청 메모
  final TextEditingController _memo = TextEditingController(
    text: '공실여부:\n\n공실일정:\n\n시공일정:\n\n입주일정:\n\n시공예산:\n',
  );

  // 상담방법/상담자/고객명
  String? _consultMethod;
  final String _firstCounselor = '지영환';
  final TextEditingController _customerName = TextEditingController();

  // UI 보조
  bool _saving = false;
  bool _showAddrHint = false;
  bool _loadingEdit = false;

  // 카카오 팝업 메시지 수신
  html.EventListener? _popupListener;

  // 현재 떠있는 팝오버
  OverlayEntry? _currentPopover;

  // 프로젝트명 자동 채우기 추적
  bool _projectUserEdited = false; // 사용자가 직접 수정했는지
  bool _settingProject = false; // 코드가 자동으로 넣는 중인지

  // ===== [수정폼 전용] 상담 차수 상태 =====
  final List<_ConsultRound> _rounds = []; // 1차/2차 ... 데이터
  final List<GlobalKey> _roundKeys = []; // 각 차수의 날짜/시간 선택용 앵커 키

  void _addRound({_ConsultRound? initial}) {
    setState(() {
      _rounds.add(
        initial ??
            _ConsultRound(
              date: DateTime.now(),
              method: _consultMethods.first,
            ),
      );
      _roundKeys.add(GlobalKey());
    });
  }

  void _removeRound(int i) {
    setState(() {
      if (i >= 0 && i < _rounds.length) {
        _rounds.removeAt(i);
        _roundKeys.removeAt(i);
      }
    });
  }

  // ===== 담당자 드롭다운용 상태 (id만 보관) =====
  List<_UserLite> _userOptions = [];
  Map<String, _UserLite> _userById = {};
  String? _managerId; // 상담/계약담당자
  String? _siteMainId; // 현장 정담당자
  String? _siteSubId; // 현장 부담당자
  String? _designerId; // 디자이너

  // ===== 옵션들 =====
  final List<String> _receptionSources = const [
    '채널톡',
    '오늘의집',
    '쇼룸방문',
    '지인',
    '인터넷검색',
  ];
  final List<String> _types = const ['주거공간', '상업공간'];
  final List<String> _regions = const ['대구/경북', '부산/경남', '그외지역'];
  final List<String> _branches = const ['미지정', '시지·경산', '월성', '수성못', '침산'];
  final List<String> _emptyOptions = const ['공실', '주거중', '세입자', '계약전'];
  final List<String> _consultMethods = const [
    '전화상담',
    '시지·경산점',
    '월성점',
    '수성못',
    '침산점',
    '현장실측',
    '기타',
    '취소',
  ];

  // ===== 라이프사이클 =====
  @override
  void initState() {
    super.initState();

    _phone1.addListener(() => _applyPhoneMask(_phone1));
    _phone2.addListener(() => _applyPhoneMask(_phone2));

    if (kIsWeb) {
      _popupListener = (html.Event e) {
        try {
          final me = e as html.MessageEvent;
          if (me.data is String) {
            final obj = jsonDecode(me.data as String);
            if (obj is Map &&
                (obj['type'] == 'kakao-postcode-result' ||
                    obj['type'] == 'postcode_result')) {
              final address = (obj['address'] ?? '') as String;
              final building = (obj['buildingName'] ?? '') as String;

              final combined =
                  building.isNotEmpty ? '$address ($building)' : address;
              _address1Controller.text = combined;

              // 프로젝트명 자동 채우기 (빌딩명)
              final current = _projectNameController.text.trim();
              final canOverwrite = !_projectUserEdited || current.isEmpty;

              if (building.isNotEmpty && canOverwrite) {
                _settingProject = true;
                _projectNameController.text = building;
                _settingProject = false;
                if (mounted) setState(() {});
              }

              setState(() => _showAddrHint = false);
            }
          }
        } catch (_) {}
      };
      html.window.addEventListener('message', _popupListener);
    }

    // 사용자 목록 먼저 로딩 (드롭다운)
    _loadUserOptions();

    // 수정 모드면 기존 데이터 로드
    if (_isEdit) _loadEditDocument();
    _loadUserOptions();
  }

  @override
  void dispose() {
    _removePopover();
    if (_popupListener != null) {
      html.window.removeEventListener('message', _popupListener);
      _popupListener = null;
    }
    _phone1.dispose();
    _phone2.dispose();
    _project.dispose();
    _addr1.dispose();
    _addr2.dispose();
    _area.dispose();
    _memo.dispose();
    _customerName.dispose();
    super.dispose();
  }

  // ===== 유틸 =====
  void _applyPhoneMask(TextEditingController c) {
    final d = c.text.replaceAll(RegExp(r'[^0-9]'), '');
    String f;
    if (d.startsWith('02')) {
      if (d.length <= 2) {
        f = d;
      } else if (d.length <= 5) {
        f = '${d.substring(0, 2)}-${d.substring(2)}';
      } else if (d.length <= 9) {
        f = '${d.substring(0, 2)}-${d.substring(2, 5)}-${d.substring(5)}';
      } else {
        f = '${d.substring(0, 2)}-${d.substring(2, 6)}-${d.substring(6, 10)}';
      }
    } else {
      if (d.length <= 3) {
        f = d;
      } else if (d.length <= 7) {
        f = '${d.substring(0, 3)}-${d.substring(3)}';
      } else if (d.length <= 11) {
        f = '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7)}';
      } else {
        f = '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7, 11)}';
      }
    }
    if (c.text != f) {
      c.value = TextEditingValue(
        text: f,
        selection: TextSelection.collapsed(offset: f.length),
      );
      setState(() {});
    }
  }

  void _openKakaoPopup() {
    if (!kIsWeb) return;
    setState(() => _showAddrHint = true);
    html.window.open(
      '/kakao_postcode.html',
      'kakao_postcode',
      'width=520,height=640,menubar=no,toolbar=no,location=no,status=no',
    );
  }

  Future<void> _loadUserOptions() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('users')
          // 운영 전환 시 A안(권장): .where('isActive', isEqualTo: true)
          .get();

      final list = <_UserLite>[];
      for (final d in qs.docs) {
        final data = d.data();
        final name = (data['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        list.add(_UserLite(
          id: d.id,
          name: name,
          email: (data['email'] ?? '').toString(),
        ));
      }

      final dedup = {for (final u in list) u.id: u}.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _userOptions = dedup;
        _userById = {for (final u in dedup) u.id: u};

        if (_managerId != null && !_userById.containsKey(_managerId!))
          _managerId = null;
        if (_siteMainId != null && !_userById.containsKey(_siteMainId!))
          _siteMainId = null;
        if (_siteSubId != null && !_userById.containsKey(_siteSubId!))
          _siteSubId = null;
        if (_designerId != null && !_userById.containsKey(_designerId!))
          _designerId = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사용자 목록 불러오기 실패: $e')),
      );
    }
  }

  // ===== 검증 =====
  bool get _valid {
    final phoneOk = _phone1.text.replaceAll(RegExp(r'[^0-9]'), '').length >= 9;

    // ✅ 수정1차: "접수등록(신규)"에서는 시공/입주예정일을 필수에서 제외
    final bool constructOk = _isEdit ? (_constructRange != null) : true;
    final bool moveInOk = _isEdit ? (_moveInDate != null) : true;

    return (_receptionSource != null) &&
        (_type != null) &&
        phoneOk &&
        (_region != null) &&
        (_branch != null) &&
        _projectNameController.text.trim().isNotEmpty &&
        _address1Controller.text.trim().isNotEmpty &&
        _address2Controller.text.trim().isNotEmpty &&
        _area.text.trim().isNotEmpty &&
        (_emptyStatus != null) &&
        constructOk && // ✅ 수정1차
        moveInOk && // ✅ 수정1차
        (_consultMethod != null) &&
        (_reservationDate != null) &&
        _memo.text.trim().isNotEmpty &&
        _customerName.text.trim().isNotEmpty;    // 담당자 4개는 선택 필수로 두지 않았습니다. (원하면 여기에 && _managerId != null 등 추가)
  }

  // ===== 저장 =====
  Future<void> _submit() async {
    if (!_valid) return;
    setState(() => _saving = true);

    final reservation = DateTime(
      _reservationDate!.year,
      _reservationDate!.month,
      _reservationDate!.day,
      _reservationHour,
      _reservationMinute,
    );

    final map = <String, dynamic>{
      'receptionSource': _receptionSource,
      'type': _type,
      'phone1': _phone1.text,
      'phone2': _phone2.text,
      'region': _region,
      'branch': _branch,
      'project': _projectNameController.text.trim(),
      'address1': _address1Controller.text.trim(),
      'address2': _address2Controller.text.trim(),
      'area': _area.text.trim(),
      'emptyStatus': _emptyStatus,

      // 일정
      'constructStart': _constructRange?.start.toIso8601String(),
      'constructEnd': _constructRange?.end.toIso8601String(),
      'moveInDate': _moveInDate?.toIso8601String(),

      // 상담 예약
      'reservationDateTime': reservation.toIso8601String(),
      'consultMethod': _consultMethod,

      'memo': _memo.text.trim(),
      'firstCounselor': _firstCounselor,
      'customerName': _customerName.text.trim(),

      // 담당자 저장 (id + name 복제 저장)
      'managerId': _managerId,
      'managerName': _userById[_managerId]?.name,
      'siteMainId': _siteMainId,
      'siteMainName': _userById[_siteMainId]?.name,
      'siteSubId': _siteSubId,
      'siteSubName': _userById[_siteSubId]?.name,
      'designerId': _designerId,
      'designerName': _userById[_designerId]?.name,

      //삭제기능
      'isDeleted': false,
      'deletedAt': null,
      
      'isConsultTarget':
          _selectedManagerId != null && _selectedManagerId!.isNotEmpty,

      // (수정폼 전용) 상담 차수
      if (_isEdit) 'consultRounds': _rounds.map((r) => r.toMap()).toList(),
    };

    try {
      if (_isEdit) {
        await FirebaseFirestore.instance
            .collection('receptions')
            .doc(widget.editingDocId)
            .update({
          ...map,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (widget.onSubmit != null) {
          await Future.sync(
              () => widget.onSubmit!({...map, 'id': widget.editingDocId}));
        }
      } else {
        final docRef =
            await FirebaseFirestore.instance.collection('receptions').add({
          ...map,
          'createdAtTs': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'createdAtIso': DateTime.now().toIso8601String(),
          'status': 'new',
        });

        await docRef.update({'id': docRef.id});
        if (widget.onSubmit != null) {
          await Future.sync(() => widget.onSubmit!({...map, 'id': docRef.id}));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? '수정 완료' : '접수등록 완료')),
      );
      widget.onCancel();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      setState(() => _saving = false);
    }
  }

  Future<void> _loadEditDocument() async {
    setState(() => _loadingEdit = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('receptions')
          .doc(widget.editingDocId)
          .get();

      if (!snap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('문서를 찾을 수 없습니다.')),
          );
          widget.onCancel();
        }
        return;
      }

      final d = snap.data()!;

      // ===== 텍스트/선택 값 =====
      _receptionSource = d['receptionSource'];
      _type = d['type'];
      _phone1.text = (d['phone1'] ?? '').toString();
      _phone2.text = (d['phone2'] ?? '').toString();
      _region = d['region'];
      _branch = d['branch'];
      _project.text = (d['project'] ?? '').toString();
      _addr1.text = (d['address1'] ?? '').toString();
      _addr2.text = (d['address2'] ?? '').toString();
      _area.text = (d['area'] ?? '').toString();
      _emptyStatus = d['emptyStatus'];
      _consultMethod = d['consultMethod'];
      _memo.text = (d['memo'] ?? '').toString();
      _customerName.text = (d['customerName'] ?? '').toString();

      // ===== 일정 =====
      DateTime? _parseIso(dynamic v) {
        if (v == null) return null;
        try {
          return DateTime.parse(v.toString());
        } catch (_) {
          return null;
        }
      }

      final cs = _parseIso(d['constructStart']);
      final ce = _parseIso(d['constructEnd']);
      if (cs != null && ce != null) {
        _constructRange = DateTimeRange(
          start: DateTime(cs.year, cs.month, cs.day),
          end: DateTime(ce.year, ce.month, ce.day),
        );
      }

      final md = _parseIso(d['moveInDate']);
      if (md != null) {
        _moveInDate = DateTime(md.year, md.month, md.day);
      }

      final rdt = _parseIso(d['reservationDateTime']);
      if (rdt != null) {
        _reservationDate = DateTime(rdt.year, rdt.month, rdt.day);
        _reservationHour = rdt.hour;
        _reservationMinute = rdt.minute;
      }

      // ===== 담당자 id =====
      _managerId = d['managerId']?.toString();
      _siteMainId = d['siteMainId']?.toString();
      _siteSubId = d['siteSubId']?.toString();
      _designerId = d['designerId']?.toString();

      // ===== 상담 차수 =====
      _rounds.clear();
      _roundKeys.clear();
      if (d['consultRounds'] is List) {
        for (final item in (d['consultRounds'] as List)) {
          final r = _ConsultRound.fromMap(item);
          if (r != null) {
            _rounds.add(r);
            _roundKeys.add(GlobalKey());
          }
        }
      }
      if (_rounds.isEmpty) {
        _addRound(); // 기본 1차
      }

      if (mounted) setState(() => _loadingEdit = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingEdit = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('불러오기 실패: $e')));
      widget.onCancel();
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    if (_isEdit && _loadingEdit) {
      return const Center(child: CircularProgressIndicator());
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: dark ? Colors.grey[300] : Colors.grey[800],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Card(
            margin: EdgeInsets.zero,
            color: dark ? const Color(0xFF101213) : Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: dark ? const Color(0xFF2A2B2E) : const Color(0xFFE6E6EA),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _form(labelStyle),
            ),
          ),
        ),
      ),
    );
  }

  final _keyConstruct = GlobalKey();
  final _keyMoveIn = GlobalKey();
  final _keyReserve = GlobalKey();

  get _selectedManagerId => null;

  Widget _form(TextStyle labelStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 접수유형
        _row(
          '접수유형',
          labelStyle,
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: _receptionSources
                .map(
                  (e) => _radioChip(
                    groupValue: _receptionSource,
                    value: e,
                    onChanged: (v) => setState(() => _receptionSource = v),
                    label: e,
                  ),
                )
                .toList(),
          ),
        ),
        _divider(),

        // (수정폼 전용) 상담 차수 섹션
        if (_isEdit) ...[
          _row(
            '상담 차수',
            labelStyle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1차(기존 예약일시 + 상담방법 묶음)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '1차',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dateFieldAnchor(
                            key: _keyReserve,
                            text: _reservationDate == null
                                ? ''
                                : '${DateFormat('yyyy-MM-dd').format(_reservationDate!)} '
                                    '${_twod(_reservationHour)}:${_twod(_reservationMinute)}',
                            hint: '상담일시 선택',
                            onTap: () => _showDateTimePopover(
                              anchorKey: _keyReserve,
                              initialDate: _reservationDate,
                              initialHour: _reservationHour,
                              initialMinute: _reservationMinute,
                              onPicked: (d, h, m) {
                                setState(() {
                                  _reservationDate = d;
                                  _reservationHour = h;
                                  _reservationMinute = m;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 32,
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _reservationDate = null;
                                  _reservationHour = 14;
                                  _reservationMinute = 30;
                                });
                              },
                              child: const Text('초기화',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: _consultMethods
                            .map(
                              (e) => _radioChip(
                                groupValue: _consultMethod,
                                value: e,
                                onChanged: (v) =>
                                    setState(() => _consultMethod = v),
                                label: e,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // (추가 차수 리스트)
                ...List.generate(_rounds.length, (i) {
                  final r = _rounds[i];
                  final key = _roundKeys[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE6E6EA)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${i + 2}차',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _dateFieldAnchor(
                            key: key,
                            text: DateFormat('yyyy-MM-dd HH:mm').format(r.date),
                            hint: '날짜/시간',
                            onTap: () => _showDateTimePopover(
                              anchorKey: key,
                              initialDate: DateTime(
                                  r.date.year, r.date.month, r.date.day),
                              initialHour: r.date.hour,
                              initialMinute: r.date.minute,
                              onPicked: (d, h, m) {
                                setState(() {
                                  r.date =
                                      DateTime(d.year, d.month, d.day, h, m);
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _MenuField<String>(
                            label: '상담방법',
                            value: r.method,
                            items: _consultMethods,
                            toText: (v) => v,
                            onSelected: (v) => setState(() => r.method = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '삭제',
                          onPressed: () => _removeRound(i),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  );
                }),

                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _addRound,
                    icon: const Icon(Icons.add),
                    label: const Text('차수 추가'),
                  ),
                ),
              ],
            ),
          ),
          _divider(),
        ],

        // === 담당자 4개 드롭다운 (등록/수정 공통) ===
        if (_isEdit) ...[
          _row(
            '상담/계약담당자',
            labelStyle,
            child: _userDropdown(
              label: '선택해 주세요',
              valueId: _managerId,
              onChanged: (v) => _managerId = v,
            ),
          ),
          _divider(),
          _row(
            '현장 정담당자',
            labelStyle,
            child: _userDropdown(
              label: '선택해 주세요',
              valueId: _siteMainId,
              onChanged: (v) => _siteMainId = v,
            ),
          ),
          _divider(),
          _row(
            '현장 부담당자',
            labelStyle,
            child: _userDropdown(
              label: '선택해 주세요',
              valueId: _siteSubId,
              onChanged: (v) => _siteSubId = v,
            ),
          ),
          _divider(),
          _row(
            '디자이너',
            labelStyle,
            child: _userDropdown(
              label: '선택해 주세요',
              valueId: _designerId,
              onChanged: (v) => _designerId = v,
            ),
          ),
          _divider(),
        ],
        // 유형
        _row(
          '유형',
          labelStyle,
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: _types
                .map(
                  (e) => _radioChip(
                    groupValue: _type,
                    value: e,
                    onChanged: (v) => setState(() => _type = v),
                    label: e,
                  ),
                )
                .toList(),
          ),
        ),
        _divider(),

        // 고객연락처
        _row(
          '고객연락처',
          labelStyle,
          child: Row(
            children: [
              Expanded(
                child: _tf(
                  _phone1,
                  hint: '고객연락처(000-0000-0000)',
                  inputType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tf(
                  _phone2,
                  hint: '고객연락처(000-0000-0000)',
                  inputType: TextInputType.phone,
                ),
              ),
            ],
          ),
        ),
        _divider(),

        // 간편지역
        _row(
          '간편지역',
          labelStyle,
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: _regions
                .map(
                  (e) => _radioChip(
                    groupValue: _region,
                    value: e,
                    onChanged: (v) => setState(() => _region = v),
                    label: e,
                  ),
                )
                .toList(),
          ),
        ),
        _divider(),

        // 지점
        _row(
          '지점',
          labelStyle,
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: _branches
                .map(
                  (e) => _radioChip(
                    groupValue: _branch,
                    value: e,
                    onChanged: (v) => setState(() => _branch = v),
                    label: e,
                    selectedColor: Colors.black,
                  ),
                )
                .toList(),
          ),
        ),
        _divider(),

        // 프로젝트명
        _row(
          '프로젝트명',
          labelStyle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _openKakaoPopup,
                behavior: HitTestBehavior.opaque,
                child: AbsorbPointer(
                  absorbing: false,
                  child: _tf(
                    _projectNameController,
                    hint: '아파트명/빌딩-상가명/동',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '- 아파트 동/호수 및 번지 정보를 입력하지 마세요!!',
                style: TextStyle(color: Colors.red[400], fontSize: 12),
              ),
            ],
          ),
        ),
        _divider(),

        // 주소
        _row(
          '주소',
          labelStyle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _openKakaoPopup,
                      behavior: HitTestBehavior.opaque,
                      child: AbsorbPointer(
                        child: _tf(
                          _address1Controller,
                          hint: '주소1 (자동: 도로명주소 (빌딩명))',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      onPressed: _openKakaoPopup,
                      child: const Text('주소검색'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _tf(
                _address2Controller,
                hint: '주소2 (상세주소: 동/호, 번지 등 직접 입력)',
              ),
              const SizedBox(height: 6),
              Text(
                '- 상세주소에 동/호수 및 번지를 입력하세요.',
                style: TextStyle(color: Colors.red[300], fontSize: 12),
              ),
              if (_showAddrHint)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '팝업에서 주소 선택 후 자동 입력됩니다.',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
            ],
          ),
        ),
        _divider(),

        // 평수
        _row(
          '평수',
          labelStyle,
          child: _tf(
            _area,
            hint: '평수',
            inputType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        _divider(),

        // 공실여부
        _row(
          '공실여부',
          labelStyle,
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: _emptyOptions
                .map(
                  (e) => _radioChip(
                    groupValue: _emptyStatus,
                    value: e,
                    onChanged: (v) => setState(() => _emptyStatus = v),
                    label: e,
                  ),
                )
                .toList(),
          ),
        ),
        _divider(),

        // 시공예정일
        _row(
          '시공예정일',
          labelStyle,
          child: Row(
            children: [
              Expanded(
                child: _dateFieldAnchor(
                  key: _keyConstruct,
                  text: _constructRange == null
                      ? ''
                      : '${DateFormat('yyyy-MM-dd').format(_constructRange!.start)} ~ '
                          '${DateFormat('yyyy-MM-dd').format(_constructRange!.end)}',
                  hint: '시공예정일(시작~종료)',
                  onTap: () => _showRangePopoverSynced(
                    anchorKey: _keyConstruct,
                    initial: _constructRange,
                    onPicked: (r) => setState(() => _constructRange = r),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _resetButton(
                onPressed: () => setState(() => _constructRange = null),
              ),
            ],
          ),
        ),
        _divider(),

        // 입주예정일
        _row(
          '입주예정일',
          labelStyle,
          child: Row(
            children: [
              Expanded(
                child: _dateFieldAnchor(
                  key: _keyMoveIn,
                  text: _moveInDate == null
                      ? ''
                      : DateFormat('yyyy-MM-dd').format(_moveInDate!),
                  hint: '입주예정일',
                  onTap: () => _showSingleDatePopover(
                    anchorKey: _keyMoveIn,
                    initial: _moveInDate,
                    onPicked: (d) => setState(() => _moveInDate = d),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _resetButton(
                onPressed: () => setState(() => _moveInDate = null),
              ),
            ],
          ),
        ),
        _divider(),

        // 상담요청
        _row(
          '상담요청',
          labelStyle,
          child: SizedBox(
            height: 240,
            child: TextField(
              controller: _memo,
              expands: true,
              maxLines: null,
              minLines: null,
              decoration: _decoration(),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        _divider(),

        // (등록폼 전용) 상담 예약/방법 — 수정폼에서는 위의 1차 블럭에서 이미 노출됨
        if (!_isEdit) ...[
          _row(
            '상담 예약일',
            labelStyle,
            child: Row(
              children: [
                Expanded(
                  child: _dateFieldAnchor(
                    key: _keyReserve,
                    text: _reservationDate == null
                        ? ''
                        : '${DateFormat('yyyy-MM-dd').format(_reservationDate!)} '
                            '${_twod(_reservationHour)}:${_twod(_reservationMinute)}',
                    hint: '상담예약일시',
                    onTap: () => _showDateTimePopover(
                      anchorKey: _keyReserve,
                      initialDate: _reservationDate,
                      initialHour: _reservationHour,
                      initialMinute: _reservationMinute,
                      onPicked: (d, h, m) {
                        setState(() {
                          _reservationDate = d;
                          _reservationHour = h;
                          _reservationMinute = m;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _resetButton(onPressed: () {
                  setState(() {
                    _reservationDate = null;
                    _reservationHour = 14;
                    _reservationMinute = 30;
                  });
                }),
              ],
            ),
          ),
          _divider(),
          _row(
            '상담방법',
            labelStyle,
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              children: _consultMethods
                  .map(
                    (e) => _radioChip(
                      groupValue: _consultMethod,
                      value: e,
                      onChanged: (v) => setState(() => _consultMethod = v),
                      label: e,
                    ),
                  )
                  .toList(),
            ),
          ),
          _divider(),
        ],

        _row('최초상담자', labelStyle, child: Text(_firstCounselor)),
        _divider(),
        _row('고객명', labelStyle, child: _tf(_customerName, hint: '고객명')),
        const SizedBox(height: 18),

        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _saving ? null : widget.onCancel,
              child: Text(_isEdit ? '수정취소' : '접수취소'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (!_saving && _valid) ? _submit : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? '수정완료' : '접수등록'),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------- 공용 입력/레이블 ----------------
  Widget _row(String label, TextStyle labelStyle, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(label, style: labelStyle),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 24, thickness: 1, color: Color(0x22FFFFFF));

  Widget _tf(
    TextEditingController c, {
    String? hint,
    TextInputType? inputType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: c,
      keyboardType: inputType,
      inputFormatters: inputFormatters,
      decoration: _decoration(hintText: hint),
      onChanged: (_) => setState(() {
        // 사용자가 프로젝트명 직접 수정했는지 체크
        if (c == _projectNameController && !_settingProject) {
          _projectUserEdited = true;
        }
      }),
    );
  }

  InputDecoration _decoration({String? hintText}) => const InputDecoration(
        hintText: '',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ).copyWith(hintText: hintText);

  Widget _radioChip({
    required String? groupValue,
    required String value,
    required ValueChanged<String?> onChanged,
    required String label,
    Color? selectedColor,
  }) {
    final selected = groupValue == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? (selectedColor ?? Colors.black) : Colors.black45,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }

  // == 담당자 드롭다운 공용 위젯 (value, items 모두 String id)
  Widget _userDropdown({
    required String label,
    required String? valueId,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: valueId, // String? id
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ).copyWith(labelText: label),
      items: _userOptions.map((u) {
        return DropdownMenuItem<String>(
          value: u.id,
          child: Text(u.name),
        );
      }).toList(),
      onChanged: (v) => setState(() => onChanged(v)),
    );
  }

  // ---------------- 팝오버/캘린더 ----------------
  Widget _dateFieldAnchor({
    required Key key,
    required String text,
    required String hint,
    required VoidCallback onTap,
  }) {
    final showPlaceholder = text.isEmpty;
    return InkWell(
      key: key,
      onTap: onTap,
      child: InputDecorator(
        decoration: _decoration().copyWith(hintText: null),
        isEmpty: showPlaceholder,
        child: Row(
          children: [
            Expanded(
              child: Text(
                showPlaceholder ? hint : text,
                style: TextStyle(
                  color: showPlaceholder ? Colors.black45 : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.calendar_today, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _resetButton({required VoidCallback onPressed}) {
    return SizedBox(
      height: 40,
      child: OutlinedButton(onPressed: onPressed, child: const Text('초기화')),
    );
  }

  void _removePopover() {
    _DropdownOverlayRegistry.closeAll();
    _currentPopover?.remove();
    _currentPopover = null;
  }

  Rect _anchorRect(GlobalKey key) {
    final box = key.currentContext!.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }

  OverlayEntry _buildPopover({
    required Rect anchor,
    required double preferredWidth,
    double? preferredHeight,
    required Widget content,
  }) {
    _DropdownOverlayRegistry.closeAll();

    final media = MediaQuery.of(context);
    final viewW = media.size.width;
    final viewH = media.size.height;

    const margin = 12.0;
    final desiredH = (preferredHeight ?? 480).toDouble();
    final belowTop = anchor.bottom + 6;
    final spaceBelow = viewH - belowTop - margin;
    final spaceAbove = anchor.top - margin;

    double top;
    if (spaceBelow >= desiredH) {
      top = belowTop;
    } else if (spaceAbove >= desiredH) {
      top = anchor.top - 6 - desiredH;
    } else {
      top = (viewH - desiredH) / 2;
    }

    final left = (anchor.left + preferredWidth + 8 > viewW)
        ? (viewW - preferredWidth - margin)
        : anchor.left;

    final maxH = desiredH.clamp(280.0, viewH - margin * 2);

    return OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _removePopover,
                child: const SizedBox.shrink(),
              ),
            ),
            Positioned(
              left: left.clamp(margin, viewW - preferredWidth - margin),
              top: top.clamp(margin, viewH - margin),
              child: Material(
                elevation: 12,
                color: Colors.white,
                clipBehavior: Clip.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFE6E6EA)),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: preferredWidth,
                    maxWidth: preferredWidth,
                    minHeight: maxH,
                    maxHeight: maxH,
                  ),
                  child: SingleChildScrollView(child: content),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSingleDatePopover({
    required GlobalKey anchorKey,
    required DateTime? initial,
    required ValueChanged<DateTime> onPicked,
  }) {
    _removePopover();
    final anchor = _anchorRect(anchorKey);
    DateTime temp = initial ?? DateTime.now();

    final content = SizedBox(
      width: 420,
      child: Column(
        children: [
          _popoverHeader('입주예정일 선택'),
          CalendarDatePicker(
            initialDate: temp,
            firstDate: DateTime(DateTime.now().year - 2),
            lastDate: DateTime(DateTime.now().year + 3),
            onDateChanged: (d) => temp = DateTime(d.year, d.month, d.day),
          ),
          _popoverActions(
            onOk: () {
              onPicked(temp);
              _removePopover();
            },
          ),
        ],
      ),
    );

    _currentPopover = _buildPopover(
      anchor: anchor,
      preferredWidth: 420,
      preferredHeight: 480,
      content: content,
    );
    Overlay.of(context).insert(_currentPopover!);
  }

  void _showRangePopoverSynced({
    required GlobalKey anchorKey,
    required DateTimeRange? initial,
    required ValueChanged<DateTimeRange> onPicked,
  }) {
    _removePopover();
    final anchor = _anchorRect(anchorKey);

    DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

    final now = DateTime.now();
    DateTimeRange temp = initial ??
        DateTimeRange(
          start: _d(now),
          end: _d(now.add(const Duration(days: 1))),
        );

    DateTime? startSel = _d(temp.start);
    DateTime? endSel = _d(temp.end);
    bool pickingStart = endSel == null;

    DateTime leftMonth =
        DateTime((startSel ?? now).year, (startSel ?? now).month, 1);
    DateTime rightMonth = _addMonths(leftMonth, 1);

    void handlePick(StateSetter setSB, DateTime d) {
      final picked = _d(d);
      if (pickingStart || startSel == null) {
        startSel = picked;
        endSel = null;
        pickingStart = false;
      } else {
        if (picked.isBefore(startSel!)) {
          startSel = picked;
          endSel = null;
          pickingStart = false;
        } else {
          endSel = picked;
          pickingStart = true;
        }
      }
      setSB(() {});
    }

    final content = StatefulBuilder(
      builder: (context, setSB) {
        return SizedBox(
          width: 760,
          child: Column(
            children: [
              _popoverHeader('시공예정일(기간) 선택'),
              Row(
                children: [
                  Expanded(
                    child: _buildMonthPanel(
                      month: leftMonth,
                      start: startSel,
                      end: endSel,
                      onPrev: () => setSB(() {
                        leftMonth = _addMonths(leftMonth, -1);
                        rightMonth = _addMonths(leftMonth, 1);
                      }),
                      onNext: () => setSB(() {
                        leftMonth = _addMonths(leftMonth, 1);
                        rightMonth = _addMonths(leftMonth, 1);
                      }),
                      onPick: (d) => handlePick(setSB, d),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _buildMonthPanel(
                      month: rightMonth,
                      start: startSel,
                      end: endSel,
                      onPrev: () => setSB(() {
                        rightMonth = _addMonths(rightMonth, -1);
                        leftMonth = _addMonths(rightMonth, -1);
                      }),
                      onNext: () => setSB(() {
                        rightMonth = _addMonths(rightMonth, 1);
                        leftMonth = _addMonths(rightMonth, -1);
                      }),
                      onPick: (d) => handlePick(setSB, d),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      (startSel == null)
                          ? ''
                          : (endSel == null)
                              ? '시작: ${DateFormat('yyyy-MM-dd').format(startSel!)}'
                              : '선택: ${DateFormat('yyyy-MM-dd').format(startSel!)} ~ ${DateFormat('yyyy-MM-dd').format(endSel!)}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ),
              ),
              _popoverActions(
                onOk: () {
                  if (startSel == null) {
                    _removePopover();
                    return;
                  }
                  final start = startSel!;
                  final end = endSel ?? startSel!;
                  onPicked(DateTimeRange(start: start, end: end));
                  _removePopover();
                },
              ),
            ],
          ),
        );
      },
    );

    _currentPopover = _buildPopover(
      anchor: anchor,
      preferredWidth: 760,
      preferredHeight: 500,
      content: content,
    );
    Overlay.of(context).insert(_currentPopover!);
  }

  Widget _buildMonthPanel({
    required DateTime month,
    required DateTime? start,
    required DateTime? end,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    required ValueChanged<DateTime> onPick,
  }) {
    final theme = Theme.of(context);
    final ymText = '${month.year}년 ${month.month}월';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: onPrev,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ymText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: const [
              Expanded(child: _DowText('일')),
              Expanded(child: _DowText('월')),
              Expanded(child: _DowText('화')),
              Expanded(child: _DowText('수')),
              Expanded(child: _DowText('목')),
              Expanded(child: _DowText('금')),
              Expanded(child: _DowText('토')),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _buildMonthGrid(
            month: month,
            start: start,
            end: end,
            onPick: onPick,
            primary: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildMonthGrid({
    required DateTime month,
    required DateTime? start,
    required DateTime? end,
    required ValueChanged<DateTime> onPick,
    required Color primary,
  }) {
    DateTime d(int y, int m, int day) => DateTime(y, m, day);
    final first = d(month.year, month.month, 1);
    final last = d(month.year, month.month + 1, 0);
    final firstWeekday = first.weekday % 7; // 일=0
    final days = last.day;

    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (int day = 1; day <= days; day++) {
      final date = d(month.year, month.month, day);
      final isStart = (start != null &&
          start!.year == date.year &&
          start!.month == date.month &&
          start!.day == day);
      final isEnd = (end != null &&
          end!.year == date.year &&
          end!.month == date.month &&
          end!.day == day);

      bool inRange = false;
      if (start != null && end != null) {
        final a = DateTime(start!.year, start!.month, start!.day);
        final b = DateTime(end!.year, end!.month, end!.day);
        inRange = !isStart && !isEnd && (date.isAfter(a) && date.isBefore(b));
      }

      cells.add(
        InkWell(
          onTap: () => onPick(date),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: inRange ? primary.withOpacity(0.12) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isStart || isEnd)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  '$day',
                  style: TextStyle(
                    color: (isStart || isEnd) ? Colors.white : null,
                    fontWeight: (isStart || isEnd)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    return GridView.count(
      crossAxisCount: 7,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }

  void _showDateTimePopover({
    required GlobalKey anchorKey,
    required DateTime? initialDate,
    required int initialHour,
    required int initialMinute,
    required void Function(DateTime date, int hour, int minute) onPicked,
  }) {
    _removePopover();
    final anchor = _anchorRect(anchorKey);

    final now = DateTime.now();
    DateTime tempDate = initialDate ?? DateTime(now.year, now.month, now.day);
    int tempHour = initialHour;
    int tempMinute = initialMinute;

    final hours = List<int>.generate(24, (i) => i);
    final minutes = List<int>.generate(12, (i) => i * 5);

    final content = StatefulBuilder(
      builder: (context, setSB) {
        return SizedBox(
          width: 640,
          child: Column(
            children: [
              _popoverHeader('상담예약일시 선택'),
              CalendarDatePicker(
                initialDate: tempDate,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 3),
                onDateChanged: (d) => setSB(() {
                  tempDate = DateTime(d.year, d.month, d.day);
                }),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _MenuField<int>(
                        label: '시',
                        value: tempHour,
                        items: hours,
                        toText: (v) => _twod(v),
                        onSelected: (v) => setSB(() => tempHour = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MenuField<int>(
                        label: '분',
                        value: tempMinute,
                        items: minutes,
                        toText: (v) => _twod(v),
                        onSelected: (v) => setSB(() => tempMinute = v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _popoverActions(
                onOk: () {
                  onPicked(tempDate, tempHour, tempMinute);
                  _removePopover();
                },
              ),
            ],
          ),
        );
      },
    );

    _currentPopover = _buildPopover(
      anchor: anchor,
      preferredWidth: 640,
      preferredHeight: 520,
      content: content,
    );
    Overlay.of(context).insert(_currentPopover!);
  }

  Widget _popoverHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(.2)),
        ),
      ),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _popoverActions({required VoidCallback onOk}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: _removePopover, child: const Text('닫기')),
          const SizedBox(width: 8),
          FilledButton(onPressed: onOk, child: const Text('확인')),
        ],
      ),
    );
  }

  String _twod(int n) => n.toString().padLeft(2, '0');
}

// ============================================================================
// 루트 오버레이 드롭다운(시간/분/상담방법)
// ============================================================================
class _MenuField<T> extends StatefulWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) toText;
  final ValueChanged<T> onSelected;

  const _MenuField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.toText,
    required this.onSelected,
  });

  @override
  State<_MenuField<T>> createState() => _MenuFieldState<T>();
}

class _MenuFieldState<T> extends State<_MenuField<T>> {
  OverlayEntry? _entry;

  void _close() {
    _entry?.remove();
    _entry = null;
    _DropdownOverlayRegistry.unregister(_close);
  }

  void _open() {
    _DropdownOverlayRegistry.closeAll();

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final fieldOffset = box.localToGlobal(Offset.zero);
    final fieldSize = box.size;

    final media = MediaQuery.of(context);
    final viewW = media.size.width;
    final viewH = media.size.height;

    const menuMinWidth = 160.0;
    const menuMaxHeight = 320.0;
    const itemHeight = 40.0;

    final menuWidth = fieldSize.width.clamp(menuMinWidth, viewW - 24);
    final desiredHeight =
        (widget.items.length * itemHeight).clamp(itemHeight, menuMaxHeight);

    final spaceBelow = viewH - (fieldOffset.dy + fieldSize.height) - 12;
    final openBelow = spaceBelow >= desiredHeight;

    final left = fieldOffset.dx.clamp(12.0, viewW - menuWidth - 12.0);
    final top = openBelow
        ? (fieldOffset.dy + fieldSize.height)
        : (fieldOffset.dy - desiredHeight);

    _entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const SizedBox.shrink(),
              ),
            ),
            Positioned(
              left: left,
              top: top.clamp(12.0, viewH - desiredHeight - 12.0),
              width: menuWidth,
              height: desiredHeight,
              child: Material(
                elevation: 10,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFE6E6EA)),
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemExtent: itemHeight,
                  itemCount: widget.items.length,
                  itemBuilder: (_, i) {
                    final v = widget.items[i];
                    final text = widget.toText(v);
                    final selected = v == widget.value;
                    return InkWell(
                      onTap: () {
                        widget.onSelected(v);
                        _close();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(child: Text(text)),
                            if (selected) const Icon(Icons.check, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context, rootOverlay: true)!.insert(_entry!);
    _DropdownOverlayRegistry.register(_close);
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ).copyWith(labelText: widget.label),
        child: Row(
          children: [
            Expanded(child: Text(widget.toText(widget.value))),
            const Icon(Icons.expand_more, size: 20),
          ],
        ),
      ),
    );
  }
}

class _DropdownOverlayRegistry {
  static final List<VoidCallback> _closers = [];

  static void register(VoidCallback closer) {
    _closers.add(closer);
  }

  static void unregister(VoidCallback closer) {
    _closers.remove(closer);
  }

  static void closeAll() {
    for (final c in _closers.reversed.toList()) {
      try {
        c();
      } catch (_) {}
    }
    _closers.clear();
  }
}

class _UserDropdown extends StatelessWidget {
  final String label;
  final List<UserOption> options;
  final UserOption? value;
  final ValueChanged<UserOption?> onChanged;

  const _UserDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ).copyWith(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UserOption>(
          isExpanded: true,
          value: value == null
              ? null
              : options.firstWhere(
                  (o) => o.id == value!.id,
                  orElse: () => value!, // 목록에 없어도 수정폼에서 표시 유지
                ),
          items: <DropdownMenuItem<UserOption>>[
            const DropdownMenuItem<UserOption>(
              value: null,
              child: Text('선택해 주세요'),
            ),
            ...options.map(
              (o) => DropdownMenuItem<UserOption>(
                value: o,
                child: Text(o.name),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// 요일 텍스트 작은 위젯
class _DowText extends StatelessWidget {
  final String text;
  const _DowText(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }
}
