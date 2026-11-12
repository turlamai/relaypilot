# Contributing to RelayPilot

This file is a thin pointer. The binding rules live in the documents it
references; nothing here overrides them.

## Read first

- [AGENTS.md](AGENTS.md) — the development discipline: product boundary,
  Rivet boundary, truthfulness rules, and the verification list every
  change must pass before submission.
- [ROADMAP.md](ROADMAP.md) — claim one bounded slice at a time and record
  the evidence it asks for.
- [docs/CLI-SPEC.md](docs/CLI-SPEC.md) — CLI behavior changes land in the
  spec first, then the code.

## Verify before submitting

Requires Racket CS 9.x and [Rivet](https://github.com/turlamai/rivet):

```bash
raco pkg install --auto --no-docs rivet
raco make racket/backend.rkt
raco test tests/
python3 shared/cli-golden/runner.py --binary scripts/relaypilot-cli.sh
scripts/check-release-version.sh
racket scripts/third-party-notices.rkt --check
```

With `RELAYPILOT_XRAY_BIN` pointing at the pinned Xray binary, `raco test
tests/` additionally runs config validation and a real loopback SOCKS
session through a supervised engine process; without it those tests skip
with a printed reason — a skip is not a pass.

## Golden contract

The CLI's byte-level golden contract lives in `shared/cli-golden/`. Never
edit golden bytes by hand and never delete a case to get green; re-record
with `--record` after a spec change and review the diff.

## Pull requests

- Keep PRs one bounded slice each; state what is implemented, what is
  released, and what was verified on a real machine — separately.
- Security-sensitive reports go through [SECURITY.md](SECURITY.md), never
  public issues.
- **License terms:** RelayPilot is proprietary ([LICENSE](LICENSE)); no
  open-source license is granted. By opening a pull request you grant the
  copyright holder a perpetual, worldwide, royalty-free right to use,
  reproduce, modify, and distribute your contribution as part of
  RelayPilot under its proprietary license. Do not submit third-party
  code that cannot be licensed on those terms.
