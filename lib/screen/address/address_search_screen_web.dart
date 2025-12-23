import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

class AddressSearchScreenWeb extends StatefulWidget {
  const AddressSearchScreenWeb({super.key});

  @override
  State<AddressSearchScreenWeb> createState() => _AddressSearchScreenWebState();
}

class _AddressSearchScreenWebState extends State<AddressSearchScreenWeb> {
  @override
  void initState() {
    super.initState();

    const viewType = 'kakao-postcode-view';

    ui.platformViewRegistry.registerViewFactory(
      viewType,
          (int viewId) {
        final iframe = html.IFrameElement()
          ..src = '/kakao_postcode.html'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        return iframe;
      },
    );

    html.window.onMessage.listen((event) {
      final String address = event.data.toString();
      Navigator.pop(context, address);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('주소 검색')),
      body: HtmlElementView(viewType: 'kakao-postcode-view'),
    );
  }
}
