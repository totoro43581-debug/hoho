// lib/widget/web_list_scaffold.dart
// ===================================================================
// Web 공통 리스트 스캐폴드
// - 수정1차: 상단 액션바(삭제/등록/검색/갯수)
// - 수정2차: 갯수 팝업(10/25/50/100) + 화이트 배경
// - 수정3차: 모든 버튼 WebCommonButton.pill()로 통일
// - 수정4차: 가로 스크롤 기본 지원
// - 수정5차(누적): 삭제 버튼 "항상 표시" (onDeleteTap==null이면 비활성)
//               '전체' 텍스트는 옵션(기본 숨김)으로 변경 (원 UI 훼손 방지)
// - 수정6차(누적):
//   1) 반응형 폭 확장: 화면 가로가 커지면 리스트(테이블)도 같이 넓어지게 처리
//   2) 가로 스크롤은 유지(테이블이 더 넓을 때만 스크롤 발생)
// ===================================================================

import 'dart:math' as math; // ✅ 수정6차: width 계산용
import 'package:flutter/material.dart';
import 'package:hoho/widget/web_common_button.dart';

class WebListScaffold extends StatelessWidget {
  final int limit;
  final ValueChanged<int> onLimitChanged;

  final String searchHint;
  final ValueChanged<String> onSearchChanged;

  // ✅ 수정5차: 삭제 버튼 항상 표시용
  final VoidCallback? onDeleteTap;
  final bool showDeleteButton;

  final bool showRegisterButton;
  final VoidCallback? onRegisterTap;

  // ✅ 수정5차: '전체' 텍스트 옵션화(기본 false)
  final bool showAllLabel;
  final String allLabelText;

  final Widget childTable;

  const WebListScaffold({
    super.key,
    required this.limit,
    required this.onLimitChanged,
    required this.searchHint,
    required this.onSearchChanged,
    this.onDeleteTap,
    this.showDeleteButton = true, // ✅ 기본: 삭제 버튼은 보이게
    this.showRegisterButton = false,
    this.onRegisterTap,
    this.showAllLabel = false, // ✅ 기본: '전체' 숨김
    this.allLabelText = '전체',
    required this.childTable,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ============================================================
        // 상단 액션 바
        // ============================================================
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // ===== 삭제 버튼 (수정5차: 항상 표시/비활성 처리) =====
              if (showDeleteButton) ...[
                WebCommonButton.pill(
                  text: '삭제',
                  onPressed: onDeleteTap, // null이면 자동 비활성
                ),
                const SizedBox(width: 10),
              ],

              // ===== 갯수 드롭다운 =====
              _LimitDropdown(
                value: limit,
                onChanged: onLimitChanged,
              ),

              // ===== '전체' 라벨(옵션) =====
              if (showAllLabel) ...[
                const SizedBox(width: 16),
                Text(allLabelText),
              ],

              const Spacer(),

              // ===== 검색 =====
              SizedBox(
                width: 220,
                height: 36,
                child: TextField(
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: searchHint,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    suffixIcon: const Icon(Icons.search),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // ===== 등록 버튼 =====
              if (showRegisterButton)
                WebCommonButton.pill(
                  text: '등록',
                  onPressed: onRegisterTap,
                  minWidth: 96,
                  height: 36,
                ),
            ],
          ),
        ),

        const Divider(height: 1),

        // ============================================================
        // 수정6차: 반응형 폭 확장 + 가로 스크롤 유지
        // - availableWidth(현재 화면 폭)를 기준으로
        //   minWidth = max(1200, availableWidth) 로 강제
        // ============================================================
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final targetMinWidth = math.max(1200.0, availableWidth);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: targetMinWidth),
                  child: childTable,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ===================================================================
// 갯수 선택 드롭다운 (화이트 팝업 고정)
// ===================================================================
class _LimitDropdown extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _LimitDropdown({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: value,
        borderRadius: BorderRadius.circular(8),
        dropdownColor: Colors.white, // ✅ 항상 화이트
        items: const [
          DropdownMenuItem(value: 10, child: Text('10')),
          DropdownMenuItem(value: 25, child: Text('25')),
          DropdownMenuItem(value: 50, child: Text('50')),
          DropdownMenuItem(value: 100, child: Text('100')),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
