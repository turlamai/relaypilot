// RelayPilot product journey (#13 S2): drives the real UI in index.html
// (clicks, typing, dialogs) and asserts what the user would see. Loaded by
// app.js only when both ?e2e=1 and the host gate (RELAYPILOT_E2E=1) are on.
// Verdicts go to the host harness route as a typed report, like probe.js.
export async function runJourney(app) {
  const { state, rpc, get, t, refresh, trace } = app;
  const report = { phase: "running", ok: false, view: "product", steps: {} };
  const push = async () => {
    report.steps = {};
    for (const [id, s] of Object.entries(temp)) report.steps[id] = s;
    await post("/api/host/e2e_report", { payload: report });
  };
  const temp = {};
  const assert = (cond, msg) => { if (!cond) throw new Error(msg); };
  async function post(path, body) {
    const res = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body || {}) });
    return { status: res.status, json: await res.json().catch(() => null) };
  }
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const activeEntry = () => state.profiles.find((p) => p.id === state.activeId);
  async function waitUntil(pred, ms = 15000) {
    const end = Date.now() + ms;
    while (!pred()) { if (Date.now() > end) throw new Error("timeout waiting for UI state"); await sleep(50); }
  }
  const idle = () => waitUntil(() => !state.busy);
  const q = (sel, parent = document) => parent.querySelector(sel);
  async function click(sel, parent = document) {
    const el = q(sel, parent);
    assert(el, "missing element " + sel);
    assert(!el.disabled, "disabled element " + sel);
    el.click();
    await sleep(30);
  }
  const setVal = (sel, value, parent = document) => { const el = q(sel, parent); assert(el, "missing " + sel); el.value = value; };
  const dialog = () => q("#modal");
  const rootEl = () => q("#root");
  const text = (sel, parent = document) => ((q(sel, parent) || {}).textContent || "");
  async function step(id, fn) {
    try { temp[id] = { ok: true, detail: String(await fn()) }; }
    catch (e) { temp[id] = { ok: false, detail: String((e && e.message) || e) }; }
    await push();
  }
  const tag = Date.now().toString(36).slice(-5);
  const nameA = `E2E Import ${tag}`;
  const nameB = `E2E Second ${tag}`;
  const source = "[Rule]\nDOMAIN-SUFFIX, lab.internal, DIRECT\nFINAL, DIRECT\n";
  let idA = "", idB = "";

  await step("boot", async () => {
    await waitUntil(() => state.root && !state.loadError);
    assert(q("h1").textContent === t("nav.overview"), "h1 " + q("h1").textContent);
    assert(document.querySelectorAll(".nav-button").length === 4, "nav entries");
    assert(text(".notice") === t("banner"), "banner");
    assert(q("#target-add"), "no add-target form");
    return `library ${state.root} · ${state.profiles.length} profiles · v${state.version}`;
  });

  await step("import", async () => {
    const wasEmpty = state.profiles.length === 0;
    await click('[data-action="import"]');
    assert(dialog().open, "import dialog did not open");
    setVal("#import-name", nameA, dialog());
    setVal("#import-source", source + "\n[URL Rewrite]\n^https://example.com https://example.org 302", dialog());
    await click('[data-action="preview-import"]', dialog());
    await idle();
    assert(text("#dialog-title", dialog()) === t("import.preview.title"), "preview " + text("#dialog-title", dialog()));
    assert(text(".diff", dialog()).includes(t("import.preview.unsupportedCount", 1)), "unsupported count");
    const create = q('[data-action="confirm-import"]', dialog());
    assert(create.disabled, "create should wait for the ack");
    q("#import-ack", dialog()).checked = true;
    q("#import-ack", dialog()).dispatchEvent(new Event("change", { bubbles: true }));
    await click('[data-action="confirm-import"]', dialog());
    await idle();
    const entry = state.profiles.find((p) => p.name === nameA);
    assert(entry && entry.status === "valid" && entry.ruleCount === 2, "entry " + JSON.stringify(entry));
    idA = entry.id;
    assert(state.view === "profiles" && state.selected === idA, "view/selection");
    assert(document.querySelectorAll(".rule-row").length === 2, "rule rows");
    if (wasEmpty) assert(state.activeId === idA, "first profile becomes active");
    return `${entry.name} · ${entry.ruleCount} rules · 1 unsupported line acknowledged`;
  });

  await step("import-rejected", async () => {
    await click('[data-action="import"]');
    setVal("#import-name", nameA, dialog());
    setVal("#import-source", source, dialog());
    await click('[data-action="preview-import"]', dialog());
    await idle();
    const err = q("#import-error", dialog());
    assert(err && !err.hidden && err.textContent === t("import.error.name"), "inline error " + (err && err.textContent));
    await click('[data-action="close-modal"]', dialog());
    return "duplicate name refused before any write";
  });

  await step("saved-target", async () => {
    await click('[data-view="connect"]');
    setVal("#target-add", "nas.lab.internal");
    q('[data-form="add-target"]').requestSubmit();
    await idle();
    await waitUntil(() => state.routes["nas.lab.internal"]);
    const row = text('[data-route="nas.lab.internal"]');
    const r = state.routes["nas.lab.internal"];
    assert(r.policy === "DIRECT" && row === t("targets.result", t("policy.direct"), r.outbound), "route row " + row + " / " + JSON.stringify(r));
    return row;
  });

  await step("route-patch", async () => {
    await click('[data-action="patch"][data-target="nas.lab.internal"]');
    setVal("#patch-policy", "REJECT", dialog());
    await click('[data-action="preview-patch"]', dialog());
    await idle();
    assert(text("#dialog-title", dialog()) === t("patch.confirm.title"), "confirm " + text("#dialog-title", dialog()));
    assert(text(".diff", dialog()).includes(t("policy.reject")), "diff shows next policy");
    await click('[data-action="apply-patch"]', dialog());
    await idle();
    assert(state.routes["nas.lab.internal"].policy === "REJECT", "policy " + state.routes["nas.lab.internal"].policy);
    assert(q('[data-action="undo"]'), "no undo offered");
    const read = JSON.parse(await rpc("library-read-profile", { root: state.root, profileId: state.activeId }));
    assert(read.rules[0] === "DOMAIN,nas.lab.internal,REJECT", "rules " + read.rules[0]);
    return read.rules[0];
  });

  await step("undo", async () => {
    await click('.topbar [data-action="undo"]');
    await idle();
    assert(state.routes["nas.lab.internal"].policy === "DIRECT", "policy " + state.routes["nas.lab.internal"].policy);
    assert(activeEntry().ruleCount === 2, "ruleCount " + activeEntry().ruleCount);
    assert(!state.undo, "undo stack should clear");
    return "restored snapshot → DIRECT · 2 rules";
  });

  await step("trace", async () => {
    await click('[data-view="trace"]');
    setVal("#target", "lab.internal");
    q('[data-form="inspect"]').requestSubmit();
    await idle();
    assert(q(".result-heading h2") && q(".result-heading h2").textContent === "lab.internal", "target heading");
    assert(text(".actual-result strong") === t("policy.direct"), "result " + text(".actual-result strong"));
    assert(text(".route-explanation").includes(String(t("trace.cause.suffix", 1))), "cause " + text(".route-explanation"));
    const sel = q("#expected-policy");
    sel.value = "REJECT";
    sel.dispatchEvent(new Event("change", { bubbles: true }));
    assert(text(".result-heading .badge") === t("trace.mismatch"), "badge " + text(".result-heading .badge"));
    await click('[data-view="connect"]');
    assert(q('.list [data-action="inspect-target"][data-target="lab.internal"]'), "no mismatch row in 待处理");
    await click('.list [data-action="inspect-target"][data-target="lab.internal"]');
    await idle();
    await click('.route-explanation [data-action="patch"]');
    setVal("#patch-policy", "REJECT", dialog());
    await click('[data-action="preview-patch"]', dialog());
    await idle();
    await click('[data-action="apply-patch"]', dialog());
    await idle();
    assert(trace.decision.policy === "REJECT" && text(".result-heading .badge") === t("trace.match"), "after patch " + text(".result-heading .badge"));
    await click('.topbar [data-action="undo"]');
    await idle();
    assert(trace.decision.policy === "DIRECT", "undo " + trace.decision.policy);
    const sel2 = q("#expected-policy");
    sel2.value = "";
    sel2.dispatchEvent(new Event("change", { bubbles: true }));
    return "explain (rule 1, DOMAIN-SUFFIX) → expectation mismatch listed → patch → match → undo";
  });

  await step("export", async () => {
    assert(q('[data-action="redact"]').getAttribute("aria-checked") === "true", "redact should default to on");
    await click('[data-action="export"]');
    await idle();
    assert(trace.lastExport, "no export written");
    const redacted = (await post("/api/host/e2e_export_read", { path: trace.lastExport })).json;
    const bundle = JSON.parse(redacted);
    assert(bundle.traceId === "[redacted]" && !redacted.includes("lab.internal"), "redacted bundle leaks: " + redacted.slice(0, 80));
    await click('[data-action="redact"]');
    await click('[data-action="export"]');
    await idle();
    const full = (await post("/api/host/e2e_export_read", { path: trace.lastExport })).json;
    assert(full.includes("lab.internal") && JSON.parse(full).traceId !== "[redacted]", "full bundle " + full.slice(0, 80));
    await click('[data-action="redact"]');
    return "redacted bundle written → target hidden; redact off → target + trace id kept";
  });

  await step("editor", async () => {
    await click('[data-view="profiles"]');
    await click(`[data-profile="${idA}"]`);
    await waitUntil(() => state.detail && state.detail.rules);
    await click('[data-action="edit-profile"]');
    setVal("#rules-source", "FINAL, REJECT", dialog());
    await click('[data-action="preview-profile"]', dialog());
    await idle();
    assert(text("#dialog-title", dialog()) === t("editor.confirm.title"), "confirm " + text("#dialog-title", dialog()));
    await click('[data-action="save-profile"]', dialog());
    await idle();
    assert(activeEntry().ruleCount === 1 && state.detail.rules[0] === "FINAL,REJECT", "after save " + JSON.stringify(state.detail.rules));
    await click('.topbar [data-action="undo"]');
    await idle();
    assert(activeEntry().ruleCount === 2, "undo ruleCount " + activeEntry().ruleCount);
    return "validate → preview → save (1 rule) → undo (2 rules)";
  });

  await step("editor-rejected", async () => {
    await click('[data-action="edit-profile"]');
    setVal("#rules-source", "FINAL, NOPE", dialog());
    await click('[data-action="preview-profile"]', dialog());
    await idle();
    const err = q("#rules-error", dialog());
    assert(err && !err.hidden && err.textContent.includes("unknown-rule-policy"), "issues " + (err && err.textContent));
    assert(activeEntry().ruleCount === 2, "rejected text must not be written");
    await click('[data-action="close-modal"]', dialog());
    return err.textContent.slice(0, 60);
  });

  await step("switch", async () => {
    await click('[data-action="import"]');
    setVal("#import-name", nameB, dialog());
    setVal("#import-source", "[Rule]\nDOMAIN-SUFFIX, example.com, DIRECT\nFINAL, DIRECT\n", dialog());
    await click('[data-action="preview-import"]', dialog());
    await idle();
    await click('[data-action="confirm-import"]', dialog());
    await idle();
    const entry = state.profiles.find((p) => p.name === nameB);
    assert(entry && entry.id, "second profile");
    idB = entry.id;
    await click(`[data-profile="${idB}"]`);
    await waitUntil(() => state.detail && state.detail.rules && state.selected === idB);
    await click('[data-action="use-profile"]');
    await click('[data-action="confirm-profile"]', dialog());
    await idle();
    assert(state.activeId === idB, "active " + state.activeId);
    await click('.topbar [data-action="undo"]');
    await idle();
    assert(state.activeId === idA, "active after undo " + state.activeId);
    return `switch to ${entry.name} → undo → ${activeEntry().name}`;
  });

  await step("delete", async () => {
    const before = state.profiles.length;
    await click(`[data-profile="${idB}"]`);
    await waitUntil(() => state.selected === idB && state.detail);
    assert(q('[data-action="delete-profile"]'), "delete action missing for a non-active profile");
    await click('[data-action="delete-profile"]');
    await click('[data-action="confirm-delete"]', dialog());
    await idle();
    assert(state.profiles.length === before - 1, "count " + state.profiles.length);
    await click('.topbar [data-action="undo"]');
    await idle();
    assert(state.profiles.length === before, "count after undo " + state.profiles.length);
    return `deleted ${nameB} → undo restored the snapshot`;
  });

  await step("session", async () => {
    await click('[data-view="connect"]');
    await click('[data-action="session"]');
    await click('[data-action="start-session"]', dialog());
    await waitUntil(() => state.session !== "starting" && !state.busy);
    if (state.session === "running") {
      const port = state.handle.inboundPort;
      assert(port > 0, "inboundPort");
      const label = text(".session-title");
      assert(label === t("session.running"), "label " + label);
      await sleep(2200);
      await click('[data-action="session"]');
      await click('[data-action="stop-session"]', dialog());
      await idle();
      assert(state.session === "idle", "session after stop");
      return `running on loopback ${port} → stopped`;
    }
    assert(state.session === "idle", "session " + state.session);
    assert(text("#toast").includes(t("session.engineUnavailable")), "toast " + text("#toast"));
    return "skipped: engine binary not configured · idle with the unavailable notice";
  });

  await step("i18n", async () => {
    const r = await get("/api/host/i18n");
    const zh = Object.keys(r.zh), en = Object.keys(r.en);
    assert(zh.length === en.length && zh.every((k) => k in r.en), "zh/en key parity");
    const leaks = Array.from(document.querySelectorAll("#root body, #root *")).map((n) => n.childNodes.length === 1 && n.firstChild.nodeType === 3 ? n.textContent : "").filter((s) => /%@|%lld/.test(s));
    assert(leaks.length === 0, "unformatted placeholders " + leaks[0]);
    return `${zh.length} keys × 2 · no raw placeholders`;
  });

  await step("settings", async () => {
    const pick = async (id, value) => {
      const el = q("#" + id, rootEl());
      assert(el, "missing #" + id);
      el.value = value;
      el.dispatchEvent(new Event("change", { bubbles: true }));
      await sleep(60);
    };
    await click('[data-view="settings"]');
    assert(text("h1") === t("nav.settings"), "h1 " + text("h1"));
    await pick("theme", "dark");
    assert(document.documentElement.dataset.theme === "dark", "theme " + document.documentElement.dataset.theme);
    await pick("theme", "light");
    assert(document.documentElement.dataset.theme === "light", "theme " + document.documentElement.dataset.theme);
    await pick("theme", "system");
    assert(text("h1") === t("nav.settings"), "heading back " + text("h1"));
    const before = state.redact;
    await click('[data-action="redact"]');
    assert(state.redact === !before, "redact switch");
    await click('[data-action="redact"]');
    return "theme dark/light · redact switch";
  });

  await step("tray", async () => {
    // Quick find: keyboard opens it, a profile pick opens that profile.
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "k", ctrlKey: true, bubbles: true }));
    await sleep(60);
    assert(dialog().open && q("#command-search", dialog()), "quick find dialog");
    const input = q("#command-search", dialog());
    input.value = nameA;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    await sleep(60);
    await click(`[data-open-profile="${idA}"]`, dialog());
    assert(!dialog().open && state.view === "profiles" && state.selected === idA, "profile pick " + state.view);
    // The carrier pushes tray picks over the event stream; open it now.
    await new Promise((resolve, reject) => {
      const es = app.connectEvents();
      const timer = setTimeout(() => reject(new Error("event stream did not open")), 15000);
      es.addEventListener("open", () => { clearTimeout(timer); resolve(); }, { once: true });
      es.addEventListener("error", () => { clearTimeout(timer); reject(new Error("event stream failed")); }, { once: true });
    });
    // The carrier holds the menu the page last posted and runs items itself.
    await sleep(200);
    const held = await get("/api/host/e2e_tray");
    const ids = held.menu.map((i) => i.id);
    for (const id of ["show", "quick-find", "profile:" + idA, "go:trace", "go:settings", "quit"]) assert(ids.includes(id), "menu lacks " + id);
    const checked = held.menu.find((i) => i.id === "profile:" + idA);
    assert(checked && checked.checked === true && checked.label === nameA, "active item " + JSON.stringify(checked));
    assert(held.view === state.view, "view " + held.view);
    await post("/api/host/e2e_tray_invoke", { id: "go:connect" });
    await waitUntil(() => state.view === "connect");
    return `quick find → ${nameA} · tray ${ids.length} items (${held.backend}) · pick go:connect → connect`;
  });

  await refresh();
  app.render();
  report.phase = "done";
  report.ok = Object.values(temp).every((s) => s.ok);
  report.stepCount = Object.keys(temp).length;
  await push();
}
