#lang racket/base
;; Real-window evidence for the glaze carrier (#13 S0–S2): boot the host with
;; the in-process RVT1 engine bridge, open probe.html?e2e=1 (RPC surface
;; journey) then index.html?e2e=1 (product journey), poll the typed report
;; route until each terminates, capture PNGs, assert verdicts. Runs on every
;; declared platform (Xvfb on Linux CI).
;; Run: racket host/verify.rkt
(require glaze/app
         glaze/window
         json
         net/http-client
         net/url
         racket/file
         racket/list
         racket/port
         racket/runtime-path
         racket/string
         "main.rkt")

(define-runtime-path evidence-dir "../.glaze/verify")

;; Surface glaze hatch/readback log lines in headless CI evidence.
(void
 (thread
  (lambda ()
    (define rcv (make-log-receiver (current-logger) 'info))
    (let loop ()
      (define v (sync rcv))
      (eprintf "[glaze-log] ~a: ~a\n" (vector-ref v 0) (vector-ref v 1))
      (loop)))))

(define verdicts '())
(define report-box (box #f))
(define product-box (box #f))
(define tray-box (box #f))

(define (api-post url path body)
  (define u (string->url url))
  (define-values (status headers port)
    (http-sendrecv (url-host u) path
                   #:port (url-port u)
                   #:method #"POST"
                   #:headers (list #"Content-Type: application/json")
                   #:data (string->bytes/utf-8 (jsexpr->string body))))
  (define text (port->string port))
  (close-input-port port)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (string->jsexpr text)))

(define (api-get url path)
  (define u (string->url url))
  (define-values (status headers port)
    (http-sendrecv (url-host u) path #:port (url-port u) #:method #"GET"))
  (define text (port->string port))
  (close-input-port port)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (string->jsexpr text)))

(define (save-shot! shot name)
  (cond
    [(and shot (file-exists? shot))
     (make-directory* evidence-dir)
     (define dest (build-path evidence-dir name))
     (copy-file shot dest #:exists-ok? #t)
     dest]
    [else #f]))

(putenv "RELAYPILOT_E2E" "1")
(start-engine!)

(define (await-report url deadline-ms)
  (define deadline (+ (current-inexact-milliseconds) deadline-ms))
  (let loop ()
    (define r (api-post url "/api/host/e2e_report_get" (hasheq)))
    (cond
      [(and (hash? r) (equal? (hash-ref r 'phase #f) "done")) r]
      [(>= (current-inexact-milliseconds) deadline) (or r (hasheq 'phase "timeout"))]
      [else (sleep 0.5) (loop)])))

;; Load a page and wait for the product title, so the harness gate (read at
;; load) is in effect before the report is polled.
(define (load-page! wv url page)
  (webview-navigate wv (string-append url page))
  (define deadline (+ (current-inexact-milliseconds) 45000))
  (let loop ()
    (cond
      [(and (string? (webview-title wv))
            (string-prefix? (webview-title wv) "RelayPilot")) #t]
      [(>= (current-inexact-milliseconds) deadline) #f]
      [else (sleep 0.1) (loop)]))
  (sleep 1.0)
  #t)

(define-values (_kind stop)
  (run-app
   #:public-dir (assemble-public-dir)
   #:api api
   #:events host-bus
   #:transport 'http
   #:api-token #f
   #:title "RelayPilot"
   #:width 1200
   #:height 800
   #:current-version app-version
   #:on-ready
   (lambda (wv url)
     ;; On Windows the webview reports about:blank until the first navigation
     ;; completes, so the url is asserted after the initial load.
     (define loaded? (load-page! wv url "index.html"))
     (define url-ok? (and (string? (webview-url wv)) (string-prefix? (webview-url wv) url)))
     (define boot-shot (save-shot! (webview-capture! wv) "relaypilot-host-boot.png"))

     ;; ---- S1 RPC surface journey (probe page) ----
     (define report (begin (load-page! wv url "probe.html?e2e=1") (await-report url 180000)))
     (set-box! report-box report)
     (define e2e-shot (save-shot! (webview-capture! wv) "relaypilot-host-e2e.png"))

     ;; ---- S2 product journey (real UI) ----
     (api-post url "/api/host/e2e_reset" (hasheq))
     (define product (begin (load-page! wv url "index.html?e2e=1") (await-report url 240000)))
     (set-box! product-box product)
     (define product-shot (save-shot! (webview-capture! wv) "relaypilot-product-e2e.png"))

     ;; ---- S4 carrier route: a tray menu pick made outside the page ----
     ;; The host holds the menu the page last posted; invoking an item here
     ;; exercises the real action (broadcast → SSE → the page's action path).
     (define tray-before (api-get url "/api/host/e2e_tray"))
     (set-box! tray-box tray-before)
     (define (tray-view)
       (api-post url "/api/host/e2e_tray_invoke" (hasheq 'id "go:trace"))
       (let/ec return
         (define deadline (+ (current-inexact-milliseconds) 20000))
         (let loop ()
           (define r (api-get url "/api/host/e2e_tray"))
           (cond
             [(and (hash? r) (equal? (hash-ref r 'view #f) "trace")) (return r)]
             [(>= (current-inexact-milliseconds) deadline) (return r)]
             [else (sleep 0.2) (loop)]))))
     (define tray-invoked (equal? (hash-ref (tray-view) 'view #f) "trace"))
     (api-post url "/api/host/e2e_tray_invoke" (hasheq 'id "go:settings"))
     (sleep 1.5)
     (define settings-shot (save-shot! (webview-capture! wv) "relaypilot-product-settings.png"))

     (define (step-ok? rep id)
       (define s (hash-ref (hash-ref rep 'steps (hasheq)) (string->symbol id) #f))
       (and (hash? s) (eq? #t (hash-ref s 'ok #f))))
     (define (report-ok? rep n)
       (list (cons 'report-done (equal? (hash-ref rep 'phase #f) "done"))
             (cons 'journey-ok (eq? #t (hash-ref rep 'ok #f)))
             (cons 'step-count (= n (hash-ref rep 'stepCount 0)))))
     (set! verdicts
           (append
            (list (cons 'page-loaded (or loaded? (and url-ok? boot-shot)))
                  (cons 'url url-ok?)
                  (cons 'boot-capture (and boot-shot (> (file-size boot-shot) 0))))
            (report-ok? report 10)
            (list (cons 'health (step-ok? report "health"))
                  (cons 'i18n (step-ok? report "i18n"))
                  (cons 'token-sheet (step-ok? report "token-sheet"))
                  (cons 'rpc-explain-route (step-ok? report "explain-route"))
                  (cons 'rpc-diagnose-route (step-ok? report "diagnose-route"))
                  (cons 'rpc-compile-engine-config (step-ok? report "compile-engine-config"))
                  (cons 'rpc-engine-dry-run (step-ok? report "engine-dry-run"))
                  (cons 'rpc-engine-session (step-ok? report "engine-session"))
                  (cons 'rpc-library-flow (step-ok? report "library-flow"))
                  (cons 'rpc-error-channel (step-ok? report "error-channel"))
                  (cons 'e2e-capture (and e2e-shot (> (file-size e2e-shot) 0))))
            (report-ok? product 16)
            (list (cons 'ui-boot (step-ok? product "boot"))
                  (cons 'ui-settings (step-ok? product "settings"))
                  (cons 'ui-tray-menu (step-ok? product "tray"))
                  (cons 'tray-menu
                        (let* ([ids (map (lambda (i) (hash-ref i 'id #f))
                                         (hash-ref tray-before 'menu '()))]
                               [active-item (findf (lambda (i) (string-prefix? (format "~a" (hash-ref i 'id "")) "profile:"))
                                                   (hash-ref tray-before 'menu '()))])
                          (and (member "show" ids) (member "quick-find" ids)
                               (member "go:trace" ids) (member "quit" ids)
                               active-item (eq? #t (hash-ref active-item 'checked #f)))))
                  (cons 'tray-route (and tray-invoked #t))
                  (cons 'settings-capture (and settings-shot (> (file-size settings-shot) 0)))
                  (cons 'ui-import (step-ok? product "import"))
                  (cons 'ui-import-rejected (step-ok? product "import-rejected"))
                  (cons 'ui-saved-target (step-ok? product "saved-target"))
                  (cons 'ui-route-patch (step-ok? product "route-patch"))
                  (cons 'ui-undo (step-ok? product "undo"))
                  (cons 'ui-trace (step-ok? product "trace"))
                  (cons 'ui-export (step-ok? product "export"))
                  (cons 'ui-editor (step-ok? product "editor"))
                  (cons 'ui-editor-rejected (step-ok? product "editor-rejected"))
                  (cons 'ui-switch (step-ok? product "switch"))
                  (cons 'ui-delete (step-ok? product "delete"))
                  (cons 'ui-session (step-ok? product "session"))
                  (cons 'ui-i18n (step-ok? product "i18n"))
                  (cons 'product-capture (and product-shot (> (file-size product-shot) 0))))))
     (webview-close wv))))

(stop)
(stop-engine!)
(make-directory* evidence-dir)
(call-with-output-file (build-path evidence-dir "relaypilot-host-report.json")
  (lambda (out)
    (write-json (hasheq 'carrier (or (unbox report-box) (hasheq))
                        'product (or (unbox product-box) (hasheq))
                        'tray (or (unbox tray-box) (hasheq)))
                out)
    (newline out))
  #:exists 'truncate/replace)
(for ([v (in-list verdicts)])
  (printf "[verify] ~a = ~a\n" (car v) (cdr v)))
(printf "[verify] carrier report: ~a\n" (jsexpr->string (or (unbox report-box) (hasheq))))
(printf "[verify] product report: ~a\n" (jsexpr->string (or (unbox product-box) (hasheq))))
(unless (and (pair? verdicts) (andmap cdr verdicts))
  (eprintf "[verify] glaze carrier verification failed\n")
  (exit 1))
(displayln "[verify] ALL PASS")
