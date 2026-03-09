# Canvas LMS Environment - Evidence Documentation

## Environment Overview

This document provides evidence of the Canvas LMS environment setup and testing performed as part of the gym_anything framework.

## Environment Details

- **Environment ID**: canvas_lms_env@0.1
- **Base Image**: ubuntu-gnome-systemd_highres
- **Docker Image**: lbjay/canvas-docker (fat container with all services)
- **Resources**: 4 CPU, 10GB RAM

## Admin Credentials

- **Email**: canvas@example.edu
- **Password**: canvas-docker
- **API Token**: canvas-docker

## Known Issues and Reliability

### Canvas Startup Time

**IMPORTANT**: Canvas LMS requires 2-3 minutes to fully initialize after the Docker container starts. During this time, agents may encounter:

- "The connection was reset" errors in Firefox
- "Unable to connect" errors
- Pages loading indefinitely ("Waiting for localhost...")
- Blank Firefox windows

**Mitigation (Implemented)**:
- All `setup_task.sh` scripts now include a comprehensive health check (`ensure_canvas_ready_for_task`) that:
  1. Waits up to 120 seconds for Canvas HTTP endpoint to respond
  2. Ensures Firefox is running
  3. Refreshes the page to clear any connection errors
  4. Takes a screenshot only after Canvas is confirmed accessible

**Task Description Update**:
- All task descriptions now include: "Note: If Canvas shows a connection error or is loading slowly, wait a few seconds and refresh the page - the server may still be initializing."

### Historical Test Results

During initial testing (2026-02-01), the following reliability issues were observed:

| Test Episode | Initial State | Issue |
|--------------|---------------|-------|
| episode_20260201_141556 | Ubuntu desktop only | Firefox not open |
| episode_20260201_170143 | Login page loading | Page still loading (OK with delay) |
| episode_20260201_172301 | Login page ready | OK |
| episode_20260201_195319 | Blank page loading | Canvas not loaded |
| episode_20260201_200903 | "Connection reset" error | Canvas server unavailable |
| episode_20260201_220013 | "Unable to connect" error | Canvas server unavailable |

**Success Rate Before Fixes**: 2/6 (33%)

**Expected Success Rate After Fixes**: >90% (health check ensures Canvas is ready before task starts)

## Test Data Created

### Users (11 total)
| ID | Name | Login |
|----|------|-------|
| 1 | User (Admin) | canvas@example.edu |
| 34 | Jane Smith | jsmith |
| 35 | Michael Jones | mjones |
| 36 | Alice Wilson | awilson |
| 37 | Bob Brown | bbrown |
| 38 | Carlos Garcia | cgarcia |
| 39 | Diana Lee | dlee |
| 40 | Emily Patel | epatel |
| 41 | Frank Kim | fkim |
| 42 | Professor Anderson | teacher1 |
| 43 | Dr. Martinez | teacher2 |

### Courses (6 total after testing)
| Code | Name |
|------|------|
| BIO101 | Introduction to Biology |
| HIST201 | World History |
| CS110 | Computer Science Fundamentals |
| CHEM101 | Introduction to Chemistry |
| ENG101 | English Composition |
| DS101 | Introduction to Data Science (created during testing) |

### Enrollments (BASELINE: 9 enrollments - Emily Patel NOT in CS110)
| User | Course | Type |
|------|--------|------|
| Professor Anderson | BIO101 | TeacherEnrollment |
| Professor Anderson | CS110 | TeacherEnrollment |
| Dr. Martinez | HIST201 | TeacherEnrollment |
| Jane Smith | BIO101 | StudentEnrollment |
| Michael Jones | BIO101 | StudentEnrollment |
| Alice Wilson | BIO101 | StudentEnrollment |
| Bob Brown | HIST201 | StudentEnrollment |
| Carlos Garcia | HIST201 | StudentEnrollment |
| Diana Lee | HIST201 | StudentEnrollment |

**CRITICAL**: The checkpoint baseline must have **9 enrollments** with Emily Patel (epatel) NOT enrolled in CS110.
The enroll_student task requires adding her enrollment, so she must not be pre-enrolled.

The previous note "Emily Patel | CS110 | StudentEnrollment (created during testing)" was incorrect - this was
from manual testing AFTER the checkpoint, not IN the checkpoint baseline.

### Assignments (1 total after testing)
| ID | Title | Course | Points | State |
|----|-------|--------|--------|-------|
| 1 | Lab Report 1 | BIO101 | 100 | published |

## Verification Checklist

- [x] Docker container starts successfully (canvas-lms)
- [x] PostgreSQL database is accessible
- [x] Redis cache is running
- [x] Canvas web interface is accessible at http://localhost/
- [x] Login page renders correctly (after 2-3 minute initialization)
- [x] Test users created successfully (11 users)
- [x] Test courses created successfully (5 courses)
- [x] Enrollments created and activated (9 enrollments)
- [x] Pre-task health check implemented
- [x] Task descriptions updated with loading delay warning

## Verifier Security (Updated 2026-02-02)

### CRITICAL FIX: Secure Database Verification

