#lang racket/base

(require racket/list
         rivet/backend
         (prefix-in core: "core/model.rkt")
         "core/ai/redact.rkt"
         "core/decision.rkt"
         "core/diagnostics/bundle.rkt"
         "core/engines/interface.rkt"
         "core/engines/runtime.rkt"
         "core/engines/xray.rkt"
         "core/errors.rkt"
         "core/json.rkt"
         ;; The library RPCs share names with the core functions they wrap;
         ;; a prefix keeps the RPC bodies from shadowing themselves.
         (prefix-in lib: "core/library.rkt")
         "core/model.rkt"
         "core/profile/json.rkt")

(provide start)

(define-record RouteDecision
               ([traceId : String] [ruleIndex : Int64]
                                   [policy : String]
                                   [outbound : String]
                                   [steps : (List String)]
                                   [warnings : (List String)]))

(define-record CompiledEngineConfig
               ([adapter : String] [adapterVersion : String] [sha256 : String] [json : String]))

(define-record EngineDryRun
               ([adapter : String] [adapterVersion : String] [sha256 : String]
                                   [available : Bool] [validated : Bool]
                                   [engineVersion : String] [engineOutput : (List String)]))

(define-record EngineSessionHandle ([sessionId : String] [inboundPort : Int64] [engineVersion : String]))

(define-record EngineSessionStop ([stopped : Bool] [exitStatus : String] [events : (List String)]))

(define-record ProfileIssue ([index : Int64] [code : String] [detail : String]))

(define-record LibraryEntry ([id : String]
                             [name : String]
                             [description : String]
                             [ruleCount : Int64]
                             [status : String]
                             [issues : (List ProfileIssue)]
                             [targets : (List String)]))

(define-record LibrarySnapshot ([activeProfileId : String] [profiles : (List LibraryEntry)]))

(define-record UnsupportedLine ([line : Int64] [text : String] [code : String] [detail : String]))

(define-record ImportPreview ([importableRules : (List String)]
                              [placeholderGroups : (List String)]
                              [unsupported : (List UnsupportedLine)]
                              [hasFinal : Bool]
                              [warnings : (List String)]
                              [nameAvailable : Bool]))

(define-record LibraryMutation ([profileId : String] [ruleCount : Int64]))

(define-record PatchPreview ([sameAsCurrent : Bool]
                             [currentPolicy : String]
                             [currentOutbound : String]
                             [nextPolicy : String]
                             [nextOutbound : String]
                             [ruleText : String]))

(define-record PatchOutcome ([ruleIndex : Int64] [rules : (List String)]))

;; ---- library RPCs ----------------------------------------------------------------
;; The library root is a user-owned folder the host passes on every call; the
;; backend keeps no cross-call library state. Errors use the shared
;; exn:fail:relaypilot classification so hosts can present one kind taxonomy.

