# Jenkins Environment Evidence Documentation

This directory contains evidence that the Jenkins environment was successfully set up, tested, and validated with real end-to-end task execution.

## Environment Overview

- **Application:** Jenkins CI/CD Server 2.541.1
- **Docker Image:** `jenkins/jenkins:lts-jdk21`
- **Pattern:** Docker-in-QEMU (same as OpenEMR, FreeScout, etc.)
- **Base Image:** `ubuntu-gnome-systemd_highres` (1920x1080)
- **Resources:** 4 CPU, 8GB RAM, networking enabled
- **Admin Credentials:** admin / Admin123!

## Boot Test Results

- **Boot time:** ~170 seconds total (VM boot + Docker + Jenkins startup)
- **Jenkins ready:** HTTP 200 within 27 seconds of container start
- **Firefox:** Window detected within 1 second of launch
- **SSH/VNC:** Accessible on dynamic ports

**Screenshot Evidence:** `screenshots/jenkins_initial_state.png` - Shows Jenkins dashboard with "Welcome to Jenkins!" message, "Create a job" button visible, Jenkins 2.541.1 running.

## Task Test Results (All Validated End-to-End via Interactive GUI)

### Task 1: create_freestyle_job - Score: 100/100

**Test method:** Interactive GUI via ask_cua.py + xdotool, then export_result.sh + verifier.py

**Interactive steps:**
1. Used ask_cua.py to locate "New Item" link on dashboard, clicked via xdotool
2. Typed "HelloWorld-Build" in job name field
3. Selected "Freestyle project" option
4. Used browser console JS (`document.getElementById('ok-button').click()`) to submit
5. Navigated to Build Steps, clicked "Add build step" > "Execute shell"
6. Typed `echo 'Hello from Jenkins!'` in command textarea
7. Used browser console JS (`document.querySelector('button[name=Submit]').click()`) to save

**Export result JSON:**
```json
{
    "initial_job_count": 0,
    "current_job_count": 1,
    "job_found": true,
    "job": {
        "name": "HelloWorld-Build",
        "build_command": "echo 'Hello from Jenkins!'"
    },
    "export_timestamp": "2026-02-12T04:04:02+00:00"
}
```

**Verifier output:** Score: 100/100 - all 4 criteria passed

### Task 2: create_pipeline_job - Score: 100/100

**Test method:** Interactive GUI via ask_cua.py + xdotool, then export_result.sh + verifier.py

**Interactive steps:**
1. Navigated to /view/all/newJob, typed "Maven-Build-Pipeline"
2. Selected "Pipeline" option via ask_cua.py coordinates
3. Used browser console JS to click OK
4. Clicked "Pipeline" tab in sidebar
5. Changed "Definition" dropdown to "Pipeline script from SCM"
6. Changed "SCM" dropdown to "Git"
7. Typed repository URL: `https://github.com/jenkins-docs/simple-java-maven-app`
8. Set Script Path to `jenkins/Jenkinsfile` via browser console JS
9. Used browser console JS to save

**Export result JSON:**
```json
{
    "initial_job_count": 0,
    "current_job_count": 1,
    "job_found": true,
    "job": {
        "name": "Maven-Build-Pipeline",
        "type": "WorkflowJob",
        "scm_url": "https://github.com/jenkins-docs/simple-java-maven-app",
        "script_path": "jenkins/Jenkinsfile"
    },
    "export_timestamp": "2026-02-12T04:45:02+00:00"
}
```

**Verifier output:** Score: 100/100 - all 6 criteria passed (job_exists, correct_name, correct_type, has_scm, correct_repo, correct_script_path)

### Task 3: trigger_build - Score: 100/100

**Test method:** Setup script created Test-Build-Job, interactive GUI click on "Build Now", then export_result.sh + verifier.py

**Interactive steps:**
1. setup_task.sh created "Test-Build-Job" via REST API
2. Navigated to /job/Test-Build-Job/ in Firefox
3. Used ask_cua.py to locate "Build Now" link, clicked via xdotool
4. Waited for build completion (5 seconds)
5. Refreshed page to confirm build #1 SUCCESS

