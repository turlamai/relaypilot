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
;; the user could mistype). Trace lands in S3, settings/tray in S4.
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
         glaze/types      ; GString, GInt64, GBool, GValue
         racket/file
         racket/runtime-path
         json
         (prefix-in engine: "../racket/backend.rkt")
         (prefix-in core: "../racket/core/version.rkt")
         rivet/bridge)

;; The route list schema tooling reads (glaze.rktd points here).
;; start-engine! wires the codec to the in-process RVT1 transport — the
;; app entry and the real-window verifier both call it; schema checks load
;; this module without starting anything.
(provide api start-engine! stop-engine! assemble-public-dir app-version)

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

(define api (append api-rpc api-host))

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
  (define-values (_kind stop)
    (run-app
     #:public-dir (assemble-public-dir)
     #:api api
     #:transport transport
     #:api-token (or (getenv "GLAZE_API_TOKEN") #t)
     #:title "RelayPilot"
     #:width 1200
     #:height 800
     #:current-version app-version
     #:app-id "relaypilot"))
  (stop-engine!)
  (stop))
