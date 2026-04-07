# Firefox Memory Leak Audit (`firefox_memory_leak_audit@1`)

## Overview
Debugging memory leaks in web applications is a critical task for front-end developers, as these leaks often cause performance degradation and eventually crash the browser tab. This task evaluates the agent's ability to use the Firefox Developer Tools Memory panel to capture heap snapshots, interact with a complex web application to trigger a specific memory leak, and save the diagnostic artifacts for analysis.

## Rationale
**Why this task is valuable:**
- **Browser-Specific Tooling:** Requires proficient navigation of the Firefox DevTools Memory panel.
- **Developer Workflow Execution:** Simulates a real-world debugging workflow involving context switching between DevTools and the web view.
- **Artifact Generation:** Produces complex `.fxsnapshot` files that objectively prove task success.

**Real-world Context:** A QA tester has reported Bug #402: a severe memory leak in the company's internal photo gallery application. The lead developer has asked you to reproduce the bug in Firefox and provide baseline and post-leak memory snapshots.

## Task Description

**Goal:** Capture a baseline memory snapshot, trigger the reported memory leak in the local photo gallery app, and capture a second snapshot containing the leaked memory.

**Starting State:**
- Firefox is running and maximized, open to `http://localhost:8080/`.

**Expected Actions:**
1. Open the Firefox Developer Tools and navigate to the "Memory" panel.
2. Click "Take Snapshot" to capture the initial memory state.
3. Save the snapshot exactly as `~/Documents/baseline.fxsnapshot`.
4. Switch focus to the web page and trigger the leak:
   - Click the "Load High-Res Gallery" button.
   - Wait a moment for the image grid to fully render.
   - Click the "Destroy Gallery" button.
5. Switch back to the DevTools Memory panel and take a second memory snapshot.
6. Save this second snapshot exactly as `~/Documents/leaked.fxsnapshot`.

**Final State:**
- Two heap snapshot files exist in `~/Documents/`.
- `leaked.fxsnapshot` is significantly larger than the baseline.

## Verification Strategy

### Primary Verification: Artifact Size Comparison
- Verifies `baseline.fxsnapshot` and `leaked.fxsnapshot` exist.
- Compares sizes: `leaked.fxsnapshot` must be significantly larger (at least 1MB difference).

### Secondary Verification: VLM Trajectory
- Visual Language Model confirms the DevTools Memory panel was opened.
- VLM confirms the gallery application buttons were clicked.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Baseline Snapshot | 20 | `baseline.fxsnapshot` exists |
| Leaked Snapshot | 20 | `leaked.fxsnapshot` exists |
| Leak Verification | 30 | Leaked snapshot is substantially larger than baseline |
| Trajectory: DevTools | 15 | VLM confirms Memory panel usage |
| Trajectory: Interaction | 15 | VLM confirms button clicks |
| **Total** | **100** | |

Pass Threshold: 70 points