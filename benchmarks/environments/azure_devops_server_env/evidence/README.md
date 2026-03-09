# Azure DevOps Server Environment - Evidence Documentation

All evidence in this directory was captured from a single environment instance on 2026-02-24.
Install/setup logs are from the initial boot sequence; task screenshots and verification
outputs are from the running VM after checkpoint reload. This is normal for the Gym-Anything
framework which uses QEMU savevm checkpoints. The end state is consistent across all evidence.

## Environment Overview

- **Application**: Azure DevOps Server 2022 Express Edition
- **Base Image**: `windows-11` (Windows 11 QEMU VM)
- **Resources**: 10GB RAM, 4 CPU cores, network enabled
- **Project**: TailwindTraders (Agile process template)
- **URL**: `http://localhost/DefaultCollection`
- **Auth**: Windows NTLM (automatic with Docker user)

## Verification Checklist

### Installation (pre_start)

- [x] Azure DevOps Server 2022 Express downloaded (3.3MB web installer)
- [x] Silent install completed (exit code 0)
- [x] SQL Server 2022 Express installed via unattended config
- [x] 8-step configuration completed: IIS, SQL, databases, services, collection, website
- [x] TFSJobAgent service running
- [x] SQL Server service running
- [x] Web interface responding (HTTP 200)

**Log snippet** (from `pre_start_install_log.txt`):
```
Installer exit code: 0
Azure DevOps Server binaries installed successfully.
...
ServerConfiguration completed successfully.
...
Service 'TFSJobAgent': Running
SQL Server service: Running
Azure DevOps web interface is ready! (HTTP 200)
```

### Setup (post_start)

- [x] Edge browser policies configured (NTLM auth, suppress first-run, suppress restore dialog)
- [x] OneDrive disabled, uninstalled, and toast notifications suppressed
- [x] TailwindTraders project created (Agile process template)
- [x] 4 sprints created (Sprint 1-4, Jan-Mar 2026) and assigned to team
- [x] Default iterations (Iteration 1/2/3) removed from team
- [x] 15 work items seeded (7 User Stories, 4 Bugs, 4 Tasks) — IDs 1-15
- [x] Git repository initialized with Flask inventory API (9 files on main branch)
- [x] Feature branch `feature/add-search-endpoint` created with search.py commit
- [x] Edge browser warm-up completed

**Work Items** (from `work_items_verification.txt`):
```
Total work items found: 15
[1] User Story - Implement product inventory search (Sprint 1)
[2] User Story - Add real-time stock level notifications (Sprint 2)
[3] User Story - Create supplier management module (Sprint 2)
[4] User Story - Implement barcode scanning (Sprint 3)
[5] User Story - Design REST API rate limiting (Sprint 1)
[6] Bug - Product price calculation incorrect (Sprint 1)
[7] Bug - API 500 error with special characters (Sprint 1)
[8] Bug - Inventory count negative (Sprint 1)
[9] Bug - Dashboard chart blank (Sprint 2)
[10] Task - PostgreSQL migration scripts (Sprint 1)
[11] Task - CI/CD pipeline (Sprint 1)
[12] Task - Integration tests (Sprint 1)
[13] User Story - Product import/export (Sprint 3)
[14] User Story - Multi-warehouse support (Sprint 3)
[15] Task - Redis caching layer (Sprint 2)
```

**Git Repository** (from `environment_state_verification.txt`):
```
Repos: 1
  - TailwindTraders (default branch: refs/heads/main)
    Branch: refs/heads/feature/add-search-endpoint
    Branch: refs/heads/main
```

**Team Iterations** (from `environment_state_verification.txt`):
```
Team iterations: 4
  - Sprint 1 (2026-01-06 to 2026-01-19)
  - Sprint 2 (2026-01-20 to 2026-02-02)
  - Sprint 3 (2026-02-03 to 2026-02-16)
  - Sprint 4 (2026-02-17 to 2026-03-02)
```

### Task Start States (verified with visual_grounding MCP tool)

#### Task 1: create_user_story
- **Screenshot**: `task1_create_user_story.png`
- **Start state**: Backlog page with 7 User Stories listed, "+ New Work Item" button visible
- **URL**: `_backlogs/backlog/TailwindTraders%20Team/Stories`
- **No popups or overlays**

#### Task 2: create_bug_report
- **Screenshot**: `task2_create_bug_report.png`
- **Start state**: Work Items page showing recently updated items, filter controls, "+ New Work Item" button
- **URL**: `_workitems`
- **No popups or overlays**

#### Task 3: resolve_bug_work_item
- **Screenshot**: `task3_resolve_bug_work_item.png`
- **Start state**: Backlog page with 7 User Stories listed
- **URL**: `_backlogs/backlog/TailwindTraders%20Team/Stories`
- **No popups or overlays**
- **Note**: Originally used Kanban board view, but Azure DevOps Server doesn't render API-created items on the board until the board is manually initialized through the UI. Changed to Backlogs view which reliably shows all items.

