#lang racket/base

;; Profile library semantics for native hosts: canonical profile files under a
;; user-owned root, a small library-state.json for active/description facts,
;; non-raising validation reports, per-line Surge import previews, and route
;; patches. Hosts reach all of it through backend RPCs; the CLI keeps its own
;; file-based paths.

(require json
         racket/file
         racket/list
         racket/path
         racket/string
         "decision.rkt"
         "errors.rkt"
         "json.rkt"
         "model.rkt"
         "profile/json.rkt"
         "rules/surge.rkt")

(provide library-state-path
         profile-file-path
         read-library-state
         write-library-state!
         profile-load-report
         profile-validation-issues
         profile-targets
         surge-import-preview
         library-snapshot
         library-import-commit!
         library-update-rules!
         library-delete-profile!
         library-set-active!
         library-patch-preview
         library-patch-apply!
         require-profile
         require-valid-profile
         profile-name-taken?
         valid-hostname?)

;; ---- issue reports -------------------------------------------------------------
;; Issues are structured so hosts can localize presentation. `index` is the
;; 1-based rule line when the issue names a rule, 0 when it does not.

(define (issue index code detail)
  (hasheq 'index index 'code code 'detail detail))

(define (valid-hostname? value)
  (and (string? value)
       (<= 1 (string-length value) 253)
       (let ([labels (string-split value "." #:trim? #f)])
         (and (pair? labels)
              (for/and ([label (in-list labels)])
                (and (<= 1 (string-length label) 63)
                     (regexp-match? #px"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$"
                                    (string-downcase label))))))))

(define (duplicated-values items)
  (for/fold ([seen '()]
             [dupes '()]
             #:result (reverse dupes))
            ([value (in-list items)])
    (if (member value seen)
        (values seen
                (if (member value dupes)
                    dupes
                    (cons value dupes)))
        (values (cons value seen) dupes))))

(define (non-empty-string? value)
  (and (string? value) (positive? (string-length value))))

;; Structural mirror of validate-profile plus the reachability facts hosts
;; need (FINAL presence/position, domain formats, adapter-ignored options).
;; tests/library.rkt locks the mirror to validate-profile: any profile with
;; zero issues must pass validate-profile, and any profile validate-profile
;; rejects must report at least one issue.
(define (profile-validation-issues profile)
  (define issues '())
  (define (add! index code detail)
    (set! issues (cons (issue index code detail) issues)))
  (unless (= (relay-profile-schema-version profile) 1)
    (add! 0 "schema-version" "unsupported Relay Profile schema version"))
  (unless (non-empty-string? (relay-profile-id profile))
    (add! 0 "profile-id" "profile id must not be empty"))
  (define node-ids (map proxy-node-id (relay-profile-nodes profile)))
  (define policy-ids (map policy-group-id (relay-profile-policies profile)))
  (for ([node (in-list (relay-profile-nodes profile))]
        [node-id (in-list node-ids)]
        #:unless (and (non-empty-string? node-id)
                      (non-empty-string? (proxy-node-address node))
                      (exact-integer? (proxy-node-port node))
                      (<= 1 (proxy-node-port node) 65535)))
    (add! 0 "invalid-node" (format "invalid proxy node: ~a" node-id)))
  (for ([id (in-list (duplicated-values node-ids))])
    (add! 0 "duplicate-node-id" (format "duplicate node id: ~a" id)))
  (for ([id (in-list (duplicated-values policy-ids))])
    (add! 0 "duplicate-policy-id" (format "duplicate policy id: ~a" id)))
  (define known-targets (append node-ids policy-ids '("DIRECT" "REJECT")))
  (for ([group (in-list (relay-profile-policies profile))])
    (unless (memq (policy-group-kind group) '(select fallback))
      (add! 0 "unsupported-policy-kind"
            (format "policy group ~a has unsupported kind" (policy-group-id group))))
    (when (null? (policy-group-members group))
      (add! 0 "empty-policy-group"
            (format "policy group ~a must have members" (policy-group-id group))))
    (for ([member-id (in-list (policy-group-members group))]
          #:unless (member member-id known-targets))
      (add! 0 "unknown-policy-member"
            (format "policy group ~a references unknown member ~a"
                    (policy-group-id group)
                    member-id)))
    (when (and (policy-group-selected group)
               (not (member (policy-group-selected group) (policy-group-members group))))
      (add! 0 "invalid-selected-member"
            (format "policy group ~a selected member is not in the group"
                    (policy-group-id group)))))
  (for ([rule (in-list (relay-profile-rules profile))])
    (define line (relay-rule-index rule))
    (unless (member (relay-rule-policy rule) known-targets)
      (add! line "unknown-rule-policy"
            (format "rule references unknown policy: ~a" (relay-rule-policy rule))))
    (when (and (memq (relay-rule-kind rule) '(domain domain-suffix))
               (not (valid-hostname? (relay-rule-value rule))))
      (add! line "invalid-domain"
            (format "invalid domain value: ~a" (relay-rule-value rule)))))
  ;; Rule options are deliberately not an issue here: import excludes them
  ;; with a precise per-line reason, and profiles that already carry options
  ;; (like the shipped example) evaluate locally without them.
  (define final-position
    (for/first ([rule (in-list (relay-profile-rules profile))]
                [position (in-naturals 1)]
                #:when (eq? (relay-rule-kind rule) 'match))
      position))
  (cond
    [(not final-position)
     (add! 0 "no-final" "missing FINAL fallback rule")]
    [(not (= final-position (length (relay-profile-rules profile))))
     (add! final-position "final-not-last" "FINAL must be the last rule")])
  (reverse issues))

;; Load one canonical profile file without raising. Returns two values: the
;; profile or #f, and the issue list explaining a failure.
(define (profile-load-report path)
  (with-handlers
    ([exn:fail?
      (lambda (exn)
        (values #f (list (issue 0 "unusable-profile" (exn-message exn)))))])
    (define profile (read-relay-profile path))
    (define issues (profile-validation-issues profile))
    (values profile issues)))

(define (profile-status issues)
  (if (null? issues) "valid" "invalid"))

;; Policy targets a rule may reference, in stable order: DIRECT, REJECT,
;; policy groups, nodes.
(define (profile-targets profile)
  (append '("DIRECT" "REJECT")
          (map policy-group-id (relay-profile-policies profile))
          (map proxy-node-id (relay-profile-nodes profile))))

;; ---- library state ---------------------------------------------------------------

(define library-state-file "library-state.json")

(define (library-state-path root)
  (build-path root library-state-file))

(define (profile-file-path root id)
  (build-path root (string-append id ".relayprofile.json")))

(define (empty-library-state)
  (hasheq 'version 1 'activeProfileId "" 'profiles (hasheq)))

(define (read-library-state root)
  (with-handlers
    ([exn:fail? (lambda (_) (empty-library-state))])
    (define raw (with-input-from-file (library-state-path root) read-json))
    (unless (hash? raw) (raise-argument-error 'read-library-state "hash?" raw))
    (hasheq 'version 1
            'activeProfileId
            (let ([id (hash-ref raw 'activeProfileId "")])
              (if (string? id) id ""))
            'profiles
            ;; read-json yields symbol keys; the rest of this module keys the
            ;; entries map by the canonical string profile id.
            (let ([entries (hash-ref raw 'profiles (hasheq))])
              (if (hash? entries)
                  (for/hash ([(key value) (in-hash entries)])
                    (values (if (symbol? key) (symbol->string key) key)
                            value))
                  (hasheq))))))

(define (write-library-state! root state)
  (make-directory* root)
  (define temporary (make-temporary-file "relaypilot-state-~a.tmp" #f root))
  (dynamic-wind void
                (lambda ()
                  (call-with-output-file
                   temporary
                   (lambda (out)
                     (write-bytes (jsexpr->canonical-bytes state) out))
                   #:exists 'truncate/replace)
                  (rename-file-or-directory temporary (library-state-path root) #t))
                (lambda ()
                  (when (file-exists? temporary)
                    (delete-file temporary)))))

(define (state-description state profile-id)
  (define entry (hash-ref (hash-ref state 'profiles) profile-id #f))
  (if (and (hash? entry) (string? (hash-ref entry 'description #f)))
      (hash-ref entry 'description)
      ""))

(define (set-state-description! state profile-id description)
  (define entries (hash-ref state 'profiles))
  (define entry (hash-ref entries profile-id (hasheq)))
  (hash-set state
            'profiles
            (hash-set entries profile-id (hash-set entry 'description description))))

;; ---- Surge import preview ---------------------------------------------------------

;; Per-line classification of foreign Surge text. Nothing is silently dropped:
;; every non-importable line comes back with a precise reason, and accepted
;; rules are exactly what a follow-up import commit writes.

(define (comment-line? line)
  (or (string=? line "")
      (string-prefix? line "#")
      (string-prefix? line ";")
      (string-prefix? line "//")))

(define (section-header? line)
  ;; #px, not #rx: POSIX bracket expressions treat the escaped close bracket
  ;; differently and this pattern silently stops matching section headers.
  (regexp-match? #px"^\\[[^\\]]+\\]$" line))

(define (normalize-policy policy)
  (cond
    [(string-ci=? policy "DIRECT") "DIRECT"]
    [(string-ci=? policy "REJECT") "REJECT"]
    [else policy]))

(define (surge-import-preview text)
  (define lines (string-split text "\n"))
  (define accepted-rules '())
  (define unsupported '())
  (define section (box ""))
  (define saw-final (box #f))
  (define referenced-policies (box '()))
  (define (add-unsupported line text code detail)
    (set! unsupported
          (cons (hasheq 'line line 'text text 'code code 'detail detail) unsupported)))
  (define (remember-policy! policy)
    (unless (or (string=? policy "DIRECT") (string=? policy "REJECT"))
      (unless (member policy (unbox referenced-policies))
        (set-box! referenced-policies
                  (append (unbox referenced-policies) (list policy))))))
  (define (accept-rule! line text rule)
    (define normalized (normalize-policy (relay-rule-policy rule)))
    (define value
      (if (memq (relay-rule-kind rule) '(domain domain-suffix))
          (string-downcase (relay-rule-value rule))
          (relay-rule-value rule)))
    (cond
      [(unbox saw-final)
       (add-unsupported line text "after-final"
                        "this line comes after FINAL and would never execute")]
      [(not (null? (relay-rule-options rule)))
       (add-unsupported line text "unsupported-options"
                        (format "rule options are not importable: ~a"
                                (string-join (relay-rule-options rule) ",")))]
      [(not (non-empty-string? normalized))
       (add-unsupported line text "invalid-policy" "the rule has no policy")]
      [(and (memq (relay-rule-kind rule) '(domain domain-suffix))
            (not (valid-hostname? value)))
       (add-unsupported line text "invalid-domain"
                        (format "invalid domain value: ~a" (relay-rule-value rule)))]
      [else
       (remember-policy! normalized)
       (set! accepted-rules
             (cons (if (eq? (relay-rule-kind rule) 'match)
                       (string-append "FINAL," normalized)
                       (string-append
                        (case (relay-rule-kind rule)
                          [(domain) "DOMAIN"]
                          [(domain-suffix) "DOMAIN-SUFFIX"]
                          [(ip-cidr) "IP-CIDR"]
                          [(ip-cidr6) "IP-CIDR6"]
                          [(geoip) "GEOIP"]
                          [else "FINAL"])
                        ","
                        value
                        ","
                        normalized))
                   accepted-rules))
       (when (eq? (relay-rule-kind rule) 'match)
         (set-box! saw-final #t))]))
  (for ([raw (in-list lines)]
        [number (in-naturals 1)])
    (define line (string-trim raw))
    (cond
      [(comment-line? line) (void)]
      [(section-header? line)
       (set-box! section
                 (string-downcase
                  (substring line 1 (sub1 (string-length line)))))]
      [else
       (define current (unbox section))
       (cond
         [(string=? current "rule")
          (with-handlers
            ([exn:fail?
              (lambda (exn)
                (add-unsupported number line "unsupported-rule"
                                 "only DOMAIN, DOMAIN-SUFFIX, IP-CIDR, IP-CIDR6, GEOIP and FINAL are importable"))])
            (define rule (parse-surge-rule line number "import-preview"))
            (when rule (accept-rule! number line rule)))]
         [(string=? current "proxy")
          (add-unsupported number line "unsupported-section-entry"
                            "proxy nodes are outside the importable subset (the engine adapter compiles a narrow VLESS slice only)")]
         [(string=? current "proxy group")
          (add-unsupported number line "unsupported-section-entry"
                            "proxy groups cannot be imported without supported member nodes")]
         [else
          (add-unsupported number line "unsupported-section"
                            (if (string=? current "")
                                "this line is outside any [Rule] section"
                                (format "the [~a] section is not importable" current)))])]))
  (define rules (reverse accepted-rules))
  (define referenced (unbox referenced-policies))
  ;; Rules that name unavailable proxies or groups keep their semantics as
  ;; placeholder select groups whose only member is DIRECT. The preview
  ;; states this mapping explicitly; it is never presented as a usable exit.
  (define warnings
    (append
     (if (null? referenced)
         '()
         (list (format "policy groups ~a have no importable exits; they are created as placeholders that fall back to DIRECT"
                       (string-join referenced ", "))))
     (if (for/or ([rule (in-list rules)]) (string-prefix? rule "FINAL,"))
         '()
         (list "no FINAL fallback rule was importable; the created profile would have no default route"))
     (if (null? rules) (list "no importable routing rules were found") '())))
  (hasheq 'rules rules
          'ruleCount (length rules)
          'groups referenced
          'unsupported (reverse unsupported)
          'hasFinal (unbox saw-final)
          'warnings warnings))

;; ---- snapshot ----------------------------------------------------------------------

(define (sorted-profile-paths root)
  (sort
   (for/list ([path (in-directory root)]
              #:when (regexp-match? #rx"[.]relayprofile[.]json$" (path->string path)))
     path)
   string<?
   #:key path->string))

(define (library-snapshot root)
  (define state (read-library-state root))
  (define entries
    (for/list ([path (in-list (sorted-profile-paths root))])
      (define stem
        (substring (path->string (file-name-from-path path))
                   0
                   (- (string-length (path->string (file-name-from-path path)))
                      (string-length ".relayprofile.json"))))
      (define-values (profile issues) (profile-load-report path))
      (hasheq 'id
              (if profile (relay-profile-id profile) stem)
              'name
              (if profile (relay-profile-name profile) stem)
              'description
              (state-description state (if profile (relay-profile-id profile) stem))
              'ruleCount
              (if profile (length (relay-profile-rules profile)) 0)
              'status
              (profile-status issues)
              'issues
              issues
              'targets
              (if profile (profile-targets profile) '()))))
  (define valid-ids
    (for/list ([entry (in-list entries)] #:when (string=? (hash-ref entry 'status) "valid"))
      (hash-ref entry 'id)))
  (define requested (hash-ref state 'activeProfileId ""))
  (define active-id
    (cond
      [(and (non-empty-string? requested) (member requested valid-ids)) requested]
      [(pair? valid-ids) (car valid-ids)]
      [else ""]))
  (hasheq 'activeProfileId active-id 'profiles entries))

;; ---- mutations ---------------------------------------------------------------------

(define (require-profile root profile-id)
  (unless (non-empty-string? profile-id)
    (raise-relaypilot 'validation 1 "profile id must not be empty"))
  (define path (profile-file-path root profile-id))
  (unless (file-exists? path)
    (raise-relaypilot 'validation 1 (format "profile not found: ~a" profile-id)))
  (define-values (profile issues) (profile-load-report path))
  (unless profile
    (raise-relaypilot 'validation 1
                      (format "profile ~a does not load: ~a"
                              profile-id
                              (hash-ref (car issues) 'detail ""))))
  (values path profile issues))

(define (require-valid-profile root profile-id)
  (define-values (path profile issues) (require-profile root profile-id))
  (unless (null? issues)
    (raise-relaypilot 'validation 1
                      (format "profile ~a has unresolved issues: ~a"
                              profile-id
                              (hash-ref (car issues) 'detail ""))))
  (values path profile))

(define (unique-profile-id root base)
  (define candidate (regexp-replace* #rx"[^a-z0-9-]+" (string-downcase base) "-"))
  (define cleaned (string-trim candidate #rx"-+"))
  (define prefix (if (non-empty-string? cleaned) cleaned "imported"))
  (let loop ([attempt 0])
    (define id (if (zero? attempt) prefix (format "~a-~a" prefix attempt)))
    (if (file-exists? (profile-file-path root id))
        (loop (add1 attempt))
        id)))

;; Names are user-facing identifiers in the host library; duplicates would
;; make "open by name" ambiguous, so they are rejected before any write.
(define (profile-name-taken? root name)
  (for/or ([path (in-list (sorted-profile-paths root))])
    (define-values (profile _) (profile-load-report path))
    (and profile (string=? (relay-profile-name profile) name))))

(define (write-profile! root profile)
  (define path (profile-file-path root (relay-profile-id profile)))
  (make-directory* root)
  (define temporary (make-temporary-file "relaypilot-profile-~a.tmp" #f root))
  (dynamic-wind void
                (lambda ()
                  (call-with-output-file
                   temporary
                   (lambda (out)
                     (write-bytes (jsexpr->canonical-bytes (relay-profile->jsexpr profile)) out))
                   #:exists 'truncate/replace)
                  (rename-file-or-directory temporary path #t))
                (lambda ()
                  (when (file-exists? temporary)
                    (delete-file temporary))))
  path)

;; Import commit re-runs the preview so the accepted rule set can only come
;; from the same classification the user confirmed.
(define (library-import-commit! root name description text)
  (unless (and (string? name) (non-empty-string? name) (<= (string-length name) 80))
    (raise-relaypilot 'validation 1 "profile name must be 1-80 characters"))
  (when (profile-name-taken? root name)
    (raise-relaypilot 'validation 1 (format "profile name already exists: ~a" name)))
  (define preview (surge-import-preview text))
  (define rules (hash-ref preview 'rules))
  (unless (pair? rules)
    (raise-relaypilot 'validation 1 "no importable routing rules were found"))
  (unless (hash-ref preview 'hasFinal)
    (raise-relaypilot 'validation 1
                      "imported rules have no FINAL fallback; add a FINAL rule before importing"))
  (define id (unique-profile-id root name))
  (define parsed (parse-surge-rules rules id))
  (define groups
    (for/list ([group-name (in-list (hash-ref preview 'groups))])
      (policy-group group-name group-name 'select (list "DIRECT") #f)))
  (define profile
    (relay-profile 1 id name '() groups parsed (hasheq)))
  (write-profile! root profile)
  (define state (read-library-state root))
  ;; The first profile in an empty library becomes active immediately; later
  ;; imports never switch (hosts confirm switches explicitly).
  (define state-with-active
    (if (non-empty-string? (hash-ref state 'activeProfileId ""))
        state
        (hash-set state 'activeProfileId id)))
  (write-library-state! root (set-state-description! state-with-active id description))
  (hasheq 'profileId id 'ruleCount (length (relay-profile-rules profile))))

;; Rule editor: replace the rule set of an existing profile with parsed lines.
(define (library-update-rules! root profile-id rules-text)
  (define-values (path profile _) (require-profile root profile-id))
  (define rules
    (with-handlers
      ([exn:fail?
        (lambda (exn)
          (raise-relaypilot 'validation 1 (format "rules do not parse: ~a" (exn-message exn))))])
      (parse-surge-rules rules-text profile-id)))
  (define known-targets (profile-targets profile))
  (for ([rule (in-list rules)])
    (unless (member (relay-rule-policy rule) known-targets)
      (raise-relaypilot 'validation 1
                        (format "rule ~a references unknown policy: ~a"
                                (relay-rule-index rule)
                                (relay-rule-policy rule)))))
  (define candidate
    (relay-profile (relay-profile-schema-version profile)
                   (relay-profile-id profile)
                   (relay-profile-name profile)
                   (relay-profile-nodes profile)
                   (relay-profile-policies profile)
                   rules
                   (relay-profile-dns profile)))
  (define issues (profile-validation-issues candidate))
  (unless (null? issues)
    (raise-relaypilot 'validation 1
                      (format "rules have unresolved issues: ~a"
                              (hash-ref (car issues) 'detail ""))))
  (write-profile! root candidate)
  (hasheq 'profileId profile-id 'ruleCount (length rules)))

(define (library-delete-profile! root profile-id)
  (define state (read-library-state root))
  (when (string=? (hash-ref state 'activeProfileId) profile-id)
    (raise-relaypilot 'validation 1 "the active profile cannot be deleted"))
  (define path (profile-file-path root profile-id))
  (unless (file-exists? path)
    (raise-relaypilot 'validation 1 (format "profile not found: ~a" profile-id)))
  (delete-file path)
  (hasheq 'profileId profile-id 'ruleCount 0))

(define (library-set-active! root profile-id)
  (require-valid-profile root profile-id)
  (define state (read-library-state root))
  (write-library-state! root (hash-set state 'activeProfileId profile-id))
  (hasheq 'profileId profile-id 'ruleCount 0))

;; ---- route patches ------------------------------------------------------------------

(define patch-flow-port 443)

(define (patch-rule-value target)
  (string-downcase (string-trim target)))

(define (rebuild-rules profile rules)
  (for/list ([rule (in-list rules)]
             [index (in-naturals 1)])
    (struct-copy relay-rule rule [index index])))

(define (patch-rules profile target policy)
  (define value (patch-rule-value target))
  (define kept
    (for/list ([rule (in-list (relay-profile-rules profile))]
               #:unless (and (eq? (relay-rule-kind rule) 'domain)
                             (string-ci=? (relay-rule-value rule) value)))
      rule))
  (cons (relay-rule 1 'domain value policy '() "route-patch") kept))

;; Route facts for a domain target under a candidate profile. Requires a FINAL
;; rule (callers guarantee it through the validity check).
(define (route-facts-for profile target)
  (define trace
    (decide-flow profile
                 (connection-flow (patch-rule-value target)
                                  #f
                                  patch-flow-port
                                  'tcp
                                  #f)))
  (hasheq 'policy (decision-trace-requested-policy trace)
          'outbound (decision-trace-selected-outbound trace)))

(define (library-patch-preview root profile-id target policy)
  (define-values (_ profile) (require-valid-profile root profile-id))
  (unless (member policy (profile-targets profile))
    (raise-relaypilot 'validation 1 (format "unknown policy target: ~a" policy)))
  (unless (valid-hostname? (patch-rule-value target))
    (raise-relaypilot 'validation 1 (format "invalid domain target: ~a" target)))
  (define current (route-facts-for profile target))
  (define candidate
    (relay-profile (relay-profile-schema-version profile)
                   (relay-profile-id profile)
                   (relay-profile-name profile)
                   (relay-profile-nodes profile)
                   (relay-profile-policies profile)
                   (rebuild-rules profile (patch-rules profile target policy))
                   (relay-profile-dns profile)))
  (define next (route-facts-for candidate target))
  (hasheq 'sameAsCurrent
          (and (string=? (hash-ref current 'policy) policy)
               (string=? (hash-ref current 'outbound) (hash-ref next 'outbound)))
          'currentPolicy (hash-ref current 'policy)
          'currentOutbound (hash-ref current 'outbound)
          'nextPolicy (hash-ref next 'policy)
          'nextOutbound (hash-ref next 'outbound)
          'ruleText (format "DOMAIN,~a,~a" (patch-rule-value target) policy)))

(define (library-patch-apply! root profile-id target policy)
  (define-values (_ profile) (require-valid-profile root profile-id))
  (unless (member policy (profile-targets profile))
    (raise-relaypilot 'validation 1 (format "unknown policy target: ~a" policy)))
  (unless (valid-hostname? (patch-rule-value target))
    (raise-relaypilot 'validation 1 (format "invalid domain target: ~a" target)))
  (define rules (rebuild-rules profile (patch-rules profile target policy)))
  (define candidate
    (relay-profile (relay-profile-schema-version profile)
                   (relay-profile-id profile)
                   (relay-profile-name profile)
                   (relay-profile-nodes profile)
                   (relay-profile-policies profile)
                   rules
                   (relay-profile-dns profile)))
  (define issues (profile-validation-issues candidate))
  (unless (null? issues)
    (raise-relaypilot 'validation 1
                      (format "patched profile has unresolved issues: ~a"
                              (hash-ref (car issues) 'detail ""))))
  (write-profile! root candidate)
  (hasheq 'ruleIndex 1
          'rules (map rule->string (relay-profile-rules candidate))))
