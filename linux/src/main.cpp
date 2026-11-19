// RelayPilot Linux host — GTK4 window over one embedded Racket CS backend.
//
// Third platform leg implementing the design/ v0.3 contract: Overview
// (engine session lifecycle + attention items), Route Check (real
// DecisionTrace, expectation compare, route patch), Profiles (Surge-subset
// import with the per-line unsupported report, rule editor, switch/delete),
// Settings. Engine facts arrive exclusively through the RVT1 RPCs generated
// in GeneratedBackend.hpp — the same surface the macOS anchor leg uses.
//
// Threading follows the podlens Linux host: boot the runtime off the UI
// thread, dispatch every completion back through g_idle_add. UI strings run
// through the generated i18n table (zh default; RELAYPILOT_LANG=en opts
// out). Honest states everywhere: without RELAYPILOT_XRAY_BIN the session
// start fails with the engine-unavailable reason and the UI stays usable.
#include <gtk/gtk.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <type_traits>
#include <vector>

#include "GeneratedBackend.hpp"
#include "GeneratedI18n.hpp"

// GTK's G_CALLBACK / g_signal_connect* are fixed-arity macros: any bare
// comma inside a multi-line lambda body splits them into extra arguments.
// Variadic redefinitions pass whole expressions through untouched.
#ifdef G_CALLBACK
#undef G_CALLBACK
#endif
#define G_CALLBACK(...) ((GCallback)(__VA_ARGS__))


// GTK's G_CALLBACK / g_signal_connect* are fixed-arity macros: any bare
// comma inside a multi-line lambda body splits them into extra arguments.
// Variadic redefinitions pass whole expressions through untouched.
#ifdef G_CALLBACK
#undef G_CALLBACK
#endif
#define G_CALLBACK(...) ((GCallback)(__VA_ARGS__))
#ifdef g_signal_connect
#undef g_signal_connect
#endif
#define g_signal_connect(instance, detailed_signal, ...) \
    relaypilot_connect_data((instance), (detailed_signal), __VA_ARGS__, \
                            nullptr, static_cast<GConnectFlags>(0))
#ifdef g_signal_connect_data
#undef g_signal_connect_data
#endif
template <typename... Args>
static auto relaypilot_connect_data(Args&&... args) {
  return (g_signal_connect_data)(std::forward<Args>(args)...);
}
#define g_signal_connect_data(...) \
    relaypilot_connect_data(__VA_ARGS__)

namespace fs = std::filesystem;

