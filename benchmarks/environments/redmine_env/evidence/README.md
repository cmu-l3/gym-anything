# Redmine Environment — Evidence Documentation

## Environment Summary

- **Application**: Redmine 6.0 (open-source project management)
- **Deployment**: Docker-in-QEMU (redmine:6.0-bookworm + postgres:16)
- **Port**: 3000
- **Admin credentials**: `admin` / `Admin1234!`
- **REST API enabled**: Yes (via seed script)

## Seeded Data

| Entity | Count |
|--------|-------|
| Users | 7 (+ admin = 8 total) |
| Projects | 3 |
| Issues | 23 |
| Journals (comments) | 6 |
| Time entries | 7 |

### Projects
1. **Phoenix E-Commerce Platform** (`phoenix-ecommerce`) — Frontend/backend web app
2. **Mobile Application v2** (`mobile-app-v2`) — React Native cross-platform app
3. **Infrastructure & DevOps** (`infra-devops`) — CI/CD, Kubernetes, security

### Users
- `alice.chen` — Manager
- `bob.walker` — Developer
- `carol.santos` — Developer
- `david.kim` — Developer
- `eve.martinez` — Reporter
- `frank.nguyen` — Reporter
- `grace.lee` — Developer

## Screenshots

### Task Start States (verified working, logged in as admin)

| File | Description |
|------|-------------|
| `01_create_bug_issue_task_start.png` | create_bug_issue: New issue form, Phoenix E-Commerce Platform, Bug tracker |
| `02_add_issue_comment_task_start.png` | add_issue_comment: Issue #18 (CI/CD migration, In Progress) |
| `03_close_issue_task_start.png` | close_issue: Issue #22 (SSL certificate, Resolved) |
| `04_update_issue_status_task_start.png` | update_issue_status: Issue #11 (Biometric auth, New) |
| `05_log_time_on_issue_task_start.png` | log_time_on_issue: Issue #13 (Offline mode, New) |

### Additional Evidence

| File | Description |
|------|-------------|
| `02_issues_list.png` | Redmine issues list overview |
| `02_projects_list.png` | Redmine projects list showing 3 seeded projects |
| `03_phoenix_issues_list.png` | Phoenix E-Commerce Platform issues list |
| `04_biometric_issue_11.png` | Issue #11 detail page |
| `05_cicd_issue_18.png` | Issue #18 detail page |
| `06_ssl_issue_22.png` | Issue #22 detail page |
| `07_offline_issue_13.png` | Issue #13 detail page |

## Task Verification

### Issue API Check (via REST API with key)
```
Issue #11 (update_issue_status): Status=New    | Biometric authentication fails after app backgrounding on Android 14
Issue #18 (add_issue_comment):   Status=In Progress | Migrate CI/CD from Jenkins to GitHub Actions
Issue #22 (close_issue):         Status=Resolved   | SSL certificate for api.devlabs.io expires in 14 days
Issue #13 (log_time_on_issue):   Status=New    | Offline mode: local changes lost on sync conflict
```

### Seed Result File
Located at `/tmp/redmine_seed_result.json` (also copied to `/home/ga/redmine_seed_result.json`)

## Environment Setup Notes

### Key Technical Details
- `docker-compose-v2` package (NOT `docker-compose-plugin`) on Ubuntu 22.04 Jammy
- `SECRET_KEY_BASE` must be passed explicitly to `docker exec` (not inherited from docker-compose env)
- Redmine version validation: closed versions cannot be assigned to issues — create as 'open', then close after issue creation
- Firefox profile at `/home/ga/.mozilla/firefox/default.profile/`
- task_utils.sh uses `XAUTHORITY=/home/ga/.Xauthority` for all display commands

### Setup Times (typical)
- `pre_start` (Docker install): ~60s
- `post_start` (Redmine setup + seed): ~90-120s
- `pre_task` (Firefox launch + navigate): ~29s
- From post_start cache (savevm): ~57s total (28s VM boot + 29s pre_task)
- Total cold boot: ~3-5 min

