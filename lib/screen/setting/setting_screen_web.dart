import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class SettingScreenWeb extends StatefulWidget {
  final VoidCallback onCancel;

  const SettingScreenWeb({super.key, required this.onCancel});

  @override
  State<SettingScreenWeb> createState() => _SettingScreenWebState();
}

class _SettingScreenWebState extends State<SettingScreenWeb> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String _email = '';

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _email = user.email ?? '';
        final doc = await FirebaseFirestore.instance
            .collection('receptions')
            .doc('receptions')
            .get();

        if (doc.exists) {
          _nameController.text = doc['customerName'] ?? '';
          _phoneController.text = doc['phoneNumber'] ?? '';
        }

        setState(() {});
      }
    } catch (e) {
      debugPrint('설정 정보 불러오기 오류: $e');
    }
  }

  Future<void> updateUserData() async {
    try {
      await FirebaseFirestore.instance
          .collection('receptions')
          .doc('receptions')
          .update({
        'customerName': _nameController.text,
        'phoneNumber': _phoneController.text,
      });

      if (_passwordController.text.isNotEmpty) {
        await FirebaseAuth.instance.currentUser
            ?.updatePassword(_passwordController.text);
      }

      widget.onCancel();
    } catch (e) {
      debugPrint('설정 정보 수정 오류: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500), // 📌 폭 넓게
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildReadOnlyRow('아이디', _email),
                const SizedBox(height: 20),
                _buildEditableRow('이름', _nameController),
                const SizedBox(height: 20),
                _buildEditableRow('연락처', _phoneController),
                const SizedBox(height: 20),
                _buildEditableRow('비밀번호 변경', _passwordController),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: updateUserData,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black),
                      child: const Text(
                          '수정', style: TextStyle(color: Colors.white)),
                    ),
                    ElevatedButton(
                      onPressed: widget.onCancel, // ✅ pop 대신 콜백
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                      child: const Text('취소', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyRow(String label, String value) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    );
  }

  Widget _buildEditableRow(String label, TextEditingController controller) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(
          child: TextField(
            controller: controller,
            obscureText: label.contains('비밀번호'),
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
