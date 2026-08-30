# Fresh-machine onboarding

This is the canonical bootstrap entry point for a new workstation or a fresh coding-agent environment. Complete this document before implementation work. The objective is a reproducible machine that can build, test, inspect, and operate this repository without rediscovering tooling mid-campaign.

## 1. Preflight rule

1. Clone the repository and enter its root.
2. Confirm the intended repository/branch and fetch current `origin/main`.
3. Read the repository control-plane documents before changing code: `START_HERE.md`, `AGENTS.md`, `.agent/STATE.yaml`, `.agent/EXECUTION_PROMPT.md`, `.agent/BOOT_PROMPT.md`, `README.md`.
4. Install/verify the machine prerequisites below.
5. Enable the committed agent integrations and repository-local skills.
6. Restore dependencies from lockfiles/pins; do not casually upgrade them during bootstrap.
7. Run the baseline validation commands.
8. Only then begin a development campaign. If a prerequisite cannot be satisfied, record it as an environment blocker rather than weakening a gate.

Credentials, API keys, signing material, account logins, licensed models/assets, and other secrets are machine/user responsibilities. Never commit them.

## 2. Supported host and prerequisites

**Primary host:** Windows-first authoring is supported; real iOS build/simulator/device validation requires macOS with the pinned Xcode-era toolchain.

**Required machine tools**
- Git
- Swift toolchain compatible with the repository packages
- XcodeGen for generating the Xcode project
- macOS/Xcode when executing iOS build/UI/device gates

**Task-dependent / optional tools**
- Physical iPhone and authenticated account state for the owner-only validation batch


## 3. Agent setup

- Load repository instructions before acting. Prefer committed repository state over chat history.
- Repository-local skills: `goal`.
- Agent adapter/config directories present in this repository should be discovered and used in-place; do not duplicate them globally unless the harness cannot load repository-local configuration.
- Relevant committed agent surfaces: `.agent/`, `.agents/`, `.claude/`, `.kimi-code/`, `.opencode/`.
- MCP policy: No root `.mcp.json` is committed. Do not fabricate an iOS-capable MCP on Windows; use the repository's remote/macOS build plane when a gate truly requires Xcode.
- Keep MCP/plugin authority narrow. Documentation/diagnostic MCPs are not permission to change architecture, bypass tests, or publish.
- Authentication for GitHub and coding-agent CLIs is configured separately on the machine. Never write tokens into tracked files.

## 4. Bootstrap

Run the repository's pinned bootstrap, not an improvised dependency upgrade:

```bash
swift --version
xcodegen --version
# On macOS:
xcodegen generate
swift package resolve
```

Current durable state may legitimately say there is no agent-actionable coding campaign and only owner/device validation remains. Bootstrap must not turn that into invented implementation work.


## 5. Editor/LSP baseline

Use SourceKit-LSP/Swift language support. On macOS, let Xcode resolve platform SDK semantics; a Windows-only editor cannot certify UIKit/SwiftUI runtime behavior.

The editor is optional; the language servers are not. Agents should have diagnostics/type information available before editing non-trivial code.

## 6. Baseline verification

```bash
swift test
# On the qualified macOS/Xcode plane, run the repository CI/build scripts and only then the documented DEVICE_VALIDATION batch when authorized.
```

A fresh machine is considered **development-ready** only when the applicable non-external gates above pass. Hardware/device/signing/account gates may remain explicitly blocked if the repository already classifies them that way.

## 7. Fresh-agent instruction

Use this exact operating rule when handing the repository to a new agent:

> Read `ONBOARDING.md` first. Set up every applicable prerequisite, repository-local skill, MCP/plugin, dependency, browser/device/runtime tool, and validation gate described there. Then read the repository's durable agent state and only start implementation after preflight is green or a genuine environment blocker is recorded. Do not replace pinned tooling, skip gates, or invent work to compensate for a missing machine capability.
