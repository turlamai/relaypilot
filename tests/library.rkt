#lang racket/base

(require rackunit
         racket/file
         racket/list
         racket/string
         "../racket/core/errors.rkt"
         "../racket/core/library.rkt"
         "../racket/core/model.rkt"
         "../racket/core/profile/json.rkt"
         "support.rkt")

;; ---- validation report -----------------------------------------------------------

(check-equal? (profile-validation-issues sample-profile) '())
(check-not-exn (lambda () (validate-profile sample-profile)))

(define (first-issue-code profile)
  (hash-ref (car (profile-validation-issues profile)) 'code))

;; A rule referencing an unknown policy must report and must also be rejected
;; by validate-profile — the mirror stays locked to the canonical validator.
(define unknown-policy-profile
  (relay-profile 1
                 "unknown-policy"
                 "Unknown Policy"
                 '()
                 '()
                 (list (relay-rule 1 'domain "example.com" "Ghost" '() "test")
                       (relay-rule 2 'match "" "DIRECT" '() "test"))
                 (hasheq)))
(check-equal? (first-issue-code unknown-policy-profile) "unknown-rule-policy")
(check-exn exn:fail?
           (lambda () (validate-profile unknown-policy-profile)))

(define missing-final-profile
  (relay-profile 1 "no-final" "No Final" '() '()
                 (list (relay-rule 1 'domain-suffix "example.com" "DIRECT" '() "test"))
                 (hasheq)))
(check-equal? (first-issue-code missing-final-profile) "no-final")

(define bad-domain-profile
  (relay-profile 1 "bad-domain" "Bad Domain" '() '()
                 (list (relay-rule 1 'domain "not a domain" "DIRECT" '() "test")
                       (relay-rule 2 'match "" "DIRECT" '() "test"))
                 (hasheq)))
(check-equal? (first-issue-code bad-domain-profile) "invalid-domain")

(check-true (valid-hostname? "nas.lab.internal"))
(check-true (valid-hostname? "localhost"))
(check-false (valid-hostname? "-leading-hyphen.example.com"))
(check-false (valid-hostname? "trailing-.example.com"))
(check-false (valid-hostname? "with space.example.com"))

;; ---- import preview ---------------------------------------------------------------

(define import-sample
  (string-append
   "[Proxy]\n"
   "lab-a = http, 127.0.0.1, 7890\n"
   "\n"
   "[Proxy Group]\n"
   "policy-main = select, lab-a\n"
   "\n"
   "[Rule]\n"
   "# a comment stays out of the report\n"
   "DOMAIN-SUFFIX, lab.internal, DIRECT\n"
   "DOMAIN, GitHub.com, direct\n"
   "IP-CIDR, 10.0.0.0/8, DIRECT, no-resolve\n"
   "DOMAIN-KEYWORD, ads, REJECT\n"
   "DOMAIN-SUFFIX, github.com, policy-main\n"
   "FINAL, policy-main\n"
   "DOMAIN-SUFFIX, unreachable.example, DIRECT\n"
   "\n"
   "[General]\n"
   "external-policy = example-policy\n"))

(define preview (surge-import-preview import-sample))

;; Rules keep their semantics: the unavailable policy-main becomes a
;; placeholder select group (stated in warnings), not a silent rewrite.
(check-equal? (hash-ref preview 'rules)
              (list "DOMAIN-SUFFIX,lab.internal,DIRECT"
                    "DOMAIN,github.com,DIRECT"
                    "DOMAIN-SUFFIX,github.com,policy-main"
                    "FINAL,policy-main"))
(check-equal? (hash-ref preview 'groups) (list "policy-main"))
(check-true (hash-ref preview 'hasFinal))
(check-equal? (length (hash-ref preview 'warnings)) 1)

(define preview-codes
  (map (lambda (row) (hash-ref row 'code)) (hash-ref preview 'unsupported)))
(check-not-false (member "unsupported-section-entry" preview-codes) "proxy and group lines report")
(check-not-false (member "unsupported-options" preview-codes) "no-resolve reports")
(check-not-false (member "unsupported-rule" preview-codes) "DOMAIN-KEYWORD reports")
(check-not-false (member "after-final" preview-codes) "post-FINAL line reports")
(check-not-false (member "unsupported-section" preview-codes) "[General] reports")

(define finalless-import
  (surge-import-preview
   "[Rule]\nDOMAIN-SUFFIX, lab.internal, policy-main\n"))
(check-false (hash-ref finalless-import 'hasFinal))
(check-not-false (ormap (lambda (warning)
                                (string-contains? warning "FINAL"))
                              (hash-ref finalless-import 'warnings)))
(check-not-false (ormap (lambda (warning)
                                (string-contains? warning "placeholder"))
                              (hash-ref finalless-import 'warnings)))

;; ---- snapshot + mutations ----------------------------------------------------------

(define root (make-temporary-file "relaypilot-library-~a" 'directory))

(define (issue-codes issues)
  (map (lambda (entry) (hash-ref entry 'code)) issues))

(dynamic-wind void
              (lambda ()
                ;; An empty library has no active profile and no entries.
                (define empty-snapshot (library-snapshot root))
                (check-equal? (hash-ref empty-snapshot 'activeProfileId) "")
                (check-equal? (hash-ref empty-snapshot 'profiles) '())

                (define created
                  (library-import-commit!
                   root "Imported Lab" "导入的示例"
                   "[Rule]\nDOMAIN-SUFFIX, lab.internal, DIRECT\nFINAL, DIRECT\n"))
                (define created-id (hash-ref created 'profileId))
                (check-equal? (hash-ref created 'ruleCount) 2)
                (check-true (file-exists? (profile-file-path root created-id)))

                ;; Duplicate names are refused before any write happens.
                (check-exn relaypilot-error?
                           (lambda ()
                             (library-import-commit!
                              root "Imported Lab" ""
                              "[Rule]\nFINAL, DIRECT\n")))

                (define snapshot (library-snapshot root))
                (check-equal? (hash-ref snapshot 'activeProfileId) created-id)
                (define entry (car (hash-ref snapshot 'profiles)))
                (check-equal? (hash-ref entry 'status) "valid")
                (check-equal? (hash-ref entry 'description) "导入的示例")
                (check-equal? (hash-ref entry 'targets) (list "DIRECT" "REJECT"))

                ;; The active profile cannot be deleted.
                (check-exn relaypilot-error?
                           (lambda () (library-delete-profile! root created-id)))

                ;; Rule editor round trip.
                (library-update-rules! root created-id "DOMAIN, lab.internal, DIRECT\nFINAL, DIRECT")
                (define updated (library-snapshot root))
                (check-equal? (hash-ref (car (hash-ref updated 'profiles)) 'ruleCount) 2)

                ;; Unknown policies are rejected with the canonical error kind.
                (check-exn relaypilot-error?
                           (lambda ()
                             (library-update-rules! root created-id "DOMAIN, lab.internal, Ghost")))

                ;; Route patch: preview reports the change, apply writes it.
                (define preview-result
                  (library-patch-preview root created-id "NAS.Lab.internal" "REJECT"))
                (check-equal? (hash-ref preview-result 'currentPolicy) "DIRECT")
                (check-equal? (hash-ref preview-result 'nextPolicy) "REJECT")
                (check-equal? (hash-ref preview-result 'ruleText) "DOMAIN,nas.lab.internal,REJECT")
                (check-false (hash-ref preview-result 'sameAsCurrent))

                (define outcome (library-patch-apply! root created-id "nas.lab.internal" "REJECT"))
                (check-equal? (hash-ref outcome 'ruleIndex) 1)
                (check-equal? (car (hash-ref outcome 'rules)) "DOMAIN,nas.lab.internal,REJECT")

                ;; Re-applying the same target and policy is a no-op.
                (define settled (library-patch-preview root created-id "nas.lab.internal" "REJECT"))
                (check-true (hash-ref settled 'sameAsCurrent))

                ;; A second patch replaces the existing exact-DOMAIN rule's
                ;; policy without touching the other rules.
                (library-patch-apply! root created-id "nas.lab.internal" "DIRECT")
                (define replaced-profile
                  (read-relay-profile (profile-file-path root created-id)))
                (check-equal? (length (relay-profile-rules replaced-profile)) 3)
                (check-equal? (rule->string (car (relay-profile-rules replaced-profile)))
                              "DOMAIN,nas.lab.internal,DIRECT")

                ;; Invalid targets and policies are refused.
                (check-exn relaypilot-error?
                           (lambda () (library-patch-apply! root created-id "not a domain" "DIRECT")))
                (check-exn relaypilot-error?
                           (lambda () (library-patch-apply! root created-id "nas.lab.internal" "Ghost")))

                ;; A second profile can become active, then be deleted again.
                (define second
                  (library-import-commit! root "Second" "" "[Rule]\nFINAL, DIRECT\n"))
                (define second-id (hash-ref second 'profileId))
                (library-set-active! root second-id)
                (check-equal? (hash-ref (library-snapshot root) 'activeProfileId) second-id)
                (library-delete-profile! root created-id)
                (check-false (file-exists? (profile-file-path root created-id)))
                (check-equal? (hash-ref (library-snapshot root) 'activeProfileId) second-id)

                ;; Unusable profile files surface as invalid entries.
                (call-with-output-file
                 (profile-file-path root "broken")
                 (lambda (out) (display "{not json" out)))
                (define with-broken (library-snapshot root))
                (define broken-entry
                  (findf (lambda (candidate)
                           (string=? (hash-ref candidate 'id) "broken"))
                         (hash-ref with-broken 'profiles)))
                (check-equal? (hash-ref broken-entry 'status) "invalid")
                (check-true (pair? (hash-ref broken-entry 'issues))))
              (lambda () (delete-directory/files root)))

;; ---- wire surface ------------------------------------------------------------------

;; The backend RPC shape is covered by tests/backend.rkt; this module locks
;; the core semantics those RPCs expose.
(check-true (procedure? surge-import-preview))
(check-true (procedure? library-snapshot))
