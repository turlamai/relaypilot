// RelayPilot carrier probe (#13). Boot smoke + RPC surface journey over the
// loopback HTTP adapter. Journeys run only when BOTH ?e2e=1 and the host
// gate (RELAYPILOT_E2E=1) are on; otherwise the page stays an idle boot
// probe. Verdicts are reported to the host harness route as a typed report.
"use strict";

const statusEl = document.getElementById("status");
const stepsEl = document.getElementById("steps");
const params = new URLSearchParams(location.search);
const e2e = params.get("e2e") === "1";

const steps = [];
function record(id, ok, detail) {
  steps.push({ id, ok, detail });
  const li = document.createElement("li");
  li.className = ok ? "ok" : "bad";
  li.innerHTML =
    `<span class="mark">${ok ? "✓" : "✗"}</span>` +
    `<span class="name"></span><span class="detail"></span>`;
  li.querySelector(".name").textContent = id;
  li.querySelector(".detail").textContent = detail || "";
  stepsEl.appendChild(li);
}

async function post(path, body) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body || {}),
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch (_) { /* non-JSON */ }
  return { status: res.status, json, text };
}

async function get(path) {
  const res = await fetch(path);
  return { status: res.status, json: await res.json().catch(() => null) };
}

async function rpc(name, args) {
  return post("/api/rpc/" + name, args);
}

function setStatus(text, cls) {
  statusEl.textContent = text;
  statusEl.className = "status" + (cls ? " " + cls : "");
}

const assert = (cond, msg) => { if (!cond) throw new Error(msg); };

