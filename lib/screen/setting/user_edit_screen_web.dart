import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hoho/widget/web_common_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ 비밀번호 재설정 메일 발송용

class UserEditScreenWeb extends StatefulWidget {
  final String userId;
  final VoidCallback onBack;

  const UserEditScreenWeb({
    super.key,
    required this.userId,
    required this.onBack,
  });

  @override
  State<UserEditScreenWeb> createState() => _UserEditScreenWebState();
}

class _UserEditScreenWebState extends State<UserEditScreenWeb> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _managerColorController = TextEditingController();

  bool _isActive = true;

  // 라디오 그룹(기존 화면 유지)
  String _accountStatus = '매니저(승인)'; // 등급관리
  String _branchAuth = '모두'; // 지점권한
  String _spaceAuth = '모두'; // 공간권한
  String _team = '소속팀없음'; // 소속팀
  String _workType = '내근'; // 근무형태
  String _workLogType = '지원팀'; // 업무일지

  bool _loading = true;

  // ✅ 수정4차: 관리자 여부(현재 로그인 사용자 기준)
  bool _isAdmin = false;

  // ===========================
  // 수정1차: 버튼 스타일(회색 + 보라)
  // ===========================
  ButtonStyle _greyPurpleBtn() {
    const purple = Color(0xFF7C4DFF);
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFF3F4F6),
      foregroundColor: purple,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: purple),
      ),
    );
  }

  // ===========================
  // 수정2차: 색상 파싱/정규화
  // ===========================
  Color _parseHexToColor(String? hex) {
    if (hex == null) return Colors.transparent;
    final h = hex.trim();
    if (h.isEmpty) return Colors.transparent;
    try {
      final v = int.parse(h.replaceFirst('#', ''), radix: 16);
      return Color(0xFF000000 | v);
    } catch (_) {
      return Colors.transparent;
    }
  }

  String _normalizeHex(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final v = t.startsWith('#') ? t.substring(1) : t;
    if (v.length != 6) return t.startsWith('#') ? t : '#$t';
    return '#${v.toUpperCase()}';
  }

  // ✅ 수정4차: 관리자 role 판별(현재 로그인 사용자 문서 기준)
  bool _isAdminRole(String role) {
    return role == '최고관리자' || role == '부관리자';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // ✅ 수정4차: 현재 로그인 사용자 role 조회 → 관리자 여부 결정
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        final meSnap =
        await FirebaseFirestore.instance.collection('users').doc(current.uid).get();
        final me = meSnap.data() ?? {};
        final myRole = (me['role'] ?? me['accountStatus'] ?? '').toString();
        _isAdmin = _isAdminRole(myRole);
      } else {
        _isAdmin = false;
      }

      final snap = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      final data = snap.data() ?? {};

      _emailController.text = (data['email'] ?? '').toString();
      _nameController.text = (data['name'] ?? '').toString();
      _phoneController.text = (data['phone'] ?? '').toString();
      _managerColorController.text = (data['managerColor'] ?? '').toString();

      _isActive = (data['isActive'] ?? true) == true;

      _accountStatus = (data['role'] ?? data['accountStatus'] ?? _accountStatus).toString();
      _branchAuth = (data['branchAuth'] ?? _branchAuth).toString();
      _spaceAuth = (data['spaceAuth'] ?? _spaceAuth).toString();
      _team = (data['team'] ?? _team).toString();
      _workType = (data['workType'] ?? _workType).toString();
      _workLogType = (data['workLogType'] ?? _workLogType).toString();
    } catch (_) {
      // 유지
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final managerColor = _normalizeHex(_managerColorController.text);

    await FirebaseFirestore.instance.collection('users').doc(widget.userId).set({
      'email': _emailController.text.trim(),
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'managerColor': managerColor,
      'isActive': _isActive,
      'role': _accountStatus,
      'branchAuth': _branchAuth,
      'spaceAuth': _spaceAuth,
      'team': _team,
      'workType': _workType,
      'workLogType': _workLogType,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장되었습니다.')),
      );
    }
  }

  // ============================================================
  // ✅ 수정3차(유지): 비밀번호 재설정 메일 보내기 (Blaze 없이)
  // ✅ 수정4차: 관리자만 실행 가능(보안)
  // ============================================================
  Future<void> _sendPasswordResetEmail() async {
    if (!_isAdmin) {
      _showSnack('권한이 없습니다.');
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnack('이메일이 비어있습니다.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnack('비밀번호 재설정 메일을 발송했습니다.');
    } on FirebaseAuthException catch (e) {
      _showSnack('메일 발송 실패: ${e.message ?? e.code}');
    } catch (e) {
      _showSnack('메일 발송 실패: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ---------------------------
  // 라디오 UI (기존 구조 유지)
  // ---------------------------
  Widget _radioRow(String title, List<String> items, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: items.map((it) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Radio<String>(
                    value: it,
                    groupValue: value,
                    onChanged: (v) => onChanged(v ?? it),
                  ),
                  Text(it),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _managerColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('사용자 편집', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                ElevatedButton(
                  style: _greyPurpleBtn(),
                  onPressed: widget.onBack,
                  child: const Text('목록으로'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 18),

            Expanded(
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _radioRow(
                          '등급관리',
                          const ['승인대기', '미승인', '파트너', '매니저(승인)', '총괄매니저', '부관리자', '최고관리자'],
                          _accountStatus,
                              (v) => setState(() => _accountStatus = v),
                        ),
                        _radioRow(
                          '지점권한',
                          const ['수성', '월성', '모두'],
                          _branchAuth,
                              (v) => setState(() => _branchAuth = v),
                        ),
                        _radioRow(
                          '공간권한',
                          const ['주거공간', '상업공간', '모두'],
                          _spaceAuth,
                              (v) => setState(() => _spaceAuth = v),
                        ),
                        _radioRow(
                          '소속팀',
                          const ['소속팀없음', '1팀', '2팀', '3팀', '4팀', '5팀', '스페이스', '지원팀'],
                          _team,
                              (v) => setState(() => _team = v),
                        ),
                        _radioRow(
                          '근무형태',
                          const ['내근', '외근', '없음'],
                          _workType,
                              (v) => setState(() => _workType = v),
                        ),
                        _radioRow(
                          '업무일지',
                          const ['주거', '상업', '디자인', '지원팀'],
                          _workLogType,
                              (v) => setState(() => _workLogType = v),
                        ),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _emailController,
                                decoration: const InputDecoration(labelText: '이메일'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _nameController,
                                decoration: const InputDecoration(labelText: '이름'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                decoration: const InputDecoration(labelText: '휴대폰번호'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _managerColorController,
                                decoration: InputDecoration(
                                  labelText: '매니저색상(예:#8654D9)',
                                  suffixIcon: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: InkWell(
                                      onTap: () async {
                                        final hex = await WebCommonDialog.pickManagerColorHex(
                                          context,
                                          initialHex: _managerColorController.text,
                                        );
                                        if (hex != null && mounted) {
                                          setState(() => _managerColorController.text = hex);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: _parseHexToColor(_managerColorController.text),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.black26),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        Row(
                          children: [
                            const Text('근무여부', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 16),
                            Switch(
                              value: _isActive,
                              onChanged: (v) => setState(() => _isActive = v),
                            ),
                            Text(_isActive ? '근무중' : '미근무'),
                          ],
                        ),

                        const SizedBox(height: 22),

                        Row(
                          children: [
                            const Spacer(),
                            ElevatedButton(
                              style: _greyPurpleBtn(),
                              onPressed: widget.onBack,
                              child: const Text('목록으로'),
                            ),
                            const SizedBox(width: 10),

                            if (_isAdmin) ...[
                              ElevatedButton(
                                style: _greyPurpleBtn(),
                                onPressed: _sendPasswordResetEmail,
                                child: const Text('비밀번호 재설정 메일'),
                              ),
                              const SizedBox(width: 10),
                            ],

                            ElevatedButton(
                              style: _greyPurpleBtn(),
                              onPressed: _save,
                              child: const Text('저장'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