namespace {


// ---------------------------------------------------------------------------
// i18n — zh default, en fallback, then the key. RELAYPILOT_LANG=en opts out.
// ---------------------------------------------------------------------------

char const* g_lang = std::getenv("RELAYPILOT_LANG") != nullptr &&
                             std::string(std::getenv("RELAYPILOT_LANG")) == "en"
                         ? "en"
                         : "zh";

char const* tr(char const* key) {
  for (auto const& entry : rivet_app::kI18nTable) {
    if (entry.key != key) continue;
    std::string_view active = g_lang[0] == 'z' ? entry.zh : entry.en;
    if (!active.empty()) {
      // The table rows are static; the pointers outlive the call.
      return active.data();
    }
    std::string_view other = g_lang[0] == 'z' ? entry.en : entry.zh;
    return other.empty() ? entry.key.data() : other.data();
  }
  return key;
}

std::string trf(char const* key, std::string const& argument) {
  std::string pattern = tr(key);
  auto at = pattern.find("%@");
  if (at == std::string::npos) return pattern;
  return pattern.substr(0, at) + argument + pattern.substr(at + 2);
}

std::string policy_name(std::string const& policy) {
  if (policy == "DIRECT") return tr("policy.direct");
  if (policy == "REJECT") return tr("policy.reject");
  return policy;
}

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------

struct Widgets;

struct AppState;
AppState& state();

void show_toast(std::string const& message, bool undoable);
void dispatch_ui(std::function<void()> run);
void update_overview();
void update_nav();
void update_trace_result();
void render_profile_list();
void render_profile_detail();
void refresh_library();
void show_page(int page);
char const* page_id(int page);
GtkWidget* make_badge(char const* cssClass, char const* text);
void set_badge(GtkWidget* badge, char const* cssClass, char const* text);

// ---------------------------------------------------------------------------
// UI dispatch — backend completions arrive on the reader thread.
// ---------------------------------------------------------------------------

struct UiTask {
  std::function<void()> run;
};

int run_ui_task(gpointer user_data) {
  auto* task = static_cast<UiTask*>(user_data);
  task->run();
  delete task;
  return G_SOURCE_REMOVE;
}

void dispatch_ui(std::function<void()> run) {
  g_idle_add(run_ui_task, new UiTask{std::move(run)});
}

template <typename T, typename Then>
void on_result(rivet_app::Result<T> result, Then then) {
  dispatch_ui([result = std::move(result), then = std::move(then)]() mutable {
    if (!result.succeeded()) {
      try {
        std::rethrow_exception(result.error);
      } catch (std::exception const& e) {
        show_toast(std::string(tr("common.error")) + e.what(), false);
      } catch (...) {
        show_toast(std::string(tr("common.error")) + "unknown backend failure",
                   false);
      }
      return;
    }
    try {
      if constexpr (std::is_void_v<T>) {
        then();
      } else {
        then(*result.value);
      }
    } catch (std::exception const& e) {
      show_toast(std::string(tr("common.error")) + e.what(), false);
    }
  });
}

// ---------------------------------------------------------------------------
// Semantic tokens mirrored from design/prototype/shared.css (light/dark
// pairs follow the desktop theme via prefers-color-scheme, GTK 4.8+).
// ---------------------------------------------------------------------------

void apply_css() {
  auto* provider = gtk_css_provider_new();
  gtk_css_provider_load_from_string(
      provider,
      "@define-color rp_accent #A6472E;\n"
      "@define-color rp_accent_soft #F7E8E1;\n"
      "@define-color rp_on_accent #FFFFFF;\n"
      "@define-color rp_ok #237346;\n"
      "@define-color rp_ok_soft #EAF4ED;\n"
      "@define-color rp_warn #94540A;\n"
      "@define-color rp_warn_soft #FFF3DF;\n"
      "@define-color rp_danger #B3261E;\n"
      "@define-color rp_danger_soft #FFF0EE;\n"
      "@media (prefers-color-scheme: dark) {\n"
      "  @define-color rp_accent #EDAC91;\n"
      "  @define-color rp_accent_soft #38251D;\n"
      "  @define-color rp_on_accent #201B16;\n"
      "  @define-color rp_ok #92DCB0;\n"
      "  @define-color rp_ok_soft #1E3025;\n"
      "  @define-color rp_warn #F0BE6E;\n"
      "  @define-color rp_warn_soft #342B1C;\n"
      "  @define-color rp_danger #FFA59E;\n"
      "  @define-color rp_danger_soft #3A211E;\n"
      "}\n"
      ".rp-title { font-size: 26px; font-weight: 700; letter-spacing: -0.02em; }\n"
      ".rp-subtitle { font-size: 13px; opacity: 0.75; }\n"
      ".rp-section { font-size: 16px; font-weight: 700; }\n"
      ".rp-meta { font-size: 12px; opacity: 0.7; }\n"
      ".rp-mono { font-family: monospace; }\n"
      ".rp-card { padding: 20px; border-radius: 12px; "
      "background: alpha(currentColor, 0.04); "
      "border: 1px solid alpha(currentColor, 0.10); }\n"
      ".rp-badge { font-size: 11px; font-weight: 700; padding: 3px 9px; "
      "border-radius: 8px; }\n"
      ".rp-badge-ok { background: @rp_ok_soft; color: @rp_ok; }\n"
      ".rp-badge-warn { background: @rp_warn_soft; color: @rp_warn; }\n"
      ".rp-badge-error { background: @rp_danger_soft; color: @rp_danger; }\n"
      ".rp-hero-title { font-size: 30px; font-weight: 700; }\n"
      ".rp-emblem { padding: 14px; border-radius: 9999px; "
      "background: alpha(currentColor, 0.06); }\n"
      ".rp-emblem-running { background: @rp_ok_soft; color: @rp_ok; }\n"
      ".rp-banner { padding: 5px 20px; font-size: 11px; opacity: 0.75; }\n"
      ".rp-footer { border-top: 1px solid alpha(currentColor, 0.12); "
      "padding: 8px 20px; font-size: 11px; opacity: 0.7; }\n"
      ".rp-sidebar { padding: 14px 10px; background: "
      "alpha(currentColor, 0.05); }\n"
      ".rp-nav { padding: 10px 12px; border-radius: 8px; }\n"
      ".rp-nav-active { background: alpha(currentColor, 0.10); "
      "box-shadow: inset 2.5px 0 @rp_accent; }\n"
      ".rp-issue-symbol { background: @rp_warn_soft; color: @rp_warn; "
      "border-radius: 8px; padding: 4px 8px; }\n"
      ".rp-note { border-radius: 8px; padding: 12px; font-size: 12px; "
      "background: alpha(currentColor, 0.05); }\n"
      ".rp-source { font-family: monospace; font-size: 12px; padding: 10px; "
      "border-radius: 8px; background: alpha(currentColor, 0.06); }\n"
      ".rp-error { color: @rp_danger; font-size: 13px; }\n"
      ".rp-rule-row { border-bottom: 1px solid alpha(currentColor, 0.08); "
      "padding: 8px 0; }\n"
      ".rp-sep { background: alpha(currentColor, 0.10); min-height: 1px; }\n");
  gtk_style_context_add_provider_for_display(
      gdk_display_get_default(), GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(provider);
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum class SessionPhase { idle, starting, running };
enum class Page { overview = 0, trace = 1, profiles = 2, settings = 3 };

struct ImportFlow {
  std::string name;
  std::string text;
  std::optional<rivet_app::ImportPreview> preview;
  bool acknowledged = false;
};

struct EditorFlow {
  std::string profileId;
  std::string profileName;
  bool isActive = false;
  std::string originalText;
};

struct PatchFlow {
  std::string target;
  std::string policy = "DIRECT";
  std::optional<rivet_app::PatchPreview> preview;
};

struct ActivityEvent {
  std::string time;
  std::string text;
};

struct Widgets {
  // Shell.
  GtkLabel* footerSession = nullptr;
  GtkLabel* footerRules = nullptr;
  GtkWidget* toastBox = nullptr;
  GtkLabel* toastLabel = nullptr;
  GtkWidget* toastUndo = nullptr;
  std::vector<GtkWidget*> navButtons;
  GtkLabel* navProfilesCount = nullptr;
  GtkStack* stack = nullptr;

  // Overview.
  GtkWidget* emblem = nullptr;
  GtkWidget* emblemIcon = nullptr;
  GtkLabel* sessionTitle = nullptr;
  GtkLabel* sessionSub = nullptr;
  GtkButton* sessionButton = nullptr;
  GtkLabel* activeProfile = nullptr;
  GtkLabel* defaultRoute = nullptr;
  GtkLabel* ruleCount = nullptr;
  GtkWidget* statusBadge = nullptr;
  GtkWidget* pendingBadge = nullptr;
  GtkWidget* pendingList = nullptr;
  GtkWidget* pendingClear = nullptr;
  GtkWidget* targetsList = nullptr;
  GtkLabel* targetsEmpty = nullptr;
  GtkWidget* eventsList = nullptr;

  // Trace.
  GtkEntry* targetEntry = nullptr;
  GtkLabel* traceError = nullptr;
  GtkButton* inspectButton = nullptr;
  GtkWidget* resultBox = nullptr;
  GtkLabel* resultTarget = nullptr;
  GtkWidget* expectBadge = nullptr;
  GtkComboBoxText* expectationPicker = nullptr;
  GtkLabel* actualPolicy = nullptr;
  GtkLabel* actualOutbound = nullptr;
  GtkLabel* causeTitle = nullptr;
  GtkLabel* causeBody = nullptr;
  GtkLabel* causeSource = nullptr;
  GtkWidget* stepsBox = nullptr;
  GtkButton* saveTargetButton = nullptr;
  GtkLabel* artifactLine = nullptr;

  // Profiles.
  GtkEntry* search = nullptr;
  GtkComboBoxText* filter = nullptr;
  GtkLabel* resultsCount = nullptr;
  GtkWidget* listBox = nullptr;
  GtkWidget* detailEmpty = nullptr;
  GtkWidget* detailBox = nullptr;
  GtkLabel* detailTitle = nullptr;
  GtkWidget* detailBadge = nullptr;
  GtkWidget* detailIssues = nullptr;
  GtkWidget* rulesBox = nullptr;
  GtkWidget* actionRow = nullptr;

  // Settings.
  GtkComboBoxText* theme = nullptr;
  GtkToggleButton* redact = nullptr;
};

struct AppState {
  rivet::linux_runtime::Backend* backend = nullptr;
  std::unique_ptr<rivet_app::API> api;
  std::unique_ptr<rivet::linux_runtime::Backend> startup_backend;
  std::thread startup_thread;
  std::mutex startup_mutex;
  std::string startup_error;
  std::atomic_bool shutting_down{false};

  std::string libraryRoot;
  rivet_app::LibrarySnapshot snapshot;
  std::string activeProfileJson;

  SessionPhase phase = SessionPhase::idle;
  std::string sessionId;

  std::vector<std::string> savedTargets;
  std::map<std::string, std::string> expectations;
  std::map<std::string, rivet_app::RouteDecision> routeCache;

  std::vector<ActivityEvent> events;
  bool canUndo = false;
  std::string undoActiveId;
  std::map<std::string, std::optional<std::string>> undoProfiles;

  bool redact = true;
  std::string theme = "system";

  std::string traceInput;
  std::string traceTarget;
  rivet_app::RouteDecision traceDecision;
  rivet_app::CompiledEngineConfig traceArtifact;
  bool traceHasResult = false;
  bool traceBusy = false;
  std::string traceError;

  std::string profilesQuery;
  std::string profilesFilter = "all";
  std::string selectedProfileId;

  std::optional<ImportFlow> importFlow;
  std::optional<EditorFlow> editorFlow;
  std::optional<PatchFlow> patchFlow;

  Page page = Page::overview;
  GtkWidget* window = nullptr;
  Widgets w;
};

AppState g_state;
Widgets& w = g_state.w;

// ---------------------------------------------------------------------------
// Preferences — user intent (expectations, saved targets, theme, redaction)
// persists host-side under the XDG state directory. Never profile data.
// ---------------------------------------------------------------------------

fs::path prefs_path() {
  char const* state = std::getenv("XDG_STATE_HOME");
  fs::path base =
      (state != nullptr && *state != '\0')
          ? fs::path(state)
          : (fs::path(std::getenv("HOME") != nullptr ? std::getenv("HOME") : ".") /
             ".local" / "state");
  return base / "relaypilot" / "host-prefs.json";
}

std::string json_escape(std::string const& value) {
  std::string out;
  for (char c : value) {
    if (c == '"' || c == '\\') {
      out.push_back('\\');
      out.push_back(c);
    } else if (c == '\n') {
      out += "\\n";
    } else {
      out.push_back(c);
    }
  }
  return out;
}

void load_preferences() {
  std::ifstream in(prefs_path());
  if (!in) return;
  std::string body((std::istreambuf_iterator<char>(in)),
                   std::istreambuf_iterator<char>());
  auto string_array = [&](std::string const& key) {
    std::vector<std::string> items;
    auto keyAt = body.find("\"" + key + "\"");
    if (keyAt == std::string::npos) return items;
    auto open = body.find('[', keyAt);
    auto close = body.find(']', open);
    if (open == std::string::npos || close == std::string::npos) return items;
    std::string section = body.substr(open + 1, close - open - 1);
    std::size_t at = 0;
    while (true) {
      auto quote = section.find('"', at);
      if (quote == std::string::npos) break;
      auto end = section.find('"', quote + 1);
      if (end == std::string::npos) break;
      items.push_back(section.substr(quote + 1, end - quote - 1));
      at = end + 1;
    }
    return items;
  };
  g_state.savedTargets = string_array("savedTargets");
  auto mapAt = body.find("\"expectations\"");
  if (mapAt != std::string::npos) {
    auto open = body.find('{', mapAt);
    auto close = body.find('}', open);
    if (open != std::string::npos && close != std::string::npos) {
      std::string section = body.substr(open + 1, close - open - 1);
      std::size_t at = 0;
      while (true) {
        auto quote = section.find('"', at);
        if (quote == std::string::npos) break;
        auto keyEnd = section.find('"', quote + 1);
        if (keyEnd == std::string::npos) break;
        auto colon = section.find(':', keyEnd);
        if (colon == std::string::npos) break;
        auto valueStart = section.find('"', colon);
        if (valueStart == std::string::npos) break;
        auto valueEnd = section.find('"', valueStart + 1);
        if (valueEnd == std::string::npos) break;
        g_state.expectations[section.substr(quote + 1, keyEnd - quote - 1)] =
            section.substr(valueStart + 1, valueEnd - valueStart - 1);
        at = valueEnd + 1;
      }
    }
  }
  if (body.find("\"redact\":false") != std::string::npos) g_state.redact = false;
  if (body.find("\"theme\":\"light\"") != std::string::npos) g_state.theme = "light";
  if (body.find("\"theme\":\"dark\"") != std::string::npos) g_state.theme = "dark";
}

void save_preferences() {
  fs::path path = prefs_path();
  std::error_code ec;
  fs::create_directories(path.parent_path(), ec);
  std::ofstream out(path, std::ios::trunc);
  out << "{\"savedTargets\":[";
  for (std::size_t i = 0; i < g_state.savedTargets.size(); ++i) {
    if (i != 0) out << ",";
    out << "\"" << json_escape(g_state.savedTargets[i]) << "\"";
  }
  out << "],\"expectations\":{";
  bool first = true;
  for (auto const& [target, policy] : g_state.expectations) {
    if (!first) out << ",";
    first = false;
    out << "\"" << json_escape(target) << "\":\"" << json_escape(policy) << "\"";
  }
  out << "},\"redact\":" << (g_state.redact ? "true" : "false") << ",\"theme\":\""
      << g_state.theme << "\"}";
}

// ---------------------------------------------------------------------------
// Toast + activity
// ---------------------------------------------------------------------------

void show_toast(std::string const& message, bool undoable) {
  gtk_label_set_text(w.toastLabel, message.c_str());
  gtk_widget_set_visible(w.toastUndo, undoable);
  gtk_widget_set_visible(GTK_WIDGET(w.toastBox), TRUE);
}

void add_event(std::string const& text) {
  char buffer[16];
  std::time_t now = std::time(nullptr);
  std::tm local{};
  localtime_r(&now, &local);
  std::snprintf(buffer, sizeof(buffer), "%02d:%02d", local.tm_hour, local.tm_min);
  g_state.events.insert(g_state.events.begin(), ActivityEvent{buffer, text});
  if (g_state.events.size() > 8) g_state.events.pop_back();
}

// ---------------------------------------------------------------------------
// Derived facts
// ---------------------------------------------------------------------------

rivet_app::LibraryEntry const* active_entry() {
  for (auto const& entry : g_state.snapshot.profiles) {
    if (entry.id == g_state.snapshot.activeProfileId) return &entry;
  }
  return nullptr;
}

rivet_app::LibraryEntry const* entry_by_id(std::string const& id) {
  for (auto const& entry : g_state.snapshot.profiles) {
    if (entry.id == id) return &entry;
  }
  return nullptr;
}

std::string default_route_name() {
  if (g_state.activeProfileJson.empty()) return tr("fact.defaultRoute.none");
  // The FINAL rule's policy is the default route; parse it from the
  // canonical rules list the backend returns.
  auto keyAt = g_state.activeProfileJson.find("\"rules\"");
  if (keyAt == std::string::npos) return tr("fact.defaultRoute.none");
  auto open = g_state.activeProfileJson.find('[', keyAt);
  auto close = g_state.activeProfileJson.find(']', open);
  if (open == std::string::npos || close == std::string::npos) {
    return tr("fact.defaultRoute.none");
  }
  std::string rules = g_state.activeProfileJson.substr(open + 1, close - open - 1);
  std::size_t at = rules.rfind("FINAL");
  if (at == std::string::npos) at = rules.rfind("MATCH");
  if (at == std::string::npos) return tr("fact.defaultRoute.none");
  auto comma = rules.find(',', at);
  if (comma == std::string::npos) return tr("fact.defaultRoute.none");
  auto end = rules.find('"', comma + 1);
  auto start = rules.find('"', comma);
  if (start == std::string::npos || end == std::string::npos || start >= end) {
    return tr("fact.defaultRoute.none");
  }
  return policy_name(rules.substr(start + 1, end - start - 1));
}

std::vector<std::string> pending_profile_ids() {
  std::vector<std::string> ids;
  for (auto const& entry : g_state.snapshot.profiles) {
    if (entry.status != "valid") ids.push_back(entry.id);
  }
  return ids;
}

std::vector<std::string> pending_mismatch_targets() {
  std::vector<std::string> targets;
  for (auto const& target : g_state.savedTargets) {
    auto expected = g_state.expectations.find(target);
    auto decision = g_state.routeCache.find(target);
    if (expected == g_state.expectations.end()) continue;
    if (decision == g_state.routeCache.end()) continue;
    if (decision->second.policy != expected->second) targets.push_back(target);
  }
  return targets;
}

// ---------------------------------------------------------------------------
// Widget helpers
// ---------------------------------------------------------------------------

GtkWidget* make_badge(char const* cssClass, char const* text) {
  GtkWidget* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  gtk_widget_add_css_class(box, "rp-badge");
  gtk_widget_add_css_class(box, cssClass);
  GtkWidget* label = gtk_label_new(text);
  gtk_box_append(GTK_BOX(box), label);
  g_object_set_data_full(G_OBJECT(box), "label", g_object_ref(label),
                         g_object_unref);
  return box;
}

void set_badge(GtkWidget* badge, char const* cssClass, char const* text) {
  auto* label =
      GTK_LABEL(static_cast<GtkWidget*>(g_object_get_data(G_OBJECT(badge), "label")));
  gtk_label_set_text(label, text);
  GtkStyleContext* context = gtk_widget_get_style_context(badge);
  gtk_style_context_remove_class(context, "rp-badge-ok");
  gtk_style_context_remove_class(context, "rp-badge-warn");
  gtk_style_context_remove_class(context, "rp-badge-error");
  gtk_style_context_add_class(context, cssClass);
}

GtkWidget* make_section_head(char const* title, GtkWidget* trailing) {
  auto* head = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  auto* label = gtk_label_new(title);
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_widget_add_css_class(label, "rp-section");
  gtk_box_append(GTK_BOX(head), label);
  if (trailing != nullptr) {
    gtk_widget_set_hexpand(label, TRUE);
    gtk_box_append(GTK_BOX(head), trailing);
  }
  return head;
}

GtkWidget* make_field_label(char const* text) {
  auto* label = gtk_label_new(text);
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_widget_add_css_class(label, "rp-section");
  return label;
}

// ---------------------------------------------------------------------------
// Library actions
// ---------------------------------------------------------------------------

void capture_undo() {
  g_state.undoProfiles.clear();
  g_state.undoActiveId = g_state.snapshot.activeProfileId;
  for (auto const& entry : g_state.snapshot.profiles) {
    auto json = g_state.api->library_read_profile_within(
        g_state.libraryRoot, entry.id, std::chrono::seconds(10));
    if (json.has_value()) {
      g_state.undoProfiles[entry.id] = *json;
    }
  }
  g_state.canUndo = true;
}

void undo_last_change() {
  if (g_state.api == nullptr || !g_state.canUndo) return;
  auto profiles = g_state.undoProfiles;
  auto activeId = g_state.undoActiveId;
  auto pending = std::make_shared<std::atomic_int>(
      static_cast<int>(profiles.size()));
  for (auto const& [id, json] : profiles) {
    if (json.has_value()) {
      g_state.api->library_restore_profile_async(
          g_state.libraryRoot, *json,
          [pending](rivet_app::Result<rivet_app::LibraryMutation>) {
            if (pending->fetch_sub(1) == 1) {
              dispatch_ui([] { refresh_library(); });
            }
          });
    } else {
      g_state.api->library_delete_profile_async(
          g_state.libraryRoot, id,
          [pending](rivet_app::Result<rivet_app::LibraryMutation>) {
            if (pending->fetch_sub(1) == 1) {
              dispatch_ui([] { refresh_library(); });
            }
          });
    }
  }
  if (activeId != g_state.snapshot.activeProfileId) {
    g_state.api->library_set_active_async(
        g_state.libraryRoot, activeId,
        [](rivet_app::Result<rivet_app::LibraryMutation>) {});
  }
  g_state.canUndo = false;
  add_event(tr("undo.done"));
  show_toast(tr("undo.done"), false);
}

void refresh_target_routes() {
  if (g_state.api == nullptr || g_state.activeProfileJson.empty()) return;
  for (auto const& target : g_state.savedTargets) {
    g_state.api->explain_route_async(
        g_state.activeProfileJson, target, "", 443, "tcp",
        [target](rivet_app::Result<rivet_app::RouteDecision> result) {
          on_result(std::move(result), [target](auto const& decision) {
            g_state.routeCache[target] = decision;
            update_overview();
            update_trace_result();
          });
        });
  }
}

void refresh_library() {
  if (g_state.api == nullptr) return;
  g_state.api->library_list_async(
      g_state.libraryRoot,
      [](rivet_app::Result<rivet_app::LibrarySnapshot> result) {
        on_result(std::move(result),
                  [](rivet_app::LibrarySnapshot const& snapshot) {
                    g_state.snapshot = snapshot;
                    bool found = false;
                    for (auto const& entry : snapshot.profiles) {
                      if (entry.id == g_state.selectedProfileId) found = true;
                    }
                    if (!found && !snapshot.profiles.empty()) {
                      g_state.selectedProfileId = snapshot.profiles.front().id;
                    }
                    if (snapshot.activeProfileId.empty()) {
                      g_state.activeProfileJson.clear();
                      update_overview();
                      update_nav();
                      render_profile_list();
                      render_profile_detail();
                      return;
                    }
                    g_state.api->library_read_profile_async(
                        g_state.libraryRoot, snapshot.activeProfileId,
                        [](rivet_app::Result<std::string> result) {
                          on_result(std::move(result),
                                    [](std::string const& json) {
                                      g_state.activeProfileJson = json;
                                      refresh_target_routes();
                                      update_overview();
                                      update_nav();
                                      render_profile_list();
                                      render_profile_detail();
                                    });
                        });
                    update_overview();
                    update_nav();
                    render_profile_list();
                    render_profile_detail();
                  });
      });
}

// ---------------------------------------------------------------------------
// Session lifecycle — failures surface honestly (不变式 3).
// ---------------------------------------------------------------------------

void start_session_confirmed() {
  if (g_state.api == nullptr || g_state.phase != SessionPhase::idle ||
      g_state.activeProfileJson.empty()) {
    return;
  }
  g_state.phase = SessionPhase::starting;
  update_overview();
  g_state.api->engine_session_start_async(
      g_state.activeProfileJson, 0,
      [](rivet_app::Result<rivet_app::EngineSessionHandle> result) {
        dispatch_ui([result = std::move(result)]() mutable {
          if (!result.succeeded()) {
            std::string message = "unknown engine failure";
            try {
              std::rethrow_exception(result.error);
            } catch (std::exception const& e) {
              message = e.what();
            }
            g_state.phase = SessionPhase::idle;
            add_event(std::string(tr("session.startFailed")) + " " + message);
            show_toast(std::string(tr("session.startFailed")) + " " + message,
                       false);
            update_overview();
            return;
          }
          g_state.sessionId = result.value->sessionId;
          g_state.phase = SessionPhase::running;
          add_event(tr("session.started"));
          show_toast(tr("session.started"), false);
          update_overview();
        });
      });
}

void stop_session() {
  if (g_state.api == nullptr || g_state.sessionId.empty()) return;
  auto sessionId = g_state.sessionId;
  g_state.api->engine_session_stop_async(
      sessionId,
      [](rivet_app::Result<rivet_app::EngineSessionStop> result) {
        on_result(std::move(result), [](rivet_app::EngineSessionStop const&) {
          g_state.sessionId.clear();
          g_state.phase = SessionPhase::idle;
          add_event(tr("session.stopped"));
          show_toast(tr("session.stopped"), false);
          update_overview();
        });
      });
}

// ---------------------------------------------------------------------------
// Trace
// ---------------------------------------------------------------------------

bool valid_domain(std::string const& value) {
  if (value.empty() || value.size() > 253) return false;
  std::size_t start = 0;
  while (start < value.size()) {
    auto dot = value.find('.', start);
    if (dot == std::string::npos) dot = value.size();
    auto length = dot - start;
    if (length < 1 || length > 63) return false;
    unsigned char first = static_cast<unsigned char>(value[start]);
    unsigned char last = static_cast<unsigned char>(value[dot - 1]);
    if (!std::isalnum(first) || !std::isalnum(last)) return false;
    for (std::size_t i = start; i < dot; ++i) {
      char c = value[i];
      if (!std::isalnum(static_cast<unsigned char>(c)) && c != '-') return false;
    }
    if (dot == value.size()) break;
    start = dot + 1;
  }
  return true;
}

void inspect_route(std::string target) {
  if (g_state.api == nullptr || g_state.activeProfileJson.empty()) return;
  std::transform(target.begin(), target.end(), target.begin(),
                 [](unsigned char c) {
                   return static_cast<char>(std::tolower(c));
                 });
  if (!valid_domain(target)) {
    gtk_label_set_text(w.traceError, tr("trace.error.domain"));
    gtk_widget_set_visible(GTK_WIDGET(w.traceError), TRUE);
    return;
  }
  g_state.traceError.clear();
  gtk_widget_set_visible(GTK_WIDGET(w.traceError), FALSE);
  g_state.traceTarget = target;
  g_state.traceBusy = true;
  gtk_button_set_label(w.inspectButton, tr("trace.inspecting"));
  gtk_widget_set_sensitive(GTK_WIDGET(w.inspectButton), FALSE);
  g_state.api->explain_route_async(
      g_state.activeProfileJson, target, "", 443, "tcp",
      [target](rivet_app::Result<rivet_app::RouteDecision> result) {
        on_result(std::move(result), [target](auto const& decision) {
          g_state.traceDecision = decision;
          g_state.traceHasResult = true;
          g_state.traceBusy = false;
          g_state.routeCache[target] = decision;
          gtk_button_set_label(w.inspectButton, tr("trace.inspect"));
          gtk_widget_set_sensitive(GTK_WIDGET(w.inspectButton), TRUE);
          g_state.api->compile_engine_config_async(
              g_state.activeProfileJson,
              [](rivet_app::Result<rivet_app::CompiledEngineConfig> artifact) {
                on_result(std::move(artifact),
                          [](auto const& config) {
                            g_state.traceArtifact = config;
                            update_trace_result();
                          });
              });
          update_trace_result();
        });
      });
}

void set_expectation(std::string const& target, std::string const& policy) {
  if (policy.empty()) {
    g_state.expectations.erase(target);
  } else {
    g_state.expectations[target] = policy;
  }
  save_preferences();
  update_overview();
  update_trace_result();
}

void save_target() {
  if (g_state.traceTarget.empty()) return;
  if (std::find(g_state.savedTargets.begin(), g_state.savedTargets.end(),
                g_state.traceTarget) == g_state.savedTargets.end()) {
    g_state.savedTargets.push_back(g_state.traceTarget);
    save_preferences();
    show_toast(tr("trace.savedTarget"), false);
    refresh_target_routes();
    update_overview();
  }
}

void remove_target(std::string const& target) {
  g_state.savedTargets.erase(
      std::remove(g_state.savedTargets.begin(), g_state.savedTargets.end(),
                  target),
      g_state.savedTargets.end());
  g_state.expectations.erase(target);
  save_preferences();
  show_toast(tr("trace.removedTarget"), false);
  refresh_library();
}


// ---------------------------------------------------------------------------
// Trace result rendering
// ---------------------------------------------------------------------------

char const* expectation_badge_class() {
  auto expected = g_state.expectations.find(g_state.traceTarget);
  if (expected == g_state.expectations.end()) return "rp-badge-ok";
  return expected->second != g_state.traceDecision.policy ? "rp-badge-warn"
                                                          : "rp-badge-ok";
}

char const* expectation_badge_text() {
  auto expected = g_state.expectations.find(g_state.traceTarget);
  if (expected == g_state.expectations.end()) return tr("trace.noExpectationBadge");
  return expected->second != g_state.traceDecision.policy
             ? tr("trace.mismatch")
             : tr("trace.match");
}

std::string trace_cause_text() {
  auto const& decision = g_state.traceDecision;
  if (decision.ruleIndex == 0 || decision.outbound == "relaypilot.block") {
    return tr("trace.cause.final");
  }
  auto index = std::to_string(decision.ruleIndex);
  if (decision.policy == "DIRECT") return trf("trace.cause.exact", index);
  if (decision.policy == "REJECT") return trf("trace.cause.exact", index);
  return trf("trace.cause.suffix", index);
}

GtkWidget* make_step_row(char const* number, char const* title,
                         std::string const& body, char const* source) {
  auto* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 16);
  auto* num = gtk_label_new(number);
  gtk_widget_add_css_class(num, "rp-meta");
  gtk_widget_add_css_class(num, "rp-mono");
  auto* column = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  auto* titleLabel = gtk_label_new(title);
  gtk_label_set_xalign(GTK_LABEL(titleLabel), 0.0f);
  gtk_widget_add_css_class(titleLabel, "rp-section");
  auto* bodyLabel = gtk_label_new(body.c_str());
  gtk_label_set_xalign(GTK_LABEL(bodyLabel), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(bodyLabel), TRUE);
  gtk_widget_add_css_class(bodyLabel, "rp-subtitle");
  gtk_box_append(GTK_BOX(column), titleLabel);
  gtk_box_append(GTK_BOX(column), bodyLabel);
  if (source != nullptr && *source != '\0') {
    auto* code = gtk_label_new(source);
    gtk_label_set_xalign(GTK_LABEL(code), 0.0f);
    gtk_label_set_wrap(GTK_LABEL(code), TRUE);
    gtk_widget_add_css_class(code, "rp-source");
    gtk_box_append(GTK_BOX(column), code);
  }
  gtk_box_append(GTK_BOX(row), num);
  gtk_box_append(GTK_BOX(row), column);
  return row;
}

void update_trace_result() {
  bool show = g_state.traceHasResult && !g_state.traceBusy;
  gtk_widget_set_visible(w.resultBox, show);
  if (!show) return;
  auto const& decision = g_state.traceDecision;
  auto* entry = active_entry();
  gtk_label_set_text(w.resultTarget, g_state.traceTarget.c_str());
  set_badge(w.expectBadge, expectation_badge_class(), expectation_badge_text());

  // Expectation picker: rebuild targets from the active profile.
  gtk_combo_box_text_remove_all(w.expectationPicker);
  gtk_combo_box_text_append(w.expectationPicker, "", tr("trace.expectation.none"));
  std::string current;
  if (entry != nullptr) {
    for (auto const& target : entry->targets) {
      gtk_combo_box_text_append(w.expectationPicker, target.c_str(),
                                policy_name(target).c_str());
      if (g_state.expectations[g_state.traceTarget] == target) current = target;
    }
  }
  int activeIndex = 0;
  if (entry != nullptr) {
    int index = 1;
    for (auto const& target : entry->targets) {
      if (target == current) activeIndex = index;
      ++index;
    }
  }
  gtk_combo_box_set_active(GTK_COMBO_BOX(w.expectationPicker), activeIndex);
  gtk_label_set_text(w.actualPolicy, policy_name(decision.policy).c_str());
  gtk_label_set_text(w.actualOutbound, decision.outbound.c_str());

  bool mismatch = false;
  auto expected = g_state.expectations.find(g_state.traceTarget);
  if (expected != g_state.expectations.end()) {
    mismatch = expected->second != decision.policy;
  }
  gtk_label_set_text(w.causeTitle,
                     mismatch ? tr("trace.rule.diffSource")
                              : (decision.ruleIndex != 0 ? tr("trace.rule.decides")
                                                          : tr("trace.rule.supplement")));
  gtk_label_set_text(w.causeBody, trace_cause_text().c_str());
  gtk_label_set_text(
      w.causeSource,
      decision.ruleIndex == 0
          ? decision.policy.c_str()
          : std::string("rule[" + std::to_string(decision.ruleIndex) + "] → " +
                        decision.policy + " · " + decision.outbound)
                .c_str());

  // Steps.
  for (auto* child = gtk_widget_get_first_child(w.stepsBox); child != nullptr;
       child = gtk_widget_get_first_child(w.stepsBox)) {
    gtk_box_remove(GTK_BOX(w.stepsBox), child);
  }
  auto rulesLine = std::string(entry != nullptr ? entry->name : "—") + " · " +
                   std::to_string(entry != nullptr ? entry->ruleCount : 0) + " " +
                   tr("fact.rulesCount");
  gtk_box_append(GTK_BOX(w.stepsBox),
                 make_step_row("01", tr("trace.step.load"), rulesLine, nullptr));
  if (decision.ruleIndex == 0) {
    gtk_box_append(GTK_BOX(w.stepsBox),
                   make_step_row("02", tr("trace.step.matched.final"),
                                 tr("trace.cause.final"),
                                 decision.policy.c_str()));
  } else {
    gtk_box_append(GTK_BOX(w.stepsBox),
                   make_step_row("02", tr("trace.step.matched.target"),
                                 trace_cause_text(),
                                 ("rule[" + std::to_string(decision.ruleIndex) + "] → " +
                                  decision.policy + " · " + decision.outbound)
                                     .c_str()));
  }
  std::string exitBody;
  if (decision.policy == "DIRECT") {
    exitBody = tr("trace.step.out.direct");
  } else if (decision.policy == "REJECT") {
    exitBody = tr("trace.step.out.reject");
  } else {
    exitBody = trf("trace.step.out.group",
                   decision.policy + " → " + decision.outbound);
  }
  gtk_box_append(GTK_BOX(w.stepsBox),
                 make_step_row("03", policy_name(decision.policy).c_str(),
                               exitBody, nullptr));
  for (auto const& warning : decision.warnings) {
    gtk_box_append(GTK_BOX(w.stepsBox),
                   make_step_row("⚠", warning.c_str(), "", nullptr));
  }

  // Artifact + warnings carry the real engine facts (不变式 2).
  std::string artifact =
      g_state.traceArtifact.sha256.empty()
          ? tr("trace.technical.noArtifact")
          : std::string(g_state.traceArtifact.adapter) + " " +
                g_state.traceArtifact.adapterVersion + " · " +
                g_state.traceArtifact.sha256;
  gtk_label_set_text(w.artifactLine, artifact.c_str());

  // Save-target button label.
  bool saved = std::find(g_state.savedTargets.begin(), g_state.savedTargets.end(),
                         g_state.traceTarget) != g_state.savedTargets.end();
  gtk_button_set_label(w.saveTargetButton,
                       saved ? tr("trace.removeTarget") : tr("trace.saveTarget"));
}

// ---------------------------------------------------------------------------
// Profiles rendering
// ---------------------------------------------------------------------------

std::vector<rivet_app::LibraryEntry> filtered_profiles() {
  std::string query = g_state.profilesQuery;
  std::transform(query.begin(), query.end(), query.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  std::vector<rivet_app::LibraryEntry> items;
  for (auto const& entry : g_state.snapshot.profiles) {
    bool statusMatch = g_state.profilesFilter == "all" ||
                       entry.status == g_state.profilesFilter;
    std::string haystack = entry.name + " " + entry.description;
    std::transform(haystack.begin(), haystack.end(), haystack.begin(),
                   [](unsigned char c) {
                     return static_cast<char>(std::tolower(c));
                   });
    bool textMatch = query.empty() || haystack.find(query) != std::string::npos;
    if (statusMatch && textMatch) items.push_back(entry);
  }
  return items;
}

void on_profile_row_clicked(GtkButton* button, gpointer) {
  auto* id = static_cast<std::string*>(g_object_get_data(G_OBJECT(button), "profile-id"));
  if (id != nullptr) {
    g_state.selectedProfileId = *id;
    render_profile_detail();
  }
}

void render_profile_list() {
  for (auto* child = gtk_widget_get_first_child(w.listBox); child != nullptr;
       child = gtk_widget_get_first_child(w.listBox)) {
    gtk_box_remove(GTK_BOX(w.listBox), child);
  }
  auto items = filtered_profiles();
  gtk_label_set_text(
      w.resultsCount,
      std::string(trf("profiles.results",
                      std::to_string(items.size()) + " / " +
                          std::to_string(g_state.snapshot.profiles.size())))
          .c_str());
  for (auto const& entry : items) {
    auto* row = gtk_button_new_with_label(entry.name.c_str());
    gtk_widget_add_css_class(row, "rp-nav");
    gtk_widget_set_halign(row, GTK_ALIGN_FILL);
    if (entry.id == g_state.selectedProfileId) {
      gtk_widget_add_css_class(row, "rp-nav-active");
    }
    g_object_set_data_full(G_OBJECT(row), "profile-id",
                           g_strdup(entry.id.c_str()), g_free);
    g_signal_connect(row, "clicked", G_CALLBACK(on_profile_row_clicked), nullptr);
    gtk_box_append(GTK_BOX(w.listBox), row);
  }
}

void render_profile_detail() {
  auto* entry = entry_by_id(g_state.selectedProfileId);
  gtk_widget_set_visible(w.detailBox, entry != nullptr);
  gtk_widget_set_visible(w.detailEmpty, entry == nullptr);
  if (entry == nullptr) return;

  gtk_label_set_text(w.detailTitle, entry->name.c_str());
  set_badge(w.detailBadge,
            entry->id == g_state.snapshot.activeProfileId
                ? "rp-badge-ok"
                : (entry->status == "valid" ? "rp-badge-ok" : "rp-badge-error"),
            entry->id == g_state.snapshot.activeProfileId
                ? tr("profiles.badge.active")
                : (entry->status == "valid" ? tr("profiles.filter.valid")
                                            : tr("profiles.filter.invalid")));

  // Issues note.
  while (gtk_widget_get_first_child(w.detailIssues) != nullptr) {
    gtk_box_remove(GTK_BOX(w.detailIssues),
                   gtk_widget_get_first_child(w.detailIssues));
  }
  gtk_widget_set_visible(w.detailIssues, entry->status != "valid");
  if (entry->status != "valid") {
    for (auto const& issue : entry->issues) {
      auto* line = gtk_label_new(("· " + issue.detail).c_str());
      gtk_label_set_xalign(GTK_LABEL(line), 0.0f);
      gtk_label_set_wrap(GTK_LABEL(line), TRUE);
      gtk_widget_add_css_class(line, "rp-error");
      gtk_box_append(GTK_BOX(w.detailIssues), line);
    }
  }

  // Rules (from the canonical JSON, so the list matches the file).
  while (gtk_widget_get_first_child(w.rulesBox) != nullptr) {
    gtk_box_remove(GTK_BOX(w.rulesBox),
                   gtk_widget_get_first_child(w.rulesBox));
  }
  auto keyAt = g_state.activeProfileJson.find("\"id\":\"" + entry->id + "\"");
  if (entry->id == g_state.snapshot.activeProfileId &&
      keyAt != std::string::npos) {
    auto rulesAt = g_state.activeProfileJson.find("\"rules\"", keyAt);
    auto open = g_state.activeProfileJson.find('[', rulesAt);
    auto close = g_state.activeProfileJson.find(']', open);
    if (rulesAt != std::string::npos && open != std::string::npos &&
        close != std::string::npos) {
      std::string body = g_state.activeProfileJson.substr(
          open + 1, close - open - 1);
      std::size_t at = 0;
      int index = 1;
      while (true) {
        auto quote = body.find('"', at);
        if (quote == std::string::npos) break;
        auto end = body.find('"', quote + 1);
        if (end == std::string::npos) break;
        std::string rule = body.substr(quote + 1, end - quote - 1);
        auto* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
        gtk_widget_add_css_class(row, "rp-rule-row");
        auto* number = gtk_label_new(
            (std::string(index < 10 ? "0" : "") + std::to_string(index)).c_str());
        gtk_widget_add_css_class(number, "rp-meta");
        gtk_widget_add_css_class(number, "rp-mono");
        auto* label = gtk_label_new(rule.c_str());
        gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
        gtk_widget_add_css_class(label, "rp-mono");
        gtk_widget_set_hexpand(label, TRUE);
        gtk_box_append(GTK_BOX(row), number);
        gtk_box_append(GTK_BOX(row), label);
        gtk_box_append(GTK_BOX(w.rulesBox), row);
        ++index;
        at = end + 1;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Dialog helpers — transient modal windows with explicit actions.
// ---------------------------------------------------------------------------

GtkWidget* make_dialog(char const* title, char const* subtitle) {
  auto* dialog = gtk_window_new();
  gtk_window_set_title(GTK_WINDOW(dialog), title);
  gtk_window_set_transient_for(GTK_WINDOW(dialog), GTK_WINDOW(g_state.window));
  gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);
  gtk_window_set_resizable(GTK_WINDOW(dialog), FALSE);
  gtk_window_set_default_size(GTK_WINDOW(dialog), 620, -1);
  auto* box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_set_margin_top(box, 18);
  gtk_widget_set_margin_bottom(box, 18);
  gtk_widget_set_margin_start(box, 18);
  gtk_widget_set_margin_end(box, 18);
  auto* subtitleLabel = gtk_label_new(subtitle);
  gtk_label_set_wrap(GTK_LABEL(subtitleLabel), TRUE);
  gtk_label_set_xalign(GTK_LABEL(subtitleLabel), 0.0f);
  gtk_widget_add_css_class(subtitleLabel, "rp-subtitle");
  gtk_box_append(GTK_BOX(box), subtitleLabel);
  gtk_window_set_child(GTK_WINDOW(dialog), box);
  g_object_set_data_full(G_OBJECT(dialog), "body", g_object_ref(box),
                         g_object_unref);
  return dialog;
}

GtkWidget* dialog_body(GtkWidget* dialog) {
  return GTK_WIDGET(g_object_get_data(G_OBJECT(dialog), "body"));
}

void add_dialog_actions(GtkWidget* dialog, GtkWidget* parent,
                        char const* cancelLabel, char const* confirmLabel,
                        std::function<void()> onConfirm) {
  auto* actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  gtk_widget_set_halign(actions, GTK_ALIGN_END);
  gtk_widget_set_margin_top(actions, 6);
  auto* cancel = gtk_button_new_with_label(cancelLabel);
  auto* confirm = gtk_button_new_with_label(confirmLabel);
  gtk_widget_add_css_class(confirm, "rp-nav-active");
  gtk_box_append(GTK_BOX(actions), cancel);
  gtk_box_append(GTK_BOX(actions), confirm);
  gtk_box_append(GTK_BOX(parent), actions);
  struct Ctx {
    GtkWidget* dialog;
    std::function<void()> confirm;
  };
  auto* ctx = new Ctx{dialog, std::move(onConfirm)};
  g_signal_connect_data(
      cancel, "clicked",
      G_CALLBACK(+[](GtkButton*, gpointer user_data) {
        auto* ctx = static_cast<Ctx*>(user_data);
        gtk_window_destroy(GTK_WINDOW(ctx->dialog));
        delete ctx;
      }),
      ctx, nullptr, static_cast<GConnectFlags>(0));
  g_signal_connect_data(
      confirm, "clicked",
      G_CALLBACK(+[](GtkButton*, gpointer user_data) {
        auto* ctx = static_cast<Ctx*>(user_data);
        ctx->confirm();
        gtk_window_destroy(GTK_WINDOW(ctx->dialog));
        delete ctx;
      }),
      ctx, nullptr, static_cast<GConnectFlags>(0));
}

// ---------------------------------------------------------------------------
// Session start confirm
// ---------------------------------------------------------------------------

void open_session_confirm() {
  auto* dialog = make_dialog(tr("session.startConfirm.title"),
                             tr("session.startConfirm.body"));
  auto* body = dialog_body(dialog);
  auto* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  gtk_box_append(GTK_BOX(row), gtk_label_new(tr("session.confirmProfileLabel")));
  auto* name = gtk_label_new(active_entry() != nullptr
                                 ? active_entry()->name.c_str()
                                 : "—");
  gtk_widget_add_css_class(name, "rp-mono");
  gtk_box_append(GTK_BOX(row), name);
  gtk_box_append(GTK_BOX(body), row);
  add_dialog_actions(dialog, body, tr("cancel"), tr("session.confirmStart"),
                     [] { start_session_confirmed(); });
  gtk_window_present(GTK_WINDOW(dialog));
}

// ---------------------------------------------------------------------------
// Import dialog (two stages)
// ---------------------------------------------------------------------------

struct ImportDialogCtx {
  GtkWidget* dialog;
  GtkWidget* stageBox;
  GtkEntry* nameEntry;
  GtkTextView* textArea;
  GtkLabel* errorLabel;
  ImportFlow flow;
  std::function<void()> refreshStage;
};

ImportDialogCtx* g_import = nullptr;

void render_import_stage() {
  auto* ctx = g_import;
  for (auto* child = gtk_widget_get_first_child(ctx->stageBox); child != nullptr;
       child = gtk_widget_get_first_child(ctx->stageBox)) {
    gtk_box_remove(GTK_BOX(ctx->stageBox), child);
  }
  if (ctx->flow.preview.has_value()) {
    auto const& preview = *ctx->flow.preview;
    auto* head = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 16);
    auto* left = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_box_append(GTK_BOX(left),
                   gtk_label_new(std::string(
                                     trf("import.preview.rulesCount",
                                         std::to_string(preview.importableRules.size())))
                                     .c_str()));
    gtk_box_append(GTK_BOX(left),
                   gtk_label_new(std::string(
                                     preview.placeholderGroups.empty()
                                         ? tr("import.preview.groupsNone")
                                         : trf("import.preview.groupsCount",
                                               std::to_string(
                                                   preview.placeholderGroups.size())))
                                     .c_str()));
    auto* right = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    bool none = preview.unsupported.empty();
    auto* verdict =
        gtk_label_new(none ? tr("import.preview.allSupported")
                           : std::string(trf("import.preview.unsupportedCount",
                                             std::to_string(preview.unsupported.size())))
                               .c_str());
    gtk_widget_add_css_class(verdict, none ? "rp-badge-ok" : "rp-badge-warn");
    gtk_box_append(GTK_BOX(right), verdict);
    gtk_box_append(GTK_BOX(head), left);
    gtk_box_append(GTK_BOX(head), right);
    gtk_box_append(GTK_BOX(ctx->stageBox), head);

    if (!preview.unsupported.empty()) {
      auto* list = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
      for (auto const& row : preview.unsupported) {
        auto* line = gtk_label_new(
            std::string(trf("import.preview.line",
                            std::to_string(row.line) + ": " + row.text))
                .append(" — ")
                .append(row.detail)
                .c_str());
        gtk_label_set_xalign(GTK_LABEL(line), 0.0f);
        gtk_label_set_wrap(GTK_LABEL(line), TRUE);
        gtk_widget_add_css_class(line, "rp-meta");
        gtk_box_append(GTK_BOX(list), line);
      }
      auto* scroll = gtk_scrolled_window_new();
      gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), list);
      gtk_widget_set_size_request(scroll, -1, 120);
      gtk_box_append(GTK_BOX(ctx->stageBox), scroll);
      auto* ack = gtk_check_button_new_with_label(tr("import.ack"));
      gtk_check_button_set_active(GTK_CHECK_BUTTON(ack), ctx->flow.acknowledged);
      g_signal_connect(
          ack, "toggled",
          G_CALLBACK(+[](GtkCheckButton* button, gpointer) {
            if (g_import != nullptr) g_import->flow.acknowledged =
                gtk_check_button_get_active(button);
          }),
          nullptr);
      gtk_box_append(GTK_BOX(ctx->stageBox), ack);
    }
    auto* note = gtk_label_new(tr("import.mappingNote"));
    gtk_label_set_wrap(GTK_LABEL(note), TRUE);
    gtk_label_set_xalign(GTK_LABEL(note), 0.0f);
    gtk_widget_add_css_class(note, "rp-meta");
    gtk_box_append(GTK_BOX(ctx->stageBox), note);

    auto* actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(actions, GTK_ALIGN_END);
    auto* back = gtk_button_new_with_label(tr("import.back"));
    auto* create = gtk_button_new_with_label(tr("import.create"));
    gtk_widget_set_sensitive(
        create, ctx->flow.acknowledged || preview.unsupported.empty());
    gtk_box_append(GTK_BOX(actions), back);
    gtk_box_append(GTK_BOX(actions), create);
    gtk_box_append(GTK_BOX(ctx->stageBox), actions);
    g_signal_connect_data(
        back, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_import != nullptr) {
            g_import->flow.preview.reset();
            g_import->refreshStage();
          }
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
    g_signal_connect_data(
        create, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_import == nullptr) return;
          auto flow = g_import->flow;
          auto dialog = g_import->dialog;
          capture_undo();
          g_state.api->library_import_commit_async(
              g_state.libraryRoot, flow.name, "", flow.text,
              [dialog](rivet_app::Result<rivet_app::LibraryMutation> result) {
                on_result(std::move(result),
                          [dialog](rivet_app::LibraryMutation const& mutation) {
                            gtk_window_destroy(GTK_WINDOW(dialog));
                            g_import = nullptr;
                            g_state.selectedProfileId = mutation.profileId;
                            add_event(tr("import.created"));
                            show_toast(tr("import.created"), true);
                            refresh_library();
                          });
              });
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
  } else {
    auto* nameLabel = make_field_label(tr("import.name"));
    gtk_box_append(GTK_BOX(ctx->stageBox), nameLabel);
    gtk_box_append(GTK_BOX(ctx->stageBox), GTK_WIDGET(ctx->nameEntry));
    auto* sourceLabel = make_field_label(tr("import.source"));
    gtk_box_append(GTK_BOX(ctx->stageBox), sourceLabel);
    auto* scroll = gtk_scrolled_window_new();
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll),
                                  GTK_WIDGET(ctx->textArea));
    gtk_widget_set_size_request(scroll, -1, 160);
    gtk_box_append(GTK_BOX(ctx->stageBox), scroll);
    if (!ctx->flow.name.empty() || !ctx->flow.text.empty()) {
      // nothing — the widgets already hold the values
    }
    auto* error = gtk_label_new("");
    gtk_widget_add_css_class(error, "rp-error");
    gtk_label_set_wrap(GTK_LABEL(error), TRUE);
    gtk_box_append(GTK_BOX(ctx->stageBox), error);
    ctx->errorLabel = GTK_LABEL(error);
    if (g_state.importFlow.has_value() && !g_state.importFlow->text.empty()) {
      // keep error text if a failed preview stored one
    }
    auto* actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(actions, GTK_ALIGN_END);
    auto* review = gtk_button_new_with_label(tr("import.preview"));
    gtk_box_append(GTK_BOX(actions), review);
    gtk_box_append(GTK_BOX(ctx->stageBox), actions);
    g_signal_connect_data(
        review, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_import == nullptr) return;
          auto* buffer = gtk_text_view_get_buffer(g_import->textArea);
          GtkTextIter startIter, endIter;
          gtk_text_buffer_get_bounds(buffer, &startIter, &endIter);
          auto* raw = gtk_text_buffer_get_text(buffer, &startIter, &endIter, TRUE);
          std::string text = raw != nullptr ? raw : "";
          g_free(raw);
          g_import->flow.name = gtk_editable_get_text(GTK_EDITABLE(g_import->nameEntry));
          g_import->flow.text = text;
          g_state.importFlow = g_import->flow;
          g_state.api->library_import_preview_async(
              g_state.libraryRoot, g_import->flow.name, g_import->flow.text,
              [](rivet_app::Result<rivet_app::ImportPreview> result) {
                dispatch_ui([result = std::move(result)]() mutable {
                  if (g_import == nullptr) return;
                  if (!result.succeeded()) {
                    std::string message = "unknown failure";
                    try {
                      std::rethrow_exception(result.error);
                    } catch (std::exception const& e) {
                      message = e.what();
                    }
                    gtk_label_set_text(g_import->errorLabel, message.c_str());
                    gtk_widget_set_visible(GTK_WIDGET(g_import->errorLabel), TRUE);
                    return;
                  }
                  auto preview = std::move(*result.value);
                  if (preview.importableRules.empty()) {
                    gtk_label_set_text(g_import->errorLabel, tr("import.error.empty"));
                    gtk_widget_set_visible(GTK_WIDGET(g_import->errorLabel), TRUE);
                    return;
                  }
                  g_import->flow.preview = std::move(preview);
                  g_import->flow.acknowledged = g_import->flow.preview->unsupported.empty();
                  g_import->refreshStage();
                });
              });
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
  }
}

void open_import_dialog() {
  auto* dialog = make_dialog(tr("import.title"), tr("import.body"));
  auto* stageBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_box_append(GTK_BOX(dialog_body(dialog)), stageBox);
  auto* ctx = new ImportDialogCtx{dialog,
                                  stageBox,
                                  GTK_ENTRY(gtk_entry_new()),
                                  GTK_TEXT_VIEW(gtk_text_view_new()),
                                  nullptr,
                                  ImportFlow{},
                                  nullptr};
  gtk_text_view_set_wrap_mode(ctx->textArea, GTK_WRAP_WORD_CHAR);
  ctx->refreshStage = [] { render_import_stage(); };
  g_import = ctx;
  render_import_stage();
  gtk_window_present(GTK_WINDOW(dialog));
  g_signal_connect_data(
      dialog, "destroy",
      G_CALLBACK(+[](GtkWidget*, gpointer) { g_import = nullptr; }),
      nullptr, nullptr, static_cast<GConnectFlags>(0));
}

// ---------------------------------------------------------------------------
// Rule editor dialog (two stages)
// ---------------------------------------------------------------------------

struct EditorDialogCtx {
  GtkWidget* dialog;
  GtkWidget* stageBox;
  GtkTextView* textArea;
  GtkWidget* issueBox;
  bool stage = false;  // false = edit, true = confirm
  EditorFlow flow;
  std::function<void()> refreshStage;
};

EditorDialogCtx* g_editor = nullptr;

void render_editor_stage() {
  auto* ctx = g_editor;
  for (auto* child = gtk_widget_get_first_child(ctx->stageBox); child != nullptr;
       child = gtk_widget_get_first_child(ctx->stageBox)) {
    gtk_box_remove(GTK_BOX(ctx->stageBox), child);
  }
  auto* nameLabel = gtk_label_new(ctx->flow.profileName.c_str());
  gtk_widget_add_css_class(nameLabel, "rp-mono");
  gtk_label_set_xalign(GTK_LABEL(nameLabel), 0.0f);
  gtk_box_append(GTK_BOX(ctx->stageBox), nameLabel);
  if (!ctx->stage) {
    auto* scroll = gtk_scrolled_window_new();
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll),
                                  GTK_WIDGET(ctx->textArea));
    gtk_widget_set_size_request(scroll, -1, 160);
    gtk_box_append(GTK_BOX(ctx->stageBox), scroll);
    auto* grammar = gtk_label_new(tr("editor.grammar"));
    gtk_label_set_wrap(GTK_LABEL(grammar), TRUE);
    gtk_label_set_xalign(GTK_LABEL(grammar), 0.0f);
    gtk_widget_add_css_class(grammar, "rp-meta");
    gtk_box_append(GTK_BOX(ctx->stageBox), grammar);
    auto* append = gtk_button_new_with_label(tr("editor.appendFinal"));
    gtk_widget_set_halign(append, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(ctx->stageBox), append);
    g_signal_connect_data(
        append, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_editor == nullptr) return;
          auto* buffer = gtk_text_view_get_buffer(g_editor->textArea);
          GtkTextIter startIter, endIter;
          gtk_text_buffer_get_bounds(buffer, &startIter, &endIter);
          auto* raw = gtk_text_buffer_get_text(buffer, &startIter, &endIter, TRUE);
          std::string text = raw != nullptr ? raw : "";
          g_free(raw);
          std::string trimmed = text;
          while (!trimmed.empty() && (trimmed.back() == '\n' || trimmed.back() == ' '))
            trimmed.pop_back();
          gtk_text_buffer_set_text(
              buffer, (trimmed.empty() ? "FINAL, DIRECT" : trimmed + "\nFINAL, DIRECT")
                          .c_str(),
              -1);
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
    auto* issueBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_box_append(GTK_BOX(ctx->stageBox), issueBox);
    ctx->issueBox = issueBox;
    auto* actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(actions, GTK_ALIGN_END);
    auto* cancel = gtk_button_new_with_label(tr("cancel"));
    auto* validate = gtk_button_new_with_label(tr("editor.validatePreview"));
    gtk_widget_add_css_class(validate, "rp-nav-active");
    gtk_box_append(GTK_BOX(actions), cancel);
    gtk_box_append(GTK_BOX(actions), validate);
    gtk_box_append(GTK_BOX(ctx->stageBox), actions);
    g_signal_connect_data(
        cancel, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_editor != nullptr) {
            gtk_window_destroy(GTK_WINDOW(g_editor->dialog));
            g_editor = nullptr;
          }
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
    g_signal_connect_data(
        validate, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_editor == nullptr) return;
          auto* buffer = gtk_text_view_get_buffer(g_editor->textArea);
          GtkTextIter startIter, endIter;
          gtk_text_buffer_get_bounds(buffer, &startIter, &endIter);
          auto* raw = gtk_text_buffer_get_text(buffer, &startIter, &endIter, TRUE);
          std::string text = raw != nullptr ? raw : "";
          g_free(raw);
          g_state.api->library_validate_rules_async(
              g_state.libraryRoot, g_editor->flow.profileId, text,
              [](rivet_app::Result<std::vector<rivet_app::ProfileIssue>> result) {
                dispatch_ui([result = std::move(result)]() mutable {
                  if (g_editor == nullptr) return;
                  auto* buffer = gtk_text_view_get_buffer(g_editor->textArea);
                  GtkTextIter startIter, endIter;
                  gtk_text_buffer_get_bounds(buffer, &startIter, &endIter);
                  auto* raw =
                      gtk_text_buffer_get_text(buffer, &startIter, &endIter, TRUE);
                  std::string text = raw != nullptr ? raw : "";
                  g_free(raw);
                  if (!result.succeeded()) {
                    std::string message = "unknown failure";
                    try {
                      std::rethrow_exception(result.error);
                    } catch (std::exception const& e) {
                      message = e.what();
                    }
                    for (auto* child = gtk_widget_get_first_child(g_editor->issueBox);
                         child != nullptr;
                         child = gtk_widget_get_first_child(g_editor->issueBox)) {
                      gtk_box_remove(GTK_BOX(g_editor->issueBox), child);
                    }
                    auto* line = gtk_label_new(("· " + message).c_str());
                    gtk_label_set_wrap(GTK_LABEL(line), TRUE);
                    gtk_label_set_xalign(GTK_LABEL(line), 0.0f);
                    gtk_widget_add_css_class(line, "rp-error");
                    gtk_box_append(GTK_BOX(g_editor->issueBox), line);
                    return;
                  }
                  if (!result.value->empty()) {
                    for (auto* child = gtk_widget_get_first_child(g_editor->issueBox);
                         child != nullptr;
                         child = gtk_widget_get_first_child(g_editor->issueBox)) {
                      gtk_box_remove(GTK_BOX(g_editor->issueBox), child);
                    }
                    for (auto const& issue : *result.value) {
                      auto* line = gtk_label_new(("· " + issue.detail).c_str());
                      gtk_label_set_xalign(GTK_LABEL(line), 0.0f);
                      gtk_label_set_wrap(GTK_LABEL(line), TRUE);
                      gtk_widget_add_css_class(line, "rp-error");
                      gtk_box_append(GTK_BOX(g_editor->issueBox), line);
                    }
                    return;
                  }
                  g_editor->flow.originalText = text;
                  g_editor->stage = true;
                  g_editor->refreshStage();
                });
              });
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
  } else {
    auto* subtitle = gtk_label_new(ctx->flow.isActive ? tr("editor.confirm.body.active")
                                                     : tr("editor.confirm.body.other"));
    gtk_label_set_wrap(GTK_LABEL(subtitle), TRUE);
    gtk_label_set_xalign(GTK_LABEL(subtitle), 0.0f);
    gtk_widget_add_css_class(subtitle, "rp-subtitle");
    gtk_box_append(GTK_BOX(ctx->stageBox), subtitle);
    auto* before = gtk_label_new(ctx->flow.originalText.empty()
                                     ? tr("editor.none")
                                     : ctx->flow.originalText.c_str());
    gtk_widget_add_css_class(before, "rp-source");
    gtk_label_set_wrap(GTK_LABEL(before), TRUE);
    gtk_box_append(GTK_BOX(ctx->stageBox), before);
    auto* after = gtk_label_new(tr("editor.confirm.after"));
    gtk_widget_add_css_class(after, "rp-section");
    gtk_box_append(GTK_BOX(ctx->stageBox), after);
    auto* buffer = gtk_text_view_get_buffer(ctx->textArea);
    GtkTextIter startIter, endIter;
    gtk_text_buffer_get_bounds(buffer, &startIter, &endIter);
    auto* raw = gtk_text_buffer_get_text(buffer, &startIter, &endIter, TRUE);
    std::string text = raw != nullptr ? raw : "";
    g_free(raw);
    auto* afterText = gtk_label_new(text.c_str());
    gtk_widget_add_css_class(afterText, "rp-source");
    gtk_label_set_wrap(GTK_LABEL(afterText), TRUE);
    gtk_box_append(GTK_BOX(ctx->stageBox), afterText);
    auto* actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(actions, GTK_ALIGN_END);
    auto* back = gtk_button_new_with_label(tr("patch.back"));
    auto* save = gtk_button_new_with_label(tr("editor.confirm.save"));
    gtk_widget_add_css_class(save, "rp-nav-active");
    gtk_box_append(GTK_BOX(actions), back);
    gtk_box_append(GTK_BOX(actions), save);
    gtk_box_append(GTK_BOX(ctx->stageBox), actions);
    g_signal_connect_data(
        back, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_editor != nullptr) {
            g_editor->stage = false;
            g_editor->refreshStage();
          }
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
    g_signal_connect_data(
        save, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_editor == nullptr) return;
          auto flow = g_editor->flow;
          auto* buffer = gtk_text_view_get_buffer(g_editor->textArea);
          GtkTextIter startIter, endIter;
          gtk_text_buffer_get_bounds(buffer, &startIter, &endIter);
          auto* raw = gtk_text_buffer_get_text(buffer, &startIter, &endIter, TRUE);
          std::string text = raw != nullptr ? raw : "";
          g_free(raw);
          auto dialog = g_editor->dialog;
          capture_undo();
          g_state.api->library_update_rules_async(
              g_state.libraryRoot, flow.profileId, text,
              [dialog](rivet_app::Result<rivet_app::LibraryMutation> result) {
                dispatch_ui([result = std::move(result), dialog]() mutable {
                  gtk_window_destroy(GTK_WINDOW(dialog));
                  g_editor = nullptr;
                  on_result(std::move(result),
                            [](rivet_app::LibraryMutation const&) {
                              add_event(tr("editor.saved"));
                              show_toast(tr("editor.saved"), true);
                              refresh_library();
                            });
                });
              });
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
  }
}

