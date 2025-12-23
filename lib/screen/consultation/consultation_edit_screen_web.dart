import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ConsultationEditScreenWeb extends StatefulWidget {
  final String consultationId;
  final VoidCallback onBack;

  const ConsultationEditScreenWeb({
    super.key,
    required this.consultationId,
    required this.onBack,
  });

  @override
  State<ConsultationEditScreenWeb> createState() => _ConsultationEditScreenWebState();
}

class _ConsultationEditScreenWebState extends State<ConsultationEditScreenWeb> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  final _customerName = TextEditingController();
  final _phone = TextEditingController();
  final _projectName = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('consultations')
          .doc(widget.consultationId)
          .get();
      final data = snap.data();
      if (data != null) {
        _customerName.text = (data['customerName'] ?? '').toString();
        _phone.text = (data['phone1'] ?? data['phone'] ?? '').toString();
        _projectName.text = (data['projectName'] ?? '').toString();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로드 오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('consultations')
          .doc(widget.consultationId)
          .update({
        'customerName': _customerName.text.trim(),
        'phone1': _phone.text.trim(),
        'projectName': _projectName.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('수정되었습니다.')));
      widget.onBack(); // 리스트로 복귀(메인컨텐츠 전환)
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장 오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _customerName.dispose();
    _phone.dispose();
    _projectName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Scaffold/AppBar 없이, 카드 내부에 박아서 쓰는 패널용 UI
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 내부 헤더(카드 상단)
            Container(
              height: 48,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('리스트로'),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '상담 수정 (ID: ${widget.consultationId})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 폼
            Form(
              key: _formKey,
              child: Column(
                children: [
                  _row('고객명', _customerName),
                  const SizedBox(height: 12),
                  _row('연락처', _phone),
                  const SizedBox(height: 12),
                  _row('프로젝트명', _projectName),
                  const SizedBox(height: 20),

                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      // FilledButton이 없는 Flutter 버전 대비 안전판
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? SizedBox( // const 빼서 버전 이슈 회피
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.save),
                      label: const Text('저장'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, TextEditingController c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: c,
            validator: (v) => (v == null || v.trim().isEmpty) ? '필수 입력' : null,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
