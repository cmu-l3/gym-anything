# JFrog Artifactory Environment — Evidence Documentation

## Environment Overview

- **Artifactory version**: OSS 7.77.3 (Open Source Edition)
- **Backend database**: PostgreSQL 13
- **Delivery**: Docker Compose inside QEMU VM
- **Default credentials**: `admin` / `password`
- **UI URL**: `http://localhost:8082`

## Test Results

### Boot Test (Verified 2026-02-21)

1. **Docker containers**: Running successfully
   - `artifactory` (port 8081/8082)
   - `artifactory-postgresql`

2. **Artifactory accessibility**: HTTP 200 on `/artifactory/api/system/ping`

3. **Firefox**: Opens and displays the Artifactory login page at `http://localhost:8082/ui/login/`

4. **Login**: Credentials `admin` / `password` accepted, dashboard loads correctly

### Screenshots

#### Environment-level screenshots

| File | Description |
|------|-------------|
| `01_login_page.png` | Artifactory login page (state agents see at task start) |
| `02_dashboard_after_login.png` | Post-login dashboard with onboarding wizard (first login) |

#### Per-task initial state screenshots (1920×1080, captured from live VM)

Each screenshot was captured inside the VM immediately after the task's `setup_task.sh` ran,
showing the exact Firefox UI state the agent sees at the start of the task.

| File | Task | Starting page |
|------|------|---------------|
| `create_local_maven_repo_initial.png` | create_local_maven_repo | `/ui/admin/repositories` |
| `create_local_npm_repo_initial.png` | create_local_npm_repo | `/ui/admin/repositories` |
| `create_local_pypi_repo_initial.png` | create_local_pypi_repo | `/ui/admin/repositories` |
| `create_remote_repo_initial.png` | create_remote_repo | `/ui/admin/repositories` |
| `create_virtual_repo_initial.png` | create_virtual_repo | `/ui/admin/repositories` |
| `upload_artifact_initial.png` | upload_artifact | `/ui/repos/tree/General/example-repo-local` |
| `add_user_initial.png` | add_user | `/ui/admin/security/users` |
| `create_group_initial.png` | create_group | `/ui/admin/security/groups` |
| `set_permission_target_initial.png` | set_permission_target | `/ui/admin/security/permissions` |
| `create_access_token_initial.png` | create_access_token | `/ui/admin/security/access-tokens` |

## Known Behaviors

### Onboarding Wizard
On first login after a fresh environment reset, Artifactory shows a "Welcome To JFrog Platform" onboarding wizard. Agents should:
1. Close the Firefox "Save Password?" dialog (click "Not now")
2. Click "Skip" to dismiss the wizard
3. Navigate to the required admin section

### API Limitations (OSS 7.x)
Artifactory OSS 7.x restricts many REST API operations to Pro tier:
- **NOT available via REST API**: creating repos, users, groups, permission targets
- **Available via REST API**: GET operations (list repos, users, groups), artifact upload/download
- **Available via UI**: all management operations (creating repos, users, groups, permissions)

This means:
- All 10 tasks are implemented as **UI-based tasks** (agents use Firefox to interact)
- Verifiers use **GET REST API** calls (which work in OSS) to verify results
- Setup scripts do **not** pre-create repos/users/groups via REST API

### Default Repository
Artifactory OSS 7.x includes `example-repo-local` (Generic type) by default. This is the only repo present at task start for upload-related tasks.

## Task Inventory

### Original Tasks (Starter / Reference)

| Task | Description | Difficulty |
|------|-------------|------------|
| `create_local_maven_repo` | Create `team-releases` Maven local repo | medium |
| `create_local_npm_repo` | Create `npm-local` npm local repo | medium |
| `create_local_pypi_repo` | Create `pypi-local` PyPI local repo | medium |
| `create_remote_repo` | Create `maven-central-proxy` remote Maven repo proxying Maven Central | medium |
| `create_virtual_repo` | Create `generic-virtual` virtual repo including `example-repo-local` | hard |
| `upload_artifact` | Upload `commons-io-2.15.1.jar` to `example-repo-local` | medium |
| `add_user` | Create user `john_doe` | medium |
| `create_group` | Create group `developers` | medium |
| `set_permission_target` | Create `public-read` permission target granting `anonymous` Read access to `example-repo-local` | hard |
| `create_access_token` | Generate admin access token with description `CI/CD pipeline token` | medium |

### New Tasks (Very Hard / Realistic)

| Task | Occupation / Industry | Deliverables | Difficulty |
|------|----------------------|--------------|------------|
| `setup_release_pipeline_repos` | DevOps Engineer / Fintech (Meridian Payments) | Local Maven + Remote Maven proxy + Virtual Maven + Group + Permission | very_hard |
| `security_hardening_service_account` | Platform Security Engineer / Healthcare (Apex Healthcare) | Non-admin user + Group + Membership + NPM repo + Permission + Access token | very_hard |
| `federated_npm_registry_setup` | Frontend Platform Engineer / Retail (GlobalRetail Inc.) | NPM local + Remote + Virtual + User + Group + Membership + Permission | very_hard |
| `multi_team_pypi_infrastructure` | ML Infrastructure Engineer / Data Analytics (DataCore Technologies) | 2×PyPI local + Remote + Virtual + 2×Groups + 2×Permissions | very_hard |
| `tradex_platform_setup` | Artifact Repository Administrator / Capital Markets (Nexus Financial) | Generic repo + Maven repo + Group + 4-priv permission (2 repos) + Token + Artifact upload | very_hard |

### New Task Verification Summary

All new tasks use the `copy_from_env` pattern: `export_result.sh` (post_task hook) collects state
from the Artifactory REST API and writes `/tmp/<task_name>_result.json`; the verifier reads this file.

| Task | Do-nothing score | Offline mock full score | Pass threshold |
|------|-----------------|------------------------|----------------|
| `setup_release_pipeline_repos` | 0 | 100 | 60 |
| `security_hardening_service_account` | 0 | 100 | 60 |
| `federated_npm_registry_setup` | 0 | 100 | 60 |
| `multi_team_pypi_infrastructure` | 0 | 100 | 60 |
| `tradex_platform_setup` | 0 | 100 | 60 |

Live testing (2026-03-02): `tradex_platform_setup` do-nothing test: score=0, passed=False ✓
Screenshot: `tradex_platform_setup_initial.png`
