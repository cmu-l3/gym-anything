# Review Untrusted Workspace Task

**Difficulty**: 🟡 Medium  
**Skills**: Security review, workspace trust, configuration inspection, documentation  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Perform a security review of an untrusted workspace by inspecting configuration files for malicious patterns, then document your findings and create a security checklist.

## Scenario

A community contributor submitted a PR to your open-source project. You've cloned their fork to review the changes. When you open the workspace in VSCode, you see a "Do you trust the authors?" warning banner because the workspace is in Restricted Mode.

You need to carefully inspect the workspace configuration files (`.vscode/tasks.json`, `.vscode/settings.json`, `package.json`) for security risks before deciding whether to trust the workspace.

## Expected Workflow

1. Open the workspace at `/home/ga/workspace/untrusted_pr`
2. Notice the VSCode trust warning (Restricted Mode banner)
3. Manually inspect `.vscode/tasks.json` for suspicious commands
4. Inspect `package.json` for suspicious scripts (especially `postinstall`)
5. Inspect `.vscode/settings.json` and `.vscode/extensions.json`
6. Create `SECURITY_REVIEW.md` documenting your findings
7. Create `TRUST_CHECKLIST.md` with reusable security patterns

## Verification

Checks for:
1. `SECURITY_REVIEW.md` exists with comprehensive content
2. Review mentions all key files (tasks.json, settings.json, package.json)
3. Review identifies suspicious patterns (curl | bash, postinstall script)
4. Review includes a clear trust decision
5. `TRUST_CHECKLIST.md` exists with at least 5 security pattern categories

**Pass Threshold**: 70%