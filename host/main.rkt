#lang racket/base

;; RelayPilot glaze carrier (#13 S0) — carrier skeleton.
;;
;; Owner decision 2026-11-23 (relaypilot#13): the desktop UI moves from the
;; rivet native line to glaze. This module is the single web UI's host
;; adapter. S0 ships only the carrier: the glaze app shell, the HTTP/native
;; transport, the runtime public dir (token sheet served single-source from
;; design/prototype/shared.css) and the i18n single source (shared/i18n).
;; The typed RPC surface over rivet/bridge lands in S1; product screens in
;; S2–S4. The Racket control plane (racket/), rivet-schema.json and the CLI
;; are untouched by this slice.
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
         (prefix-in core: "../racket/core/version.rkt"))

;; The route list schema tooling reads (glaze.rktd points here). Schema
;; checks load this module without starting anything.
(provide api assemble-public-dir app-version)

(define-runtime-path probe-dir "web")

(define app-version core:app-version)

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

  ;; ---- acceptance harness gate (#13 S0) ---------------------------------
  ;; The probe page carries an in-page journey harness (?e2e=1) because
  ;; glaze exposes no JS injection into the webview. These routes are inert
  ;; unless RELAYPILOT_E2E=1 (verify.rkt / CI only).
  [(POST "api/host/e2e" #:returns GValue)
   (e2e)
   (hasheq 'enabled (e2e-enabled?))]
  [(POST "api/host/e2e_report" #:returns GBool)
   (e2eReport [payload GValue])
   (host-e2e-report! payload)
   #t]
  [(POST "api/host/e2e_report_get" #:returns GValue)
   (e2eReportGet)
   (or (unbox e2e-report-box) (hasheq 'phase "waiting"))]
  [(POST "api/host/e2e_reset" #:returns GBool)
   (e2eReset)
   (when (e2e-enabled?) (set-box! e2e-report-box #f))
   #t])

(define api api-host)

(define-runtime-path i18n-zh-path "../shared/i18n/zh.json")
(define-runtime-path i18n-en-path "../shared/i18n/en.json")

;; ---- harness gate state ---------------------------------------------------
(define (e2e-enabled?) (equal? (getenv "RELAYPILOT_E2E") "1"))
(define e2e-report-box (box #f))

(define (host-e2e-report! payload)
  (when (e2e-enabled?) (set-box! e2e-report-box payload))
  (void))

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

(module+ main
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
  (stop))
