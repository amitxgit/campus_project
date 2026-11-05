// firebase_functions/checkin.js
// Helpers for Bluetooth check-in and phone binding, used by markAttendance.
//
// Bluetooth token
// ---------------
// iOS can only broadcast service UUIDs and a short name, so the whole token
// fits in one 128-bit service UUID (16 bytes):
//
//   bytes 0-1   magic 0xBA 0x7C   (marks the UUID as a Batchwise check-in)
//   bytes 2-5   bleCode            (random u32 per session, big-endian)
//   bytes 6-7   step               (u16, same 5 s step counter as the QR)
//   bytes 8-15  HMAC-SHA256(secret, "ble:<sessionId>:<step>"), first 8 bytes
//
// The signature uses the same server-issued per-session secret as the QR,
// with a "ble:" prefix so a QR signature can never pass as a Bluetooth one.
// Must match lib/core/attendance/ble_token.dart.
//
// Phone binding
// -------------
// The app sends a random installation ID kept on the phone. The server
// stores only its SHA-256. A student account is bound to the first phone it
// marks attendance from, and in each session one phone can mark one student.
// Admins reset the binding from the user's profile.
const crypto = require("crypto");

const BLE_MAGIC = [0xba, 0x7c];
const BLE_SIG_BYTES = 8;

function signBle(secret, sessionId, step) {
  return crypto
    .createHmac("sha256", secret)
    .update(`ble:${sessionId}:${step}`)
    .digest()
    .subarray(0, BLE_SIG_BYTES);
}

// "xxxxxxxx-xxxx-..." or 32 hex chars -> {code, step, sig} or null.
function parseBleToken(token) {
  if (typeof token !== "string") return null;
  const hex = token.replace(/-/g, "").toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(hex)) return null;
  const b = Buffer.from(hex, "hex");
  if (b[0] !== BLE_MAGIC[0] || b[1] !== BLE_MAGIC[1]) return null;
  return { code: b.readUInt32BE(2), step: b.readUInt16BE(6), sig: b.subarray(8, 16) };
}

// Builds the token as a UUID string (used by tests; the app builds its own).
function buildBleToken(secret, sessionId, code, step) {
  const b = Buffer.alloc(16);
  b[0] = BLE_MAGIC[0];
  b[1] = BLE_MAGIC[1];
  b.writeUInt32BE(code >>> 0, 2);
  b.writeUInt16BE(step & 0xffff, 6);
  signBle(secret, sessionId, step).copy(b, 8);
  const h = b.toString("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

function bleSigOk(secret, sessionId, step, sig) {
  const expected = signBle(secret, sessionId, step);
  return Buffer.isBuffer(sig) && sig.length === expected.length && crypto.timingSafeEqual(sig, expected);
}

// Validates the installation ID and returns its SHA-256 (hex), or null.
function deviceHash(deviceId) {
  if (typeof deviceId !== "string" || deviceId.length < 16 || deviceId.length > 128) return null;
  return crypto.createHash("sha256").update(deviceId).digest("hex");
}

function newBleCode() {
  return crypto.randomBytes(4).readUInt32BE(0);
}

module.exports = { BLE_MAGIC, signBle, parseBleToken, buildBleToken, bleSigOk, deviceHash, newBleCode };