void open_editor_dialog(rivet_app::LibraryEntry const& entry) {
  auto json = g_state.api->library_read_profile_within(
      g_state.libraryRoot, entry.id, std::chrono::seconds(10));
  std::string rules;
  if (json.has_value()) {
    auto keyAt = json->find("\"rules\"");
    auto open = json->find('[', keyAt == std::string::npos ? 0 : keyAt);
    auto close = json->find(']', open);
    if (open != std::string::npos && close != std::string::npos) {
      std::string body = json->substr(open + 1, close - open - 1);
      std::size_t at = 0;
      while (true) {
        auto quote = body.find('"', at);
        if (quote == std::string::npos) break;
        auto end = body.find('"', quote + 1);
        if (end == std::string::npos) break;
        if (!rules.empty()) rules += "\n";
        rules += body.substr(quote + 1, end - quote - 1);
        at = end + 1;
      }
    }
  }
  auto* dialog = make_dialog(tr("editor.title"), tr("editor.body"));
  auto* stageBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_box_append(GTK_BOX(dialog_body(dialog)), stageBox);
  auto* textArea = GTK_TEXT_VIEW(gtk_text_view_new());
  gtk_text_view_set_wrap_mode(textArea, GTK_WRAP_WORD_CHAR);
  EditorDialogCtx* ctx = new EditorDialogCtx{
      dialog, stageBox, textArea, nullptr, false,
      EditorFlow{entry.id, entry.name, entry.id == g_state.snapshot.activeProfileId,
                 rules},
      nullptr};
  gtk_text_buffer_set_text(gtk_text_view_get_buffer(textArea), rules.c_str(), -1);
  ctx->refreshStage = [] { render_editor_stage(); };
  g_editor = ctx;
  render_editor_stage();
  gtk_window_present(GTK_WINDOW(dialog));
  g_signal_connect_data(
      dialog, "destroy",
      G_CALLBACK(+[](GtkWidget*, gpointer) {
        if (g_editor != nullptr) g_editor = nullptr;
      }),
      nullptr, nullptr, static_cast<GConnectFlags>(0));
}

