// lib/service/soft_delete_service.dart
// ===================================================================
// SoftDeleteService
// - 수정1차: Firestore 소프트삭제/복원 공통 유틸
// ===================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class SoftDeleteService {
  // ✅ 소프트 삭제
  static Future<void> softDelete({
    required String collection,
    required String docId,
  }) async {
    await FirebaseFirestore.instance.collection(collection).doc(docId).update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  // ✅ 복원
  static Future<void> restore({
    required String collection,
    required String docId,
  }) async {
    await FirebaseFirestore.instance.collection(collection).doc(docId).update({
      'isDeleted': false,
      'deletedAt': null,
    });
  }

  // ✅ (선택) 완전 삭제(휴지통에서만 사용 권장)
  static Future<void> hardDelete({
    required String collection,
    required String docId,
  }) async {
    await FirebaseFirestore.instance.collection(collection).doc(docId).delete();
  }

  // ✅ (권장) 기존 문서들 isDeleted 필드 없으면 false로 채우기 (관리자 1회 실행용)
  static Future<void> migrateFillIsDeletedFalse({
    required String collection,
    int batchSize = 300,
  }) async {
    final qs = await FirebaseFirestore.instance.collection(collection).limit(batchSize).get();
    if (qs.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    int count = 0;

    for (final doc in qs.docs) {
      final data = doc.data();
      if (!data.containsKey('isDeleted')) {
        batch.update(doc.reference, {'isDeleted': false});
        count++;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
  }
}