### Login Mechanism
- `ensure_redmine_logged_in()` in `task_utils.sh` uses xdotool GUI automation
- Starts Firefox at login URL via `su - ga -c "...firefox..."`
- Fills username/password fields with xdotool clicks + typing
- Navigates to target URL via address bar (Ctrl+L)
- Works reliably from root hook context (`sudo -E bash -lc`)

### Seed Performance
- Admin password: `admin` → `Admin1234!` (disabled `must_change_passwd`)
- REST API enabled via `Setting` model
- Versions created 'open', then closed at end of seed to satisfy validation
- 23 issues seeded (not 24 because one version assignment was skipped)

## New Tasks — Do-Nothing Test Results (2026-03-07)

All 5 new very_hard tasks were live-tested against the running QEMU environment.
Do-nothing (agent takes no actions) must yield `score=0, passed=False`.

| Task | Score | Passed | Status |
|------|-------|--------|--------|
| `release_blocking_triage` | 0 | False | PASS |
| `security_incident_reopening` | 0 | False | PASS |
| `cross_project_workload_audit` | 0 | False | PASS |
| `milestone_replanning` | 0 | False | PASS |
| `sprint_closeout_mobile_v2` | 0 | False | PASS |

Evidence files per task: `<task>_start.png`, `<task>_do_nothing_result.json`, `<task>_evidence.json`

### New Task Seeded Data (discovered from live runs)

| Issue | ID | Project | Seeded State |
|-------|----|---------|--------------|
| Payment gateway timeout | #2 | phoenix-ecommerce | In Progress, Urgent |
| Login button unresponsive on mobile Safari | #1 | phoenix-ecommerce | New, Bob Walker, due 2026-02-26 |
| SSL certificate expires in 14 days | #22 | infra-devops | Resolved, Urgent |
| Implement centralized log aggregation | #21 | infra-devops | New, Carol Santos, 60h estimated, Q2 2025 Goals |
| Migrate CI/CD to GitHub Actions | #19 | infra-devops | High priority (K8s-related) |
| Dark mode: tab bar icons inverted | #17 | mobile-app-v2 | Resolved, v1.9 Legacy |
| Offline mode: local changes lost | #13 | mobile-app-v2 | New, v2.0 Release |
| Push notifications not delivered | #12 | mobile-app-v2 | In Progress, 2.5h Development logged |

## Task Descriptions

### 1. `create_bug_issue` (Easy)
Start state: Firefox at `/projects/phoenix-ecommerce/issues/new` (redirect to login)
Goal: Log in, create Bug with Subject="Cart total incorrect after applying coupon code", Priority=High, Assignee=Bob Walker, Category=Backend

### 2. `update_issue_status` (Easy)
Start state: Firefox at issue #11 (Biometric auth, Status=New)
Goal: Log in, change status from New → In Progress, add note

### 3. `add_issue_comment` (Easy)
Start state: Firefox at issue #18 (CI/CD migration, Status=In Progress)
Goal: Log in, add a specific comment about CI/CD migration phase completion

### 4. `close_issue` (Easy)
Start state: Firefox at issue #22 (SSL certificate, Status=Resolved)
Goal: Log in, change status from Resolved → Closed, add closing note

### 5. `log_time_on_issue` (Easy)
Start state: Firefox at issue #13 (Offline mode, Status=New)
Goal: Log in, log 3.5 hours of Development activity with a comment

---

## New Very Hard Tasks

### 6. `release_blocking_triage` (Very Hard) — Engineering Manager
**Occupation**: Software Engineering Manager (Computer and Mathematical)
**Start state**: Firefox at phoenix-ecommerce issues list
**Actions required**:
1. Find all Urgent/Immediate open issues in v1.0 Launch — add "RELEASE BLOCKER: Must be resolved before v1.0 Launch." comment; change New→In Progress if applicable
2. Reassign login button issue from bob.walker to carol.santos; set due_date = v1.0 Launch milestone date; add reassignment comment
**Verification** (100pts, pass≥60):
- Payment gateway has RELEASE BLOCKER comment (25pts)
- Login button has reassignment comment mentioning carol/due date (25pts)
- Login button assignee = Carol Santos (25pts)
- Login button due_date = v1.0 Launch due date 2026-04-05 (25pts)
**Do-nothing result**: `release_blocking_triage_do_nothing_result.json` — score=0 ✓

