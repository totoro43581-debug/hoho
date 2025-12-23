// lib/screen/home/home_screen_web.dart
// ============================================================
// HomeScreenWeb — 수정1차
// - 상담 탭 강제 경로 고정: _ForceConsultation 사용 (임시 4px 보라색 바 표시)
// - v2, 새 파일 없이 기존 ConsultationListScreenWeb 그대로 사용
//
// HomeScreenWeb — ✅ 수정2차
// - 상담 상세(detail) 서브상태 추가
// - 상담 상세 화면은 접수 상세(ReceptionDetailScreenWeb) 재사용(= 동일 UI 확정)
// - ConsultationListScreenWeb → onDetailTap 콜백을 받아 HomeScreenWeb 상태로 제어
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 접수
import 'package:hoho/screen/reception/reception_list_screen_web.dart';
import 'package:hoho/screen/reception/reception_register_screen_web.dart';
import 'package:hoho/screen/reception/reception_detail_screen_web.dart';
import 'package:hoho/screen/reception/reception_timeline_screen_web.dart';

// 상담 (기존 파일 그대로)
import 'package:hoho/screen/consultation/consultation_list_screen_web.dart';
import 'package:hoho/screen/consultation/consultation_edit_screen_web.dart';

// 설정 + 사용자 리스트
//import 'package:hoho/screen/setting/setting_screen_web.dart';
import 'package:hoho/screen/setting/user_list_screen_web.dart';
import 'package:hoho/screen/setting/user_edit_screen_web.dart';

// 삭제 + 휴지통
import 'package:hoho/screen/common/recycle_bin_screen_web.dart';

// 통합일정
import 'package:hoho/screen/schedule/schedule_screen_web.dart';

class HomeScreenWeb extends StatefulWidget {
  const HomeScreenWeb({super.key});

  @override
  State<HomeScreenWeb> createState() => _HomeScreenWebState();
}

class _HomeScreenWebState extends State<HomeScreenWeb> {
  int _selectedIndex = 0; // 0=접수, 1=상담, ...
  int? _popupIndex; // 99=설정, 98=사용자
  String _userName = '사용자';

  // 접수 서브상태
  String _receptionSubScreen = 'list';
  String? _selectedReceptionId;
  Map<String, dynamic>? _selectedReceptionData;

  // 상담 서브상태
  String _consultationSubScreen = 'list'; // 'list' | 'detail' | 'edit'   ✅ 수정2차
  String? _selectedConsultationId;
  Map<String, dynamic>? _selectedConsultationData; // ✅ 수정2차: 상담 상세에 넘길 rowData

  // 사용자 서브상태
  String _userSubScreen = 'list';
  String? _selectedUserId;

