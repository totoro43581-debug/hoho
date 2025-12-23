// lib/screen/setting/user_edit_screen_web.dart
// ===================================================================
// 사용자 편집 (Web)
// - (기존 주석 블록이 있다면 삭제하지 말고 "위에 그대로 두고",
//   아래 코드(=import부터 파일 끝까지)로 교체하세요.)
//
// - 수정1차(누적):
//   1) 버튼 UI 통일: 회색 바탕 + 보라색 글자/테두리(접수/상담 리스트 톤)
//
// - 수정2차(누적):
//   1) "정렬/레이아웃 변경 금지" 원칙 준수: 기존 배치 그대로 유지
//   2) 매니저색상 선택: 브라우저 기본 컬러피커(input type="color")로 변경
//      - 텍스트 입력 유지
//      - 입력칸 오른쪽 색상칩(■) 클릭 시 컬러피커 열림
//
// - 수정3차(누적):
//   1) Blaze 없이 진행: "관리자 비밀번호 직접 변경" 제거
//   2) 대신 "비밀번호 재설정 메일 보내기"로 전환 (직원이 본인 메일로 변경)
// ===================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:html' as html; // ✅ 수정2차: Web 기본 컬러피커 사용
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hoho/widget/web_common_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ 수정3차: reset email 발송용

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

  // (기존에 있던 비밀번호 입력칸 컨트롤러는 유지하되, Blaze 없이 직접 변경은 하지 않음)
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _newPasswordConfirmController = TextEditingController();

  bool _isActive = true;

  // 라디오 그룹(기존 화면 유지)
  String _accountStatus = '매니저(승인)'; // 등급관리
  String _branchAuth = '모두'; // 지점권한
  String _spaceAuth = '모두'; // 공간권한
  String _team = '소속팀없음'; // 소속팀
  String _workType = '내근'; // 근무형태
  String _workLogType = '지원팀'; // 업무일지

  bool _loading = true;

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
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
  // ✅ 수정3차: 비밀번호 재설정 메일 보내기 (Blaze 없이)
  // - 해당 이메일로 reset link 발송
  // - 직원이 본인 이메일에서 링크 열어 새 비밀번호 설정
  // ============================================================
  Future<void> _sendPasswordResetEmail() async {
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
    _newPasswordController.dispose();
    _newPasswordConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    // ✅ 레이아웃 유지: 기존 구조 그대로 (정렬/배치 변경 없음)
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 타이틀 + 목록으로
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

                        // 입력 영역(기존 배치 유지)
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

                        // (기존 비밀번호 입력칸은 유지 — 단, 직접 변경 기능은 사용하지 않음)
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newPasswordController,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: '비밀번호 변경(사용 안 함)'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _newPasswordConfirmController,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: '비밀번호 확인(사용 안 함)'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // 근무여부 토글(기존 유지)
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

                        // 하단 버튼(기존 위치 유지 + reset 버튼만 추가)
                        Row(
                          children: [
                            const Spacer(),
                            ElevatedButton(
                              style: _greyPurpleBtn(),
                              onPressed: widget.onBack,
                              child: const Text('목록으로'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: _greyPurpleBtn(),
                              onPressed: _sendPasswordResetEmail,
                              child: const Text('비밀번호 재설정 메일'),
                            ),
                            const SizedBox(width: 10),
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
