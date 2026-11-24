// RelayPilot product UI (#13 S2): overview/connect + profile library, evolved
// from design/prototype/app.js. Every decision, validation and mutation comes
// from the engine through the typed RPC routes (host/main.rkt); the page never
// re-implements routing or rule validation. Strings come from shared/i18n.
"use strict";
(() => {
  const root = document.getElementById("root");
  const modal = document.getElementById("modal");
  const toast = document.getElementById("toast");
  const params = new URLSearchParams(location.search);
  const e2e = params.get("e2e") === "1";
  const PREF_KEY = "relaypilot-ui-v1";
  const $ = (selector, parent = document) => parent.querySelector(selector);

  // ---- icons (prototype set) ----------------------------------------------
  const paths = {
    grid: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
    route: "M5 3v12a4 4 0 0 0 4 4h10 M15 15l4 4-4 4 M5 7h10a4 4 0 0 1 4 4v1",
    file: "M14 2H5v20h14V7z M14 2v6h5 M8 12h8 M8 16h6",
    arrow: "M5 12h14 M14 7l5 5-5 5",
    check: "M5 12l4 4L19 6",
    close: "M6 6l12 12 M18 6L6 18",
    power: "M12 2v10 M5 5a9 9 0 1 0 14 0",
    shield: "M12 3l8 3v6c0 5-8 9-8 9S4 17 4 12V6z M8 12l3 3 5-6",
    info: "M12 11v6 M12 7h.01 M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
    plus: "M12 5v14 M5 12h14",
    warning: "M12 3L2 21h20z M12 9v5 M12 17h.01",
    settings: "M4 7h16 M4 17h16 M8 4v6 M16 14v6",
    search: "M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14z M16 16l5 5",
    search: "M20 20l-5-5 M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0",
    copy: "M9 9h12v12H9z M15 5V3H3v12h2"
  };
  const icon = (name) =>
    `<svg class="od-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name] || paths.info}"/></svg>`;
  const esc = (value) =>
    String(value).replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));

  // ---- transport ------------------------------------------------------------
  class ApiError extends Error {
    constructor(message, status) { super(message); this.status = status; }
  }
  async function post(path, body) {
    const res = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {})
    });
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch (_) { /* non-JSON */ }
    if (!res.ok) throw new ApiError((json && (json.error || json.code)) || text || "HTTP " + res.status, res.status);
    return json;
  }
  async function get(path) {
    const res = await fetch(path);
    if (!res.ok) throw new ApiError("HTTP " + res.status, res.status);
    return res.json();
  }
  const rpc = (name, args) => post("/api/rpc/" + name, args);

  // ---- i18n (single source: shared/i18n via /api/host/i18n) ----------------
  let strings = {};
  function t(key, ...args) {
    let i = 0;
    const text = Object.prototype.hasOwnProperty.call(strings, key) ? strings[key] : key;
    return String(text).replace(/%lld|%@/g, () => (i < args.length ? String(args[i++]) : ""));
  }

  // ---- state ----------------------------------------------------------------
  const state = {
    view: "connect",
    root: "",
    version: "",
    profiles: [],
    activeId: "",
    activeRaw: "",
    activeJson: null,
    selected: "",
    detail: null,          // parsed profile JSON of the selected entry (or { error })
    query: "",
    filter: "all",
    session: "idle",        // idle | starting | running
    handle: null,           // { sessionId, inboundPort, engineVersion }
    targets: [],
    expectations: {},     // domain -> expected policy id (comparison only)
    redact: true,          // diagnostic export hides the target + trace id
    theme: "system",       // system | light | dark (html[data-theme])
    routes: {},             // domain -> RouteDecision | null
    events: [],
    undo: null,
    loadError: null,
    busy: false
  };
  const trace = { input: "", target: "", decision: null, inspecting: false, lastExport: "" };
  try {
    if (!e2e) {
      const saved = JSON.parse(localStorage.getItem(PREF_KEY) || "{}");
      if (Array.isArray(saved.targets)) state.targets = saved.targets.filter((x) => typeof x === "string");
      if (saved.expectations && typeof saved.expectations === "object") state.expectations = saved.expectations;
      if (typeof saved.redact === "boolean") state.redact = saved.redact;
      if (["system", "light", "dark"].includes(saved.theme)) state.theme = saved.theme;
    }
  } catch (_) { /* in-memory list remains available */ }
  function storePreferences() {
    if (e2e) return;
    try { localStorage.setItem(PREF_KEY, JSON.stringify({ targets: state.targets, expectations: state.expectations, redact: state.redact, theme: state.theme })); } catch (_) { /* session only */ }
  }
  // Theme: system follows the OS while the window is open; the token sheet
  // (shared.css) carries the light and dark sets behind html[data-theme].
  function applyTheme() {
    const dark = state.theme === "dark" || (state.theme === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
    document.documentElement.dataset.theme = dark ? "dark" : "light";
  }
  applyTheme();
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", applyTheme);
  // Interface text follows the system language (single source: shared/i18n).
  function applyLocale(i18n, locale) {
    strings = i18n[locale] || i18n.zh || {};
    document.documentElement.lang = locale === "en" ? "en" : "zh-CN";
  }

  const names = { connect: "nav.overview", trace: "nav.trace", profiles: "nav.profiles", settings: "nav.settings" };
  const navIcons = { connect: "grid", trace: "route", profiles: "file", settings: "settings" };
  const keyboard = /Mac|iPhone|iPad/.test(navigator.platform || "") ? "⌘ K" : "Ctrl K";
  const active = () => state.profiles.find((p) => p.id === state.activeId) || null;
  const selected = () => state.profiles.find((p) => p.id === state.selected) || null;
  const running = () => state.session === "running";
  const busy = () => state.session === "starting";
  const policyName = (policy) =>
    policy === "DIRECT" ? t("policy.direct") : policy === "REJECT" ? t("policy.reject") : String(policy || t("policy.unset"));
  const validDomain = (value) =>
    value.length <= 253 && /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/i.test(value);
  const parseRule = (text) => {
    const parts = String(text).split(",").map((s) => s.trim());
    const kind = parts[0];
    if (kind === "FINAL") return { kind, value: "", policy: parts[1] || "", options: parts.slice(2) };
    return { kind, value: parts[1] || "", policy: parts[2] || "", options: parts.slice(3) };
  };
  const ruleLabel = (rule) => (rule.kind === "FINAL" ? t("profiles.rule.fallback") : rule.value);

  let notifyTimer;
  function notify(message, undoable = false) {
    clearTimeout(notifyTimer);
    toast.innerHTML = `<span>${esc(message)}</span>${undoable ? `<button type="button" data-action="undo">${esc(t("undo"))}</button>` : ""}<button type="button" data-action="dismiss">${esc(t("close"))}</button>`;
    toast.hidden = false;
    if (!undoable) notifyTimer = setTimeout(() => { toast.hidden = true; }, 5500);
  }
  function fail(e) { notify(t("common.error", (e && e.message) || String(e))); }
  function event(text) {
    state.events.unshift({ time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false }), text });
    state.events = state.events.slice(0, 8);
  }

  // ---- data ----------------------------------------------------------------
  async function readProfile(id) {
    return rpc("library-read-profile", { root: state.root, profileId: id });
  }
  async function refresh() {
    const snap = await rpc("library-list", { root: state.root });
    state.profiles = snap.profiles;
    state.activeId = snap.activeProfileId;
    if (!state.profiles.some((p) => p.id === state.selected)) state.selected = "";
    state.activeRaw = "";
    state.activeJson = null;
    state.routes = {};
    if (state.activeId) {
      state.activeRaw = await readProfile(state.activeId);
      state.activeJson = JSON.parse(state.activeRaw);
      await Promise.all(state.targets.map(async (domain) => {
        try {
          state.routes[domain] = await rpc("explain-route", { profileJson: state.activeRaw, domain, ip: "", port: 443, network: "tcp" });
        } catch (_) { state.routes[domain] = null; }
      }));
      if (trace.target) {
        try { trace.decision = await explain(trace.target); } catch (_) { trace.decision = null; }
      }
    } else {
      trace.decision = null;
    }
    if (state.selected) await loadDetail(state.selected, false);
  }
  const explain = (domain) => rpc("explain-route", { profileJson: state.activeRaw, domain, ip: "", port: 443, network: "tcp" });
  async function loadDetail(id, rerender = true) {
    state.detail = null;
    try {
      state.detail = JSON.parse(await readProfile(id));
    } catch (e) {
      state.detail = { error: e.message };
    }
    if (rerender) renderResults();
  }
  // One user action at a time; after it settles the library and the saved
  // target routes are re-read from the engine, then the UI re-renders once.
  async function run(fn) {
    if (state.busy) return;
    state.busy = true;
    try {
      await fn();
      if (state.root) await refresh();
    }
    catch (e) { fail(e); }
    finally { state.busy = false; render(); }
  }
  async function runUndo() {
    const undo = state.undo;
    state.undo = null;
    if (!undo) return;
    await run(async () => { await undo(); event(t("undo.done")); notify(t("undo.done")); });
  }
  const restoreUndo = (profileJson) => async () => {
    await rpc("library-restore-profile", { root: state.root, profileJson });
  };

  // ---- shell ----------------------------------------------------------------
  function shell(content) {
    const pending = state.profiles.filter((p) => p.status !== "valid").length;
    const nav = Object.entries(names).map(([id, key]) =>
      `<button type="button" class="nav-button ${state.view === id ? "active" : ""}" data-view="${id}" ${state.view === id ? 'aria-current="page"' : ""}>${icon(navIcons[id])}<span>${esc(t(key))}</span>${id === "profiles" ? `<span class="nav-meta">${pending ? pending + " " + esc(t("pending.title")) : state.profiles.length}</span>` : ""}</button>`).join("");
    const p = active();
    const footerLeft = `${esc(sessionName())}${p ? " · " + esc(p.name) : ""}`;
    const footerRight = state.root ? `${esc(t("overview.libraryPath"))}: ${esc(state.root)}` : "";
    return `<div class="app"><aside class="sidebar"><div class="wordmark"><span class="mark">${icon("route")}</span>RelayPilot</div><nav class="nav" aria-label="${esc(t("nav.label"))}">${nav}</nav><div class="sidebar-bottom"><div class="local-note">${icon("shield")}<span>${esc(t("sidebarNote")).replace(/\n/g, "<br>")}</span></div></div></aside><main class="main"><header class="topbar"><div class="breadcrumb"><span>${esc(t("workspace"))}</span><span aria-hidden="true">/</span><strong>${esc(t(names[state.view]))}</strong></div><div class="od-cluster"><button type="button" class="btn subtle command-trigger" data-action="commands" aria-label="${esc(t("settings.quickfind"))}">${icon("search")}<span>${esc(t("settings.quickfind"))}</span><kbd>${keyboard}</kbd></button>${state.undo ? `<button type="button" class="btn subtle" data-action="undo">${esc(t("topUndo"))}</button>` : ""}</div></header><div class="notice">${icon("info")}<span>${esc(t("banner"))}</span></div><div class="content">${content}</div><footer class="footer"><span>${footerLeft}</span><span>${footerRight}</span></footer></main></div>`;
  }
  const sessionName = () => (running() ? t("session.running") : busy() ? t("session.starting") : t("session.idle"));
  const heading = (title, description, action = "") =>
    `<div class="page-heading"><div><h1 tabindex="-1">${title}</h1><p>${description}</p></div>${action}</div>`;

  // ---- overview ------------------------------------------------------------
  function sessionSection() {
    const p = active();
    const label = sessionName();
    let sub, facts;
    if (!p) {
      sub = t("overview.emptyLibrary.body");
      facts = `<div><dt>${esc(t("fact.activeProfile"))}</dt><dd>—</dd><button type="button" class="action-link" data-action="import">${esc(t("profiles.import"))}</button></div><div><dt>${esc(t("fact.defaultRoute"))}</dt><dd>${esc(t("policy.unset"))}</dd></div><div><dt>${esc(t("overview.libraryPath"))}</dt><dd class="mono small" title="${esc(state.root)}">${esc(state.root)}</dd></div>`;
    } else {
      const fallback = (state.activeJson && state.activeJson.rules || []).map(parseRule).find((r) => r.kind === "FINAL");
      sub = running() ? t("session.running.sub") + " " + t("session.port", state.handle && state.handle.inboundPort) : busy() ? t("session.starting.sub") : t("session.idle.sub");
      facts = `<div><dt>${esc(t("fact.activeProfile"))}</dt><dd>${esc(p.name)}</dd><button type="button" class="action-link" data-action="choose-profile">${esc(t("fact.manageProfiles"))}</button></div><div><dt>${esc(t("fact.defaultRoute"))}</dt><dd>${esc(policyName(fallback ? fallback.policy : ""))}</dd><dd class="muted">${esc(fallback ? fallback.policy : t("fact.defaultRoute.none"))}</dd></div><div><dt>${esc(t("fact.profileStatus"))}</dt><dd>${esc(t("fact.rulesCount", p.ruleCount))}</dd><dd class="muted">${esc(p.status === "valid" ? t("fact.status.valid") : t("fact.status.invalid"))}</dd></div>`;
    }
    const button = running()
      ? `<button type="button" class="btn danger large" data-action="session" ${state.busy ? "disabled" : ""}>${icon("power")}${esc(t("session.stop"))}</button>`
      : `<button type="button" class="btn primary large" data-action="session" ${busy() || state.busy ? "disabled" : ""}>${icon("power")}${esc(busy() ? t("session.starting.button") : t("session.start"))}</button>`;
    return `<section class="session" aria-label="${esc(t("nav.overview"))}"><div class="session-top"><div class="session-state"><span class="status-emblem ${running() ? "running" : ""}">${icon(running() ? "check" : "power")}</span><div><div class="session-title" role="status">${esc(label)}</div><p class="session-sub">${esc(sub)}</p></div></div>${button}</div>${busy() ? '<div class="progress" aria-label="' + esc(t("session.starting")) + '"><span></span></div>' : ""}<dl class="fact-grid">${facts}</dl></section>`;
  }
  // Latest decision for a domain: the saved-target route, else the trace view.
  const decisionFor = (domain) => (trace.target === domain ? trace.decision : state.routes[domain]);
  function pendingSection() {
    const unresolved = state.profiles.filter((p) => p.status !== "valid");
    const mismatches = [...new Set([...state.targets, trace.target])].filter((d) => d && state.expectations[d] && decisionFor(d) && decisionFor(d).policy !== state.expectations[d]);
    const count = unresolved.length + mismatches.length;
    const body = count
      ? `<div class="list">${unresolved.map((item) => `<button type="button" class="list-row issue-row" data-open-profile="${esc(item.id)}"><span class="issue-symbol">${icon("warning")}</span><span class="od-field od-fill"><strong>${esc(item.name)}</strong><span class="hint">${esc(item.issues && item.issues[0] ? item.issues[0].detail : t("pending.invalidHint"))}</span></span><span class="row-action">${esc(t("pending.goProfile"))} ${icon("arrow")}</span></button>`).join("")}${mismatches.map((domain) => `<button type="button" class="list-row issue-row" data-action="inspect-target" data-target="${esc(domain)}"><span class="issue-symbol">${icon("route")}</span><span class="od-field od-fill"><strong class="mono">${esc(domain)}</strong><span class="hint">${esc(t("pending.mismatchHint", policyName(state.expectations[domain]), policyName(decisionFor(domain).policy)))}</span></span><span class="row-action">${esc(t("pending.viewDiff"))} ${icon("arrow")}</span></button>`).join("")}</div>`
      : `<div class="clear-state">${icon("check")}<div class="od-field"><strong>${esc(t("pending.clear.title"))}</strong><span>${esc(t("pending.clear.body"))}</span></div></div>`;
    return `<section class="section-block"><div class="section-head"><h2>${esc(t("pending.title"))}</h2><span class="badge ${count ? "warn" : "ok"}">${icon(count ? "warning" : "check")}${esc(count ? t("pending.count", count) : t("pending.clear"))}</span></div>${body}</section>`;
  }
  function targetsSection() {
    const rows = state.targets.length
      ? state.targets.map((domain) => {
          const r = state.routes[domain];
          const expected = state.expectations[domain] || "";
          const result = !state.activeId ? t("policy.unset") : r ? t("targets.result", policyName(r.policy), policyName(r.outbound)) : "…";
          return `<div class="list-row" data-target-row="${esc(domain)}"><button type="button" class="od-field od-fill target-link" data-action="inspect-target" data-target="${esc(domain)}"><strong class="mono">${esc(domain)}</strong><span class="hint" data-route="${esc(domain)}">${esc(result)}</span>${expected ? `<span class="small ${expected === (r && r.policy) ? "muted" : ""}">${esc(expected === (r && r.policy) ? t("target.match") : t("target.mismatch"))}</span>` : ""}</button><span class="od-cluster row-actions">${state.activeId ? `<button type="button" class="action-link" data-action="patch" data-target="${esc(domain)}">${esc(t("targets.patch"))}</button>` : ""}<button type="button" class="action-link" data-action="remove-target" data-target="${esc(domain)}">${esc(t("trace.removeTarget"))}</button></span></div>`;
        }).join("")
      : `<p class="empty">${esc(t("targets.empty"))}</p>`;
    return `<section><div class="section-head"><h2>${esc(t("targets.title"))}</h2><button type="button" class="action-link" data-view="trace">${esc(t("targets.inspectOthers"))}</button></div>${rows}<form class="search-form add-target" data-form="add-target"><div class="field"><label for="target-add">${esc(t("trace.field"))}</label><input id="target-add" type="text" inputmode="url" autocomplete="off" spellcheck="false" placeholder="${esc(t("targets.add.placeholder"))}" aria-describedby="target-add-error"></div><button type="submit" class="btn">${esc(t("targets.add"))}</button></form><p id="target-add-error" class="field-error" role="alert" hidden></p></section>`;
  }
  function eventsSection() {
    const rows = state.events.length
      ? state.events.map((e) => `<div class="event-row"><time>${esc(e.time)}</time><p>${esc(e.text)}</p></div>`).join("")
      : `<p class="empty">${esc(t("events.empty"))}</p>`;
    return `<section><div class="section-head"><h2>${esc(t("events.title"))}</h2><span class="small muted">${esc(t("events.recentFirst"))}</span></div>${rows}</section>`;
  }
  // ---- trace (S3) -------------------------------------------------------------
  // The decision comes from explain-route; the page only lays it out.
  function causeFor(d) {
    const rules = (state.activeJson && state.activeJson.rules) || [];
    const rule = d && d.ruleIndex > 0 ? parseRule(rules[d.ruleIndex - 1] || "") : null;
    if (!rule || !rule.kind) return t("trace.cause.none");
    if (rule.kind === "FINAL") return t("trace.cause.final");
    if (rule.kind === "DOMAIN") return t("trace.cause.exact", d.ruleIndex);
    if (rule.kind === "DOMAIN-SUFFIX") return t("trace.cause.suffix", d.ruleIndex);
    return t("trace.cause.cidr", d.ruleIndex);
  }
  async function inspectTarget(domain) {
    if (!validDomain(domain)) return;
    trace.target = domain;
    trace.input = domain;
    trace.decision = state.activeRaw ? await explain(domain) : null;
  }
  function traceView() {
    const p = active();
    const d = trace.decision;
    const target = trace.target;
    const expected = state.expectations[target] || "";
    const mismatch = !!(expected && d && expected !== d.policy);
    const targets = p ? (p.targets || []) : [];
    const form = `<form class="search-form" data-form="inspect"><div class="field"><label for="target">${esc(t("trace.field"))}</label><input id="target" type="text" inputmode="url" autocomplete="off" spellcheck="false" value="${esc(trace.input)}" aria-describedby="target-error" placeholder="${esc(t("targets.add.placeholder"))}"></div><button type="submit" class="btn primary" ${state.busy ? "disabled" : ""}>${icon("search")}${esc(t("trace.inspect"))}</button></form><p id="target-error" class="field-error" role="alert" hidden></p><div class="examples"><span>${esc(t("targets.title"))}</span>${state.targets.map((x) => `<button type="button" class="action-link" data-action="inspect-target" data-target="${esc(x)}">${esc(x)}</button>`).join("")}</div>`;
    if (!d) return heading(esc(t("nav.trace")), esc(t("trace.subtitle"))) + form + `<p class="empty">${esc(t("trace.prompt"))}</p>`;
    const rules = (state.activeJson && state.activeJson.rules) || [];
    const ruleText = d.ruleIndex > 0 ? (rules[d.ruleIndex - 1] || "") : "";
    const steps = (d.steps || []).map((s, i) => `<div class="trace-step"><span class="step-num">${String(i + 1).padStart(2, "0")}</span><div><p class="mono small">${esc(s)}</p></div></div>`).join("");
    const canPatch = p && p.status === "valid";
    return heading(esc(t("nav.trace")), esc(t("trace.subtitle"))) + form + `
      <section aria-label="${esc(t("trace.steps.title"))}">
        <div class="result-heading"><h2 class="mono">${esc(target)}</h2><span class="badge ${expected ? (mismatch ? "warn" : "ok") : ""}">${icon(expected ? (mismatch ? "warning" : "check") : "info")}${esc(t(expected ? (mismatch ? "trace.mismatch" : "trace.match") : "trace.noExpectationBadge"))}</span></div>
        <div class="comparison"><div class="expectation"><label for="expected-policy">${esc(t("trace.expectation.label"))}</label><select id="expected-policy"><option value="">${esc(t("trace.expectation.none"))}</option>${targets.map((x) => `<option value="${esc(x)}" ${expected === x ? "selected" : ""}>${esc(policyName(x))} · ${esc(x)}</option>`).join("")}</select><p>${esc(t("trace.expectation.note"))}</p></div><div class="actual-result"><span class="comparison-label">${esc(t("trace.actual"))}</span><strong>${esc(policyName(d.policy))}</strong><span class="mono">${esc(d.outbound)}</span></div></div>
        <div class="route-explanation ${mismatch ? "attention" : ""}"><div class="od-field od-fill"><strong>${esc(t(mismatch ? "trace.rule.diffSource" : ruleText ? "trace.rule.decides" : "trace.rule.supplement"))}</strong><span>${esc(causeFor(d))}</span><code>${esc(ruleText || t("policy.unset"))}</code></div>${canPatch ? `<button type="button" class="btn ${mismatch ? "primary" : ""}" data-action="patch" data-target="${esc(target)}">${esc(t("targets.patch"))}</button>` : ""}</div>
        ${state.targets.includes(target) ? "" : `<button type="button" class="action-link section-block" data-action="save-target">${esc(t("trace.saveTarget"))}</button>`}
        <div class="section-head section-block"><h2>${esc(t("trace.steps.title"))}</h2><span class="small muted">${esc(t("trace.steps.note"))}</span></div>
        <div class="trace-list">${steps || `<p class="empty">${esc(causeFor(d))}</p>`}</div>
        ${(d.warnings || []).map((w) => `<div class="note warn section-block">${icon("warning")}<div>${esc(w)}</div></div>`).join("")}
        <details class="technical section-block"><summary>${esc(t("trace.technical.title"))}</summary><dl><dt>${esc(t("trace.technical.traceId"))}</dt><dd>${esc(d.traceId)}</dd><dt>${esc(t("trace.technical.profile"))}</dt><dd>${esc(p ? p.name : "—")}</dd><dt>${esc(t("trace.technical.execution"))}</dt><dd>${esc(t("trace.technical.execution.value"))}</dd><dt>${esc(t("trace.technical.artifact"))}</dt><dd>${esc(t("trace.technical.noArtifact"))}</dd></dl>
          <div class="settings-row"><div class="od-field od-fill"><strong id="redact-label">${esc(t("settings.redact"))}</strong><span>${esc(t("settings.redact.desc"))}</span></div><button type="button" class="switch" role="switch" aria-checked="${state.redact}" aria-labelledby="redact-label" data-action="redact"><span>${esc(t(state.redact ? "switch.on" : "switch.off"))}</span>${icon(state.redact ? "check" : "close")}</button></div>
          <div class="od-cluster"><button type="button" class="btn" data-action="export">${esc(t("settings.export.button"))}</button><button type="button" class="btn" data-action="copy-trace">${icon("copy")}${esc(t("trace.copy"))}</button></div><p class="small muted">${esc(t("settings.export.desc"))}</p></details>
      </section>`;
  }
  async function exportDiagnostic() {
    const bundle = await rpc("diagnose-route", { profileJson: state.activeRaw, domain: trace.target, ip: "", port: 443, network: "tcp", redact: state.redact });
    // Destination: the native save panel; under the harness gate a fixture path.
    const pick = await post(e2e ? "/api/host/e2e_export" : "/api/dialog/save", e2e ? {} : { defaultName: "relaypilot-diagnostic.json" });
    if (!pick || !pick.path) return;
    await post("/api/host/write", { path: pick.path, data: bytesToB64(new TextEncoder().encode(bundle)) });
    trace.lastExport = pick.path;
    event(t("settings.export.done"));
    notify(t("settings.export.done"));
  }
  const bytesToB64 = (bytes) => { let s = ""; for (const b of bytes) s += String.fromCharCode(b); return btoa(s); };
  async function copyTrace() {
    const d = trace.decision;
    const text = `RelayPilot ${state.version}\n${t("trace.technical.traceId")}: ${d.traceId}\n${t("trace.field")}: ${trace.target}\n${t("trace.actual")}: ${d.policy} → ${d.outbound}\n${t("trace.technical.execution")}: ${t("trace.technical.execution.value")}`;
    try { await navigator.clipboard.writeText(text); notify(t("trace.copied")); }
    catch (_) { openDialog(esc(t("trace.copy")), esc(t("trace.copyFallback")), `<textarea aria-label="${esc(t("trace.copy"))}" readonly>${esc(text)}</textarea><div class="dialog-actions"><button type="button" class="btn" data-action="close-modal">${esc(t("close"))}</button></div>`); $("textarea", modal).select(); }
  }

  function overview() {
    return heading(esc(t("nav.overview")), esc(t("overview.subtitle"))) + sessionSection() + pendingSection() +
      `<div class="split section-block">${targetsSection()}${eventsSection()}</div>`;
  }

  // ---- profiles ------------------------------------------------------------
  const filteredProfiles = () =>
    state.profiles.filter((p) => (state.filter === "all" || p.status === state.filter) &&
      (p.name + " " + p.description).toLowerCase().includes(state.query.trim().toLowerCase()));
  const statusBadge = (p) => p.status === "valid"
    ? `<span class="badge ok">${esc(t("fact.status.valid"))}</span>`
    : `<span class="badge error">${esc(t("fact.status.invalid"))}</span>`;
  function profileResults() {
    const items = filteredProfiles();
    const p = selected();
    let detail = `<div class="selection-placeholder"><h2>${esc(items.length ? t("profiles.pick") : t("profiles.nomatch"))}</h2><p>${esc(items.length ? t("profiles.pick.body") : t("profiles.nomatch.body"))}</p><button type="button" class="btn" data-action="clear-filters">${esc(t("profiles.clearFilters"))}</button></div>`;
    if (p) {
      const isActive = p.id === state.activeId;
      const rules = state.detail && !state.detail.error ? (state.detail.rules || []) : null;
      const issues = p.issues && p.issues.length
        ? `<div class="note error section-block" role="status">${icon("warning")}<div><strong>${esc(t("profiles.issues.title"))}</strong><ul class="report-list">${p.issues.map((i) => `<li>${esc(i.detail)} <span class="muted small mono">${esc(i.code)}${i.index ? " · #" + i.index : ""}</span></li>`).join("")}</ul></div></div>`
        : "";
      const rulesHtml = rules === null
        ? (state.detail ? `<p class="empty">${esc(state.detail.error)}</p>` : `<p class="empty">…</p>`)
        : rules.length
          ? rules.map((text, i) => { const r = parseRule(text); return `<div class="rule-row"><span class="index">${String(i + 1).padStart(2, "0")}</span><span class="od-field"><span class="rule-target">${esc(ruleLabel(r))}</span><span class="small muted">${esc(r.kind)}</span></span><span class="small">${esc(r.policy)}</span></div>`; }).join("")
          : `<p class="empty">${esc(t("profiles.noRules"))}</p>`;
      const actions = p.status !== "valid"
        ? `<button type="button" class="btn primary" data-action="edit-profile">${esc(t("profiles.edit"))}</button>`
        : isActive
          ? `<span class="badge ok">${esc(t("profiles.badge.active"))}</span>`
          : `<button type="button" class="btn primary" data-action="use-profile">${esc(t("profiles.use"))}</button>`;
      detail = `<section class="profile-detail" aria-label="${esc(p.name)}"><div class="section-head"><h2>${esc(p.name)}</h2>${statusBadge(p)}</div><p class="muted small">${esc(p.description || t("profiles.description.placeholder"))}</p>${issues}<div class="section-head section-block"><h3>${esc(t("profiles.rules.title"))}</h3><span class="small muted">${esc(t("profiles.rulesCount", p.ruleCount))}</span></div>${rulesHtml}<div class="od-cluster section-block">${actions}<button type="button" class="btn" data-action="edit-profile" ${state.detail && state.detail.error ? "disabled" : ""}>${esc(t("profiles.edit"))}</button>${isActive ? "" : `<button type="button" class="btn danger" data-action="delete-profile">${esc(t("profiles.delete"))}</button>`}</div></section>`;
    }
    return `<p class="results-count" role="status">${esc(t("profiles.results", items.length, state.profiles.length))}</p><div class="profile-layout"><div class="profile-list" aria-label="${esc(t("nav.profiles"))}">${items.length ? items.map((item) => `<button type="button" class="profile-button ${item.id === state.selected ? "selected" : ""}" data-profile="${esc(item.id)}" aria-pressed="${item.id === state.selected}">${icon("file")}<span class="od-field od-fill"><strong>${esc(item.name)}</strong><span class="small muted">${esc(item.description || t("profiles.description.placeholder"))}</span><span>${item.id === state.activeId ? `<span class="badge ok">${esc(t("profiles.badge.active"))}</span>` : statusBadge(item)}</span></span></button>`).join("") : `<p class="empty">${esc(t("profiles.empty"))}</p>`}</div>${detail}</div>`;
  }
  function profiles() {
    return heading(esc(t("nav.profiles")), esc(t("profiles.subtitle")),
      `<button type="button" class="btn primary" data-action="import">${icon("plus")}${esc(t("profiles.import"))}</button>`) +
      `<div class="library-toolbar"><div class="field"><label for="profile-search">${esc(t("profiles.search"))}</label><input type="search" id="profile-search" autocomplete="off" placeholder="${esc(t("profiles.search.placeholder"))}" value="${esc(state.query)}"></div><div class="field"><label for="profile-filter">${esc(t("profiles.filter"))}</label><select id="profile-filter">${[["all", "profiles.filter.all"], ["valid", "profiles.filter.valid"], ["invalid", "profiles.filter.invalid"]].map(([v, k]) => `<option value="${v}" ${state.filter === v ? "selected" : ""}>${esc(t(k))}</option>`).join("")}</select></div></div><div id="profile-results">${profileResults()}</div>`;
  }

  function render() {
    const focusId = document.activeElement && document.activeElement.id;
    document.title = "RelayPilot — " + t(names[state.view]);
    root.innerHTML = shell(state.loadError
      ? `<div class="note error" role="alert">${icon("warning")}<div><strong>${esc(t("library.loadFailed", state.loadError))}</strong></div><button type="button" class="btn" data-action="retry">${esc(t("common.retry"))}</button></div>`
      : state.root ? ({ connect: overview, trace: traceView, profiles: profiles, settings: settingsView })[state.view]() : `<p class="empty">${esc(t("common.loading"))}</p>`);
    if (focusId) { const el = $("#" + focusId, root); if (el) el.focus(); }
    reportTrayState();
  }
  function renderResults() { const el = $("#profile-results", root); if (el) el.innerHTML = profileResults(); }
  function go(view) { state.view = view; render(); const h = $("h1", root); if (h) h.focus({ preventScroll: true }); }
  function openProfile(id) { state.query = ""; state.filter = "all"; state.view = "profiles"; state.selected = id; render(); loadDetail(id); }

  // ---- dialogs ---------------------------------------------------------------
  let modalReturn = null;
  function openDialog(title, description, body) {
    modalReturn = document.activeElement;
    modal.innerHTML = `<div class="dialog-header"><div><h2 id="dialog-title">${title}</h2>${description ? `<p>${description}</p>` : ""}</div><button type="button" class="btn subtle close-button" data-action="close-modal" aria-label="${esc(t("close"))}">${icon("close")}</button></div><div class="dialog-body">${body}</div>`;
    if (!modal.open) modal.showModal();
    const first = $("input:not([type=checkbox]),textarea,select,button", modal); if (first) first.focus();
  }
  function closeDialog() { if (modal.open) modal.close(); }
  modal.addEventListener("close", () => {
    const fallback = $(`[data-view="${state.view}"]`, root);
    (modalReturn && modalReturn.isConnected ? modalReturn : fallback || document.body).focus();
  });
  const actions = (primary, label, disabled = false, extra = "") =>
    `<div class="dialog-actions">${extra}<button type="button" class="btn" data-action="close-modal">${esc(t("cancel"))}</button><button type="button" class="btn primary" data-action="${primary}" ${disabled ? "disabled" : ""}>${label}</button></div>`;
  const inlineError = (id, message) => { const box = $("#" + id, modal); if (box) { box.textContent = message; box.hidden = !message; } };

  // session
  function confirmSession() {
    const p = active();
    if (!p) { fail(new Error(t("overview.emptyLibrary.body"))); return; }
    const stop = running();
    openDialog(esc(stop ? t("session.stopConfirm.title") : t("session.startConfirm.title")),
      esc(stop ? t("session.stopConfirm.body") : t("session.startConfirm.body")),
      `<div class="field"><span class="small muted">${esc(t("session.confirmProfileLabel"))}</span><strong class="mono">${esc(p.name)}</strong></div>${actions(stop ? "stop-session" : "start-session", esc(stop ? t("session.confirmStop") : t("session.confirmStart")))}`);
  }
  let pollTimer = null;
  let eventCursor = 0;
  function pollEvents() {
    if (!running()) return;
    rpc("engine-session-events", { sessionId: state.handle.sessionId }).then((list) => {
      if (!Array.isArray(list)) return;
      for (const line of list.slice(eventCursor)) event(String(line).slice(0, 160));
      const fresh = list.length < eventCursor || list.length > eventCursor;
      eventCursor = list.length;
      if (fresh && state.view === "connect") render();
    }).catch((e) => event(t("common.error", e.message)));
  }
  async function startSession() {
    closeDialog();
    const p = active();
    state.session = "starting";
    render();
    try {
      const dry = await rpc("engine-dry-run", { profileJson: state.activeRaw, socksPort: 0 });
      if (!dry.available) {
        state.session = "idle";
        event(t("session.engineUnavailable"));
        notify(t("session.engineUnavailable"));
        return;
      }
      const handle = await rpc("engine-session-start", { profileJson: state.activeRaw, socksPort: 0 });
      state.handle = handle;
      eventCursor = 0;
      state.session = "running";
      event(t("session.started"));
      notify(t("session.started"));
      pollTimer = setInterval(pollEvents, 2000);
      pollEvents();
    } catch (e) {
      state.session = "idle";
      event(t("session.startFailed"));
      throw e;
    }
  }
  async function stopSession() {
    closeDialog();
    const sessionId = state.handle && state.handle.sessionId;
    clearInterval(pollTimer);
    state.session = "idle";
    try {
      if (sessionId) await rpc("engine-session-stop", { sessionId });
    } finally {
      state.handle = null;
      event(t("session.stopped"));
      notify(t("session.stopped"));
    }
  }
  window.addEventListener("pagehide", () => {
    if (running() && state.handle) {
      fetch("/api/rpc/engine-session-stop", { method: "POST", keepalive: true, headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sessionId: state.handle.sessionId }) }).catch(() => {});
    }
  });

  // saved targets
  function addTarget() {
    const input = $("#target-add", root);
    const value = (input.value || "").trim().toLowerCase().replace(/\.$/, "");
    const error = $("#target-add-error", root);
    const refuse = (message) => { error.textContent = message; error.hidden = false; input.setAttribute("aria-invalid", "true"); input.focus(); };
    if (!validDomain(value)) return refuse(t("trace.error.domain"));
    if (state.targets.includes(value)) return refuse(t("targets.duplicate"));
    state.targets = [...state.targets, value].sort();
    storePreferences();
    run(async () => {
      if (state.activeRaw) {
        try { state.routes[value] = await rpc("explain-route", { profileJson: state.activeRaw, domain: value, ip: "", port: 443, network: "tcp" }); }
        catch (_) { state.routes[value] = null; }
      }
    });
  }
  function removeTarget(domain) {
    state.targets = state.targets.filter((d) => d !== domain);
    delete state.routes[domain];
    delete state.expectations[domain];
    storePreferences();
    event(t("trace.removedTarget"));
    render();
  }
  function inspectFromForm() {
    const input = $("#target", root);
    const value = (input.value || "").trim().toLowerCase().replace(/\.$/, "");
    const error = $("#target-error", root);
    if (!validDomain(value)) { error.textContent = t("trace.error.domain"); error.hidden = false; input.setAttribute("aria-invalid", "true"); input.focus(); return; }
    error.hidden = true;
    run(() => inspectTarget(value));
  }

  // route patch (single target, applied to the active profile)
  let patch = null;
  function patchDialog(domain) {
    const p = active();
    const options = (p.targets || []).map((id) => `<option value="${esc(id)}">${esc(policyName(id))} · ${esc(id)}</option>`).join("");
    patch = { target: domain, profileId: p.id };
    openDialog(esc(t("patch.title")), esc(t("patch.body")),
      `<div class="field"><span class="small muted">${esc(t("patch.target"))}</span><code class="source-code">${esc(domain)}</code></div><div class="field"><label for="patch-policy">${esc(t("patch.policy"))}</label><select id="patch-policy">${options}</select></div><p class="small muted">${esc(t("patch.note"))}</p><div class="note error" id="patch-error" role="alert" hidden></div>${actions("preview-patch", esc(t("patch.preview")))}`);
  }
  async function previewPatch() {
    const policy = $("#patch-policy", modal).value;
    const pv = await rpc("library-patch-preview", { root: state.root, profileId: patch.profileId, target: patch.target, policy });
    if (pv.sameAsCurrent) { inlineError("patch-error", t("patch.same")); return; }
    patch.policy = policy;
    openDialog(esc(t("patch.confirm.title")), esc(t("patch.confirm.body")),
      `<div class="diff"><div><h3>${esc(t("patch.confirm.before"))}</h3><p>${esc(policyName(pv.currentPolicy))}</p><p class="muted mono">${esc(pv.currentOutbound)}</p></div><div><h3>${esc(t("patch.confirm.after"))}</h3><p>${esc(policyName(pv.nextPolicy))}</p><p class="muted mono">${esc(pv.nextOutbound)}</p></div></div><code class="source-code">+ ${esc(pv.ruleText)}</code><div class="dialog-actions"><button type="button" class="btn" data-action="edit-rule">${esc(t("patch.back"))}</button><button type="button" class="btn primary" data-action="apply-patch">${esc(t("patch.confirm.apply"))}</button></div>`);
  }
  async function applyPatch() {
    const before = await readProfile(patch.profileId);
    await rpc("library-patch-apply", { root: state.root, profileId: patch.profileId, target: patch.target, policy: patch.policy });
    state.undo = restoreUndo(before);
    closeDialog();
    event(t("patch.applied.detail", patch.target, policyName(patch.policy)));
    notify(t("patch.applied"), true);
  }

  // import
  let draft = null;
  function importDialog(keep) {
    draft = keep || { name: "imported-profile", source: "" };
    openDialog(esc(t("import.title")), esc(t("import.body")),
      `<div class="field"><label for="import-name">${esc(t("import.name"))}</label><input type="text" id="import-name" maxlength="80" autocomplete="off" value="${esc(draft.name)}"></div><div class="field"><label for="import-source">${esc(t("import.source"))}</label><textarea id="import-source" spellcheck="false" placeholder="[Rule]&#10;DOMAIN-SUFFIX, example.com, DIRECT&#10;FINAL, DIRECT">${esc(draft.source)}</textarea></div><div id="import-error" class="note error" role="alert" hidden></div>${actions("preview-import", esc(t("import.preview")))}`);
  }
  async function previewImport() {
    const name = $("#import-name", modal).value.trim();
    const source = $("#import-source", modal).value;
    const refuse = (key) => inlineError("import-error", t(key));
    if (!name || /[\\/:*?"<>|]/.test(name)) return refuse("import.error.name");
    if (!source.trim()) return refuse("import.error.empty");
    const pv = await rpc("library-import-preview", { root: state.root, name, text: source });
    draft = { name, source, preview: pv };
    if (!pv.nameAvailable) return refuse("import.error.name");
    if (!pv.importableRules.length) return refuse("import.error.empty");
    openDialog(esc(t("import.preview.title")), esc(t("import.preview.body")),
      `<div class="diff"><div><h3>${esc(t("import.preview.rulesCount", pv.importableRules.length))}</h3><p>${esc(pv.placeholderGroups.length ? t("import.preview.groupsCount", pv.placeholderGroups.length) : t("import.preview.groupsNone"))}</p><p class="muted">${esc(pv.hasFinal ? "FINAL" : pv.warnings[0] || "")}</p></div><div><h3>${esc(t("import.preview.unsupportedCount", pv.unsupported.length))}</h3><p class="muted">${esc(pv.unsupported.length ? "" : t("import.preview.allSupported"))}</p></div></div>${pv.unsupported.length ? `<div><h3>${esc(t("import.preview.unsupportedTitle"))}</h3><ul class="report-list">${pv.unsupported.map((u) => `<li><strong>${esc(t("import.preview.line", u.line, u.text))}</strong><br><span class="muted">${esc(u.detail)} <span class="mono small">${esc(u.code)}</span></span></li>`).join("")}</ul></div><label class="check-label"><input type="checkbox" id="import-ack"><span>${esc(t("import.ack"))}</span></label>` : ""}<p class="small muted">${esc(t("import.mappingNote"))}</p><div class="dialog-actions"><button type="button" class="btn" data-action="back-import">${esc(t("import.back"))}</button><button type="button" class="btn primary" data-action="confirm-import" ${!pv.hasFinal || pv.unsupported.length ? "disabled" : ""}>${esc(t("import.create"))}</button></div>`);
  }
  async function confirmImport() {
    const wasEmpty = state.profiles.length === 0;
    const made = await rpc("library-import-commit", { root: state.root, name: draft.name, description: "", text: draft.source });
    // The first profile of an empty library becomes active on commit; there
    // is nothing to undo back to in that case.
    state.undo = wasEmpty ? null : async () => { await rpc("library-delete-profile", { root: state.root, profileId: made.profileId }); };
    closeDialog();
    state.selected = made.profileId;
    state.view = "profiles";
    event(t("import.created.detail", draft.name));
    notify(t("import.created"), !wasEmpty);
  }

  // rule editor
  let edit = null;
  function editProfile() {
    const p = selected();
    if (!p || !state.detail || state.detail.error) return;
    const text = (state.detail.rules || []).join("\n");
    edit = { id: p.id, name: p.name, text, rules: null };
    openDialog(esc(t("editor.title")), esc(t("editor.body")),
      `<p class="mono">${esc(p.name)}</p><div class="field"><label for="rules-source">${esc(t("editor.rules"))}</label><textarea id="rules-source" spellcheck="false">${esc(text)}</textarea></div><p class="small muted">${esc(t("editor.grammar"))}</p><button type="button" class="action-link" data-action="append-final">${esc(t("editor.appendFinal"))}</button><div id="rules-error" class="note error" role="alert" hidden></div>${actions("preview-profile", esc(t("editor.validatePreview")))}`);
  }
  async function previewProfile() {
    const text = $("#rules-source", modal).value;
    const issues = await rpc("library-validate-rules", { root: state.root, profileId: edit.id, rulesText: text });
    if (Array.isArray(issues) && issues.length) {
      inlineError("rules-error", t("editor.fixFirst") + " " + issues.map((i) => `#${i.index} ${i.code}: ${i.detail}`).join(" / "));
      return;
    }
    edit.text = text;
    const p = selected();
    openDialog(esc(t("editor.confirm.title")), esc(p && p.id === state.activeId ? t("editor.confirm.body.active") : t("editor.confirm.body.other")),
      `<p class="mono">${esc(edit.name)}</p><div class="diff"><div><h3>${esc(t("editor.confirm.before"))}</h3><code class="source-code">${esc((state.detail && state.detail.rules || []).join("\n") || t("editor.none"))}</code></div><div><h3>${esc(t("editor.confirm.after"))}</h3><code class="source-code">${esc(text)}</code></div></div><div class="dialog-actions"><button type="button" class="btn" data-action="back-profile">${esc(t("import.back"))}</button><button type="button" class="btn primary" data-action="save-profile">${esc(t("editor.confirm.save"))}</button></div>`);
  }
  async function saveProfile() {
    const before = await readProfile(edit.id);
    const made = await rpc("library-update-rules", { root: state.root, profileId: edit.id, rulesText: edit.text });
    state.undo = restoreUndo(before);
    closeDialog();
    event(t("editor.saved.detail", edit.name, made.ruleCount));
    notify(t("editor.saved"), true);
  }

  // switch / delete
  function confirmSwitch() {
    const p = selected();
    if (!p || p.status !== "valid") return;
    const a = active();
    openDialog(esc(t("switch.title")), esc(running() ? t("switch.body.running") : t("switch.body.idle")),
      `<div class="diff"><div><h3>${esc(t("switch.from"))}</h3><p>${esc(a ? a.name : "—")}</p></div><div><h3>${esc(t("switch.to"))}</h3><p>${esc(p.name)}</p></div></div>${actions("confirm-profile", esc(t("switch.confirm")))}`);
  }
  // Switching the active profile: one path for the library button and the
  // tray menu. Runs inside run(), so refresh + one re-render follow.
  async function activateProfile(id) {
    const p = state.profiles.find((x) => x.id === id);
    if (!p || p.status !== "valid" || p.id === state.activeId) return;
    const previous = state.activeId;
    await rpc("library-set-active", { root: state.root, profileId: p.id });
    state.undo = previous && previous !== p.id ? async () => { await rpc("library-set-active", { root: state.root, profileId: previous }); } : null;
    closeDialog();
    event(t("switch.applied.detail", p.name));
    notify(t("switch.done"), !!state.undo);
  }
  function deleteDialog() {
    const p = selected();
    if (!p || p.id === state.activeId) { notify(t("delete.activeRefused")); return; }
    openDialog(esc(t("delete.title")), esc(t("delete.body")),
      `<p class="mono">${esc(p.name)}</p>${actions("confirm-delete", esc(t("delete.confirm")))}`);
  }
  async function confirmDelete() {
    const p = selected();
    const before = await readProfile(p.id);
    await rpc("library-delete-profile", { root: state.root, profileId: p.id });
    state.undo = restoreUndo(before);
    closeDialog();
    state.selected = "";
    event(t("delete.done.detail", p.name));
    notify(t("delete.done"), true);
  }

  // ---- actions ----------------------------------------------------------------
  async function handle(action, button) {
    switch (action) {
      case "dismiss": toast.hidden = true; return;
      case "close-modal": closeDialog(); return;
      case "undo": await runUndo(); return;
      case "retry": state.loadError = null; render(); await boot(); return;
      case "session": confirmSession(); return;
      case "start-session": await run(startSession); return;
      case "stop-session": await run(stopSession); return;
      case "choose-profile": openProfile(state.activeId); return;
      case "patch": patchDialog(button.dataset.target); return;
      case "preview-patch": await run(previewPatch); return;
      case "edit-rule": patchDialog(patch.target); return;
      case "apply-patch": await run(applyPatch); return;
      case "remove-target": removeTarget(button.dataset.target); return;
      case "inspect-target": closeDialog(); state.view = "trace"; run(() => inspectTarget(button.dataset.target)); return;
      case "save-target": {
        const domain = trace.target;
        if (!state.targets.includes(domain)) { state.targets = [...state.targets, domain].sort(); storePreferences(); }
        event(t("trace.savedTarget")); notify(t("trace.savedTarget")); render(); return;
      }
      case "export": await run(exportDiagnostic); return;
      case "copy-trace": await copyTrace(); return;
      case "redact": state.redact = !state.redact; storePreferences(); render(); $('[data-action="redact"]', root).focus(); return;
      case "import": importDialog(); return;
      case "preview-import": await run(previewImport); return;
      case "back-import": importDialog({ name: draft.name, source: draft.source }); return;
      case "confirm-import": await run(confirmImport); return;
      case "edit-profile": editProfile(); return;
      case "append-final": { const input = $("#rules-source", modal); input.value = input.value.trim() + "\nFINAL, DIRECT"; input.focus(); return; }
      case "preview-profile": await run(previewProfile); return;
      case "back-profile": { const draftText = edit.text; editProfile(); edit.text = draftText; $("#rules-source", modal).value = draftText; return; }
      case "save-profile": await run(saveProfile); return;
      case "use-profile": confirmSwitch(); return;
      case "confirm-profile": { const id = selected() && selected().id; await run(() => activateProfile(id)); return; }
      case "commands": commands(); return;
      case "delete-profile": deleteDialog(); return;
      case "confirm-delete": await run(confirmDelete); return;
      case "clear-filters": state.query = ""; state.filter = "all"; renderResults(); $("#profile-search", root).focus(); return;
    }
  }
  document.addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b || b.disabled) return;
    if (b.dataset.view) { closeDialog(); go(b.dataset.view); return; }
    if (b.dataset.openProfile) { closeDialog(); openProfile(b.dataset.openProfile); return; }
    if (b.dataset.commandTarget) { closeDialog(); state.view = "trace"; run(() => inspectTarget(b.dataset.commandTarget)); return; }
    if (b.dataset.commandView) { closeDialog(); go(b.dataset.commandView); return; }
    if (b.dataset.profile) { state.selected = b.dataset.profile; renderResults(); loadDetail(b.dataset.profile); return; }
    if (b.dataset.action) { handle(b.dataset.action, b).catch(fail); }
  });
  document.addEventListener("submit", (e) => {
    const form = e.target.dataset && e.target.dataset.form;
    if (form === "add-target") { e.preventDefault(); addTarget(); }
    if (form === "inspect") { e.preventDefault(); inspectFromForm(); }
  });
  document.addEventListener("input", (e) => {
    if (e.target.id === "target") trace.input = e.target.value;
    if (e.target.id === "profile-search") { state.query = e.target.value; renderResults(); $("#profile-search", root).focus(); }
    if (e.target.id === "command-search") { commandQuery = e.target.value; renderCommands(); }
  });
  document.addEventListener("change", (e) => {
    if (e.target.id === "profile-filter") { state.filter = e.target.value; renderResults(); $("#profile-filter", root).focus(); }
    if (e.target.id === "theme") { state.theme = e.target.value; storePreferences(); applyTheme(); }
    if (e.target.id === "import-ack") { const b = $('[data-action="confirm-import"]', modal); if (b) b.disabled = !e.target.checked; }
    if (e.target.id === "expected-policy") {
      const value = e.target.value;
      if (value) state.expectations[trace.target] = value; else delete state.expectations[trace.target];
      storePreferences();
      render();
      $("#expected-policy", root).focus();
    }
  });

  // ---- settings (#13 S4) ----------------------------------------------------
  const badge = (textValue, type = "") => `<span class="badge ${type}">${icon(type === "ok" ? "check" : "info")}${esc(textValue)}</span>`;
  const options = (pairs, current) => pairs.map(([value, key]) => `<option value="${value}" ${current === value ? "selected" : ""}>${esc(t(key))}</option>`).join("");
  function settingsView() {
    const canExport = Boolean(trace.target && state.activeRaw);
    return heading(esc(t("nav.settings")), esc(t("settings.subtitle"))) +
      `<section class="settings-group"><h2>${esc(t("settings.appearance"))}</h2><div class="settings-row"><div class="od-field"><label for="theme"><strong>${esc(t("settings.theme"))}</strong><span>${esc(t("settings.theme.desc"))}</span></div><select id="theme">${options([["system", "theme.system"], ["light", "theme.light"], ["dark", "theme.dark"]], state.theme)}</select></div></section>` +
      `<section class="settings-group"><h2>${esc(t("settings.privacy"))}</h2><div class="settings-row"><div class="od-field od-fill"><strong id="redact-label">${esc(t("settings.redact"))}</strong><span>${esc(t("settings.redact.desc"))}</span></div><button type="button" class="switch" role="switch" aria-checked="${state.redact}" aria-labelledby="redact-label" data-action="redact"><span>${esc(t(state.redact ? "switch.on" : "switch.off"))}</span>${icon(state.redact ? "check" : "close")}</button></div><div class="settings-row"><div class="od-field od-fill"><strong>${esc(t("settings.export"))}</strong><span>${esc(t(canExport ? "settings.export.desc" : "settings.export.none"))}</span></div><button type="button" class="btn" data-action="export" ${canExport ? "" : "disabled"}>${esc(t("settings.export.button"))}</button></div></section>` +
      `<section class="settings-group"><h2>${esc(t("settings.efficiency"))}</h2><div class="settings-row"><div class="od-field"><strong>${esc(t("settings.quickfind"))}</strong><span>${esc(t("settings.quickfind.desc"))}</span></div><button type="button" class="btn" data-action="commands">${icon("search")}${esc(t("settings.quickfind"))} <kbd>${keyboard}</kbd></button></div><div class="settings-row"><div class="od-field"><strong>${esc(t("settings.keyboard"))}</strong><span>${esc(t("settings.keyboard.desc"))}</span></div></div></section>` +
      `<section class="settings-group"><h2>${esc(t("settings.protection"))}</h2><div class="settings-row"><div class="od-field"><strong>${esc(t("settings.previewGuard"))}</strong><span>${esc(t("settings.previewGuard.desc"))}</span></div>${badge(t("settings.previewGuard.value"), "ok")}</div><div class="settings-row"><div class="od-field"><strong>${esc(t("settings.ai"))}</strong><span>${esc(t("settings.ai.desc"))}</span></div>${badge(t("settings.ai.value"))}</div></section>` +
      `<div class="note">${icon("info")}<span>${esc(t("settings.note"))}</span></div>`;
  }

  // ---- quick find -----------------------------------------------------------
  // Pages, profiles and saved targets in one list; arrows move between the
  // items and Enter opens the focused one (a plain button).
  let commandQuery = "";
  function commandItems() {
    const needle = commandQuery.trim().toLowerCase();
    return [
      ...Object.entries(names).map(([id, key]) => ({ label: t(key), kind: t("qf.kind.page"), search: t(key) + " " + id, view: id })),
      ...state.profiles.map((p) => ({ label: p.name, kind: t("qf.kind.profile"), search: p.name + " " + (p.description || ""), profile: p.id })),
      ...state.targets.map((d) => ({ label: d, kind: t("qf.kind.target"), search: d, target: d }))
    ].filter((item) => !needle || item.search.toLowerCase().includes(needle));
  }
  function renderCommands() {
    const box = $("#command-results", modal);
    if (!box) return;
    const items = commandItems();
    box.innerHTML = items.length
      ? items.map((item) => `<button type="button" class="command-item" ${item.view ? `data-command-view="${item.view}"` : item.profile ? `data-open-profile="${esc(item.profile)}"` : `data-command-target="${esc(item.target)}"`}><span class="od-field od-fill"><strong>${esc(item.label)}</strong><span>${esc(item.kind)}</span></span>${icon("arrow")}</button>`).join("")
      : `<div class="empty">${esc(t("qf.empty"))}</div>`;
  }
  function commands() {
    commandQuery = "";
    openDialog(esc(t("qf.title")), esc(t("qf.subtitle")), `<div class="field"><label for="command-search">${esc(t("qf.search"))}</label><input type="search" id="command-search" autocomplete="off" placeholder="${esc(t("qf.placeholder"))}"></div><div id="command-results" class="command-results" aria-label="${esc(t("qf.title"))}"></div><p class="small muted">${esc(t("qf.hint"))}</p>`);
    renderCommands();
  }
  const $$ = (selector, parent = document) => Array.from(parent.querySelectorAll(selector));
  function moveCommandFocus(step) {
    const items = $$(".command-item", modal);
    if (!items.length) return;
    const at = items.indexOf(document.activeElement);
    items[(at + step + items.length) % items.length].focus();
  }
  const inField = () => { const el = document.activeElement; return Boolean(el) && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT" || el.isContentEditable); };
  document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && !e.altKey && String(e.key).toLowerCase() === "k") { e.preventDefault(); commands(); return; }
    if (modal.open) {
      if ($(".command-item", modal) && (e.key === "ArrowDown" || e.key === "ArrowUp")) { e.preventDefault(); moveCommandFocus(e.key === "ArrowDown" ? 1 : -1); }
      return;
    }
    if (e.key === "/" && !inField()) {
      e.preventDefault();
      ($$("#profile-search, #target, #target-add", root)[0] || {}).focus();
    }
  });

  // ---- tray / menu status (#13 S4) ------------------------------------------
  // The carrier owns the tray. After every render the page posts the menu it
  // wants (localized labels, the active profile checked) and a tooltip; the
  // host rebuilds the native menu, and a pick comes back as a
  // relaypilot-menu event that runs the same path as a page button.
  let trayTimer = null;
  function trayMenu() {
    return [
      { id: "show", label: t("menu.show") },
      { separator: true },
      ...state.profiles.filter((p) => p.status === "valid").map((p) => ({ id: "profile:" + p.id, label: p.name, checked: p.id === state.activeId })),
      { separator: true },
      { id: "quick-find", label: t("menu.quickFind") },
      ...Object.keys(names).map((id) => ({ id: "go:" + id, label: t(names[id]) })),
      { separator: true },
      { id: "quit", label: t("menu.quit") }
    ];
  }
  function reportTrayState() {
    if (!state.root) return;
    clearTimeout(trayTimer);
    trayTimer = setTimeout(() => {
      const p = active();
      post("/api/host/tray_state", { state: { tooltip: "RelayPilot — " + sessionName() + (p ? " · " + p.name : ""), view: state.view, menu: trayMenu() } }).catch(() => {});
    }, 0);
  }
  async function trayCommand(id) {
    if (id === "quit") {
      if (running() && state.handle) { try { await stopSession(); } catch (_) { /* quitting regardless */ } }
      await post("/api/host/quit", {}).catch(() => {});
      return;
    }
    if (id === "quick-find") { commands(); return; }
    if (id.startsWith("go:")) { go(id.slice(3)); return; }
    if (id.startsWith("profile:")) { await run(() => activateProfile(id.slice(8))); }
  }
  // The event stream is opened once the first screen is up. The harness
  // opens it itself (tray step) and the verifier's boot page passes
  // ?events=0: on Linux a window capture while the stream is open kills the
  // carrier's stream writer (glaze#165), and the verifier captures around
  // the journeys, never during them.
  const eventsOff = params.get("events") === "0";
  let events = null;
  function connectEvents() {
    if (events) return events;
    events = new EventSource("/glaze/events");
    events.addEventListener("relaypilot-menu", (e) => {
      try { trayCommand(JSON.parse(e.data).id).catch(fail); } catch (_) { /* malformed frame */ }
    });
    return events;
  }

  // ---- boot -------------------------------------------------------------------
  async function boot() {
    try {
      const [i18n, ctx] = await Promise.all([get("/api/host/i18n"), get("/api/host/context")]);
      applyLocale(i18n, /^en/i.test(navigator.language || "") ? "en" : "zh");
      state.root = ctx.libraryRoot;
      state.version = ctx.version;
      await refresh();
      state.loadError = null;
      render();
      if (!e2e && !eventsOff) connectEvents();
      if (e2e && ctx.e2e === "true") {
        const harness = await import("./e2e.js");
        harness.runJourney({ state, rpc, get, t, refresh, render, event, trace, connectEvents });
      }
    } catch (e) {
      state.loadError = (e && e.message) || String(e);
      render();
    }
  }
  render();
  boot();
})();
