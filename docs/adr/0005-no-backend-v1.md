# ADR-0005 — No Backend for V1

**Status:** Accepted

## Decision

FocusTube V1 is device-centric and requires no application backend. Google/YouTube APIs are called directly by the client where authorized; extraction is local; media/history/download state is local.

A backend requires a future ADR proving a concrete need.