// ---------------------------------------------------------------------------
// Switch / delete confirms + route patch dialog
// ---------------------------------------------------------------------------

void open_switch_confirm(rivet_app::LibraryEntry const& entry) {
  auto* dialog = make_dialog(
      tr("switch.title"),
      g_state.phase == SessionPhase::running ? tr("switch.body.running")
                                             : tr("switch.body.idle"));
  auto* body = dialog_body(dialog);
  auto* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 16);
  auto* from = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_box_append(GTK_BOX(from), gtk_label_new(tr("switch.from")));
  gtk_box_append(GTK_BOX(from), gtk_label_new(
      active_entry() != nullptr ? active_entry()->name.c_str() : "—"));
  auto* to = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_box_append(GTK_BOX(to), gtk_label_new(tr("switch.to")));
  gtk_box_append(GTK_BOX(to), gtk_label_new(entry.name.c_str()));
  gtk_box_append(GTK_BOX(row), from);
  gtk_box_append(GTK_BOX(row), to);
  gtk_box_append(GTK_BOX(body), row);
  add_dialog_actions(dialog, body, tr("cancel"), tr("switch.confirm"),
                     [entry] {
                       capture_undo();
                       g_state.api->library_set_active_async(
                           g_state.libraryRoot, entry.id,
                           [](rivet_app::Result<rivet_app::LibraryMutation> result) {
                             on_result(std::move(result),
                                       [](rivet_app::LibraryMutation const&) {
                                         add_event(tr("switch.done"));
                                         show_toast(tr("switch.done"), true);
                                         refresh_library();
                                       });
                           });
                     });
  gtk_window_present(GTK_WINDOW(dialog));
}