**Previous Vulnerability (FIXED)**: Verifiers previously read JSON files from `/tmp/` that agents could manipulate. An adversarial agent could pass all tasks without completing them by creating fake result files.

**Solution Implemented**: All verifiers now use **direct database queries** executed by the verifier process, NOT agent-writable files. The verifier controls the SQL queries, making it impossible for agents to fake results.

**Key Changes**:
1. `exec_capture` function added to `env_info` in verification runner
2. Verifiers execute PostgreSQL queries directly via `docker exec canvas-lms psql ...`
3. VLM visual verification added as secondary check
4. Agent-writable JSON files are no longer trusted

### Verification Method

All verifiers now use hybrid verification:
1. **Primary**: Direct database queries (tamper-proof)
2. **Secondary**: VLM visual verification of final screenshots (bonus points)

## Verifier Criteria

### create_course (5 criteria, ALL required)
1. Course exists in database (direct query)
2. Course code matches "DS101" (case-insensitive)
3. Course name matches "Introduction to Data Science" (case-insensitive)
4. Course is in 'available' state (workflow_state = 'available')
5. Course was newly created (count increased from baseline of 5)

### create_assignment (6 criteria, ALL required)
1. Assignment exists in database (direct query)
2. Title matches "Lab Report 1" (case-insensitive)
3. Points = 100
4. Due date is set AND is at least 1 week (6 days) in the future
5. Assignment is published (workflow_state = 'published')
6. Assignment was newly created (count increased from baseline of 1)

### enroll_student (4 criteria, ALL required)
1. Enrollment record exists for epatel in CS110 (direct query)
2. Enrollment is in 'active' state
3. Enrollment type is 'StudentEnrollment'
4. Enrollment was newly created (count increased from baseline of 10)

## Task Verification Results

**NOTE**: The verification results below are from database-level testing. Visual evidence (screenshots showing task completion in the UI) has NOT been captured yet. The verifiers check database state, but no screenshots exist proving the tasks were completed through the Canvas UI.

### 1. create_course
- **Verifier Status**: Database criteria met in controlled testing
- **Visual Evidence**: NOT CAPTURED
- **Expected Result**: Course DS101 "Introduction to Data Science" visible in course listings

### 2. create_assignment
- **Verifier Status**: Database criteria met in controlled testing
- **Visual Evidence**: NOT CAPTURED
- **Expected Result**: Assignment "Lab Report 1" visible in BIO101 assignments with 100 points and future due date

### 3. enroll_student
- **Verifier Status**: Database criteria met in controlled testing
- **Visual Evidence**: NOT CAPTURED
- **Expected Result**: Emily Patel visible in CS110 People list as enrolled student

## Screenshots

### Live Test Screenshots (2026-02-02)
New screenshots captured during live interactive testing are in `evidence/live_test_screenshots/`:

1. **`01_canvas_login_page.png`** - Canvas login page fully loaded
   - Shows: Email/Password fields, "Log In" button, Canvas branding
   - URL: `localhost:3000/login/canvas`
   - Proves: Canvas web server is accessible and rendering correctly

2. **`02_login_successful_terms_dialog.png`** - Successful login
   - Shows: Green success banner "You are logged in at Canvas Docker using your credentials from Site Admin"
   - Shows: "Updated Terms of Use" dialog
   - URL: `localhost:3000/?login_success=1`
   - Proves: Credentials `canvas@example.edu / canvas-docker` work correctly

### Legacy Evidence Files
The screenshots in the root `evidence/` directory are:
- `01_login_page.png` - Canvas login page (Feb 1 22:27)
- `MISLABELED_03_login_page_not_final_state.png` - Canvas login page (Feb 1 22:31) - **RENAMED: This was mislabeled as "final state" but shows login page**
- `canvas_initial_state.png` - Initial state screenshot showing "connection reset" error (Feb 2 21:14) - **Documents the Canvas startup reliability issue**

### Task Completion Evidence (TO BE CAPTURED)
The following screenshots should be captured during successful task execution:
- Screenshot showing DS101 course in course listings (for create_course)
- Screenshot showing "Lab Report 1" assignment in BIO101 (for create_assignment)
- Screenshot showing Emily Patel enrolled in CS110 (for enroll_student)

### Expected Evidence (TO BE CAPTURED)
The following screenshots should be captured during successful task execution to provide proper evidence:
- Screenshot showing DS101 course in course listings (for create_course)
- Screenshot showing "Lab Report 1" assignment in BIO101 (for create_assignment)
- Screenshot showing Emily Patel enrolled in CS110 (for enroll_student)

### Runtime Screenshots
During task execution, screenshots are saved to `/workspace/evidence/`:
- `{task_name}_initial.png` - Initial state before task (captured after health check)
- `{task_name}_final.png` - Final state after task completion

These runtime screenshots provide the actual evidence of task completion, but require running the tasks through the environment to generate.

## Tasks Available

1. **create_course** - Create a new course (DS101 - Introduction to Data Science)
2. **create_assignment** - Create an assignment in BIO101 (Lab Report 1, 100 points, future due date, must be published)
3. **enroll_student** - Enroll Emily Patel in CS110 as a Student