**Export result JSON:**
```json
{
    "job_exists": true,
    "build_triggered": true,
    "build_count": 1,
    "initial_build_count": 0,
    "last_build": {
        "number": 1,
        "result": "SUCCESS",
        "building": false,
        "url": "http://localhost:8080/job/Test-Build-Job/1/",
        "duration_ms": 2032,
        "timestamp": 1770869485896
    },
    "export_timestamp": "2026-02-12T04:13:51+00:00"
}
```

**Verifier output:** Score: 100/100 - all 4 criteria passed

## Screenshots (from Interactive GUI Testing)

| File | Description |
|------|-------------|
| `jenkins_initial_state_cua.png` | Jenkins dashboard after boot (Welcome page) |
| `jenkins_new_item_page_cua.png` | New Item creation page |
| `jenkins_freestyle_name_entered.png` | Freestyle job name typed |
| `jenkins_freestyle_command_entered.png` | Shell command entered in build step |
| `jenkins_freestyle_saved.png` | Freestyle job saved |
| `jenkins_pipeline_name_entered.png` | Pipeline job name typed |
| `jenkins_pipeline_scm_configured.png` | SCM URL entered for pipeline |
| `jenkins_pipeline_saved.png` | Pipeline job saved |
| `jenkins_build_complete.png` | Build triggered and completed with SUCCESS |
| `jenkins_dashboard_with_jobs.png` | Dashboard showing all jobs (trigger_build start state) |

## Bugs Found and Fixed During Testing

1. **`set -e` in install script** - Docker pull failures would abort entire script. Removed `set -e`.
2. **Named Docker volume** - init.groovy.d files weren't accessible inside container. Changed to bind mount.
3. **`su - ga -c` in task scripts** - Fails with "Authentication failure" when script already runs as ga. Removed wrapper.
4. **CSRF 403 on job creation** - REST API needs cookie jar for CSRF. Added `-c`/`-b` cookie handling.
5. **Build result "null"** - Job-level API doesn't include `result` field. Changed to build-level API (`/lastBuild/api/json`).
6. **Missing plugins** - Skipping setup wizard means NO plugins installed. Added explicit plugin installation in post_start.
7. **Missing imagemagick** - `import -window root` needs imagemagick package. Added to install script.

## Key Implementation Details

### CSRF Token Handling
Jenkins requires cookie-based CSRF protection. The crumb obtained from `/crumbIssuer/api/json` must be sent with the same session cookie:
```bash
# Get crumb WITH cookie jar
curl -s -u admin:Admin123! -c /tmp/cookies "$JENKINS_URL/crumbIssuer/api/json"
# Use crumb WITH same cookie jar
curl -u admin:Admin123! -b /tmp/cookies -H "Jenkins-Crumb: VALUE" -X POST ...
```

### Build-Level vs Job-Level API
- Job-level API (`/job/NAME/api/json`): Returns `lastBuild.number` but NOT `result` or `building`
- Build-level API (`/job/NAME/lastBuild/api/json`): Returns full details including `result`, `building`, `duration`

### Plugin Installation
When setup wizard is skipped (`-Djenkins.install.runSetupWizard=false`), NO plugins are installed. Must install explicitly:
```bash
java -jar jenkins-cli.jar -s URL -auth admin:Admin123! install-plugin workflow-aggregator git pipeline-stage-view
java -jar jenkins-cli.jar -s URL -auth admin:Admin123! safe-restart
```

---

## New Task Test Results (5 Hard/Very-Hard Tasks Added 2026-03-02)

The following 5 new tasks were tested on 2026-03-02 using `test_new_jenkins_tasks.py`.
Each task passed Phase 4 scaffolding validation (do-nothing test returns score=0, passed=False).

### Task 6: debug_broken_pipelines — Do-Nothing Score: 0/100 ✓