void open_delete_confirm(rivet_app::LibraryEntry const& entry) {
  auto* dialog = make_dialog(tr("delete.title"), tr("delete.body"));
  auto* body = dialog_body(dialog);
  auto* name = gtk_label_new(entry.name.c_str());
  gtk_widget_add_css_class(name, "rp-mono");
  gtk_box_append(GTK_BOX(body), name);
  add_dialog_actions(dialog, body, tr("cancel"), tr("delete.confirm"),
                     [entry] {
                       if (entry.id == g_state.snapshot.activeProfileId) {
                         show_toast(tr("delete.activeRefused"), false);
                         return;
                       }
                       capture_undo();
                       g_state.api->library_delete_profile_async(
                           g_state.libraryRoot, entry.id,
                           [](rivet_app::Result<rivet_app::LibraryMutation> result) {
                             on_result(std::move(result),
                                       [](rivet_app::LibraryMutation const&) {
                                         add_event(tr("delete.done"));
                                         show_toast(tr("delete.done"), true);
                                         refresh_library();
                                       });
                           });
                     });
  gtk_window_present(GTK_WINDOW(dialog));
}

struct PatchDialogCtx {
  GtkWidget* dialog;
  GtkWidget* stageBox;
  GtkComboBoxText* policyPicker;
  PatchFlow flow;
  std::function<void()> refreshStage;
};

PatchDialogCtx* g_patch = nullptr;

void render_patch_stage() {
  auto* ctx = g_patch;
  for (auto* child = gtk_widget_get_first_child(ctx->stageBox); child != nullptr;
       child = gtk_widget_get_first_child(ctx->stageBox)) {
    gtk_box_remove(GTK_BOX(ctx->stageBox), child);
  }
  auto* target = gtk_label_new(ctx->flow.target.c_str());
  gtk_widget_add_css_class(target, "rp-mono");
  gtk_label_set_xalign(GTK_LABEL(target), 0.0f);
  gtk_box_append(GTK_BOX(ctx->stageBox), target);
  if (!ctx->flow.preview.has_value()) {
    auto* picker = GTK_COMBO_BOX_TEXT(gtk_combo_box_text_new());
    for (auto const& target : active_entry() != nullptr
                                  ? active_entry()->targets
                                  : std::vector<std::string>{}) {
      gtk_combo_box_text_append(picker, target.c_str(),
                                policy_name(target).c_str());
    }
    gtk_combo_box_set_active(GTK_COMBO_BOX(picker), 0);
    ctx->policyPicker = picker;
    gtk_box_append(GTK_BOX(ctx->stageBox), GTK_WIDGET(picker));
    auto* note = gtk_label_new(tr("patch.note"));
    gtk_label_set_wrap(GTK_LABEL(note), TRUE);
    gtk_label_set_xalign(GTK_LABEL(note), 0.0f);
    gtk_widget_add_css_class(note, "rp-meta");
    gtk_box_append(GTK_BOX(ctx->stageBox), note);
    auto* actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(actions, GTK_ALIGN_END);
    auto* preview = gtk_button_new_with_label(tr("patch.preview"));
    gtk_widget_add_css_class(preview, "rp-nav-active");
    gtk_box_append(GTK_BOX(actions), preview);
    gtk_box_append(GTK_BOX(ctx->stageBox), actions);
    g_signal_connect_data(
        preview, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_patch == nullptr) return;
          auto selected = gtk_combo_box_text_get_active_text(g_patch->policyPicker);
          if (selected == nullptr) return;
          std::string policy = selected;
          g_free(selected);
          auto flow = g_patch->flow;
          flow.policy = policy;
          g_state.api->library_patch_preview_async(
              g_state.libraryRoot, g_state.snapshot.activeProfileId, flow.target,
              policy,
              [flow](rivet_app::Result<rivet_app::PatchPreview> result) {
                dispatch_ui([result = std::move(result), flow]() mutable {
                  if (g_patch == nullptr) return;
                  if (!result.succeeded() || result.value->sameAsCurrent) {
                    show_toast(tr("patch.same"), false);
                    return;
                  }
                  g_patch->flow = flow;
                  g_patch->flow.preview = std::move(*result.value);
                  g_patch->refreshStage();
                });
              });
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
  } else {
    auto const& preview = *ctx->flow.preview;
    auto* grid = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 16);
    auto* left = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_box_append(GTK_BOX(left), gtk_label_new(tr("patch.confirm.before")));
    gtk_box_append(GTK_BOX(left),
                   gtk_label_new(policy_name(preview.currentPolicy).c_str()));
    gtk_box_append(GTK_BOX(left), gtk_label_new(preview.currentOutbound.c_str()));
    auto* right = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_box_append(GTK_BOX(right), gtk_label_new(tr("patch.confirm.after")));
    gtk_box_append(GTK_BOX(right),
                   gtk_label_new(policy_name(preview.nextPolicy).c_str()));
    gtk_box_append(GTK_BOX(right), gtk_label_new(preview.nextOutbound.c_str()));
    gtk_box_append(GTK_BOX(grid), left);
    gtk_box_append(GTK_BOX(grid), right);
    gtk_box_append(GTK_BOX(ctx->stageBox), grid);
    auto* rule = gtk_label_new(("+ " + preview.ruleText).c_str());
    gtk_widget_add_css_class(rule, "rp-source");
    gtk_box_append(GTK_BOX(ctx->stageBox), rule);
    auto* actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(actions, GTK_ALIGN_END);
    auto* back = gtk_button_new_with_label(tr("patch.back"));
    auto* apply = gtk_button_new_with_label(tr("patch.confirm.apply"));
    gtk_widget_add_css_class(apply, "rp-nav-active");
    gtk_box_append(GTK_BOX(actions), back);
    gtk_box_append(GTK_BOX(actions), apply);
    gtk_box_append(GTK_BOX(ctx->stageBox), actions);
    g_signal_connect_data(
        back, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_patch != nullptr) {
            g_patch->flow.preview.reset();
            g_patch->refreshStage();
          }
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
    g_signal_connect_data(
        apply, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer) {
          if (g_patch == nullptr) return;
          auto flow = g_patch->flow;
          auto dialog = g_patch->dialog;
          capture_undo();
          g_state.api->library_patch_apply_async(
              g_state.libraryRoot, g_state.snapshot.activeProfileId, flow.target,
              flow.policy,
              [dialog](rivet_app::Result<rivet_app::PatchOutcome> result) {
                dispatch_ui([result = std::move(result), dialog]() mutable {
                  gtk_window_destroy(GTK_WINDOW(dialog));
                  g_patch = nullptr;
                  on_result(std::move(result),
                            [](rivet_app::PatchOutcome const&) {
                              add_event(tr("patch.applied"));
                              show_toast(tr("patch.applied"), true);
                              refresh_library();
                              if (!g_state.traceTarget.empty()) {
                                auto target = g_state.traceTarget;
                                g_state.api->explain_route_async(
                                    g_state.activeProfileJson, target, "", 443,
                                    "tcp",
                                    [target](rivet_app::Result<
                                             rivet_app::RouteDecision> result) {
                                      on_result(std::move(result),
                                                [target](auto const& decision) {
                                                  g_state.traceDecision = decision;
                                                  g_state.routeCache[target] =
                                                      decision;
                                                  update_trace_result();
                                                });
                                    });
                              }
                            });
                });
              });
        }),
        nullptr, nullptr, static_cast<GConnectFlags>(0));
  }
}

