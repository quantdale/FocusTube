#!/usr/bin/env bash
# Gate-contract self-check (DDV2 convergence): the iOS CI workflow's final Gate
# must stay FAIL-CLOSED over the bounded test steps. The test steps carry
# continue-on-error ONLY to guarantee both bundles always run and diagnostics
# publish; the Gate restores the honest verdict from their persisted exit codes.
#
# This script asserts that contract structurally, so an accidental edit that
# removes/weakenes the verdict restoration fails CI even when every test passes.
set -euo pipefail

workflow=".github/workflows/ios-ci.yml"

fail() {
    echo "::error::gate-contract violation: $1"
    exit 1
}

[ -f "$workflow" ] || fail "$workflow missing"

grep -q 'name: Gate' "$workflow" ||
    fail "Gate step missing"

grep -q 'cat Artifacts/unit.exit' "$workflow" ||
    fail "Gate no longer reads unit.exit"

grep -q 'cat Artifacts/ui.exit' "$workflow" ||
    fail "Gate no longer reads ui.exit"

grep -q '\[ "\$U" != "0" \] || \[ "\$I" != "0" \]' "$workflow" ||
    fail "Gate comparison weakened: must fail unless BOTH unit and ui exits are exactly 0"

grep -q '::error::iOS CI gate failed' "$workflow" ||
    fail "Gate failure annotation missing"

echo "gate-contract OK: fail-closed verdict restoration present"
