# WP-XXX — Title

**Campaign:** IMPLEMENTATION_V1  
**Milestone/Gate:** Mx / Gx  
**Dependencies:** ...

## Objective

One outcome stated in observable terms.

## Preconditions

What must already be proven before this packet becomes ready.

## Required implementation

- concrete behaviors/interfaces/state;
- tests/test seams;
- migration/configuration if relevant.

## Ordered waypoints

### W1 — ...

Implementation + validation expectation.

### W2 — ...

...

## Validation

### Deterministic
- commands/tests

### Apple build/simulator
- build/UI/integration checks

### Live/external
- isolated checks if required

### Physical device
- mark later/deferred when appropriate; never invent evidence

## Acceptance

Map directly to `docs/14-ACCEPTANCE-GATES.md` criteria.

## Failure/blocker policy

Describe likely external vs project failures and safe fallback work. Do not introduce architecture-changing fallback dependencies without ADR.

## State transition

On pass, specify exact next milestone/gate/packet. Default action is **continue**, not stop.

## Non-goals

Explicitly list tempting work that belongs to later packets/hardening.