void open_patch_dialog(std::string const& target) {
  auto* dialog = make_dialog(tr("patch.title"), tr("patch.body"));
  auto* stageBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_box_append(GTK_BOX(dialog_body(dialog)), stageBox);
  auto* ctx = new PatchDialogCtx{dialog, stageBox, nullptr,
                                 PatchFlow{target, "DIRECT", {}}, nullptr};
  ctx->refreshStage = [] { render_patch_stage(); };
  g_patch = ctx;
  render_patch_stage();
  gtk_window_present(GTK_WINDOW(dialog));
  g_signal_connect_data(
      dialog, "destroy",
      G_CALLBACK(+[](GtkWidget*, gpointer) { g_patch = nullptr; }),
      nullptr, nullptr, static_cast<GConnectFlags>(0));
}

// ---------------------------------------------------------------------------
// Page construction
// ---------------------------------------------------------------------------

GtkWidget* build_overview() {
  auto* scroll = gtk_scrolled_window_new();
  auto* content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 20);
  gtk_widget_set_margin_top(content, 20);
  gtk_widget_set_margin_bottom(content, 20);
  gtk_widget_set_margin_start(content, 24);
  gtk_widget_set_margin_end(content, 24);

  auto* heading = gtk_label_new(tr("nav.overview"));
  gtk_label_set_xalign(GTK_LABEL(heading), 0.0f);
  gtk_widget_add_css_class(heading, "rp-title");
  auto* subtitle = gtk_label_new(tr("overview.subtitle"));
  gtk_label_set_xalign(GTK_LABEL(subtitle), 0.0f);
  gtk_widget_add_css_class(subtitle, "rp-subtitle");
  gtk_box_append(GTK_BOX(content), heading);
  gtk_box_append(GTK_BOX(content), subtitle);

  // Session card.
  auto* card = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16);
  gtk_widget_add_css_class(card, "rp-card");
  auto* top = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 16);
  auto* emblem = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_add_css_class(emblem, "rp-emblem");
  auto* icon = gtk_image_new_from_icon_name("system-shutdown-symbolic");
  gtk_box_append(GTK_BOX(emblem), icon);
  auto* stateColumn = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  auto* sessionTitle = gtk_label_new(tr("session.idle"));
  gtk_label_set_xalign(GTK_LABEL(sessionTitle), 0.0f);
  gtk_widget_add_css_class(sessionTitle, "rp-hero-title");
  auto* sessionSub = gtk_label_new(tr("session.idle.sub"));
  gtk_label_set_xalign(GTK_LABEL(sessionSub), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(sessionSub), TRUE);
  gtk_widget_add_css_class(sessionSub, "rp-subtitle");
  gtk_box_append(GTK_BOX(stateColumn), sessionTitle);
  gtk_box_append(GTK_BOX(stateColumn), sessionSub);
  auto* sessionButton = gtk_button_new_with_label(tr("session.start"));
  gtk_widget_set_valign(sessionButton, GTK_ALIGN_CENTER);
  gtk_box_append(GTK_BOX(top), emblem);
  gtk_box_append(GTK_BOX(top), stateColumn);
  gtk_box_append(GTK_BOX(top), sessionButton);
  gtk_widget_set_hexpand(stateColumn, TRUE);
  gtk_box_append(GTK_BOX(card), top);

  // Fact grid.
  auto* facts = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 24);
  auto* fact1 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_box_append(GTK_BOX(fact1), gtk_label_new(tr("fact.activeProfile")));
  auto* activeProfile = gtk_label_new("—");
  gtk_label_set_xalign(GTK_LABEL(activeProfile), 0.0f);
  gtk_box_append(GTK_BOX(fact1), activeProfile);
  auto* fact2 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_box_append(GTK_BOX(fact2), gtk_label_new(tr("fact.defaultRoute")));
  auto* defaultRoute = gtk_label_new("—");
  gtk_label_set_xalign(GTK_LABEL(defaultRoute), 0.0f);
  gtk_box_append(GTK_BOX(fact2), defaultRoute);
  auto* fact3 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_box_append(GTK_BOX(fact3), gtk_label_new(tr("fact.profileStatus")));
  auto* statusRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  auto* ruleCount = gtk_label_new("0");
  gtk_label_set_xalign(GTK_LABEL(ruleCount), 0.0f);
  auto* statusBadge = make_badge("rp-badge-ok", tr("fact.status.valid"));
  gtk_box_append(GTK_BOX(statusRow), ruleCount);
  gtk_box_append(GTK_BOX(statusRow), statusBadge);
  gtk_box_append(GTK_BOX(fact3), statusRow);
  gtk_widget_set_hexpand(fact1, TRUE);
  gtk_widget_set_hexpand(fact2, TRUE);
  gtk_box_append(GTK_BOX(facts), fact1);
  gtk_box_append(GTK_BOX(facts), fact2);
  gtk_box_append(GTK_BOX(facts), fact3);
  gtk_box_append(GTK_BOX(card), facts);
  gtk_box_append(GTK_BOX(content), card);

  // Attention.
  auto pendingBadge = make_badge("rp-badge-ok", tr("pending.clear"));
  auto* pendingHead =
      make_section_head(tr("pending.title"), pendingBadge);
  gtk_box_append(GTK_BOX(content), pendingHead);
  auto* pendingClear = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  auto* clearCheck = gtk_label_new(tr("pending.clear.title"));
  gtk_label_set_xalign(GTK_LABEL(clearCheck), 0.0f);
  gtk_widget_add_css_class(clearCheck, "rp-section");
  auto* clearText = gtk_label_new(tr("pending.clear.body"));
  gtk_label_set_xalign(GTK_LABEL(clearText), 0.0f);
  gtk_widget_add_css_class(clearText, "rp-subtitle");
  gtk_box_append(GTK_BOX(pendingClear), clearCheck);
  gtk_box_append(GTK_BOX(pendingClear), clearText);
  auto* pendingList = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_box_append(GTK_BOX(content), pendingClear);
  gtk_box_append(GTK_BOX(content), pendingList);

  // Targets + activity side by side.
  auto* split = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 24);
  auto* targetsColumn = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  auto* targetsHead =
      make_section_head(tr("targets.title"), gtk_label_new(""));
  auto* targetsList = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  auto* targetsEmpty = gtk_label_new(tr("targets.empty"));
  gtk_label_set_xalign(GTK_LABEL(targetsEmpty), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(targetsEmpty), TRUE);
  gtk_widget_add_css_class(targetsEmpty, "rp-subtitle");
  gtk_box_append(GTK_BOX(targetsColumn), targetsHead);
  gtk_box_append(GTK_BOX(targetsColumn), targetsList);
  gtk_box_append(GTK_BOX(targetsColumn), targetsEmpty);
  auto* eventsColumn = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  auto* eventsHead =
      make_section_head(tr("events.title"), gtk_label_new(tr("events.recentFirst")));
  auto* eventsList = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  gtk_box_append(GTK_BOX(eventsColumn), eventsHead);
  gtk_box_append(GTK_BOX(eventsColumn), eventsList);
  gtk_widget_set_hexpand(targetsColumn, TRUE);
  gtk_widget_set_hexpand(eventsColumn, TRUE);
  gtk_box_append(GTK_BOX(split), targetsColumn);
  gtk_box_append(GTK_BOX(split), eventsColumn);
  gtk_box_append(GTK_BOX(content), split);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), content);

  w.emblem = emblem;
  w.emblemIcon = icon;
  w.sessionTitle = GTK_LABEL(sessionTitle);
  w.sessionSub = GTK_LABEL(sessionSub);
  w.sessionButton = GTK_BUTTON(sessionButton);
  w.activeProfile = GTK_LABEL(activeProfile);
  w.defaultRoute = GTK_LABEL(defaultRoute);
  w.ruleCount = GTK_LABEL(ruleCount);
  w.statusBadge = statusBadge;
  w.pendingBadge = pendingBadge;
  w.pendingList = pendingList;
  w.pendingClear = pendingClear;
  w.targetsList = targetsList;
  w.targetsEmpty = GTK_LABEL(targetsEmpty);
  w.eventsList = eventsList;
  g_signal_connect(sessionButton, "clicked",
                   G_CALLBACK(+[](GtkButton*, gpointer) {
                     if (g_state.phase == SessionPhase::running) {
                       stop_session();
                     } else if (g_state.phase == SessionPhase::idle) {
                       open_session_confirm();
                     }
                   }),
                   nullptr);
  return scroll;
}

GtkWidget* build_trace() {
  auto* scroll = gtk_scrolled_window_new();
  auto* content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16);
  gtk_widget_set_margin_top(content, 20);
  gtk_widget_set_margin_bottom(content, 20);
  gtk_widget_set_margin_start(content, 24);
  gtk_widget_set_margin_end(content, 24);

  auto* heading = gtk_label_new(tr("nav.trace"));
  gtk_label_set_xalign(GTK_LABEL(heading), 0.0f);
  gtk_widget_add_css_class(heading, "rp-title");
  auto* subtitle = gtk_label_new(tr("trace.subtitle"));
  gtk_label_set_xalign(GTK_LABEL(subtitle), 0.0f);
  gtk_widget_add_css_class(subtitle, "rp-subtitle");
  gtk_box_append(GTK_BOX(content), heading);
  gtk_box_append(GTK_BOX(content), subtitle);

  auto* form = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  auto* field = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  gtk_box_append(GTK_BOX(field), make_field_label(tr("trace.field")));
  auto* entry = gtk_entry_new();
  gtk_widget_add_css_class(entry, "rp-mono");
  gtk_widget_set_hexpand(entry, TRUE);
  gtk_box_append(GTK_BOX(field), entry);
  auto* inspect = gtk_button_new_with_label(tr("trace.inspect"));
  gtk_box_append(GTK_BOX(form), field);
  gtk_box_append(GTK_BOX(form), inspect);
  gtk_box_append(GTK_BOX(content), form);

  auto* error = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(error), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(error), TRUE);
  gtk_widget_add_css_class(error, "rp-error");
  gtk_widget_set_visible(error, FALSE);
  gtk_box_append(GTK_BOX(content), error);

  auto* resultBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16);
  auto* resultHead = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  auto* resultTarget = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(resultTarget), 0.0f);
  gtk_widget_add_css_class(resultTarget, "rp-title");
  gtk_widget_add_css_class(resultTarget, "rp-mono");
  auto* expectBadge = make_badge("rp-badge-ok", tr("trace.noExpectationBadge"));
  gtk_box_append(GTK_BOX(resultHead), resultTarget);
  gtk_box_append(GTK_BOX(resultHead), expectBadge);
  gtk_box_append(GTK_BOX(resultBox), resultHead);

  auto* comparison = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_add_css_class(comparison, "rp-card");
  auto* expectation = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  gtk_box_append(GTK_BOX(expectation), gtk_label_new(tr("trace.expectation.label")));
  auto* picker = GTK_COMBO_BOX_TEXT(gtk_combo_box_text_new());
  gtk_box_append(GTK_BOX(expectation), GTK_WIDGET(picker));
  auto* note = gtk_label_new(tr("trace.expectation.note"));
  gtk_label_set_xalign(GTK_LABEL(note), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(note), TRUE);
  gtk_widget_add_css_class(note, "rp-meta");
  gtk_box_append(GTK_BOX(expectation), note);
  auto* actual = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  gtk_box_append(GTK_BOX(actual), gtk_label_new(tr("trace.actual")));
  auto* actualPolicy = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(actualPolicy), 0.0f);
  gtk_widget_add_css_class(actualPolicy, "rp-hero-title");
  auto* actualOutbound = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(actualOutbound), 0.0f);
  gtk_widget_add_css_class(actualOutbound, "rp-mono");
  gtk_box_append(GTK_BOX(actual), actualPolicy);
  gtk_box_append(GTK_BOX(actual), actualOutbound);
  gtk_widget_set_hexpand(expectation, TRUE);
  gtk_box_append(GTK_BOX(comparison), expectation);
  gtk_box_append(GTK_BOX(comparison), actual);
  gtk_box_append(GTK_BOX(resultBox), comparison);

  auto* cause = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  auto* causeTitle = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(causeTitle), 0.0f);
  gtk_widget_add_css_class(causeTitle, "rp-section");
  auto* causeBody = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(causeBody), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(causeBody), TRUE);
  gtk_widget_add_css_class(causeBody, "rp-subtitle");
  auto* causeSource = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(causeSource), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(causeSource), TRUE);
  gtk_widget_add_css_class(causeSource, "rp-source");
  gtk_box_append(GTK_BOX(cause), causeTitle);
  gtk_box_append(GTK_BOX(cause), causeBody);
  gtk_box_append(GTK_BOX(cause), causeSource);
  gtk_box_append(GTK_BOX(resultBox), cause);

  auto* stepsHead = make_section_head(tr("trace.steps.title"),
                                      gtk_label_new(tr("trace.steps.note")));
  auto* stepsBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_box_append(GTK_BOX(resultBox), stepsHead);
  gtk_box_append(GTK_BOX(resultBox), stepsBox);

  auto* artifactLine = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(artifactLine), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(artifactLine), TRUE);
  gtk_widget_add_css_class(artifactLine, "rp-meta");
  gtk_box_append(GTK_BOX(resultBox), artifactLine);

  auto* actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  auto* copy = gtk_button_new_with_label(tr("trace.copy"));
  auto* saveTarget = gtk_button_new_with_label(tr("trace.saveTarget"));
  gtk_box_append(GTK_BOX(actions), copy);
  gtk_box_append(GTK_BOX(actions), saveTarget);
  gtk_box_append(GTK_BOX(resultBox), actions);

  gtk_box_append(GTK_BOX(content), resultBox);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), content);

  w.targetEntry = GTK_ENTRY(entry);
  w.traceError = GTK_LABEL(error);
  w.inspectButton = GTK_BUTTON(inspect);
  w.resultBox = resultBox;
  w.resultTarget = GTK_LABEL(resultTarget);
  w.expectBadge = expectBadge;
  w.expectationPicker = picker;
  w.actualPolicy = GTK_LABEL(actualPolicy);
  w.actualOutbound = GTK_LABEL(actualOutbound);
  w.causeTitle = GTK_LABEL(causeTitle);
  w.causeBody = GTK_LABEL(causeBody);
  w.causeSource = GTK_LABEL(causeSource);
  w.stepsBox = stepsBox;
  w.saveTargetButton = GTK_BUTTON(saveTarget);
  w.artifactLine = GTK_LABEL(artifactLine);

  auto* inspectPtr = w.inspectButton;
  g_signal_connect(inspect, "clicked",
                   G_CALLBACK(+[](GtkButton*, gpointer user_data) {
                     auto* button = static_cast<GtkButton*>(user_data);
                     (void)button;
                     auto* text = gtk_editable_get_text(GTK_EDITABLE(w.targetEntry));
                     inspect_route(text != nullptr ? text : "");
                   }),
                   inspectPtr);
  g_signal_connect(entry, "activate",
                   G_CALLBACK(+[](GtkEntry*, gpointer) {
                     auto* text = gtk_editable_get_text(GTK_EDITABLE(w.targetEntry));
                     inspect_route(text != nullptr ? text : "");
                   }),
                   nullptr);
  auto* copyButton = GTK_BUTTON(copy);
  g_signal_connect(copy, "clicked",
                   G_CALLBACK(+[](GtkButton*, gpointer user_data) {
                     auto* button = static_cast<GtkButton*>(user_data);
                     (void)button;
                     if (!g_state.traceHasResult) return;
                     std::string record =
                         std::string("trace_id: ") + g_state.traceDecision.traceId +
                         "\npolicy: " + g_state.traceDecision.policy +
                         "\noutbound: " + g_state.traceDecision.outbound;
                     for (auto const& step : g_state.traceDecision.steps) {
                       record += "\nstep: " + step;
                     }
                     if (!g_state.traceArtifact.sha256.empty()) {
                       record += "\nartifact: " + g_state.traceArtifact.adapter + " " +
                                 g_state.traceArtifact.adapterVersion + " sha256=" +
                                 g_state.traceArtifact.sha256;
                     }
                     auto* display = gdk_display_get_default();
                     auto* clipboard = gdk_display_get_clipboard(display);
                     gdk_clipboard_set_text(clipboard, record.c_str());
                     show_toast(tr("trace.copied"), false);
                   }),
                   copyButton);
  g_signal_connect(saveTarget, "clicked",
                   G_CALLBACK(+[](GtkButton*, gpointer) {
                     if (!g_state.traceTarget.empty() &&
                         std::find(g_state.savedTargets.begin(),
                                   g_state.savedTargets.end(),
                                   g_state.traceTarget) !=
                             g_state.savedTargets.end()) {
                       remove_target(g_state.traceTarget);
                     } else {
                       save_target();
                     }
                   }),
                   nullptr);
  auto* pickerPtr = w.expectationPicker;
  g_signal_connect(picker, "changed",
                   G_CALLBACK(+[](GtkComboBox* box, gpointer user_data) {
                     auto* picker = static_cast<GtkComboBoxText*>(user_data);
                     (void)picker;
                     auto* selected = gtk_combo_box_text_get_active_text(
                         GTK_COMBO_BOX_TEXT(box));
                     if (selected == nullptr) return;
                     std::string value = selected;
                     g_free(selected);
                     set_expectation(g_state.traceTarget, value);
                   }),
                   pickerPtr);
  return scroll;
}

