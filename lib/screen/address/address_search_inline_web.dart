import 'dart:convert';
import 'dart:html' as html;            // 웹 전용
import 'dart:ui_web' as ui;            // view factory
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AddressSearchInlineWeb extends StatefulWidget {
  final void Function(String address, String buildingName) onSelected;
  final VoidCallback onCancel;
  const AddressSearchInlineWeb({
    super.key,
    required this.onSelected,
    required this.onCancel,
  });

  @override
  State<AddressSearchInlineWeb> createState() => _AddressSearchInlineWebState();
}

class _AddressSearchInlineWebState extends State<AddressSearchInlineWeb> {
  static const _viewType = 'kakao-postcode-view';
  static bool _viewRegistered = false;          // ✅ 한 번만 등록
  html.EventListener? _listener;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // ✅ 중복등록 방지
      if (!_viewRegistered) {
        try {
          ui.platformViewRegistry.registerViewFactory(
            _viewType,
                (int viewId) {
              final iframe = html.IFrameElement()
                ..src = '/kakao_postcode.html'
                ..style.border = '0'
                ..style.width = '100%'
                ..style.height = '100%';
              return iframe;
            },
          );
          _viewRegistered = true;
        } catch (_) {
          // 이미 등록되어 있으면 무시
          _viewRegistered = true;
        }
      }

      // ✅ 메시지 수신: JSON 문자열만 처리 (기타 이벤트 안전 무시)
      _listener = (html.Event e) {
        try {
          final me = e as html.MessageEvent;
          if (me.data is String) {
            final obj = jsonDecode(me.data as String);
            if (obj is Map && obj['type'] == 'kakao-postcode-result') {
              final address = (obj['address'] ?? '') as String;
              final building = (obj['buildingName'] ?? '') as String;

              // ✅ 같은 프레임에서 UI 갱신 금지: 다음 프레임으로 미룸
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.onSelected(address, building);
                });
              }
            }
          }
        } catch (_) {}
      };
      html.window.addEventListener('message', _listener);
    }
  }

  @override
  void dispose() {
    if (_listener != null) {
      html.window.removeEventListener('message', _listener);
      _listener = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return Center(
        child: TextButton(
          onPressed: widget.onCancel,
          child: const Text('웹 전용 기능입니다. 닫기'),
        ),
      );
    }
    return const HtmlElementView(viewType: _viewType);
  }
}
