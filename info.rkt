#lang info

(define collection 'use-pkg-name)
(define pkg-desc "RelayPilot local-first cross-platform network toolbox")
(define version "0.1.0")
(define pkg-authors '(turlamai))
;; rivet must never be declared as a package dep: the catalog entry is a
;; moving target, so CI installs the pinned commit explicitly (see ci.yml)
;; and local setups do the same before linking. Family rule from autarx.
(define deps '("base"))
(define build-deps '("rackunit-lib"))