## Technical Notes

- The fat container approach (lbjay/canvas-docker) simplifies deployment by including PostgreSQL, Redis, and Canvas in a single container
- **Canvas takes 2-3 minutes to fully initialize** - all setup scripts now include health checks
- Rails runner commands require the specific path: `cd /opt/canvas/canvas-lms && GEM_HOME=/opt/canvas/.gems /opt/canvas/.gems/bin/bundle exec rails runner`
- Database name is `canvas_development` (not canvas_production as in multi-container setups)
- Enrollments are created in "invited" state and need to be activated via `enrollment.accept!` or SQL UPDATE
- Firefox opens to the Canvas login page at environment startup
- **If Firefox shows connection errors, the health check will refresh the page automatically**

## Health Check Implementation

The `task_utils.sh` script includes two key functions:

1. **wait_for_canvas_ready(timeout)**: Polls the Canvas HTTP endpoint until it returns 200/302/303
2. **ensure_canvas_ready_for_task(max_retries)**: Comprehensive check that:
   - Verifies Canvas server is responding (up to 120s wait)
   - Ensures Firefox is running
   - Focuses and maximizes Firefox window
   - Refreshes the page to clear any stale errors
   - Takes screenshots only after Canvas is confirmed ready

## Environment Registration

The environment is registered in `constants.py`:
```python
# Canvas LMS environment
try:
    canvas_lms_tasks = [x for x in os.listdir('benchmarks/environments/canvas_lms_env/tasks') if x.find('.')==-1]
except FileNotFoundError:
    canvas_lms_tasks = ['create_course', 'create_assignment', 'enroll_student']

# In ENV_TASK_SPLITS:
'canvas_lms_env': {
    'all' : canvas_lms_tasks,
    'train' : canvas_lms_tasks,
    'test' : [],
},
```

## Known Issues

### Canvas Checkpoint Reliability (CRITICAL)

**Issue**: The QEMU checkpoint for Canvas LMS has intermittent startup issues where Canvas shows "The connection was reset" error.

**Root Cause**: The lbjay/canvas-docker container sometimes fails to initialize properly after VM restore. The container logs show:
- `FATAL: database "canvas_production" does not exist` - Configuration mismatch (environment uses canvas_development)
- `encryption key is too short` - Canvas security configuration warning
- Container marked as "unhealthy"

**Impact**:
- Task initial state is unreliable (~30%+ failure rate observed)
- Agents may start tasks with Canvas unavailable
- Visual evidence capture blocked until checkpoint is rebuilt

**Mitigation Implemented**:
1. Enhanced health check with 180-second timeout
2. Exponential backoff retry logic
3. Content verification (not just HTTP status)
4. Automatic service restart attempt

**Required Fix**: The QEMU checkpoint needs to be rebuilt with Canvas fully initialized and healthy before snapshot.

### Visual Evidence Gap

**Issue**: No screenshots proving task completion exist in evidence.

**Reason**: Canvas reliability issues prevent capturing task completion evidence.

**Status**: Blocked until checkpoint is rebuilt.

## Audit History

- **2026-02-01**: Initial environment creation
- **2026-02-01**: Audit #1 - Fixed credential mismatch, database name issues
- **2026-02-01**: Audit #2 - Fixed setup_task.sh credentials, added due date validation
- **2026-02-01**: Audit #3 - Strengthened due date validation, added workflow_state check, screenshot persistence
- **2026-02-01**: Audit #4 - Added comprehensive Canvas health checks to address 67% startup failure rate
- **2026-02-02**: Audit #5 - **CRITICAL SECURITY FIX**: Replaced vulnerable JSON-based verification with direct database queries
  - All verifiers now use `exec_capture` for direct PostgreSQL queries
  - VLM visual verification added as secondary check
  - Agent-writable JSON files no longer trusted
  - `exec_capture` exposed in verification runner's `env_info`
  - Baseline counts added to task.json metadata
- **2026-02-02**: Audit #6 - Task description and documentation fixes
  - Added "must be published/available" to create_course description
  - Added "as Student role" to enroll_student description
  - Updated due date validation to require 1 week (matching task description)
  - Renamed mislabeled `03_final_state.png` file
  - Improved health check with exponential backoff and content verification
  - Documented Canvas checkpoint reliability issue
- **2026-02-02**: Audit #7 - Final security and reliability hardening
  - Fixed pipe character vulnerability: Changed field separator from `|` to unit separator (`\x1f`) in all verifiers
  - Made health check blocking: All `setup_task.sh` scripts now `exit 1` if Canvas unavailable
  - Verified Emily Patel baseline: `initial_enrollment_count: 9` (Emily NOT enrolled in CS110)
  - All three verifiers (create_course, create_assignment, enroll_student) use `FIELD_SEP = '\x1f'`
  - Task evidence capture blocked pending QEMU checkpoint rebuild

## Testing Date

Environment created and verified: 2026-02-01
Last updated: 2026-02-02 (Audit #7 - pipe parsing fix, blocking health check)