GtkWidget* build_profiles() {
  auto* scroll = gtk_scrolled_window_new();
  auto* content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16);
  gtk_widget_set_margin_top(content, 20);
  gtk_widget_set_margin_bottom(content, 20);
  gtk_widget_set_margin_start(content, 24);
  gtk_widget_set_margin_end(content, 24);

  auto* heading = gtk_label_new(tr("nav.profiles"));
  gtk_label_set_xalign(GTK_LABEL(heading), 0.0f);
  gtk_widget_add_css_class(heading, "rp-title");
  auto* subtitle = gtk_label_new(tr("profiles.subtitle"));
  gtk_label_set_xalign(GTK_LABEL(subtitle), 0.0f);
  gtk_widget_add_css_class(subtitle, "rp-subtitle");
  gtk_box_append(GTK_BOX(content), heading);
  gtk_box_append(GTK_BOX(content), subtitle);

  auto* importButton = gtk_button_new_with_label(tr("profiles.import"));
  gtk_widget_set_halign(importButton, GTK_ALIGN_END);
  gtk_box_append(GTK_BOX(content), importButton);

  auto* toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  auto* search = gtk_entry_new();
  gtk_entry_set_placeholder_text(GTK_ENTRY(search),
                                 tr("profiles.search.placeholder"));
  gtk_widget_set_hexpand(search, TRUE);
  auto* filter = GTK_COMBO_BOX_TEXT(gtk_combo_box_text_new());
  gtk_combo_box_text_append(filter, "all", tr("profiles.filter.all"));
  gtk_combo_box_text_append(filter, "valid", tr("profiles.filter.valid"));
  gtk_combo_box_text_append(filter, "invalid", tr("profiles.filter.invalid"));
  gtk_combo_box_set_active(GTK_COMBO_BOX(filter), 0);
  gtk_box_append(GTK_BOX(toolbar), search);
  gtk_box_append(GTK_BOX(toolbar), GTK_WIDGET(filter));
  gtk_box_append(GTK_BOX(content), toolbar);

  auto* resultsCount = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(resultsCount), 0.0f);
  gtk_widget_add_css_class(resultsCount, "rp-meta");
  gtk_box_append(GTK_BOX(content), resultsCount);

  auto* split = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 20);
  auto* listBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  auto* listScroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(listScroll), listBox);
  gtk_widget_set_size_request(listScroll, 260, 360);
  auto* detailEmpty = gtk_label_new(tr("profiles.pick"));
  gtk_label_set_xalign(GTK_LABEL(detailEmpty), 0.0f);
  gtk_widget_add_css_class(detailEmpty, "rp-subtitle");
  auto* detailBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_add_css_class(detailBox, "rp-card");
  auto* detailHead = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  auto* detailTitle = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(detailTitle), 0.0f);
  gtk_widget_add_css_class(detailTitle, "rp-section");
  auto* detailBadge = make_badge("rp-badge-ok", "");
  gtk_box_append(GTK_BOX(detailHead), detailTitle);
  gtk_box_append(GTK_BOX(detailHead), detailBadge);
  auto* detailIssues = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  auto* rulesHead = gtk_label_new(tr("profiles.rules.title"));
  gtk_label_set_xalign(GTK_LABEL(rulesHead), 0.0f);
  gtk_widget_add_css_class(rulesHead, "rp-section");
  auto* rulesBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  auto* actionRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  auto* useButton = gtk_button_new_with_label(tr("profiles.use"));
  auto* editButton = gtk_button_new_with_label(tr("profiles.edit"));
  auto* deleteButton = gtk_button_new_with_label(tr("profiles.delete"));
  gtk_box_append(GTK_BOX(actionRow), useButton);
  gtk_box_append(GTK_BOX(actionRow), editButton);
  gtk_box_append(GTK_BOX(actionRow), deleteButton);
  gtk_box_append(GTK_BOX(detailBox), detailHead);
  gtk_box_append(GTK_BOX(detailBox), detailIssues);
  gtk_box_append(GTK_BOX(detailBox), rulesHead);
  gtk_box_append(GTK_BOX(detailBox), rulesBox);
  gtk_box_append(GTK_BOX(detailBox), actionRow);
  gtk_widget_set_hexpand(detailBox, TRUE);
  gtk_box_append(GTK_BOX(split), listScroll);
  gtk_box_append(GTK_BOX(split), detailBox);
  gtk_box_append(GTK_BOX(content), split);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), content);

  w.search = GTK_ENTRY(search);
  w.filter = filter;
  w.resultsCount = GTK_LABEL(resultsCount);
  w.listBox = listBox;
  w.detailEmpty = detailEmpty;
  w.detailBox = detailBox;
  w.detailTitle = GTK_LABEL(detailTitle);
  w.detailBadge = detailBadge;
  w.detailIssues = detailIssues;
  w.rulesBox = rulesBox;
  w.actionRow = actionRow;

  auto* usePtr = useButton;
  auto* editPtr = editButton;
  auto* deletePtr = deleteButton;
  g_signal_connect(useButton, "clicked",
                   G_CALLBACK(+[](GtkButton*, gpointer user_data) {
                     auto* button = static_cast<GtkButton*>(user_data);
                     (void)button;
                     auto* entry = entry_by_id(g_state.selectedProfileId);
                     if (entry != nullptr && entry->status == "valid") {
                       open_switch_confirm(*entry);
                     }
                   }),
                   usePtr);
  g_signal_connect(editButton, "clicked",
                   G_CALLBACK(+[](GtkButton*, gpointer user_data) {
                     auto* button = static_cast<GtkButton*>(user_data);
                     (void)button;
                     auto* entry = entry_by_id(g_state.selectedProfileId);
                     if (entry != nullptr) open_editor_dialog(*entry);
                   }),
                   editPtr);
  g_signal_connect(deleteButton, "clicked",
                   G_CALLBACK(+[](GtkButton*, gpointer user_data) {
                     auto* button = static_cast<GtkButton*>(user_data);
                     (void)button;
                     auto* entry = entry_by_id(g_state.selectedProfileId);
                     if (entry != nullptr) open_delete_confirm(*entry);
                   }),
                   deletePtr);
  g_signal_connect(importButton, "clicked",
                   G_CALLBACK(+[](GtkButton*, gpointer) { open_import_dialog(); }),
                   nullptr);
  g_signal_connect(search, "changed",
                   G_CALLBACK(+[](GtkEditable* editable, gpointer) {
                     auto* entry = GTK_ENTRY(editable);
                     auto* text = gtk_editable_get_text(GTK_EDITABLE(entry));
                     g_state.profilesQuery = text != nullptr ? text : "";
                     render_profile_list();
                   }),
                   nullptr);
  g_signal_connect(filter, "changed",
                   G_CALLBACK(+[](GtkComboBox* box, gpointer) {
                     auto* selected =
                         gtk_combo_box_text_get_active_text(GTK_COMBO_BOX_TEXT(box));
                     if (selected != nullptr) {
                       g_state.profilesFilter = selected;
                       g_free(selected);
                     }
                     render_profile_list();
                   }),
                   nullptr);
  return scroll;
}

GtkWidget* build_settings() {
  auto* scroll = gtk_scrolled_window_new();
  auto* content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 20);
  gtk_widget_set_margin_top(content, 20);
  gtk_widget_set_margin_bottom(content, 20);
  gtk_widget_set_margin_start(content, 24);
  gtk_widget_set_margin_end(content, 24);
  gtk_widget_set_halign(content, GTK_ALIGN_FILL);

  auto* heading = gtk_label_new(tr("nav.settings"));
  gtk_label_set_xalign(GTK_LABEL(heading), 0.0f);
  gtk_widget_add_css_class(heading, "rp-title");
  auto* subtitle = gtk_label_new(tr("settings.subtitle"));
  gtk_label_set_xalign(GTK_LABEL(subtitle), 0.0f);
  gtk_widget_add_css_class(subtitle, "rp-subtitle");
  gtk_box_append(GTK_BOX(content), heading);
  gtk_box_append(GTK_BOX(content), subtitle);

  auto* appearance = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_box_append(GTK_BOX(appearance), gtk_label_new(tr("settings.appearance")));
  auto* themeRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  gtk_box_append(GTK_BOX(themeRow), gtk_label_new(tr("settings.theme")));
  auto* theme = GTK_COMBO_BOX_TEXT(gtk_combo_box_text_new());
  gtk_combo_box_text_append(theme, "system", tr("theme.system"));
  gtk_combo_box_text_append(theme, "light", tr("theme.light"));
  gtk_combo_box_text_append(theme, "dark", tr("theme.dark"));
  gtk_combo_box_set_active(GTK_COMBO_BOX(theme),
                           g_state.theme == "system" ? 0
                               : g_state.theme == "light" ? 1 : 2);
  gtk_box_append(GTK_BOX(themeRow), GTK_WIDGET(theme));
  gtk_box_append(GTK_BOX(appearance), themeRow);
  gtk_box_append(GTK_BOX(content), appearance);

  auto* privacy = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_box_append(GTK_BOX(privacy), gtk_label_new(tr("settings.privacy")));
  auto* redactRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  gtk_box_append(GTK_BOX(redactRow), gtk_label_new(tr("settings.redact")));
  auto* redact = gtk_check_button_new();
  gtk_check_button_set_active(GTK_CHECK_BUTTON(redact), g_state.redact);
  gtk_box_append(GTK_BOX(redactRow), redact);
  gtk_box_append(GTK_BOX(privacy), redactRow);
  auto* exportRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  gtk_box_append(GTK_BOX(exportRow), gtk_label_new(tr("settings.export")));
  auto* exportButton = gtk_button_new_with_label(tr("settings.export.button"));
  gtk_box_append(GTK_BOX(exportRow), exportButton);
  gtk_box_append(GTK_BOX(privacy), exportRow);
  gtk_box_append(GTK_BOX(content), privacy);

  auto* efficiency = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_box_append(GTK_BOX(efficiency), gtk_label_new(tr("settings.efficiency")));
  gtk_box_append(GTK_BOX(efficiency), gtk_label_new(tr("settings.keyboard.desc")));
  gtk_box_append(GTK_BOX(content), efficiency);

  auto* protection = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_box_append(GTK_BOX(protection), gtk_label_new(tr("settings.protection")));
  auto* guard = gtk_label_new(tr("settings.previewGuard.value"));
  gtk_widget_add_css_class(guard, "rp-badge-ok");
  gtk_box_append(GTK_BOX(protection), guard);
  gtk_box_append(GTK_BOX(protection), gtk_label_new(tr("settings.ai.value")));
  gtk_box_append(GTK_BOX(content), protection);

  auto* note = gtk_label_new(tr("settings.note"));
  gtk_label_set_xalign(GTK_LABEL(note), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(note), TRUE);
  gtk_widget_add_css_class(note, "rp-meta");
  gtk_box_append(GTK_BOX(content), note);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), content);

  w.theme = theme;
  w.redact = GTK_TOGGLE_BUTTON(redact);
  g_signal_connect(theme, "changed",
                   G_CALLBACK(+[](GtkComboBox* box, gpointer) {
                     auto* selected =
                         gtk_combo_box_text_get_active_text(GTK_COMBO_BOX_TEXT(box));
                     if (selected == nullptr) return;
                     g_state.theme = selected;
                     g_free(selected);
                     save_preferences();
                   }),
                   nullptr);
  g_signal_connect(redact, "toggled",
                   G_CALLBACK(+[](GtkCheckButton* button, gpointer) {
                     g_state.redact = gtk_check_button_get_active(button);
                     save_preferences();
                   }),
                   nullptr);
  g_signal_connect(exportButton, "clicked",
                   G_CALLBACK(+[](GtkButton*, gpointer) {
                     if (g_state.api == nullptr ||
                         g_state.activeProfileJson.empty() ||
                         g_state.traceTarget.empty()) {
                       show_toast(tr("trace.cause.none"), false);
                       return;
                     }
                     auto target = g_state.traceTarget;
                     auto redactFlag = g_state.redact;
                     g_state.api->diagnose_route_async(
                         g_state.activeProfileJson, target, "", 443, "tcp",
                         redactFlag,
                         [target](rivet_app::Result<std::string> result) {
                           on_result(std::move(result),
                                     [target](std::string const& bundle) {
                                       fs::path out = prefs_path().parent_path() /
                                                      ("relaypilot-diagnostic-" +
                                                       target + ".json");
                                       std::ofstream file(out, std::ios::trunc);
                                       file << bundle;
                                       show_toast(tr("settings.export.done"),
                                                  false);
                                     });
                         });
                   }),
                   nullptr);
  return scroll;
}

