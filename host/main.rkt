#lang racket/base

;; RelayPilot glaze carrier (#13) — the single web UI's host adapter.
;;
;; S0 (carrier skeleton): the glaze app shell, the HTTP/native transport, the
;; runtime public dir (token sheet served single-source from
;; design/prototype/shared.css) and the i18n single source (shared/i18n).
;;
;; S1 (RPC bridge): the Racket control plane (racket/) and the rivet backend
;; (racket/backend.rkt) are unchanged; this module drives the production
;; backend over real in-process RVT1 frames through rivet/bridge (extracted
;; upstream from Podlens, turlamai/glaze#159 -> turlamai/rivet#493) and
;; exposes every registered RPC 1:1 as a typed glaze route.
;; rivet-schema.json remains the single source of the RPC contract: the
;; bridge codec converts camelCase JSON DTOs to field-ordered wire values and
;; back, and scripts/check-rpc-surface.py gates this route surface against
;; the schema.
;;
;; S2 (overview/connect + profiles): web/app.js is the product UI, evolved
;; from design/prototype and driven only through these routes; api/host/context
;; hands the page the per-user library root (single source, not an RPC input
;; the user could mistype).
;;
;; S3 (trace + diagnostics): the page exports a diagnostic bundle through
;; api/host/write to a destination the user picked in the native save panel
;; (glaze/dialogs); the capability grant scopes both to the local user.
;; Settings/tray land in S4.
;;
;; Carrier decision (#13, declared on the issue): production runs glaze's
;; first-class HTTP adapter on 127.0.0.1 with a per-launch token; the native
;; GLZ1 carrier remains available for development (RELAYPILOT_TRANSPORT=
;; native).
;;
;; Run:  racket host/main.rkt
;; Dev:  raco glaze dev  /  RELAYPILOT_TRANSPORT=native for the GLZ1 carrier.

(require glaze/app        ; run-app
         glaze/api        ; POST, GET, exn:fail:glaze:bad-param
         glaze/api-macros ; define-api-routes
         glaze/capability ; make-capability
         glaze/dialogs    ; make-dialog-routes (native save panel)
         glaze/events     ; make-event-bus, bus-broadcast! (tray → page)
         glaze/tray/main  ; make-tray, tray-set-menu! (carrier tray)
         glaze/window     ; webview-focus!
         glaze/types      ; GString, GInt64, GBool, GValue
         racket/file
         racket/path
         racket/runtime-path
         net/base64
         json
         (prefix-in engine: "../racket/backend.rkt")
         (prefix-in core: "../racket/core/version.rkt")
         rivet/bridge)

;; The route list schema tooling reads (glaze.rktd points here).
;; start-engine! wires the codec to the in-process RVT1 transport — the
;; app entry and the real-window verifier both call it; schema checks load
;; this module without starting anything.
(provide api start-engine! stop-engine! assemble-public-dir app-version host-capability
         host-bus)

(define-runtime-path schema-path "../rivet-schema.json")
(define schema (call-with-input-file schema-path read-json))
(define codec (make-bridge-codec schema))

(define-runtime-path probe-dir "web")

(define app-version core:app-version)

;; ---- one RPC call, JSON in / JSON out ------------------------------------
(define (rpc/json name args)
  (define sym (string->symbol name))
  (define wire-args (bridge-codec-encode codec sym args))
  (define-values (result err) (apply bridge-call name wire-args))
  (when err
    ;; The backend's message is the user-facing message (shared
    ;; exn:fail:relaypilot classification; library/diagnostic contracts).
    ;; glaze answers plain exns with a generic "internal error" on both
    ;; carriers; bad-param is the framework's typed channel whose message
    ;; reaches the page (HTTP 400 / native invalid-args).
    (raise (exn:fail:glaze:bad-param (format "~a" err) (current-continuation-marks))))
  (bridge-codec-decode codec sym result))

(define (bad-param message)
  (raise (exn:fail:glaze:bad-param message (current-continuation-marks))))

;; ---- typed RPC surface (1:1 with rivet-schema.json) ----------------------
;; Structured DTOs (records/lists) ride GValue at the transport boundary;
;; their shapes are enforced by the schema-driven codec, and the surface
;; gate keeps names/arity/scalar types aligned with rivet-schema.json.

(define-api-routes api-rpc
  ;; engine / decision
  [(POST "api/rpc/compile-engine-config" #:returns GValue)
   (compileEngineConfig [profileJson GString])
   (rpc/json "compile-engine-config" (hasheq 'profileJson profileJson))]
  [(POST "api/rpc/explain-route" #:returns GValue)
   (explainRoute [profileJson GString] [domain GString] [ip GString]
                 [port GInt64] [network GString])
   (rpc/json "explain-route"
             (hasheq 'profileJson profileJson 'domain domain 'ip ip
                     'port port 'network network))]
  [(POST "api/rpc/diagnose-route" #:returns GString)
   (diagnoseRoute [profileJson GString] [domain GString] [ip GString]
                  [port GInt64] [network GString] [redact GBool])
   (rpc/json "diagnose-route"
             (hasheq 'profileJson profileJson 'domain domain 'ip ip
                     'port port 'network network 'redact redact))]
  [(POST "api/rpc/engine-dry-run" #:returns GValue)
   (engineDryRun [profileJson GString] [socksPort GInt64])
   (rpc/json "engine-dry-run" (hasheq 'profileJson profileJson 'socksPort socksPort))]
  [(POST "api/rpc/engine-session-start" #:returns GValue)
   (engineSessionStart [profileJson GString] [socksPort GInt64])
   (rpc/json "engine-session-start"
             (hasheq 'profileJson profileJson 'socksPort socksPort))]
  [(POST "api/rpc/engine-session-stop" #:returns GValue)
   (engineSessionStop [sessionId GString])
   (rpc/json "engine-session-stop" (hasheq 'sessionId sessionId))]
  [(POST "api/rpc/engine-session-events" #:returns GValue)
   (engineSessionEvents [sessionId GString])
   (rpc/json "engine-session-events" (hasheq 'sessionId sessionId))]

  ;; profile library
  [(POST "api/rpc/library-list" #:returns GValue)
   (libraryList [root GString])
   (rpc/json "library-list" (hasheq 'root root))]
  [(POST "api/rpc/library-read-profile" #:returns GString)
   (libraryReadProfile [root GString] [profileId GString])
   (rpc/json "library-read-profile" (hasheq 'root root 'profileId profileId))]
  [(POST "api/rpc/library-import-preview" #:returns GValue)
   (libraryImportPreview [root GString] [name GString] [text GString])
   (rpc/json "library-import-preview" (hasheq 'root root 'name name 'text text))]
  [(POST "api/rpc/library-import-commit" #:returns GValue)
   (libraryImportCommit [root GString] [name GString] [description GString]
                        [text GString])
   (rpc/json "library-import-commit"
             (hasheq 'root root 'name name 'description description 'text text))]
  [(POST "api/rpc/library-update-rules" #:returns GValue)
   (libraryUpdateRules [root GString] [profileId GString] [rulesText GString])
   (rpc/json "library-update-rules"
             (hasheq 'root root 'profileId profileId 'rulesText rulesText))]
  [(POST "api/rpc/library-validate-rules" #:returns GValue)
   (libraryValidateRules [root GString] [profileId GString] [rulesText GString])
   (rpc/json "library-validate-rules"
             (hasheq 'root root 'profileId profileId 'rulesText rulesText))]
  [(POST "api/rpc/library-delete-profile" #:returns GValue)
   (libraryDeleteProfile [root GString] [profileId GString])
   (rpc/json "library-delete-profile" (hasheq 'root root 'profileId profileId))]
  [(POST "api/rpc/library-set-active" #:returns GValue)
   (librarySetActive [root GString] [profileId GString])
   (rpc/json "library-set-active" (hasheq 'root root 'profileId profileId))]
  [(POST "api/rpc/library-patch-preview" #:returns GValue)
   (libraryPatchPreview [root GString] [profileId GString] [target GString]
                        [policy GString])
   (rpc/json "library-patch-preview"
             (hasheq 'root root 'profileId profileId 'target target 'policy policy))]
  [(POST "api/rpc/library-patch-apply" #:returns GValue)
   (libraryPatchApply [root GString] [profileId GString] [target GString]
                       [policy GString])
   (rpc/json "library-patch-apply"
             (hasheq 'root root 'profileId profileId 'target target 'policy policy))]
  [(POST "api/rpc/library-restore-profile" #:returns GValue)
   (libraryRestoreProfile [root GString] [profileJson GString])
   (rpc/json "library-restore-profile" (hasheq 'root root 'profileJson profileJson))])

;; ---- host capabilities (outside any RPC surface gate) ------------------
(define-api-routes api-host
  [(GET "api/health" #:returns GValue)
   (healthHost)
   (hasheq 'ok "true" 'version app-version 'carrier "glaze")]

  ;; i18n single source (shared/i18n) served to the web UI; no copied
  ;; string table. zh is the default locale.
  [(GET "api/host/i18n" #:returns GValue)
   (hostI18n)
   (hasheq 'zh (call-with-input-file i18n-zh-path read-json)
           'en (call-with-input-file i18n-en-path read-json))]

  ;; Product context for the web UI: where the profile library lives (see
  ;; library-root) and whether the harness gate is on.
  [(GET "api/host/context" #:returns GValue)
   (hostContext)
   (hasheq 'libraryRoot (path->string (library-root))
           'version app-version
           'e2e (if (e2e-enabled?) "true" "false"))]


  ;; ---- acceptance harness gate (#13 S0/S1) ------------------------------
  ;; The probe page carries an in-page journey harness (?e2e=1) because
  ;; glaze exposes no JS injection into the webview. These routes are inert
  ;; unless RELAYPILOT_E2E=1 (verify.rkt / CI only).
  [(POST "api/host/e2e" #:returns GValue)
   (e2e)
   (hasheq 'enabled (e2e-enabled?))]
  [(POST "api/host/e2e_fixtures" #:returns GValue)
   (e2eFixtures)
   (host-e2e-fixtures)]
  [(POST "api/host/e2e_report" #:returns GBool)
   (e2eReport [payload GValue])
   (host-e2e-report! payload)
   #t]
  [(POST "api/host/e2e_report_get" #:returns GValue)
   (e2eReportGet)
   (or (unbox e2e-report-box) (hasheq 'phase "waiting"))]
  [(POST "api/host/e2e_reset" #:returns GBool)
   (e2eReset)
   (when (e2e-enabled?) (set-box! e2e-report-box #f) (set-box! e2e-root-box #f))
   #t]

  ;; ---- diagnostic export (#13 S3) ----------------------------------------
  ;; Export journey fixture: a destination in the temp dir plus a read-back,
  ;; so the page can prove what was written without any file access of its own.
  [(POST "api/host/e2e_export" #:returns GValue)
   (e2eExport)
   (unless (e2e-enabled?) (bad-param "export fixture: harness not enabled"))
   (hasheq 'path (path->string (make-temporary-file "relaypilot-diagnostic-~a.json")))]
  [(POST "api/host/e2e_export_read" #:returns GString)
   (e2eExportRead [path GString])
   (unless (e2e-enabled?) (bad-param "export fixture: harness not enabled"))
   (define p (string->path path))
   (if (file-exists? p) (file->string p) "")]
  ;; ---- tray / menu status (#13 S4) ----------------------------------------
  ;; The page reports the menu it wants (localized labels, checked/enabled
  ;; hints) and a tooltip after each render; the host rebuilds the native menu.
  [(POST "api/host/tray_state" #:returns GBool)
   (trayState [state GValue])
   (unless (tray-state-valid? state) (bad-param "tray state: {tooltip, menu} expected"))
   (set-box! tray-state-box state)
   (tray-refresh!)
   #t]
  ;; Journey fixtures: what the host currently holds for the tray, and a
  ;; menu pick made from outside the page (runs the item's real action).
  [(GET "api/host/e2e_tray" #:returns GValue)
   (e2eTray)
   (e2e-tray-info)]
  [(POST "api/host/e2e_tray_invoke" #:returns GString)
   (e2eTrayInvoke [id GString])
   (e2e-tray-invoke! id)]
  ;; The tray Quit item asks the page to stop a live engine session first.
  [(POST "api/host/quit" #:returns GBool)
   (hostQuit)
   (stop-engine!)
   (thread (lambda () (sleep 0.2) (exit 0)))
   #t]
  ;; Diagnostic export write; the destination is what the user picked in the
  ;; native save panel (api/dialog/save). Bytes ride base64 (GString).
  [(POST "api/host/write" #:returns GBool #:permission 'host:write)
   (hostWrite [path GString] [data GString])
   (host-write-bytes path data)
   #t])

;; ---- product context (#13 S2) ------------------------------------------
;; The library root the product UI passes to every library RPC: an explicit
;; override (scriptable runs, acceptance isolation), else the per-user app
;; data dir for the engine identifier from rivet.rktd. Top-level so the
;; runtime path and helpers stay outside the route macro.
(define-runtime-path rivet-descriptor-path "../rivet.rktd")

(define (descriptor-identifier)
  ;; rivet.rktd is a hash datum; the identifier names the per-user data dir.
  (with-handlers ([exn:fail? (lambda (_) "ai.turinglambda.relaypilot")])
    (define descriptor (with-input-from-file rivet-descriptor-path read))
    (hash-ref descriptor 'identifier)))

(define (user-library-root)
  (define override (getenv "RELAYPILOT_LIBRARY_ROOT"))
  (cond
    [(and override (positive? (string-length override))) (string->path override)]
    [else
     (define base
       (cond
         [(eq? (system-path-convention-type) 'windows)
          (or (getenv "LOCALAPPDATA") (getenv "APPDATA") (find-system-path 'home-dir))]
         [(eq? (system-type) 'macosx)
          (build-path (find-system-path 'home-dir) "Library" "Application Support")]
         [else
          (or (and (getenv "XDG_DATA_HOME") (string->path (getenv "XDG_DATA_HOME")))
              (build-path (find-system-path 'home-dir) ".local" "share"))]))
     (build-path base (descriptor-identifier) "library")]))

;; Journey fixture root: one disposable library per host process while the
;; harness gate is on, so the product journey never touches a user library.
(define e2e-root-box (box #f))
(define (e2e-library-root!)
  (unless (unbox e2e-root-box)
    (set-box! e2e-root-box (make-temporary-file "relaypilot-e2e-~a" 'directory)))
  (unbox e2e-root-box))

(define (library-root)
  (if (e2e-enabled?) (e2e-library-root!) (user-library-root)))

(define-runtime-path i18n-zh-path "../shared/i18n/zh.json")
(define-runtime-path i18n-en-path "../shared/i18n/en.json")

;; ---- harness gate state ---------------------------------------------------
(define (e2e-enabled?) (equal? (getenv "RELAYPILOT_E2E") "1"))
(define e2e-report-box (box #f))

(define api (append api-rpc api-host (make-dialog-routes)))

;; Runtime authority for the production window: the native save panel and the
;; diagnostic export write. The verifier runs without a capability (open-route
;; mode) so headless CI needs no interactive grant; the journey picks its
;; destination through the harness routes above.
(define host-capability
  (make-capability "relaypilot" '(dialog:save host:write)))

;; Export target: only what the user chose in the save panel, never an implicit
;; overwrite of a library file. Atomic replace (sibling temp + rename).
(define (host-write-bytes path data)
  (define p (string->path path))
  (define dir (path-only p))
  (unless (and dir (directory-exists? dir))
    (bad-param (format "destination directory missing: ~a" path)))
  (define tmp (build-path dir (format ".relaypilot-save-~a" (current-inexact-milliseconds))))
  (call-with-output-file tmp
    (lambda (out) (write-bytes (base64-decode (string->bytes/utf-8 data)) out))
    #:exists 'truncate/replace)
  (rename-file-or-directory tmp p #t))

;; ---- tray / menu status ----------------------------------------------------
;; The carrier owns the tray icon and the native menu; the page owns the
;; information architecture (labels come localized from the page). Picking an
;; item broadcasts back over glaze/events so the action runs the same path in
;; the page as a button click. Two items are host-owned: "show" refocuses the
;; window, "quit" ends the process (the page may first stop its session).
(define host-bus (make-event-bus))
(define tray-box (box #f))
(define window-box (box #f))
(define tray-state-box (box (hasheq 'tooltip "RelayPilot" 'menu '())))

(define (focus-window!)
  (define wv (unbox window-box))
  (when wv
    (with-handlers ([exn:fail? void]) (webview-focus! wv))))

(define (tray-quit!)
  ;; The page is told to quit through api/host/quit by its own session path;
  ;; a page that never answers must not pin the process.
  (thread (lambda () (sleep 4) (exit 0))))

(define (tray-state-valid? state)
  (and (hash? state)
       (string? (hash-ref state 'tooltip #f))
       (list? (hash-ref state 'menu '()))))

(define (tray-menu-items state)
  (define menu (hash-ref state 'menu '()))
  (filter
   menu-item?
   (for/list ([item (in-list menu)])
     (define label (and (hash? item) (hash-ref item 'label #f)))
     (define id (and (hash? item) (hash-ref item 'id #f)))
     (cond
       [(and (string? label) (string? id))
        (make-menu-item label
                        #:id id
                        #:checked? (eq? #t (hash-ref item 'checked #f))
                        #:enabled? (not (eq? #f (hash-ref item 'enabled #t)))
                        #:action
                        (lambda ()
                          (cond
                            [(string=? id "show") (focus-window!)]
                            [(string=? id "quit") (tray-quit!)]
                            [else (bus-broadcast! host-bus 'relaypilot-menu
                                                  (hasheq 'id id))])))]
       [else (menu-separator)]))))

(define (tray-refresh!)
  (define t (unbox tray-box))
  (when t
    (define state (unbox tray-state-box))
    (with-handlers ([exn:fail? (lambda (e)
                                 (eprintf "[tray] menu update failed: ~a\n" (exn-message e)))])
      (tray-set-tooltip! t (hash-ref state 'tooltip "RelayPilot"))
      (tray-set-menu! t (tray-menu-items state)))))

(define (e2e-tray-info)
  (unless (e2e-enabled?) (bad-param "tray fixture: harness not enabled"))
  (define state (unbox tray-state-box))
  (define t (unbox tray-box))
  (hasheq 'attached (and t #t)
          'backend (if t (format "~a" (tray-backend t)) "none")
          'tooltip (hash-ref state 'tooltip "")
          'view (hash-ref state 'view "")
          'menu (for/list ([item (in-list (tray-menu-items state))]
                           #:unless (menu-separator? item))
                  (hasheq 'id (menu-item-id item)
                          'label (menu-item-label item)
                          'checked (menu-item-checked? item)
                          'enabled (menu-item-enabled? item)))))

(define (e2e-tray-invoke! id)
  (unless (e2e-enabled?) (bad-param "tray fixture: harness not enabled"))
  (define hit
    (for/first ([item (in-list (tray-menu-items (unbox tray-state-box)))]
                #:when (and (not (menu-separator? item))
                            (string=? (menu-item-id item) id)))
      item))
  (unless hit (bad-param (format "no tray item ~s" id)))
  ((menu-item-action hit))
  id)

(define (host-e2e-report! payload)
  (when (e2e-enabled?) (set-box! e2e-report-box payload))
  (void))

;; Journey fixtures: the committed sample profile (examples/) and a
;; disposable library root, so the harness never touches a user library.
(define-runtime-path sample-profile-path "../examples/relay-profile.json")

(define (host-e2e-fixtures)
  (unless (e2e-enabled?) (bad-param "e2e fixtures: harness not enabled"))
  ;; The RPC probe journey gets its own disposable root (it asserts an empty
  ;; library); the product journey uses library-root, which e2e_reset rotates.
  (define root (make-temporary-file "relaypilot-e2e-~a" 'directory))
  (hasheq 'profileJson (file->string sample-profile-path)
          'libraryRoot (path->string root)))

;; ---- runtime public dir ---------------------------------------------------
;; The web UI's token sheet (design/prototype/shared.css) stays single-source
;; in the repo; the carrier assembles a runtime public dir at startup instead
;; of committing copies.
(define-runtime-path web-dir "web")
(define-runtime-path shared-css-path "../design/prototype/shared.css")

(define (assemble-public-dir)
  (define dir (build-path (find-system-path 'temp-dir)
                          (format "relaypilot-public-~a-~a"
                                  (current-seconds) (current-inexact-milliseconds))))
  ;; copy-directory/files creates `dir` as the copy of web-dir; pre-creating
  ;; it would make the copy collide with the existing directory.
  (copy-directory/files web-dir dir)
  (copy-file shared-css-path (build-path dir "shared.css"))
  dir)

;; ---- in-process engine transport -----------------------------------------
;; The backend serves RVT1 over a pipe pair inside this process: static
;; require above keeps raco exe embedding working (a runtime dynamic-require
;; cannot resolve source paths inside a distribution). The backend's own
;; session table (live engine sessions) therefore lives in this process.
(define engine-started? #f)

(define (engine:start/ports)
  (define-values (c2s-in c2s-out) (make-pipe))
  (define-values (s2c-in s2c-out) (make-pipe))
  (define t
    (thread
     (lambda ()
       ;; Explicit ports: the backend must never depend on the parameterized
       ;; current-input/output-port of whichever thread starts it.
       (engine:start-ports c2s-in s2c-out))))
  (values t s2c-in c2s-out))

(define (start-engine!)
  (unless engine-started?
    (start-bridge! engine:start/ports)
    (set! engine-started? #t)))

;; Idempotent shutdown for the app entry and the verifier.
(define (stop-engine!)
  (when engine-started?
    (stop-bridge!)
    (set! engine-started? #f)))

(module+ main
  (start-engine!)
  (define transport
    (or (let ([v (getenv "RELAYPILOT_TRANSPORT")])
          (and (member v '("native" "http")) (string->symbol v)))
        'http))
  ;; Tray resident from first paint; a platform without a native backend
  ;; degrades to the inert stub (the window stays the only surface).
  (define tray
    (make-tray #:icon #f
               #:tooltip "RelayPilot"
               #:menu (list (make-menu-item "Quit" #:id "quit" #:action tray-quit!))
               #:on-event (lambda (_) (focus-window!))))
  (set-box! tray-box tray)
  (define-values (_kind stop)
    (run-app
     #:public-dir (assemble-public-dir)
     #:api api
     #:events host-bus
     #:on-ready (lambda (wv _) (set-box! window-box wv))
     #:transport transport
     #:api-token (or (getenv "GLAZE_API_TOKEN") #t)
     #:title "RelayPilot"
     #:width 1200
     #:height 800
     #:current-version app-version
     #:capability host-capability
     #:app-id "relaypilot"))
  (stop-engine!)
  (stop))