#### Task 4: create_pull_request
- **Screenshot**: `task4_create_pull_request.png`
- **Start state**: Repos page with source files listed, "Create a pull request" banner visible for feature branch
- **URL**: `_git/TailwindTraders`
- **No popups or overlays**

### Desktop State
- **Screenshot**: `azure_devops_desktop.png`
- **State**: Windows 11 desktop with PyAutoGUI server terminal (1280x720), no OneDrive or notification popups

#### Task 5: sprint_health_audit
- **Screenshot**: `sprint_health_audit_screenshot.png`
- **Evidence**: `sprint_health_audit_evidence.json`
- **Start state**: Sprint 1 Taskboard with 8 work items (37 story points), no team capacity configured, no items deferred
- **URL**: `_sprints/taskboard/TailwindTraders%20Team/TailwindTraders/Sprint%201`
- **No popups or overlays**

#### Task 6: ci_pipeline_for_flask_api
- **Screenshot**: `ci_pipeline_for_flask_api_screenshot.png`
- **Evidence**: `ci_pipeline_for_flask_api_evidence.json`
- **Start state**: Pipelines page empty ("Create your first Pipeline"), TailwindTraders repo has Flask API code (app.py, models.py, routes.py, requirements.txt, tests/test_app.py)
- **URL**: `_build`
- **No pipelines exist**

#### Task 7: work_item_triage_and_query
- **Screenshot**: `work_item_triage_and_query_screenshot.png`
- **Evidence**: `work_item_triage_and_query_evidence.json`
- **Start state**: 3 Priority 1 bugs (IDs 6,7,8) unassigned, in TailwindTraders\Uncategorized area, no tags. No "Critical Bug Backlog" shared query.
- **URL**: `_workitems`
- **No popups or overlays**

#### Task 8: test_plan_sprint2
- **Screenshot**: `test_plan_sprint2_screenshot.png`
- **Evidence**: `test_plan_sprint2_evidence.json`
- **Start state**: Test Plans welcome/empty page — no test plans exist. Sprint 2 has user stories #2 and #3 as targets for linking.
- **URL**: `_testManagement`
- **Note**: Access level warning visible (basic access); test plan creation still works

#### Task 9: branch_policy_and_pr_merge
- **Screenshot**: `branch_policy_and_pr_merge_screenshot.png`
- **Evidence**: `branch_policy_and_pr_merge_evidence.json`
- **Start state**: PR #1 "Add JWT authentication middleware for inventory API" is Active with 0 reviewers, 0 linked work items, and no branch policies on main
- **URL**: `_git/TailwindTraders/pullrequest/1`
- **No popups or overlays**

## Known Limitations

1. **Kanban board doesn't show API-created items**: Work items created via the REST API don't appear on the Kanban board until the board is manually initialized through the browser UI. The Backlogs view works correctly. This is a known Azure DevOps Server behavior.

2. **Post-start script not fully idempotent for Git**: The Git repository initialization checks for existing refs and skips if already present, but cannot undo a partial push.

## Files in this directory

| File | Description |
|------|-------------|
| `README.md` | This documentation |
| `azure_devops_desktop.png` | Windows 11 desktop screenshot |
| `task1_create_user_story.png` | Task 1 start state screenshot |
| `task2_create_bug_report.png` | Task 2 start state screenshot |
| `task3_resolve_bug_work_item.png` | Task 3 start state screenshot |
| `task4_create_pull_request.png` | Task 4 start state screenshot |
| `pre_start_install_log.txt` | Full pre_start hook transcript |
| `post_start_setup_log.txt` | Full post_start hook transcript |
| `task_create_user_story_log.txt` | Task 1 setup log |
| `task_create_bug_report_log.txt` | Task 2 setup log |
| `task_resolve_bug_work_item_log.txt` | Task 3 setup log |
| `task_create_pull_request_log.txt` | Task 4 setup log |
| `work_items_verification.txt` | Work items API verification output |
| `environment_state_verification.txt` | Full environment state check |
| `sprint_health_audit_screenshot.png` | Task 5 start state screenshot |
| `sprint_health_audit_evidence.json` | Task 5 evidence: Sprint 1 work items and story points |
| `ci_pipeline_for_flask_api_screenshot.png` | Task 6 start state screenshot |
| `ci_pipeline_for_flask_api_evidence.json` | Task 6 evidence: empty pipelines, repo file structure |
| `work_item_triage_and_query_screenshot.png` | Task 7 start state screenshot |
| `work_item_triage_and_query_evidence.json` | Task 7 evidence: P1 bugs unassigned and miscategorized |
| `test_plan_sprint2_screenshot.png` | Task 8 start state screenshot |
| `test_plan_sprint2_evidence.json` | Task 8 evidence: no test plans, Sprint 2 user stories |
| `branch_policy_and_pr_merge_screenshot.png` | Task 9 start state screenshot |
| `branch_policy_and_pr_merge_evidence.json` | Task 9 evidence: PR #1 active, no policies, no reviewers |
