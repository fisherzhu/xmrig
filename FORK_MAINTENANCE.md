# XMRig Fork Maintenance Contract

This fork follows official XMRig releases but keeps one local policy:
developer donation defaults to 0%, and each miner may explicitly choose a
level from 0% to 99%. An explicit value in an existing configuration must
not be replaced by the compiled default.

The first fork binary release is
[`v6.26.0-static.1`](https://github.com/fisherzhu/xmrig/releases/tag/v6.26.0-static.1),
built from commit `9b34a710f644776a6f37d9f7712db01f791f9e9a`. This
document was added after that tag; it is not part of the tagged source.

## Invariants for an upstream upgrade

- With `donate-level` omitted, effective donation is 0%.
- Explicit `donate-level: 0` remains 0%; explicit 1% and other valid
  positive values remain unchanged. The upper bound remains 99%.
- At effective level 0, the miner does not construct its developer
  donation strategy. A positive level may construct it normally.
- The sample JSON, embedded default and `--help` agree with the runtime
  default. Existing miner configuration files are not silently rewritten.
- The Linux static release stays CPU-only unless a separate GPU-capable
  build and compatibility decision is approved.

These are behavioral requirements, not line-number or patch requirements.
An upstream implementation that already satisfies them needs no duplicate
fork change.

## Upgrade and release gate

For each official release, create a new `pool/vX.Y.Z` branch from the
exact upstream tag. Review upstream changes to donation defaults, config
loading, `Pools::setDonateLevel`, `Network` donation strategy creation,
help text and sample configuration. Carry forward only the minimal change
still needed, then run the invariant tests and static build from a clean
commit. Record the upstream tag, fork commit, dependency versions, binary
SHA-256 and tested platforms in the Release notes. Do not auto-merge an
upstream release or rely on a patch applying cleanly as evidence of
correctness.

Dedicated automated contract tests and a required CI gate are **pending**.
Before adopting the next upstream XMRig version, add tests that fail on an
upstream default of 1% and pass for omitted, explicit 0% and explicit
positive values. Until then, the v6.26.0-static.1 manual dry-run evidence
is recorded in the pool's local architecture-review archive and is not
equivalent to an automated upgrade gate.