// ---------------------------------------------------------------------------
// Shell + backend bootstrap
// ---------------------------------------------------------------------------

void update_nav() {
  int pending = static_cast<int>(pending_profile_ids().size() +
                                 pending_mismatch_targets().size());
  gtk_label_set_text(w.navProfilesCount,
                     (pending > 0 ? std::to_string(pending)
                                  : std::to_string(g_state.snapshot.profiles.size()))
                         .c_str());
}

void show_page(int page) {
  g_state.page = static_cast<Page>(page);
  gtk_stack_set_visible_child_name(w.stack, page_id(g_state.page));
  for (std::size_t i = 0; i < w.navButtons.size(); ++i) {
    GtkStyleContext* context =
        gtk_widget_get_style_context(w.navButtons[i]);
    if (static_cast<int>(i) == page) {
      gtk_style_context_add_class(context, "rp-nav-active");
    } else {
      gtk_style_context_remove_class(context, "rp-nav-active");
    }
  }
}

std::optional<fs::path> executable_path() {
  char buffer[4096];
  ssize_t length = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
  if (length <= 0) return std::nullopt;
  buffer[length] = '\0';
  return fs::path(buffer);
}

struct RuntimeLayout {
  fs::path petite_boot;
  fs::path scheme_boot;
  fs::path racket_boot;
  fs::path core;
};

std::optional<RuntimeLayout> discover_runtime_layout() {
  auto exe = executable_path();
  if (!exe.has_value()) return std::nullopt;
  RuntimeLayout layout{exe->parent_path() / "runtime" / "petite.boot",
                       exe->parent_path() / "runtime" / "scheme.boot",
                       exe->parent_path() / "runtime" / "racket.boot",
                       exe->parent_path() / "res" / "core.zo"};
  if (std::filesystem::exists(layout.petite_boot) &&
      std::filesystem::exists(layout.scheme_boot) &&
      std::filesystem::exists(layout.racket_boot) &&
      std::filesystem::exists(layout.core)) {
    return layout;
  }
  return std::nullopt;
}

int on_backend_finished(gpointer) {
  if (g_state.startup_thread.joinable()) {
    g_state.startup_thread.join();
  }
  std::unique_ptr<rivet::linux_runtime::Backend> backend;
  std::string error;
  {
    std::lock_guard lock(g_state.startup_mutex);
    backend = std::move(g_state.startup_backend);
    error = std::move(g_state.startup_error);
  }
  if (g_state.shutting_down.load(std::memory_order_acquire)) {
    if (backend != nullptr) backend->stop();
    return G_SOURCE_REMOVE;
  }
  if (!error.empty() || backend == nullptr) {
    gtk_label_set_text(w.toastLabel,
                       std::string("Backend error: ").append(error).c_str());
    gtk_widget_set_visible(GTK_WIDGET(w.toastBox), TRUE);
    return G_SOURCE_REMOVE;
  }
  g_state.backend = backend.release();
  g_state.api = std::make_unique<rivet_app::API>(*g_state.backend);
  load_preferences();
  // The library root honors RELAYPILOT_LIBRARY_ROOT (acceptance isolation);
  // default is the XDG data directory.
  char const* overrideRoot = std::getenv("RELAYPILOT_LIBRARY_ROOT");
  if (overrideRoot != nullptr && *overrideRoot != '\0') {
    g_state.libraryRoot = overrideRoot;
  } else {
    char const* data = std::getenv("XDG_DATA_HOME");
    fs::path base = (data != nullptr && *data != '\0')
                        ? fs::path(data)
                        : (fs::path(std::getenv("HOME") != nullptr
                                        ? std::getenv("HOME")
                                        : ".") /
                           ".local" / "share");
    g_state.libraryRoot = (base / "relaypilot" / "library").string();
  }
  std::error_code ec;
  fs::create_directories(g_state.libraryRoot, ec);
  refresh_library();
  return G_SOURCE_REMOVE;
}

void start_backend() {
  auto layout = discover_runtime_layout();
  if (!layout.has_value()) {
    show_toast("Missing Rivet runtime layout (runtime/*.boot, res/core.zo) "
               "next to the executable. Build with raco rivet build/dev.",
               false);
    return;
  }
  rivet::linux_runtime::RacketRuntimeConfig config;
  config.executable_path = executable_path()->string();
  config.petite_boot = layout->petite_boot.string();
  config.scheme_boot = layout->scheme_boot.string();
  config.racket_boot = layout->racket_boot.string();
  config.backend_bundle = layout->core.string();
  config.module_name = rivet_app::kModuleName;
  config.entry_symbol = rivet_app::kEntryName;
  g_state.startup_thread = std::thread([config = std::move(config)]() mutable {
    auto backend = std::make_unique<rivet::linux_runtime::Backend>(std::move(config));
    try {
      backend->start();
      {
        std::lock_guard lock(g_state.startup_mutex);
        g_state.startup_backend = std::move(backend);
      }
    } catch (std::exception const& e) {
      std::lock_guard lock(g_state.startup_mutex);
      g_state.startup_error = e.what();
    }
    g_idle_add(on_backend_finished, nullptr);
  });
}

void on_activate(GtkApplication* app, gpointer) {
  apply_css();
  auto* window = gtk_application_window_new(app);
  gtk_window_set_title(GTK_WINDOW(window), "RelayPilot");
  gtk_window_set_default_size(GTK_WINDOW(window), 1180, 760);

  auto* root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  auto* banner = gtk_label_new(tr("banner"));
  gtk_label_set_xalign(GTK_LABEL(banner), 0.0f);
  gtk_widget_add_css_class(banner, "rp-banner");
  gtk_box_append(GTK_BOX(root), banner);

  auto* body = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  auto* sidebar = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  gtk_widget_add_css_class(sidebar, "rp-sidebar");
  gtk_widget_set_size_request(sidebar, 210, -1);
  auto* wordmark = gtk_label_new("RelayPilot");
  gtk_label_set_xalign(GTK_LABEL(wordmark), 0.0f);
  gtk_widget_add_css_class(wordmark, "rp-section");
  gtk_box_append(GTK_BOX(sidebar), wordmark);
  std::vector<GtkWidget*> navButtons;
  char const* navTitles[] = {tr("nav.overview"), tr("nav.trace"),
                             tr("nav.profiles"), tr("nav.settings")};
  for (int i = 0; i < 4; ++i) {
    auto* button = gtk_button_new_with_label(navTitles[i]);
    gtk_widget_add_css_class(button, "rp-nav");
    gtk_widget_set_halign(button, GTK_ALIGN_FILL);
    gtk_box_append(GTK_BOX(sidebar), button);
    navButtons.push_back(button);
    int page = i;
    g_signal_connect_data(
        button, "clicked",
        G_CALLBACK(+[](GtkButton*, gpointer user_data) {
          show_page(reinterpret_cast<ptrdiff_t>(user_data));
        }),
        reinterpret_cast<gpointer>(static_cast<ptrdiff_t>(page)), nullptr,
        static_cast<GConnectFlags>(0));
  }
  auto* spacer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_vexpand(spacer, TRUE);
  gtk_box_append(GTK_BOX(sidebar), spacer);
  auto* profilesCount = gtk_label_new("0");
  gtk_widget_add_css_class(profilesCount, "rp-meta");
  gtk_box_append(GTK_BOX(sidebar), profilesCount);
  auto* localNote = gtk_label_new(tr("sidebarNote"));
  gtk_label_set_xalign(GTK_LABEL(localNote), 0.0f);
  gtk_label_set_wrap(GTK_LABEL(localNote), TRUE);
  gtk_widget_add_css_class(localNote, "rp-meta");
  gtk_box_append(GTK_BOX(sidebar), localNote);

  auto* stack = gtk_stack_new();
  gtk_stack_add_named(GTK_STACK(stack), build_overview(), "overview");
  gtk_stack_add_named(GTK_STACK(stack), build_trace(), "trace");
  gtk_stack_add_named(GTK_STACK(stack), build_profiles(), "profiles");
  gtk_stack_add_named(GTK_STACK(stack), build_settings(), "settings");
  gtk_stack_set_visible_child_name(GTK_STACK(stack), "overview");
  gtk_widget_set_hexpand(stack, TRUE);

  gtk_box_append(GTK_BOX(body), sidebar);
  gtk_box_append(GTK_BOX(body), stack);
  gtk_box_append(GTK_BOX(root), body);

  auto* footer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 16);
  gtk_widget_add_css_class(footer, "rp-footer");
  auto* footerSession = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(footerSession), 0.0f);
  auto* footerRules = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(footerRules), 1.0f);
  gtk_widget_set_hexpand(footerSession, TRUE);
  gtk_box_append(GTK_BOX(footer), footerSession);
  gtk_box_append(GTK_BOX(footer), footerRules);
  gtk_box_append(GTK_BOX(root), footer);

  auto* overlay = gtk_overlay_new();
  gtk_overlay_set_child(GTK_OVERLAY(overlay), root);
  auto* toastBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  gtk_widget_add_css_class(toastBox, "rp-toast");
  gtk_widget_set_halign(toastBox, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(toastBox, GTK_ALIGN_END);
  gtk_widget_set_visible(toastBox, FALSE);
  auto* toastLabel = gtk_label_new("");
  gtk_label_set_wrap(GTK_LABEL(toastLabel), TRUE);
  gtk_box_append(GTK_BOX(toastBox), toastLabel);
  auto* toastUndo = gtk_button_new_with_label(tr("undo"));
  gtk_box_append(GTK_BOX(toastBox), toastUndo);
  auto* toastClose = gtk_button_new_with_label(tr("close"));
  gtk_box_append(GTK_BOX(toastBox), toastClose);
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), toastBox);
  gtk_box_append(GTK_BOX(root), gtk_label_new(""));

  gtk_window_set_child(GTK_WINDOW(window), overlay);
  gtk_window_present(GTK_WINDOW(window));

  g_state.window = window;
  w.navButtons = navButtons;
  w.navProfilesCount = GTK_LABEL(profilesCount);
  w.stack = GTK_STACK(stack);
  w.footerSession = GTK_LABEL(footerSession);
  w.footerRules = GTK_LABEL(footerRules);
  w.toastBox = toastBox;
  w.toastLabel = GTK_LABEL(toastLabel);
  show_page(0);
  start_backend();

  g_signal_connect_data(
      toastUndo, "clicked",
      G_CALLBACK(+[](GtkButton*, gpointer) {
        undo_last_change();
        gtk_widget_set_visible(GTK_WIDGET(w.toastBox), FALSE);
      }),
      nullptr, nullptr, static_cast<GConnectFlags>(0));
  g_signal_connect_data(
      toastClose, "clicked",
      G_CALLBACK(+[](GtkButton*, gpointer) {
        gtk_widget_set_visible(GTK_WIDGET(w.toastBox), FALSE);
      }),
      nullptr, nullptr, static_cast<GConnectFlags>(0));

  // Quick Find (⌘K → Ctrl+K): a simple controller dialog listing pages,
  // profiles, and saved targets.
  auto* shortcut_controller = gtk_shortcut_controller_new();
  auto* controller = GTK_EVENT_CONTROLLER(shortcut_controller);
  gtk_shortcut_controller_set_scope(shortcut_controller,
                                    GTK_SHORTCUT_SCOPE_LOCAL);
  auto* shortcut = gtk_shortcut_new(
      gtk_keyval_trigger_new(GDK_KEY_k, GDK_CONTROL_MASK),
      gtk_callback_action_new(
          +[](GtkWidget*, GVariant*, gpointer) -> int {
            auto* dialog = make_dialog(tr("qf.title"), tr("qf.subtitle"));
            auto* body = dialog_body(dialog);
            auto* list = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
            char const* pages[] = {tr("nav.overview"), tr("nav.trace"),
                                   tr("nav.profiles"), tr("nav.settings")};
            for (int i = 0; i < 4; ++i) {
              auto* button = gtk_button_new_with_label(pages[i]);
              int page = i;
              g_signal_connect_data(
                  button, "clicked",
                  G_CALLBACK(+[](GtkButton*, gpointer user_data) {
                    show_page(reinterpret_cast<ptrdiff_t>(user_data));
                  }),
                  reinterpret_cast<gpointer>(static_cast<ptrdiff_t>(page)),
                  nullptr, static_cast<GConnectFlags>(0));
              gtk_box_append(GTK_BOX(list), button);
            }
            for (auto const& entry : g_state.snapshot.profiles) {
              auto* button = gtk_button_new_with_label(entry.name.c_str());
              std::string id = entry.id;
              g_signal_connect_data(
                  button, "clicked",
                  G_CALLBACK(+[](GtkButton*, gpointer user_data) {
                    auto* id = static_cast<std::string*>(user_data);
                    g_state.selectedProfileId = *id;
                    show_page(2);
                    render_profile_detail();
                  }),
                  new std::string(id),
                  reinterpret_cast<GClosureNotify>(
                      +[](gpointer data, GClosure*) {
                        delete static_cast<std::string*>(data);
                      }),
                  static_cast<GConnectFlags>(0));
              gtk_box_append(GTK_BOX(list), button);
            }
            gtk_box_append(GTK_BOX(body), list);
            gtk_window_present(GTK_WINDOW(dialog));
            return TRUE;
          },
          nullptr, nullptr));
  gtk_shortcut_controller_add_shortcut(shortcut_controller, shortcut);
  gtk_widget_add_controller(GTK_WIDGET(window), controller);
}

void on_shutdown(GApplication*, gpointer) {
  g_state.shutting_down.store(true, std::memory_order_release);
  if (g_state.backend != nullptr) {
    g_state.backend->stop();
  }
}

}  // namespace

int main(int argc, char** argv) {
  auto* app = gtk_application_new("ai.turinglambda.relaypilot",
                                  G_APPLICATION_DEFAULT_FLAGS);
  g_app = app;
  g_signal_connect(app, "activate", G_CALLBACK(on_activate), nullptr);
  g_signal_connect(app, "shutdown", G_CALLBACK(on_shutdown), nullptr);
  int const status = g_application_run(G_APPLICATION(app), argc, argv);
  g_object_unref(app);
  return status;
}
