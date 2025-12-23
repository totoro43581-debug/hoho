// lib/widget/web_common_button.dart
// ===================================================================
// Web 공통 버튼
// - 수정1차: 캡슐(라운드) + 흰 배경 + 보라 테두리/글자 (사용자 요청 고정 스타일)
// ===================================================================

import 'package:flutter/material.dart';

class WebCommonButton {
  // 고정 컬러(ERP 메인 포인트)
  static const Color kPurple = Color(0xFF7C4DFF);

  // ============================================================
  // 수정1차: 캡처와 동일한 기본 버튼 스타일
  // ============================================================
  static ButtonStyle outlinePurple({
    double radius = 22,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    double borderWidth = 1.4,
  }) {
    return OutlinedButton.styleFrom(
      backgroundColor: Colors.white, // ✅ 흰 배경
      foregroundColor: kPurple,      // ✅ 보라 글자
      padding: padding,
      side: BorderSide(color: kPurple, width: borderWidth), // ✅ 보라 테두리
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),        // ✅ 캡슐 라운드
      ),
    );
  }

  // ============================================================
  // 수정1차: 자주 쓰는 캡슐 버튼 위젯(OutlinedButton)
  // ============================================================
  static Widget pill({
    required String text,
    required VoidCallback? onPressed,
    double minWidth = 88,
    double height = 36,
  }) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        style: outlinePurple(),
        onPressed: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: Center(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
