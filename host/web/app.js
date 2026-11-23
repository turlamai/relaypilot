// RelayPilot S0 carrier probe (#13). Boot smoke: the page loads over the
// glaze carrier, the host health route answers, the i18n single source is
// served, and the token sheet (shared.css) resolves real values. Journeys
// run only when BOTH ?e2e=1 and the host gate (RELAYPILOT_E2E=1) are on.
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
  return { status: res.status, json: await res.json().catch(() => null) };
}

async function get(path) {
  const res = await fetch(path);
  return { status: res.status, json: await res.json().catch(() => null) };
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
