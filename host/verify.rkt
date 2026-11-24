#lang racket/base
;; Real-window launch smoke for the glaze carrier (#13 S0/S1): boot the host
;; with the in-process RVT1 engine bridge, open index.html?e2e=1, poll the
;; typed report route until the journey terminates, capture PNGs, assert
;; verdicts. Runs on every declared platform (Xvfb on Linux CI).
;; Run: racket host/verify.rkt
(require glaze/app
         glaze/window
         json
         net/http-client
         net/url
         racket/file
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

(define-values (_kind stop)
  (run-app
   #:public-dir (assemble-public-dir)
   #:api api
   #:transport 'http
   #:api-token #f
   #:title "RelayPilot carrier probe"
   #:width 1100
   #:height 800
   #:current-version app-version
   #:on-ready
   (lambda (wv url)
     (define deadline (+ (current-inexact-milliseconds) 45000))
     (define loaded?
       (let loop ()
         (cond
           [(and (string? (webview-title wv))
                 (string-prefix? (webview-title wv) "RelayPilot")) #t]
           [(>= (current-inexact-milliseconds) deadline) #f]
           [else (sleep 0.1) (loop)])))
     (sleep 1.0)
     (define url-ok? (equal? (webview-url wv) url))
     (define boot-shot (save-shot! (webview-capture! wv) "relaypilot-host-boot.png"))
     ;; A fragment-only navigate would not reload the document (the harness
     ;; gate is read at load); the query param forces a full load.
     (webview-navigate wv (string-append url "index.html?e2e=1"))
     (define report (await-report url 120000))
     (set-box! report-box report)
     (define e2e-shot (save-shot! (webview-capture! wv) "relaypilot-host-e2e.png"))
     (define steps (hash-ref report 'steps (hasheq)))
     (define (step-ok? id)
       (define s (hash-ref steps (string->symbol id) #f))
       (and (hash? s) (eq? #t (hash-ref s 'ok #f))))
     (set! verdicts
           (list (cons 'page-loaded (or loaded? (and url-ok? boot-shot)))
                 (cons 'url url-ok?)
                 (cons 'boot-capture (and boot-shot (> (file-size boot-shot) 0)))
                 (cons 'report-done (equal? (hash-ref report 'phase #f) "done"))
                 (cons 'journey-ok (eq? #t (hash-ref report 'ok #f)))
                 (cons 'step-count (= 10 (hash-ref report 'stepCount 0)))
                 (cons 'health (step-ok? "health"))
                 (cons 'i18n (step-ok? "i18n"))
                 (cons 'token-sheet (step-ok? "token-sheet"))
                 (cons 'rpc-explain-route (step-ok? "explain-route"))
                 (cons 'rpc-diagnose-route (step-ok? "diagnose-route"))
                 (cons 'rpc-compile-engine-config (step-ok? "compile-engine-config"))
                 (cons 'rpc-engine-dry-run (step-ok? "engine-dry-run"))
                 (cons 'rpc-engine-session (step-ok? "engine-session"))
                 (cons 'rpc-library-flow (step-ok? "library-flow"))
                 (cons 'rpc-error-channel (step-ok? "error-channel"))
                 (cons 'e2e-capture (and e2e-shot (> (file-size e2e-shot) 0)))))
     (webview-close wv))))

(stop)
(stop-engine!)
(make-directory* evidence-dir)
(call-with-output-file (build-path evidence-dir "relaypilot-host-report.json")
  (lambda (out)
    (write-json (hasheq 'carrier (or (unbox report-box) (hasheq))) out)
    (newline out))
  #:exists 'truncate/replace)
(for ([v (in-list verdicts)])
  (printf "[verify] ~a = ~a\n" (car v) (cdr v)))
(printf "[verify] carrier report: ~a\n" (jsexpr->string (or (unbox report-box) (hasheq))))
(unless (and (pair? verdicts) (andmap cdr verdicts))
  (eprintf "[verify] glaze carrier verification failed\n")
  (exit 1))
(displayln "[verify] ALL PASS")
