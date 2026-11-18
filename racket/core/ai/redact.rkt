#lang racket/base

(require racket/list
         racket/string
         "../diagnostics/bundle.rkt"
         "../model.rkt")

(provide redact-diagnostic-bundle
         profile-secrets)

(define (redact-value value secrets)
  (cond
    [(string? value)
     (for/fold ([result value])
               ([secret (in-list secrets)]
                #:when (and (string? secret) (positive? (string-length secret))))
       (string-replace result secret "[REDACTED]"))]
    [(hash? value)
     (for/hasheq ([(key nested) (in-hash value)])
       (values key (redact-value nested secrets)))]
    [(list? value) (map (lambda (nested) (redact-value nested secrets)) value)]
    [else value]))

(define (redact-diagnostic-bundle bundle secrets)
  (diagnostic-bundle (diagnostic-bundle-schema-version bundle)
                     (diagnostic-bundle-trace-id bundle)
                     (diagnostic-bundle-profile-id bundle)
                     (redact-value (diagnostic-bundle-connection bundle) secrets)
                     (redact-value (diagnostic-bundle-decision bundle) secrets)
                     (redact-value (diagnostic-bundle-engine-events bundle) secrets)
                     (redact-value (diagnostic-bundle-comparable-failures bundle) secrets)))

;; Profile secret material that must not leak into diagnostics. Values shorter
;; than 8 characters are structural ("none", "chrome") rather than secrets.
(define (profile-secrets profile)
  (remove-duplicates
   (for*/list ([node (in-list (relay-profile-nodes profile))]
               [table (in-list (list (proxy-node-credentials node) (proxy-node-tls node)))]
               [value (in-hash-values table)]
               #:when (and (string? value) (>= (string-length value) 8)))
     value)))