### 7. `security_incident_reopening` (Very Hard) — DevOps/Security Engineer
**Occupation**: DevOps / Security Engineer
**Start state**: Firefox at infra-devops issues list
**Actions required**:
1. Reopen SSL cert issue (Resolved→In Progress), escalate priority to Immediate, add REOPENED comment
2. Create new Bug issue "Automate SSL certificate renewal with certbot" (High, carol.santos, Q1 2025 Goals)
3. Add cross-reference comment to certbot issue linking to SSL cert issue
4. Log 2.0h Development on SSL cert issue
**Verification** (100pts, pass≥60):
- SSL cert status = In Progress (20pts)
- SSL cert priority = Immediate (20pts)
- SSL cert has REOPENED comment (20pts)
- New certbot issue created (carol.santos, High, Q1 2025 Goals) (20pts)
- ≥2.0h Development logged on SSL cert (20pts)
**Do-nothing result**: `security_incident_reopening_do_nothing_result.json` — score=0 ✓

### 8. `cross_project_workload_audit` (Very Hard) — Project Manager
**Occupation**: Project Manager (Computer and Mathematical)
**Start state**: Firefox at Redmine home (all projects)
**Actions required**:
1. Count open issues per developer across ALL projects, identify most overloaded
2. Reassign "Implement centralized log aggregation with OpenSearch" (carol.santos, 60h, New) to bob.walker or grace.lee
3. Add workload-balancing comment explaining the reassignment
4. Log ≥0.5h Design activity on the issue
**Verification** (100pts, pass≥50):
- Issue reassigned away from Carol Santos (25pts)
- Reassigned to bob.walker or grace.lee (25pts)
- Has workload/rebalancing comment (25pts)
- ≥0.5h Design time logged (25pts)
**Do-nothing result**: `cross_project_workload_audit_do_nothing_result.json` — score=0 ✓

### 9. `milestone_replanning` (Very Hard) — Project Manager
**Occupation**: Program/Portfolio Manager (Computer and Mathematical)
**Start state**: Firefox at infra-devops issues list
**Actions required**:
1. Move log aggregation issue from Q2 2025 Goals → Q1 2025 Goals milestone; escalate priority to High
2. Escalate K8s monitoring issue priority to Immediate; add REPRIORITIZED comment
3. Create scope change notification Feature issue (alice.chen, infra-devops, Low, Q1 2025 Goals)
**Verification** (100pts, pass≥60):
- Log agg version = Q1 2025 Goals (20pts)
- Log agg priority = High (20pts)
- K8s priority = Immediate (20pts)
- K8s has REPRIORITIZED comment (20pts)
- Scope change issue exists (assigned to alice.chen) (20pts)
**Do-nothing result**: `milestone_replanning_do_nothing_result.json` — score=0 ✓

### 10. `sprint_closeout_mobile_v2` (Very Hard) — Scrum Master
**Occupation**: Scrum Master / Project Manager (Computer and Mathematical)
**Start state**: Firefox at mobile-app-v2 issues list
**Actions required**:
1. Close dark mode bug (v1.9 Legacy, Resolved→Closed)
2. Defer offline sync issue (v2.0 Release→v2.1 Hotfix; add "Deferred" comment)
3. Log 1.5h Testing on push notif issue (grace.lee); change status→Resolved
4. Create sprint closeout Feature issue (Closed, v2.0 Release, alice.chen)
**Verification** (100pts, pass≥60):
- Dark mode status = Closed (20pts)
- Offline sync version = v2.1 Hotfix (20pts)
- Offline sync has Deferred comment (10pts)
- Push notif ≥1.5h Testing activity (25pts)
- Push notif status = Resolved (15pts)
- Closeout summary issue exists (10pts)
**Do-nothing result**: `sprint_closeout_mobile_v2_do_nothing_result.json` — score=0 ✓
