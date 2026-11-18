#lang racket/base

(require rackunit
         rivet/backend
         rivet/protocol
         "../racket/backend.rkt"
         "support.rkt")

(define-values (server-in client-out) (make-pipe))
(define-values (client-in server-out) (make-pipe))
(define server-thread (thread (lambda () (serve server-in server-out))))

(define hello (read-frame client-in))
(check-equal? (frame-type hello) message:hello)

(define next-id 1)
(define (call name . arguments)
  (define id next-id)
  (set! next-id (add1 next-id))
  (write-frame (frame message:request id (encode-value (cons name arguments))) client-out)
  (let loop ()
    (define response (read-frame client-in))
    (cond
      [(= (frame-type response) message:event) (loop)]
      [(not (= (frame-id response) id)) (error 'call "unexpected response id")]
      [(= (frame-type response) message:error)
       (error 'call "~a" (decode-value (frame-payload response)))]
      [else (decode-value (frame-payload response))])))

(define decision (call "explain-route" sample-profile-json "api.openai.com" "" 443 "tcp"))
(check-equal? (list-ref decision 1) 1)
(check-equal? (list-ref decision 2) "AI")
(check-equal? (list-ref decision 3) "us-reality-01")

(define compiled (call "compile-engine-config" sample-profile-json))
(check-equal? (list-ref compiled 0) "xray")
(check-equal? (string-length (list-ref compiled 2)) 64)
(check-regexp-match #rx"\"ruleTag\":\"relaypilot:1\"" (list-ref compiled 3))

;; Engine RPCs need the pinned binary; they are exercised when one is
;; configured and skipped with the reason otherwise.
(define engine-binary
  (let ([from-env (getenv "RELAYPILOT_XRAY_BIN")])
    (and from-env (not (string=? from-env "")) (file-exists? from-env) from-env)))

;; ---- library + diagnostics RPCs ---------------------------------------------------
;; Library state lives in a per-test temp root passed on every call.

(require racket/file
         racket/list)

(define library-root (make-temporary-file "relaypilot-wire-~a" 'directory))

(define (check-exn-rpc name thunk message-pattern)
  (check-exn exn:fail?
             (lambda ()
               (with-handlers ([exn:fail? (lambda (exn)
                                            (unless (regexp-match? message-pattern
                                                                   (exn-message exn))
                                              (error 'check-exn-rpc
                                                     "unexpected message: ~a"
                                                     (exn-message exn)))
                                            (raise exn))])
                 (thunk)))
             name))

(dynamic-wind void
              (lambda ()
                (define empty-snapshot (call "library-list" (path->string library-root)))
                (check-equal? (list-ref empty-snapshot 0) "")

                (define created
                  (call "library-import-commit"
                        (path->string library-root)
                        "Wire Import"
                        "wire description"
                        "[Rule]\nDOMAIN-SUFFIX, lab.internal, DIRECT\nFINAL, DIRECT\n"))
                (define profile-id (list-ref created 0))
                (check-true (file-exists?
                             (build-path library-root
                                         (string-append profile-id ".relayprofile.json"))))

                (define snapshot (call "library-list" (path->string library-root)))
                (check-equal? (list-ref snapshot 0) profile-id)
                (define entry (car (list-ref snapshot 1)))
                (check-equal? (list-ref entry 0) profile-id)
                (check-equal? (list-ref entry 1) "Wire Import")
                (check-equal? (list-ref entry 3) 2)
                (check-equal? (list-ref entry 4) "valid")
                (check-equal? (list-ref entry 5) '())
                (check-equal? (list-ref entry 6) (list "DIRECT" "REJECT"))

                (define profile-json
                  (call "library-read-profile" (path->string library-root) profile-id))
                (check-regexp-match #rx"Wire Import" profile-json)

                (define decision (call "explain-route" profile-json "nas.lab.internal" "" 443 "tcp"))
                (check-equal? (list-ref decision 2) "DIRECT")

                (define preview
                  (call "library-import-preview"
                        (path->string library-root)
                        "Wire Import"
                        "[Rule]\nDOMAIN-SUFFIX, x.example, DIRECT\nFINAL, DIRECT\n"))
                (check-equal? (list-ref preview 5) #f "duplicate name is unavailable")
                (check-equal? (length (list-ref preview 0)) 2)

                (define preview2
                  (call "library-patch-preview"
                        (path->string library-root)
                        profile-id
                        "nas.lab.internal"
                        "REJECT"))
                (check-equal? (list-ref preview2 1) "DIRECT")
                (check-equal? (list-ref preview2 3) "REJECT")

                (define outcome
                  (call "library-patch-apply"
                        (path->string library-root)
                        profile-id
                        "nas.lab.internal"
                        "REJECT"))
                (check-equal? (list-ref outcome 0) 1)
                (check-equal? (car (list-ref outcome 1)) "DOMAIN,nas.lab.internal,REJECT")

                ;; Single-step undo: the pre-patch canonical bytes restore.
                (define before-patch
                  (call "library-read-profile" (path->string library-root) profile-id))
                (call "library-patch-apply"
                      (path->string library-root) profile-id "nas.lab.internal" "REJECT")
                (define restored
                  (call "library-restore-profile" (path->string library-root) before-patch))
                (check-equal? (list-ref restored 0) profile-id)
                (define after-restore
                  (call "library-read-profile" (path->string library-root) profile-id))
                (check-equal? after-restore before-patch)
                (check-exn-rpc
                 "restore refuses non-profile bytes"
                 (lambda ()
                   (call "library-restore-profile" (path->string library-root) "{not json"))
                 #rx"does not parse")

                (define diagnosis
                  (call "diagnose-route" profile-json "nas.lab.internal" "" 443 "tcp" #t))
                (check-regexp-match #rx"\"traceId\":\"\\[redacted\\]\"" diagnosis)
                (check-false (regexp-match #rx"nas\\.lab\\.internal" diagnosis)
                             "redacted exports drop the target domain")
                (check-false (regexp-match #rx"lab\\.internal" diagnosis)
                             "redacted exports drop rule targets")
                (define plain
                  (call "diagnose-route" profile-json "nas.lab.internal" "" 443 "tcp" #f))
                (check-regexp-match #rx"nas\\.lab\\.internal" plain)
                (check-false (regexp-match #rx"\\[REDACTED\\]" plain))

                (check-exn-rpc
                 "unknown profile reads are refused"
                 (lambda ()
                   (call "library-read-profile" (path->string library-root) "missing"))
                 #rx"not found")
                (check-exn-rpc
                 "active profiles cannot be deleted"
                 (lambda ()
                   (call "library-delete-profile" (path->string library-root) profile-id))
                 #rx"active"))
              (lambda () (delete-directory/files library-root)))

(when engine-binary
  (define loopback-json
    "{\"schemaVersion\":1,\"id\":\"loopback\",\"name\":\"Loopback\",\"nodes\":[],\"policies\":[],\"rules\":[\"FINAL,DIRECT\"],\"dns\":{}}")
  (define dry-run (call "engine-dry-run" sample-profile-json 1080))
  (check-equal? (list-ref dry-run 0) "xray")
  (check-equal? (list-ref dry-run 3) #t)
  (check-equal? (list-ref dry-run 4) #t)
  (check-regexp-match #rx"^26[.]" (list-ref dry-run 5))

  (define handle (call "engine-session-start" loopback-json 0))
  (check-regexp-match #rx"^xray-" (list-ref handle 0))
  (check-true (exact-positive-integer? (list-ref handle 1)))
  (check-regexp-match #rx"^26[.]" (list-ref handle 2))
  (define events (call "engine-session-events" (list-ref handle 0)))
  (check-true (list? events))
  (define stopped (call "engine-session-stop" (list-ref handle 0)))
  (check-equal? (list-ref stopped 0) #t)
  (check-equal? (list-ref stopped 1) "0")
  (check-true (positive? (length (list-ref stopped 2))))
  (define unknown (call "engine-session-stop" "xray-nope"))
  (check-equal? (list-ref unknown 0) #f))

(write-frame (frame message:shutdown 0 #"") client-out)
(thread-wait server-thread)