  final List<String> _menuItems = const [
    '접수',
    '상담',
    '견적',
    '프로젝트',
    '통합일정',
    '업무일지',
    '통계',
    '관리',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snap.data();
      if (data != null && (data['name'] ?? '').toString().isNotEmpty) {
        setState(() => _userName = data['name'].toString());
      } else {
        setState(() => _userName = (user.email ?? '사용자').split('@').first);
      }
    }
  }

  Widget _buildTopBar() {
    return Container(
      height: 64,
      color: const Color(0xFF2D2B31),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Center(
            child: Text('호호', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Positioned(
            right: 0,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(20)),
                  child: Text(_displayUserName(_userName), style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 8),
                _buildPopupMenu(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _displayUserName(String? v) {
    if (v == null || v.isEmpty) return '사용자';
    return v.endsWith('님') ? v : '$v님';
  }

  Widget _buildPopupMenu() {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.settings, color: Colors.white),
      onSelected: (value) {
        if (value == 1) {
          _onPopupTap(98); // 사용자 리스트
        } else if (value == 2) {
          _onPopupTap(97); // 휴지통
        } else if (value == 3) {
          _logout();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 1, child: Text('사용자')),
        PopupMenuItem(value: 2, child: Text('휴지통')),
        PopupMenuItem(value: 3, child: Text('로그아웃')),
      ],
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_route');
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  Widget _buildMenuBar() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_menuItems.length, (index) {
          final isSelected = _selectedIndex == index;
          return GestureDetector(
            onTap: () => _onMenuTap(index),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _menuItems[index],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.black : Colors.black45,
                    ),
                  ),
                  if (isSelected) Container(margin: const EdgeInsets.only(top: 4), height: 2, width: 20, color: Colors.black),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  void _onMenuTap(int index) {
    setState(() {
      _selectedIndex = index;
      _popupIndex = null;
      if (index == 0) {
        _receptionSubScreen = 'list';
        _selectedReceptionId = null;
        _selectedReceptionData = null;
      } else if (index == 1) {
        _consultationSubScreen = 'list';
        _selectedConsultationId = null;
        _selectedConsultationData = null; // ✅ 수정2차
      }
    });
  }

  void _onPopupTap(int index) {
    setState(() {
      _popupIndex = index;
      _selectedIndex = -1;
    });
  }

  Widget _buildContent() {
    // ====== 수정1차: 상담 탭이면 경로를 강제로 고정 (_ForceConsultation) ======
    if (_popupIndex == null && _selectedIndex == 1) {
      return _ForceConsultation(
        // ✅ 수정2차: list/detail/edit 모두 이 위젯에서 제어
        mode: _consultationSubScreen,

        // 리스트에서 "수정" 버튼 눌렀을 때
        onEditTap: (id) {
          setState(() {
            _selectedConsultationId = id;
            _consultationSubScreen = 'edit';
          });
        },

        // ✅ 수정2차: 리스트에서 "상담상세" 진입(행 클릭 or 상세 버튼)
        onDetailTap: (rowData) {
          setState(() {
            _selectedConsultationData = rowData;
            _selectedConsultationId = rowData['id']?.toString();
            _consultationSubScreen = 'detail';
          });
        },

        // 편집 모드로 진입 시 기존 편집 화면 그대로 사용
        editBuilder: () {
          if (_selectedConsultationId == null) {
            setState(() => _consultationSubScreen = 'list');
            return const SizedBox.shrink();
          }
          // ✅ 기존 유지: 편집 화면은 ReceptionRegisterScreenWeb 재사용 중
          return ReceptionRegisterScreenWeb(
            editingDocId: _selectedConsultationId!,
            onCancel: () {
              setState(() {
                _consultationSubScreen = 'list';
                _selectedConsultationId = null;
                _selectedConsultationData = null; // ✅ 수정2차
              });
            },
          );
        },

        // ✅ 수정2차: 상세 모드(접수 상세 UI 그대로 재사용)
        detailBuilder: () {
          if (_selectedConsultationData == null) {
            setState(() => _consultationSubScreen = 'list');
            return const SizedBox.shrink();
          }
          return ReceptionDetailScreenWeb(
            data: _selectedConsultationData!,
            onBack: () {
              setState(() {
                _consultationSubScreen = 'list';
                _selectedConsultationId = null;
                _selectedConsultationData = null;
              });
            },
            onEdit: (id) {
              setState(() {
                _selectedConsultationId = id;
                _consultationSubScreen = 'edit';
              });
            },
            onTimeline: (detailData) {
              // ✅ 상담 상세에서도 타임라인은 동일 흐름 유지(원하시면 상담에서는 막을 수도 있음)
              setState(() {
                _selectedConsultationData = detailData;
                // 접수 흐름과 동일하게 timeline로 보내려면 상담쪽에 timeline 서브상태가 필요하지만,
                // 지금은 "상담 상세 = 접수 상세 동일" 요구라서 그대로 유지합니다.
                // 필요 시 다음 수정차에서 상담 timeline 분리/차단 처리하겠습니다.
              });
            },
          );
        },
      );
    }
    // =====================================================================

    if (_popupIndex == 98) {
      if (_userSubScreen == 'edit' && _selectedUserId != null) {
        return UserEditScreenWeb(
          userId: _selectedUserId!,
          onBack: () {
            setState(() {
              _userSubScreen = 'list';
              _selectedUserId = null;
            });
          },
        );
      }
      return UserListScreenWeb(
        onBack: () {
          setState(() {
            _popupIndex = null;
            _selectedIndex = 0;
            _receptionSubScreen = 'list';
          });
        },
        onEditTap: (uid) {
          setState(() {
            _selectedUserId = uid;
            _userSubScreen = 'edit';
          });
        },
      );
    }

    if (_popupIndex == 97) {
      return RecycleBinScreenWeb(
        onBack: () {
          setState(() {
            _popupIndex = null;
            _selectedIndex = 0;
          });
        },
      );
    }

    switch (_selectedIndex) {
      case 0:
        return _buildReceptionContent();
      default:
        final safe = (_selectedIndex >= 0 && _selectedIndex < _menuItems.length) ? _menuItems[_selectedIndex] : '';
        return Center(child: Text(safe));
    }
  }

  // ===== 접수 컨텐츠 =====
  Widget _buildReceptionContent() {
    switch (_receptionSubScreen) {
      case 'register':
        return ReceptionRegisterScreenWeb(
          onCancel: () => setState(() => _receptionSubScreen = 'list'),
        );
      case 'edit':
        if (_selectedReceptionId == null) {
          _receptionSubScreen = 'list';
          return _buildReceptionContent();
        }
        return ReceptionRegisterScreenWeb(
          editingDocId: _selectedReceptionId,
          onCancel: () {
            setState(() {
              _receptionSubScreen = 'list';
              _selectedReceptionId = null;
              _selectedReceptionData = null;
            });
          },
        );
      case 'detail':
        if (_selectedReceptionData == null) {
          _receptionSubScreen = 'list';
          return _buildReceptionContent();
        }
        return ReceptionDetailScreenWeb(
          data: _selectedReceptionData!,
          onBack: () {
            setState(() {
              _receptionSubScreen = 'list';
              _selectedReceptionId = null;
              _selectedReceptionData = null;
            });
          },
          onEdit: (id) {
            setState(() {
              _selectedReceptionId = id;
              _receptionSubScreen = 'edit';
            });
          },
          onTimeline: (detailData) {
            setState(() {
              _selectedReceptionData = detailData;
              _receptionSubScreen = 'timeline';
            });
          },
        );
      case 'timeline':
        if (_selectedReceptionData == null) {
          _receptionSubScreen = 'list';
          return _buildReceptionContent();
        }
        return ReceptionTimelineScreenWeb(
          data: _selectedReceptionData!,
          onBack: () {
            setState(() {
              _receptionSubScreen = 'detail';
            });
          },
          onDetail: () {
            setState(() {
              _receptionSubScreen = 'detail';
            });
          },
        );
      case 'list':
      default:
        return ReceptionListScreen(
          onRegisterTap: () => setState(() => _receptionSubScreen = 'register'),
          onEditTap: (id) {
            setState(() {
              _selectedReceptionId = id;
              _receptionSubScreen = 'edit';
            });
          },
          onDetailTap: (rowData) {
            setState(() {
              _selectedReceptionData = rowData;
              _selectedReceptionId = rowData['id']?.toString();
              _receptionSubScreen = 'detail';
            });
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          _buildTopBar(),
          _buildMenuBar(),
          Expanded(
            child: Container(
              color: const Color(0xFFF5F7FA),
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(blurRadius: 12, spreadRadius: 0, offset: Offset(0, 4), color: Color(0x14000000)),
                  ],
                  border: const Border.fromBorderSide(BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: _buildContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 상담 강제 경로 위젯 (수정1차)
// - mode == 'edit' 이면 편집화면 표시, 그 외엔 새 리스트 표시
// - 상단 4px 보라색 바가 보이면 "상담 경로가 이 위젯으로 바뀐 것"이 확정
//   확인 후 Container(height:4, ...) 줄은 삭제하셔도 됩니다.
//
// ✅ 수정2차
// - mode == 'detail' 추가
// - detailBuilder / onDetailTap 추가
// ============================================================
class _ForceConsultation extends StatelessWidget {
  final String mode; // 'list' | 'detail' | 'edit' ✅ 수정2차
  final VoidCallback? onRegisterTap;
  final void Function(String id)? onEditTap;

  // ✅ 수정2차
  final void Function(Map<String, dynamic> rowData)? onDetailTap;
  final Widget Function()? detailBuilder;

  final Widget Function()? editBuilder;

  const _ForceConsultation({
    required this.mode,
    this.onRegisterTap,
    this.onEditTap,
    this.onDetailTap,
    this.detailBuilder,
    this.editBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == 'edit' && editBuilder != null) {
      return editBuilder!.call();
    }
    if (mode == 'detail' && detailBuilder != null) {
      return detailBuilder!.call();
    }

    return Column(
      children: [
        // ==== 임시 확인 바 (보이면 새 경로가 맞음) ====
        // Container(height: 4, color: const Color(0xFF7C4DFF)), // 확인 후 삭제 가능
        Expanded(
          child: ConsultationListScreenWeb(
            onRegisterTap: onRegisterTap,
            onEditTap: onEditTap,
            // ✅ 수정2차: 상담리스트에서 "상담상세"로 들어갈 콜백
            onDetailTap: onDetailTap,
          ),
        ),
      ],
    );
  }
}
