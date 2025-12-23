/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");

// ✅ 수정1차: Callable(onCall) 추가 + Admin SDK 초기화
const {onCall, HttpsError} = require("firebase-functions/v2/https"); // ✅ 수정1차
const admin = require("firebase-admin"); // ✅ 수정1차
admin.initializeApp(); // ✅ 수정1차

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

/**
 * ============================================================
 * ✅ 수정1차: 관리자만 직원 비밀번호 변경 (Callable)
 * - 호출: setUserPassword({ uid, newPassword })
 * - 관리자 판정: Firestore users/{callerUid}.role 가
 *   '부관리자' 또는 '최고관리자' 인 경우만 허용
 * ============================================================
 */
exports.setUserPassword = onCall(async (request) => {
  // 1) 로그인 체크
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }

  const callerUid = request.auth.uid;
  const uid = request.data?.uid ? String(request.data.uid) : "";
  const newPassword = request.data?.newPassword ? String(request.data.newPassword) : "";

  // 2) 입력값 체크
  if (!uid) {
    throw new HttpsError("invalid-argument", "uid가 필요합니다.");
  }
  if (!newPassword || newPassword.length < 6) {
    throw new HttpsError("invalid-argument", "비밀번호는 6자 이상이어야 합니다.");
  }

  // 3) 관리자 권한 체크 (users/{callerUid}.role)
  const callerSnap = await admin.firestore().collection("users").doc(callerUid).get();
  const caller = callerSnap.exists ? callerSnap.data() : null;
  const role = caller?.role ? String(caller.role) : "";

  const isAdmin = role === "부관리자" || role === "최고관리자";
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "관리자만 사용할 수 있습니다.");
  }

  // 4) 비밀번호 변경 (Admin SDK)
  await admin.auth().updateUser(uid, { password: newPassword });

  return { ok: true };
});
