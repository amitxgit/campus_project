// functions/biometric_http.js
// HTTP endpoint for fingerprint and face-scan attendance devices.
//
// 1. ZKTeco / eSSL devices (ADMS "push" protocol), which most Indian institutes use:
//      GET  /iclock/cdata?SN=<serial>             first contact, returns options
//      POST /iclock/cdata?SN=<serial>&table=ATTLOG attendance punches, one per line
//      GET  /iclock/getrequest?SN=<serial>        polling for commands, answered "OK"
//    The device is identified by its serial number. A device is only accepted once
//    an admin sets `enabled: true` on biometric_devices/<serial>. Unknown devices
//    are recorded there (disabled) so the admin can see and approve them.
//
// 2. Any other system (Matrix, Hikvision, a custom gateway) can POST JSON:
//      POST /punches
//      Authorization: Bearer <apiKey stored on biometric_devices/<deviceId>>
//      { "deviceId": "gate-1", "punches": [ { "userId": "21CS045", "time": "2026-11-04T09:02:00+05:30", "method": "face" } ] }

const core = require("./attendance_core");

function text(status, body) {
  return { status, body, contentType: "text/plain" };
}
function json(status, body) {
  return { status, body: JSON.stringify(body), contentType: "application/json" };
}

// Load a device; record unknown ones (disabled) so an admin can approve them.
async function loadDevice(db, serverTimestamp, deviceId, extra = {}) {
  const ref = db.collection("biometric_devices").doc(deviceId);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({ enabled: false, firstSeenAt: serverTimestamp(), lastSeenAt: serverTimestamp(), ...extra }, { merge: true });
    return null;
  }
  await ref.set({ lastSeenAt: serverTimestamp() }, { merge: true });
  const device = snap.data() || {};
  return device.enabled === true ? device : null;
}

async function handleIclock(db, serverTimestamp, req, endpoint) {
  const serial = String((req.query && req.query.SN) || "").trim();
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(serial)) return text(400, "ERROR: missing SN");

  if (endpoint === "getrequest" || endpoint === "devicecmd") return text(200, "OK");

  const device = await loadDevice(db, serverTimestamp, serial, { protocol: "zkteco-adms" });

  if (req.method === "GET") {
    // Answer the handshake even before approval, so the device stays connected
    // and starts sending as soon as an admin enables it.
    return text(200, core.handshakeResponse(serial));
  }

  const table = String((req.query && req.query.table) || "").toUpperCase();
  if (table !== "ATTLOG") return text(200, "OK"); // OPERLOG, user lists, photos: not needed
  if (!device) return text(200, "OK: 0"); // not approved yet; acknowledge so it doesn't retry forever

  const offset = Number.isFinite(device.utcOffsetMinutes) ? device.utcOffsetMinutes : core.DEFAULT_UTC_OFFSET_MINUTES;
  const rows = core.parseAttlog(req.rawBody);
  let accepted = 0;
  for (const row of rows) {
    const at = core.parseDeviceTime(row.time, offset);
    if (!at) continue;
    await core.ingestPunch(db, serverTimestamp, { device, deviceId: serial, pin: row.pin, at, method: row.method });
    accepted += 1;
  }
  return text(200, `OK: ${accepted}`);
}

async function handleJson(db, serverTimestamp, req) {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  let body = req.body;
  if (typeof body === "string" || body === undefined) {
    try {
      body = JSON.parse(req.rawBody || "{}");
    } catch (e) {
      return json(400, { error: "invalid JSON" });
    }
  }
  const deviceId = String((body && body.deviceId) || "").trim();
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(deviceId)) return json(400, { error: "deviceId required" });

  const auth = String((req.headers && (req.headers.authorization || req.headers.Authorization)) || "");
  const key = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const snap = await db.collection("biometric_devices").doc(deviceId).get();
  const device = snap.exists ? snap.data() : null;
  if (!device || device.enabled !== true || !device.apiKey || key !== device.apiKey) {
    return json(401, { error: "unknown device or wrong key" });
  }

  const punches = Array.isArray(body.punches) ? body.punches.slice(0, 500) : [];
  let accepted = 0;
  for (const p of punches) {
    const pin = String((p && p.userId) || "").trim();
    const at = new Date(p && p.time);
    if (!pin || Number.isNaN(at.getTime())) continue;
    const method = ["fingerprint", "face", "card", "palm"].includes(p.method) ? p.method : "biometric";
    await core.ingestPunch(db, serverTimestamp, { device, deviceId, pin, at, method });
    accepted += 1;
  }
  return json(200, { accepted });
}

// Route a request. `req` needs: method, path, query, headers, rawBody (string), body (parsed, optional).
async function handleBiometricRequest(db, serverTimestamp, req) {
  const path = String(req.path || "/");
  const iclock = /\/iclock\/(cdata|getrequest|devicecmd)(?:\.aspx)?\/?$/i.exec(path);
  if (iclock) return handleIclock(db, serverTimestamp, req, iclock[1].toLowerCase());
  if (/\/punches\/?$/.test(path)) return handleJson(db, serverTimestamp, req);
  return text(404, "Not found");
}

module.exports = { handleBiometricRequest };