(define (issue->record entry-issue)
  (ProfileIssue (hash-ref entry-issue 'index)
                (hash-ref entry-issue 'code)
                (hash-ref entry-issue 'detail)))

(define (entry->record entry)
  (LibraryEntry (hash-ref entry 'id)
                (hash-ref entry 'name)
                (hash-ref entry 'description)
                (hash-ref entry 'ruleCount)
                (hash-ref entry 'status)
                (map issue->record (hash-ref entry 'issues))
                (hash-ref entry 'targets)))

(define-rpc (library-list [root : String] : LibrarySnapshot)
            (define snapshot (lib:library-snapshot root))
            (LibrarySnapshot (hash-ref snapshot 'activeProfileId)
                             (map entry->record (hash-ref snapshot 'profiles))))

(define-rpc (library-read-profile [root : String] [profileId : String] : String)
            (define-values (_path profile _issues) (lib:require-profile root profileId))
            (bytes->string/utf-8
             (jsexpr->canonical-bytes (relay-profile->jsexpr profile))))

(define (require-name name)
  (unless (and (string? name) (positive? (string-length name)) (<= (string-length name) 80))
    (raise-relaypilot 'validation 1 "profile name must be 1-80 characters")))

(define-rpc (library-import-preview [root : String] [name : String] [text : String]
                                    :
                                    ImportPreview)
            (require-name name)
            (define preview (lib:surge-import-preview text))
            (ImportPreview (hash-ref preview 'rules)
                           (hash-ref preview 'groups)
                           (for/list ([row (in-list (hash-ref preview 'unsupported))])
                             (UnsupportedLine (hash-ref row 'line)
                                              (hash-ref row 'text)
                                              (hash-ref row 'code)
                                              (hash-ref row 'detail)))
                           (hash-ref preview 'hasFinal)
                           (hash-ref preview 'warnings)
                           (not (lib:profile-name-taken? root name))))

(define-rpc (library-import-commit [root : String]
                                   [name : String]
                                   [description : String]
                                   [text : String]
                                   :
                                   LibraryMutation)
            (define result (lib:library-import-commit! root name description text))
            (LibraryMutation (hash-ref result 'profileId)
                             (hash-ref result 'ruleCount)))

(define-rpc (library-update-rules [root : String]
                                  [profileId : String]
                                  [rulesText : String]
                                  :
                                  LibraryMutation)
            (define result (lib:library-update-rules! root profileId rulesText))
            (LibraryMutation (hash-ref result 'profileId)
                             (hash-ref result 'ruleCount)))

(define-rpc (library-delete-profile [root : String] [profileId : String] : LibraryMutation)
            (lib:library-delete-profile! root profileId)
            (LibraryMutation profileId 0))

(define-rpc (library-set-active [root : String] [profileId : String] : LibraryMutation)
            (lib:library-set-active! root profileId)
            (LibraryMutation profileId 0))

(define-rpc (library-patch-preview [root : String]
                                   [profileId : String]
                                   [target : String]
                                   [policy : String]
                                   :
                                   PatchPreview)
            (define result (lib:library-patch-preview root profileId target policy))
            (PatchPreview (hash-ref result 'sameAsCurrent)
                          (hash-ref result 'currentPolicy)
                          (hash-ref result 'currentOutbound)
                          (hash-ref result 'nextPolicy)
                          (hash-ref result 'nextOutbound)
                          (hash-ref result 'ruleText)))

(define-rpc (library-patch-apply [root : String]
                                 [profileId : String]
                                 [target : String]
                                 [policy : String]
                                 :
                                 PatchOutcome)
            (define result (lib:library-patch-apply! root profileId target policy))
            (PatchOutcome (hash-ref result 'ruleIndex)
                          (hash-ref result 'rules)))

;; ---- diagnostics RPC ---------------------------------------------------------------

(define (diagnostic-bundle->jsexpr bundle)
  (hasheq 'schemaVersion
          (diagnostic-bundle-schema-version bundle)
          'traceId
          (diagnostic-bundle-trace-id bundle)
          'profileId
          (diagnostic-bundle-profile-id bundle)
          'connection
          (diagnostic-bundle-connection bundle)
          'decision
          (diagnostic-bundle-decision bundle)
          'engineEvents
          (diagnostic-bundle-engine-events bundle)
          'comparableFailures
          (diagnostic-bundle-comparable-failures bundle)))

;; Secrets plus every target-derived fact: the queried domain, the flow ip,
;; and the domain rule values that appear in trace steps and rule sources.
(define (diagnose-route-mask profile domain ip)
  (append
   (profile-secrets profile)
   (filter (lambda (value)
             (and (string? value) (positive? (string-length value))))
           (cons domain
                 (cons ip
                       (for/list ([rule (in-list (core:relay-profile-rules profile))]
                                  #:when (memq (core:relay-rule-kind rule)
                                               '(domain domain-suffix)))
                         (core:relay-rule-value rule)))))))

(define-rpc (diagnose-route [profileJson : String]
                            [domain : String]
                            [ip : String]
                            [port : Int64]
                            [network : String]
                            [redact : Bool]
                            :
                            String)
            (define profile (read-relay-profile profileJson))
            (define trace
              (decide-flow profile
                           (core:connection-flow (if (string=? domain "") #f domain)
                                                 (if (string=? ip "") #f ip)
                                                 port
                                                 (string->symbol network)
                                                 #f)))
            (define bundle (trace->diagnostic-bundle trace))
            (define prepared
              (if redact
                  ;; Target-derived facts leave the export together with the
                  ;; trace id, matching the host's redaction contract.
                  (struct-copy diagnostic-bundle
                               (redact-diagnostic-bundle
                                bundle
                                (diagnose-route-mask profile domain ip))
                               [trace-id "[redacted]"])
                  bundle))
            (bytes->string/utf-8 (jsexpr->canonical-bytes (diagnostic-bundle->jsexpr prepared))))

(define-rpc (explain-route [profileJson : String]
                           [domain : String]
                           [ip : String]
                           [port : Int64]
                           [network : String]
                           :
                           RouteDecision)
            (define profile (read-relay-profile profileJson))
            (define trace
              (decide-flow profile
                           (core:connection-flow (if (string=? domain "") #f domain)
                                                 (if (string=? ip "") #f ip)
                                                 port
                                                 (string->symbol network)
                                                 #f)))
            (RouteDecision (core:decision-trace-trace-id trace)
                           (core:decision-trace-rule-index trace)
                           (core:decision-trace-requested-policy trace)
                           (core:decision-trace-selected-outbound trace)
                           (core:decision-trace-steps trace)
                           (core:decision-trace-warnings trace)))

(define-rpc (compile-engine-config [profileJson : String] : CompiledEngineConfig)
            (define compiled (engine-compile xray-engine-adapter (read-relay-profile profileJson)))
            (CompiledEngineConfig (symbol->string (core:compiled-engine-config-adapter compiled))
                                  (core:compiled-engine-config-adapter-version compiled)
                                  (core:compiled-engine-config-digest compiled)
                                  (bytes->string/utf-8 (core:compiled-engine-config-bytes compiled))))

(define-rpc (engine-dry-run [profileJson : String] [socksPort : Int64] : EngineDryRun)
            (define profile (read-relay-profile profileJson))
            (define compiled
              (compile-xray-config profile (if (zero? socksPort) 1080 socksPort)))
            (define binary (resolve-engine-binary))
            (define version
              (if binary (hash-ref (engine-query-version! binary) 'version) ""))
            (define validation
              (if binary
                  (engine-validate-config (core:compiled-engine-config-bytes compiled) binary)
                  (hasheq 'available #f 'validated #f 'output (list engine-not-configured-reason))))
            (EngineDryRun "xray"
                          (core:compiled-engine-config-adapter-version compiled)
                          (core:compiled-engine-config-digest compiled)
                          (hash-ref validation 'available)
                          (hash-ref validation 'validated)
                          version
                          (hash-ref validation 'output)))

;; Live sessions live only inside this backend process; the id is opaque to
;; hosts. Events cross the wire as canonical JSON strings.
(define sessions (make-hash))
(define sessions-lock (make-semaphore 1))

(define (with-session-lock thunk)
  (call-with-semaphore sessions-lock thunk))

(define (event->string event)
  (bytes->string/utf-8 (jsexpr->canonical-bytes event)))

(define-rpc (engine-session-start [profileJson : String] [socksPort : Int64]
                                  :
                                  EngineSessionHandle)
            (define profile (read-relay-profile profileJson))
            (define binary (resolve-engine-binary))
            (unless binary
              (raise-relaypilot 'engine 3 engine-not-configured-reason))
            ;; Port 0 means "pick a free loopback port"; the compile and the
            ;; spawned engine must agree on the same concrete port.
            (define port (if (zero? socksPort) (free-loopback-port!) socksPort))
            (define compiled (compile-xray-config profile port))
            (define version (hash-ref (engine-query-version! binary) 'version))
            (define session
              (engine-session-start! (core:compiled-engine-config-bytes compiled)
                                     binary
                                     #:socks-port port))
            (with-session-lock
             (lambda () (hash-set! sessions (engine-session-id session) session)))
            (EngineSessionHandle (engine-session-id session)
                                 (engine-session-inbound-port session)
                                 version))

(define-rpc (engine-session-stop [sessionId : String] : EngineSessionStop)
            (define session
              (with-session-lock (lambda () (hash-ref sessions sessionId #f))))
            (cond
              [(not session) (EngineSessionStop #f "unknown-session" '())]
              [else
               (define result (engine-session-stop! session))
               (with-session-lock (lambda () (hash-remove! sessions sessionId)))
               (EngineSessionStop #t
                                  (format "~a" (hash-ref result 'exit-code))
                                  (map event->string (hash-ref result 'events)))]))

(define-rpc (engine-session-events [sessionId : String] : (List String))
            (define session
              (with-session-lock (lambda () (hash-ref sessions sessionId #f))))
            (if session
                (map event->string (engine-session-events session))
                '()))

(define (start in-fd out-fd)
  (serve-fds in-fd out-fd))

(module+ test-support
  (provide RouteDecision
           CompiledEngineConfig
           EngineDryRun
           EngineSessionHandle
           EngineSessionStop
           ProfileIssue
           LibraryEntry
           LibrarySnapshot
           UnsupportedLine
           ImportPreview
           LibraryMutation
           PatchPreview
           PatchOutcome
           explain-route
           compile-engine-config
           engine-dry-run
           engine-session-start
           engine-session-stop
           engine-session-events
           library-list
           library-read-profile
           library-import-preview
           library-import-commit
           library-update-rules
           library-delete-profile
           library-set-active
           library-patch-preview
           library-patch-apply
           diagnose-route))
