// lib/widget/web_common_dialog.dart
// ===================================================================
// Web 공통 다이얼로그 (화이트 배경 고정 / 컴팩트 / 오버플로우 방지)
// - 수정1차: 공통 다이얼로그 스킨(버튼 톤: 회색+보라) + 스크롤/높이제한
// - 수정2차: 컬러피커 다이얼로그(매니저색상) 공통화 (HEX 반환)
// ===================================================================

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hoho/widget/web_common_button.dart';

class WebCommonDialog {
  // ============================================================
  // 수정1차: 공통 버튼 스타일(회색 바탕 + 보라 글자/테두리)
  // ============================================================
  static ButtonStyle greyPurpleBtn() {
    const purple = Color(0xFF7C4DFF);
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFF3F4F6),
      foregroundColor: purple,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: purple),
      ),
    );
  }

  // ============================================================
  // 수정1차: 공통 다이얼로그(화이트 배경 고정 + 컴팩트 + 오버플로우 방지)
  // - maxHeight를 넘기면 내부 스크롤로 처리
  // ============================================================
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    double width = 520,
    double maxHeight = 360,
    String cancelText = '취소',
    String okText = '적용',
    VoidCallback? onCancel,
    VoidCallback? onOk,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Colors.white, // ✅ 무조건 화이트
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),

          // ✅ 오버플로우 방지(높이 제한 + 내부 스크롤)
          content: SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: content,
              ),
            ),
          ),

          actions: [
            WebCommonButton.pill(
              text: cancelText,
              onPressed: () {
                onCancel?.call();
                Navigator.pop(context);
              },
            ),
            WebCommonButton.pill(
              text: okText,
              onPressed: () {
                onOk?.call();
              },
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // 수정2차: 매니저 색상 선택 다이얼로그(HEX 반환)
  // - 중앙 다이얼로그(컴팩트)
  // - ColorPicker(사각영역+Hue 슬라이더)
  // - 결과를 '#RRGGBB' 형태로 반환
  // ============================================================
  static Future<String?> pickManagerColorHex(
      BuildContext context, {
        required String initialHex,
        double width = 560,
        double maxHeight = 420,
      }) async {
    String _normalizeHex(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return '';
      final v = t.startsWith('#') ? t.substring(1) : t;
      if (v.length != 6) return t.startsWith('#') ? t : '#$t';
      return '#${v.toUpperCase()}';
    }

    Color _parseHexToColor(String? hex) {
      if (hex == null) return const Color(0xFF7C4DFF);
      final h = hex.trim();
      if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(h)) return const Color(0xFF7C4DFF);
      final v = int.parse(h.replaceFirst('#', ''), radix: 16);
      return Color(0xFF000000 | v);
    }

    final startHex = _normalizeHex(initialHex);
    Color picked = _parseHexToColor(startHex.isEmpty ? '#7C4DFF' : startHex);

    String? resultHex;

    await WebCommonDialog.show<void>(
      context: context,
      title: '매니저 색상 선택',
      width: width,
      maxHeight: maxHeight,
      cancelText: '취소',
      okText: '적용',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 미리보기(컴팩트)
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: picked,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '#${picked.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ColorPicker(라벨/숫자 UI 최소화)
          ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            labelTypes: const [],
            portraitOnly: true,
          ),
        ],
      ),
      onOk: () {
        resultHex =
        '#${picked.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
        Navigator.pop(context);
      },
    );

    return resultHex;
  }
}