**Test method:** Loaded environment, ran export immediately (no agent actions), verified verifier.
**Setup:** Created 3 broken pipeline jobs (payment-service-ci, user-auth-service, inventory-api-build) + credential github-access-token.
**Export result (do-nothing):**
```json
{"payment_service_ci": {"result": "FAILURE", "new_build_triggered": false},
 "user_auth_service":  {"result": "FAILURE", "new_build_triggered": false},
 "inventory_api_build":{"result": "FAILURE", "new_build_triggered": false}}
```
**Verifier:** Score=0, Passed=False — "still failing (result=FAILURE) (0/30)" for each job.
**Evidence:** `debug_broken_pipelines/debug_broken_pipelines_evidence.json`

### Task 7: configure_release_pipeline — Do-Nothing Score: 0/100 ✓

**Test method:** Loaded environment (clean slate), ran export immediately, verified verifier.
**Setup:** Removes webapp-release-pipeline if it exists; clean slate confirmed.
**Export result (do-nothing):** `{"job_exists": false, "has_deploy_env_param": false, ...}`
**Verifier:** Score=0, Passed=False — "Job 'webapp-release-pipeline' does not exist"
**Evidence:** `configure_release_pipeline/configure_release_pipeline_evidence.json`
**Bug fixed:** Bash `false`/`true` interpolated into Python heredoc — changed to `"$VAR" == "true"` pattern.

### Task 8: multi_service_build_orchestration — Do-Nothing Score: 0/100 ✓

**Test method:** Loaded environment, ran export immediately on the 3 stub jobs, verified verifier.
**Setup:** Creates auth-service, api-gateway, e2e-test-suite stub pipelines.
**Export result (do-nothing):** All 3 jobs exist but no downstream triggers, no BUILD_ID params, no view.
**Verifier:** Score=0, Passed=False — "auth-service does not trigger api-gateway (0/25)..." etc.
**Evidence:** `multi_service_build_orchestration/multi_service_build_orchestration_evidence.json`
**Bug fixed:** Same `$VIEW_EXISTS` bash-to-Python boolean interpolation fixed.

### Task 9: credential_rotation_pipeline — Do-Nothing Score: 0/100 ✓

**Test method:** Loaded environment, ran export immediately, verified verifier.
**Setup:** Creates old-db-password + deprecated-api-key credentials and data-pipeline job.
**Export result (do-nothing):** New creds don't exist, pipeline still references old creds.
**Verifier:** Score=0, Passed=False — "Credential 'db-production-creds' not found (0/20)..." etc.
**Evidence:** `credential_rotation_pipeline/credential_rotation_pipeline_evidence.json`

### Task 10: project_ci_environment_setup — Do-Nothing Score: 0/100 ✓

**Test method:** Loaded environment (clean slate), ran export immediately, verified verifier.
**Setup:** Removes pre-existing alpha-* jobs, Project-Alpha CI view, npm-registry-token credential.
**Export result (do-nothing):**
```json
{"alpha_backend_build": {"exists": false, ...}, "alpha_frontend_build": {"exists": false, ...},
 "npm_registry_token": {"exists": false, ...}, "view_project_alpha_ci": {"exists": false, ...}}
```
**Verifier:** Score=0, Passed=False — "Job 'alpha-backend-build' not found (0/25)..." etc.
**Evidence:** `project_ci_environment_setup/project_ci_environment_setup_evidence.json`

---

## Screenshots (New Tasks)

Each new task directory under `evidence/` contains:
- `<task>_start.png` — Screenshot from setup_task.sh showing Jenkins dashboard in starting state.

---

## Real Data Sources

- **Docker Image:** `jenkins/jenkins:lts-jdk21` (official, 10M+ pulls)
- **GitHub Repository:** `jenkins-docs/simple-java-maven-app` (official Jenkins tutorial, 100+ stars)
- **Groovy Init Script:** Based on Jenkins Configuration as Code patterns

## Verification Pattern

All tasks use two-part verification:
1. `export_result.sh` (runs in VM) - Queries Jenkins REST API, writes JSON to `/tmp/<task>_result.json`
2. `verifier.py` (runs on host) - Uses `copy_from_env()` to get JSON, scores multiple criteria with subscores