async function boot() {
  const health = await get("/api/health");
  const gate = await post("/api/host/e2e", {});
  const enabled = !!(gate.json && gate.json.enabled);
  const version = health.json && health.json.version;
  if (!e2e || !enabled) {
    setStatus(
      `carrier ok · version ${version} · ` + (e2e ? "host gate off" : "idle (add ?e2e=1)"),
      "ok"
    );
    return;
  }
  setStatus("journey running…");
  const fx = ((await post("/api/host/e2e_fixtures", {})).json) || {};
  const report = { phase: "running", ok: false, steps: {} };
  const push = async () => {
    report.steps = {};
    for (const s of steps) report.steps[s.id] = { ok: s.ok, detail: s.detail };
    await post("/api/host/e2e_report", { payload: report });
  };
  async function step(id, fn) {
    try {
      record(id, true, await fn());
    } catch (e) {
      record(id, false, String((e && e.message) || e));
    }
    await push();
  }

  await step("health", async () => {
    assert(health.status === 200 && health.json && health.json.ok === "true",
           "status " + health.status);
    assert(health.json.carrier === "glaze", "carrier " + health.json.carrier);
    return "glaze " + version;
  });
  await step("i18n", async () => {
    const r = await get("/api/host/i18n");
    assert(r.status === 200 && r.json && r.json.zh && r.json.en, "status " + r.status);
    const zhKeys = Object.keys(r.json.zh).length;
    const enKeys = Object.keys(r.json.en).length;
    assert(zhKeys > 0 && zhKeys === enKeys, `zh ${zhKeys} / en ${enKeys}`);
    return `${zhKeys} keys × 2`;
  });
  await step("token-sheet", async () => {
    const cs = getComputedStyle(document.documentElement);
    const accent = cs.getPropertyValue("--accent").trim();
    const bg = cs.getPropertyValue("--bg").trim();
    assert(accent && bg, "shared.css tokens unresolved");
    assert(getComputedStyle(document.body).backgroundColor !== "rgba(0, 0, 0, 0)",
           "body background not applied from tokens");
    return `--accent ${accent}`;
  });

  // ---- RPC surface (S1): every call goes through rivet/bridge to the
  // production backend; the page never reimplements a decision.
  await step("explain-route", async () => {
    const r = await rpc("explain-route", { profileJson: fx.profileJson, domain: "api.openai.com",
                                           ip: "", port: 443, network: "tcp" });
    assert(r.status === 200 && r.json, "status " + r.status + " " + r.text);
    assert(r.json.policy === "AI" && r.json.outbound === "us-reality-01",
           "policy " + r.json.policy + " / " + r.json.outbound);
    assert(r.json.ruleIndex === 1, "ruleIndex " + r.json.ruleIndex);
    return `${r.json.policy} → ${r.json.outbound}`;
  });
  await step("diagnose-route", async () => {
    const r = await rpc("diagnose-route", { profileJson: fx.profileJson, domain: "nas.lab.internal",
                                            ip: "", port: 443, network: "tcp", redact: true });
    assert(r.status === 200 && typeof r.json === "string", "status " + r.status);
    const bundle = JSON.parse(r.json);
    assert(bundle.traceId === "[redacted]", "traceId " + bundle.traceId);
    assert(!r.json.includes("lab.internal"), "redacted export leaks the target");
    return "redacted bundle · " + Object.keys(bundle).length + " fields";
  });
  await step("compile-engine-config", async () => {
    const r = await rpc("compile-engine-config", { profileJson: fx.profileJson });
    assert(r.status === 200 && r.json, "status " + r.status + " " + r.text);
    assert(r.json.adapter === "xray", "adapter " + r.json.adapter);
    assert(/^[0-9a-f]{64}$/.test(r.json.sha256), "sha256 " + r.json.sha256);
    return r.json.adapter + " " + r.json.adapterVersion + " " + r.json.sha256.slice(0, 12);
  });
  let engineAvailable = false;
  await step("engine-dry-run", async () => {
    const r = await rpc("engine-dry-run", { profileJson: fx.profileJson, socksPort: 1080 });
    assert(r.status === 200 && r.json, "status " + r.status + " " + r.text);
    assert(r.json.adapter === "xray", "adapter " + r.json.adapter);
    assert(Array.isArray(r.json.engineOutput) && r.json.engineOutput.length > 0, "no engine output");
    engineAvailable = r.json.available === true;
    return engineAvailable
      ? `xray ${r.json.engineVersion} · validated ${r.json.validated}`
      : "engine not configured · " + String(r.json.engineOutput[0]).slice(0, 48);
  });
  await step("engine-session", async () => {
    if (!engineAvailable) return "skipped: engine binary not configured (dry-run reported unavailable)";
    const s = await rpc("engine-session-start", { profileJson: fx.profileJson, socksPort: 0 });
    assert(s.status === 200 && s.json && s.json.sessionId, "start " + s.status + " " + s.text);
    assert(s.json.inboundPort > 0, "inboundPort " + s.json.inboundPort);
    const e = await rpc("engine-session-events", { sessionId: s.json.sessionId });
    assert(e.status === 200 && Array.isArray(e.json), "events " + e.status);
    const x = await rpc("engine-session-stop", { sessionId: s.json.sessionId });
    assert(x.status === 200 && x.json.stopped === true, "stop " + x.status + " " + x.text);
    const again = await rpc("engine-session-stop", { sessionId: s.json.sessionId });
    assert(again.json.stopped === false && again.json.exitStatus === "unknown-session",
           "double stop " + again.text);
    return `session ${s.json.inboundPort} → exit ${x.json.exitStatus} · ${x.json.events.length} events`;
  });
  await step("library-flow", async () => {
    const root = fx.libraryRoot;
    const text = "[Rule]\nDOMAIN-SUFFIX, lab.internal, DIRECT\nFINAL, DIRECT\n";
    const empty = await rpc("library-list", { root });
    assert(empty.status === 200 && empty.json.profiles.length === 0, "library not empty");
    const created = await rpc("library-import-commit",
      { root, name: "E2E Import", description: "wire description", text });
    assert(created.status === 200 && created.json.profileId, "commit " + created.status + " " + created.text);
    assert(created.json.ruleCount === 2, "ruleCount " + created.json.ruleCount);
    const id = created.json.profileId;

    const snap = await rpc("library-list", { root });
    assert(snap.json.activeProfileId === id && snap.json.profiles.length === 1, "snapshot");
    const entry = snap.json.profiles[0];
    assert(entry.status === "valid" && entry.name === "E2E Import", "entry " + entry.status);

    const read = await rpc("library-read-profile", { root, profileId: id });
    assert(typeof read.json === "string" && read.json.includes("E2E Import"), "read");

    const pv = await rpc("library-patch-preview",
      { root, profileId: id, target: "nas.lab.internal", policy: "REJECT" });
    assert(pv.json.currentPolicy === "DIRECT" && pv.json.nextPolicy === "REJECT",
           "preview " + pv.text);
    const applied = await rpc("library-patch-apply",
      { root, profileId: id, target: "nas.lab.internal", policy: "REJECT" });
    assert(applied.json.ruleIndex === 1 && applied.json.rules[0] === "DOMAIN,nas.lab.internal,REJECT",
           "apply " + applied.text);

    const issues = await rpc("library-validate-rules",
      { root, profileId: id, rulesText: "FINAL,DIRECT\n" });
    assert(Array.isArray(issues.json) && issues.json.length === 0, "issues " + issues.text);
    const upd = await rpc("library-update-rules",
      { root, profileId: id, rulesText: "FINAL,DIRECT\n" });
    assert(upd.json.ruleCount === 1, "update " + upd.text);

    const before = await rpc("library-read-profile", { root, profileId: id });
    await rpc("library-set-active", { root, profileId: id });
    const restored = await rpc("library-restore-profile", { root, profileJson: before.json });
    assert(restored.json.profileId === id && restored.json.ruleCount === 1, "restore " + restored.text);

    const ip = await rpc("library-import-preview", { root, name: "E2E Import", text });
    assert(ip.json.nameAvailable === false && ip.json.importableRules.length === 2,
           "import preview " + ip.text);
    return "import → list → read → patch → validate → update → restore · 7 RPCs ok";
  });
  await step("error-channel", async () => {
    const r = await rpc("library-read-profile", { root: fx.libraryRoot, profileId: "missing" });
    assert(r.status === 400, "expected 400, got " + r.status);
    assert(r.json && r.json.error, "no backend message");
    assert(/not found/.test(String(r.json.error)), "unexpected message: " + r.json.error);
    return "400: " + String(r.json.error).slice(0, 48);
  });

  report.phase = "done";
  report.ok = steps.every((s) => s.ok);
  report.stepCount = steps.length;
  await post("/api/host/e2e_report", { payload: report });
  setStatus(
    report.ok ? `journey ok · ${steps.length} steps` : `journey FAILED · see steps`,
    report.ok ? "ok" : "bad"
  );
}

window.addEventListener("error", (ev) => setStatus("probe error: " + ev.message, "bad"));
window.addEventListener("unhandledrejection", (ev) =>
  setStatus("probe rejection: " + ev.reason, "bad"));
boot().catch((e) => setStatus("probe boot failed: " + e, "bad"));
