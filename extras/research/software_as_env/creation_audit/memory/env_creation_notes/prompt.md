# Environment Creation Workflow for gym_anything

This document provides a step-by-step workflow for creating new environments in the gym_anything framework. Follow these phases in order.

---

## Phase 0: Mandatory — Read Expert Feedback First

Before any other phase, read @extras/research/software_as_env/creation_audit/memory/env_creation_notes/expert_feedback.md.

That file collects notes from domain experts about specific environments and global rules. Scan it for any entry whose header matches the target env_dir, or that is marked `GLOBAL`. Treat every matching entry as a hard requirement that supersedes the defaults in this prompt. If an expert note conflicts with anything below, follow the expert note.

If the file is empty (no entries yet), continue with Phase 1 as normal.

---

## Phase 1: Understand the Framework

Before creating any environment, you must understand how gym_anything works.

### 1.1 Read Core Framework Files

Read these files to understand the framework architecture:

| File | What You'll Learn |
|------|-------------------|
| `src/gym_anything/api.py` | How `make()` and `from_config()` create environments |
| `src/gym_anything/env.py` | The `GymAnythingEnv` class - reset, step, observation handling |
| `src/gym_anything/specs.py` | `EnvSpec` and `TaskSpec` dataclasses - what fields are available |
| `src/gym_anything/runtime/runners/base.py` | Base runner interface - what methods runners provide |
| `src/gym_anything/runtime/runners/qemu_apptainer.py` | QEMU runner - how VMs are started, hooks executed |

IMPORTANT: We have to use qemu_apptainer runner and not the docker one, since we don't have access to the docker daemon on the host machine. You can run docker inside the qemu vm if there is an absolute need for it.

### 1.2 Understand the Lifecycle

```
from_config() → env.reset() → [agent interaction] → env.close()
                    │
                    ├── VM boots
                    ├── pre_start hook runs (install software)
                    ├── Desktop starts
                    ├── post_start hook runs (configure app)
                    ├── pre_task hook runs (task-specific setup)
                    └── Agent interacts via mouse/keyboard
```

### 1.3 Key Framework Concepts

| Concept | Description |
|---------|-------------|
| **Runner** | Manages VM lifecycle (QEMU/Apptainer) |
| **Hooks** | Shell scripts that run at specific lifecycle points |
| **Mounts** | Host directories mounted into the VM |
| **Observation** | Screenshot of the VM desktop |
| **Action** | Mouse/keyboard input sent to VM |
| **Verification** | Handled externally via VLM evaluators (verifier.py is a stub for compatibility) |

### 1.4 Critical Framework Rules

1. **Hooks run as root** by default - use `su - ga -c "..."` for user commands
2. **DISPLAY=:1** - always set this for GUI commands
3. **Mounts are read-only by default** - use `"mode": "rw"` if writing needed
4. **Verification is external** - verifier.py is a stub; VLM verification is done separately

---

## Phase 2: Research the Target Application

### 2.1 Understand the Target Application

Before writing any code, research how to install and configure the target application:

1. **Web Search**: Search for official installation guides, Docker images, or package managers
2. **Identify Dependencies**: List all required software (databases, runtimes, libraries)
3. **Determine Installation Method**:
   - Package manager (apt-get install)
   - Download and extract (wget + tar/unzip)
   - Docker container (for complex web apps)
   - Build from source (if necessary)

### 2.2 Key Questions to Answer

| Question | Why It Matters |
|----------|----------------|
| Is it a desktop app or web app? | Desktop apps launch directly; web apps need browser + backend services |
| What services does it need? | MySQL, Apache, etc. require startup timing coordination |
| How is data stored? | Files vs database — important for realistic data setup |
| Does it have a first-run wizard? | May need to bypass or automate initial setup |
| What network access is needed? | Set `net: true` if external downloads or APIs needed |

### 2.3 Plan the Approach

Based on research, decide:

- **Base image**: Usually `ubuntu-gnome-systemd_highres`
- **Service orchestration**: Direct services vs Docker-in-QEMU
- **Resource requirements**: CPU, memory, GPU needs

### 2.4 Plan Realistic Data (CRITICAL)

**For applications that require data (databases, documents, media files, etc.), you MUST use realistic data from real sources. Do NOT handwrite small sample data files.**

#### Why This Matters

- Handwritten sample data is often incomplete, unrealistic, or missing edge cases
- Real data exposes actual application behavior and edge cases
- Agents need to interact with realistic scenarios, not toy examples
- Verification is more meaningful with production-like data

#### How to Find Realistic Data

| Data Type | Where to Find It |
|-----------|------------------|
| **Medical/EHR data** | Synthea (synthetic patient generator), MIMIC demo data |
| **Database samples** | Official demo databases, GitHub sample datasets |
| **Documents** | Sample PDFs, DOCs from official sources, test corpora |
| **Media files** | Sample videos/audio from codec test suites, Creative Commons |
| **Spreadsheets** | Government open data portals, Kaggle datasets |
| **Configuration files** | Official documentation examples, GitHub repos |

#### Examples

**BAD - Handwritten sample data:**
```sql
INSERT INTO patients VALUES (1, 'John', 'Doe', '1990-01-01');
INSERT INTO patients VALUES (2, 'Jane', 'Smith', '1985-05-15');
```

**GOOD - Using realistic data generator:**
```bash
# Download Synthea and generate 100 realistic patients
wget https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar
java -jar synthea-with-dependencies.jar -p 100 --exporter.fhir.export=false --exporter.csv.export=true
# Then convert CSV to application-specific SQL format
```

**GOOD - Using official sample database:**
```bash
# Download official sample database
wget https://example.com/official-sample-database.sql
mysql -u user -ppass dbname < official-sample-database.sql
```

#### Data Sourcing Checklist

Before writing any data files, answer these questions:

1. Does the application have an official demo/sample database?
2. Is there a synthetic data generator for this domain (e.g., Synthea for healthcare)?
3. Are there open datasets on GitHub, Kaggle, or government portals?
4. Can I use the application's export feature to get sample data format?

**Only handwrite data as a last resort**, and if you must, ensure it:
- Covers realistic field lengths and formats
- Includes edge cases (special characters, long names, dates across years)
- Has enough volume to be representative (not just 2-3 records)

---

## Phase 3: Study Existing Environments

### 3.1 Read Core Documentation

Read these files in order:

1. `extras/research/software_as_env/creation_audit/memory/env_creation_notes/getting_started.md` - Framework overview
2. `extras/research/software_as_env/creation_audit/memory/env_creation_notes/10_cross_cutting_patterns.md` - **Essential reading.** Hard-won lessons distilled from 100+ environments: service readiness polling, dialog suppression, process detection, verification anti-gaming, Docker gotchas, coordinate scaling, setsid, pgrep bugs, XAUTHORITY, and more. Read this BEFORE writing any scripts.
3. `extras/research/software_as_env/creation_audit/memory/env_creation_notes/11_windows_environments.md` - **Required for Windows apps.** Session 0 isolation, schtasks /IT, Win32 vs PyAutoGUI, Office install patterns, PowerShell gotchas.

### 3.2 Study Similar Environments

Find and read environments similar to yours by browsing the `benchmarks/cua_world/environments/` directory: `ls benchmarks/cua_world/environments/`.

### 3.3 Key Files to Examine

For each reference environment, read:

```
benchmarks/cua_world/environments/<env_name>/
├── env.json                 # Configuration structure
├── scripts/
│   ├── install_*.sh         # Installation patterns
│   └── setup_*.sh           # Configuration patterns
└── tasks/<task_name>/
    ├── task.json            # Task structure
    ├── setup_task.sh        # Task setup patterns
    └── verifier.py          # Stub verifier (VLM verification is external)
```

### 3.4 Check Environment-Specific Notes

Look for notes in `extras/research/software_as_env/creation_audit/memory/env_creation_notes/specific_env_notes/<env_name>/` for detailed learnings about similar environments. These notes document app-specific quirks (install paths, dialog coordinates, data formats, etc.) that supplement the general patterns in `10_cross_cutting_patterns.md`.

---

## Phase 4: Create Implementation Plan

### 4.1 Define Directory Structure

```
benchmarks/cua_world/environments/<your_env_name>/
├── env.json
├── scripts/
│   ├── install_<app>.sh     # pre_start hook
│   ├── setup_<app>.sh       # post_start hook
│   └── task_utils.sh        # Shared utilities (optional)
├── config/                   # Configuration files to mount
├── tasks/
│   └── <first_task>/
│       ├── task.json
│       ├── setup_task.sh    # pre_task hook
│       └── verifier.py      # Stub (VLM verification is external)
└── utils/                    # Python utilities (optional)
```

**CRITICAL**: 
1. One of the goals is to involve some real world data (no fake or mock or synthetic data). You are free to include such data files in `assets` or `data` folder in the environment directory.

### 4.2 Define Hook Responsibilities

| Hook | Script | Responsibility |
|------|--------|----------------|
| `pre_start` | `install_<app>.sh` | Install all software and dependencies |
| `post_start` | `setup_<app>.sh` | Start services, configure app, prepare state |
| `pre_task` | `setup_task.sh` | Task-specific setup — ensure correct start state with real data |

### 4.3 Plan Task Start State (CRITICAL)

The most important part of task creation is ensuring the correct start state. The agent must see the application in exactly the right screen/view/state with real data loaded. Plan:

1. **What screen/view** should the application be on when the agent starts?
2. **What data** must be pre-loaded (real data, not synthetic)?
3. **What windows** should be open/focused?
4. **What prior steps** (if any) need to be completed programmatically before the agent takes over?

The `setup_task.sh` (pre_task hook) is responsible for achieving this state.

---

## Phase 5: Write Environment Files

### 5.1 Create env.json

Start with this template:

```json
{
  "id": "<app>_env@0.1",
  "version": "0.1",
  "base": "ubuntu-gnome-systemd_highres",
  "description": "<App Name> environment for <purpose>",
  "resources": {
    "cpu": 4,
    "mem_gb": 4,
    "gpu": 0,
    "net": true
  },
  "mounts": [
    {"source": "benchmarks/cua_world/environments/<app>_env/scripts", "target": "/workspace/scripts", "mode": "ro"},
    {"source": "benchmarks/cua_world/environments/<app>_env/config", "target": "/workspace/config", "mode": "ro"},
    {"source": "benchmarks/cua_world/environments/<app>_env/tasks", "target": "/workspace/tasks", "mode": "ro"}
  ],
  "hooks": {
    "pre_start": "/workspace/scripts/install_<app>.sh",
    "post_start": "/workspace/scripts/setup_<app>.sh"
  },
  "user_accounts": [
    {
      "name": "ga",
      "password": "password123",
      "permissions": {
        "sudo": true,
        "sudo_nopasswd": true,
        "groups": ["sudo", "audio", "video", "input"],
        "env_vars": {"DISPLAY": ":1"}
      }
    }
  ]
}
```

Adjust resources based on application needs:
- Web apps with databases: 8GB RAM
- Heavy desktop apps: 4-6GB RAM
- Simple apps: 2-4GB RAM

### 5.2 Write Installation Script (pre_start)

Template for `scripts/install_<app>.sh`:

```bash
#!/bin/bash
set -e

echo "=== Installing <App Name> ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install dependencies
apt-get install -y \
    dependency1 \
    dependency2 \
    scrot wmctrl xdotool \
    python3-pip

# Install the application
# Option A: From package manager
apt-get install -y <app-package>

# Option B: Download and install
# wget https://example.com/app.deb
# dpkg -i app.deb
# apt-get install -f -y

# Option C: For web apps - install Docker
# apt-get install -y docker.io docker-compose
# systemctl enable docker
# systemctl start docker
# usermod -aG docker ga

echo "=== <App Name> installation complete ==="
```

### 5.3 Write Setup Script (post_start)

Template for `scripts/setup_<app>.sh`:

```bash
#!/bin/bash
set -e

echo "=== Setting up <App Name> ==="

# Wait for desktop to be ready
sleep 5

# For web apps: Start services with polling
wait_for_mysql() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if mysqladmin ping -h localhost 2>/dev/null; then
            echo "MySQL is ready"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "MySQL timeout"
    return 1
}

# Configure application
mkdir -p /home/ga/.config/<app>
# Copy configs, set permissions, etc.

# For desktop apps: Create launcher script
cat > /home/ga/Desktop/launch_<app>.sh << 'EOF'
#!/bin/bash
export DISPLAY=:1
<app-command> &
EOF
chmod +x /home/ga/Desktop/launch_<app>.sh
chown ga:ga /home/ga/Desktop/launch_<app>.sh

# Start application (if needed at setup time)
su - ga -c "DISPLAY=:1 /home/ga/Desktop/launch_<app>.sh"

# Wait for app to start
sleep 3

echo "=== <App Name> setup complete ==="
```

### 5.4 Write Shared Utilities (Optional)

For complex environments, create `scripts/task_utils.sh`:

```bash
#!/bin/bash
# Shared utilities for all tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Database query function (for web apps with Docker)
app_query() {
    local query="$1"
    docker exec <db-container> mysql -u user -ppass dbname -N -e "$query" 2>/dev/null
}
```

### 5.5 Write Task Files

#### task.json

```json
{
  "id": "<task_name>@1",
  "version": "1.0",
  "env_id": "<app>_env@0.1",
  "description": "Detailed description of what the agent should do...",
  "init": {
    "timeout_sec": 180,
    "max_steps": 30,
    "reward_type": "sparse"
  },
  "hooks": {
    "pre_task": "/workspace/tasks/<task_name>/setup_task.sh"
  },
  "success": {
    "mode": "program",
    "spec": {
      "program": "verifier.py::verify_<task_name>"
    }
  }
}
```

#### setup_task.sh (pre_task)

This is the **most important script** — it determines exactly what the agent sees when it starts.

```bash
#!/bin/bash
echo "=== Setting up <task_name> task ==="

# 1. Load real data required for this task
# Example: Copy a real dataset file into the application's working directory
cp /workspace/assets/real_data_file.csv /home/ga/Documents/

# 2. Open the application to the correct screen/view
# Example: Open a specific file, navigate to a specific tab
su - ga -c "DISPLAY=:1 <app> /home/ga/Documents/real_data_file.csv &"
sleep 3

# 3. Position the application window correctly
# Example: Focus and maximize the window
DISPLAY=:1 wmctrl -r "<Window Title>" -b add,maximized_vert,maximized_horz

# 4. Navigate to the correct starting point (if needed)
# Example: Use xdotool to click through menus to reach the right screen
DISPLAY=:1 xdotool key ctrl+n  # Open new document, etc.
sleep 1

echo "=== Task setup complete ==="
```

**CRITICAL**:
1. Make sure you are using **real data** to setup tasks. Fake or Mock or Synthetic Data is strictly not allowed. You are free to temporarily download and check data format on the host machine in any scratch directory you have write access to (e.g. `/tmp/<env_name>/` or whatever scratch path the host provides).
2. Use web search if you cannot find the correct data directly, but do not compromise on task quality.
3. Large data files that would be commonly used across multiple (3 or more) tasks should be stored in the environment installation step.
4. The **task start state must be deterministic and correct** — the application must be in the exact right screen/view/state with real data loaded, ready for the agent to begin. Test this interactively using screenshot-based UI grounding to confirm what the agent will see (Claude: `visual_grounding` MCP tool; Codex: native screenshot understanding or `python ask_cua.py --question ... --screenshot_path ...`).

#### verifier.py (Stub)

**NOTE**: Verification is handled externally via VLM evaluators. The verifier.py file is a stub kept for framework compatibility.

```python
#!/usr/bin/env python3
"""Stub verifier for <task_name> task.
Actual verification is done externally via VLM evaluators.
"""

def verify_<task_name>(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
```

### 5.6 Make Scripts Executable

```bash
chmod +x benchmarks/cua_world/environments/<app>_env/scripts/*.sh
chmod +x benchmarks/cua_world/environments/<app>_env/tasks/*/*.sh
```

---

## Phase 6: Interactive Testing

Use the live environment with xdotool and screenshot-based UI grounding to verify your setup works correctly (Claude: `visual_grounding` MCP tool; Codex: native screenshot understanding or `ask_cua.py`). Focus on confirming the environment starts properly, the task start state is correct, and there is sufficient evidence that the task is completable end-to-end.

**IMPORTANT clarification:** "Interactive testing" here means keeping a single running VM instance and iterating (screenshot -> action -> screenshot) until the UI flow is understood. Only restart the environment after you change scripts. You do not need to complete the task fully end-to-end, but you must provide sufficient evidence (screenshots of key steps, correct start state, real data visible) that an agent could complete it.

### 6.1 The Interactive Testing Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                    INTERACTIVE TESTING LOOP                      │
├─────────────────────────────────────────────────────────────────┤
│  1. Start environment: env.reset()                               │
│  2. Take screenshot: DISPLAY=:1 scrot /tmp/screen.png            │
│  3. Analyze screenshot (Claude: visual_grounding; Codex: ask_cua)│
│  4. Perform action: DISPLAY=:1 xdotool mousemove X Y click 1     │
│  5. Take screenshot, observe result                              │
│  6. Repeat 2-5 until task complete                               │
│  7. If issues → fix scripts → env.close() → restart              │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Start the Environment

```python
from gym_anything.api import from_config
import paramiko

# Start environment with task
env = from_config("benchmarks/cua_world/environments/<app>_env", task_id="<task_name>")
obs = env.reset(seed=42, use_cache=False)

# Connect via SSH
ssh_port = env._runner.ssh_port
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('localhost', port=ssh_port, username='ga', password='password123')
```

### 6.3 Take Screenshot and Get UI Guidance

```python
# Take screenshot
ssh.exec_command('DISPLAY=:1 scrot /tmp/screen.png')
sftp = ssh.open_sftp()
sftp.get('/tmp/screen.png', '/tmp/local_screen.png')
sftp.close()
```

Then get UI guidance on what to do next (Claude vs Codex):

```
# Claude (supports `visual_grounding` MCP tool): call `visual_grounding` with:
#   - question: "I need to click on the File menu to import data. Where should I click?"
#   - screenshot_path: "/tmp/local_screen.png"
#
# Codex (no `visual_grounding` MCP tool): either inspect the screenshot directly, or run:
#   python ask_cua.py --question "I need to click on the File menu to import data. Where should I click?" --screenshot_path "/tmp/local_screen.png"
```

**Example questions:**
- "Where is the File menu? Give me coordinates to click."
- "Is there an error dialog visible? What does it say?"
- "Has the data loaded successfully? Is the application in the correct state?"
- "Where is the Save button?"

**IMPORTANT:** Both `visual_grounding` and `ask_cua.py` return coordinates normalized to 1280x720. Scale to actual resolution:
```python
# Scale from 1280x720 to 1920x1080
actual_x = int(cua_x * 1920 / 1280)
actual_y = int(cua_y * 1080 / 720)
```

### 6.4 Perform Actions with xdotool

```python
# Click at coordinates
ssh.exec_command(f'DISPLAY=:1 xdotool mousemove {actual_x} {actual_y} click 1')

# Type text
ssh.exec_command('DISPLAY=:1 xdotool type "Hello World"')

# Press keys
ssh.exec_command('DISPLAY=:1 xdotool key Return')
ssh.exec_command('DISPLAY=:1 xdotool key ctrl+s')

# Wait for UI
import time
time.sleep(1)
```

### 6.5 Iterate: Screenshot → Guidance → Action → Repeat

Keep looping until the task is complete:

1. Take screenshot
2. Analyze the screenshot (Claude: `visual_grounding`; Codex: native screenshot understanding or `ask_cua.py`)
3. Execute xdotool command
4. Repeat

### 6.6 Verify Task Start State

After setting up the task, use screenshot-based UI grounding (Claude: `visual_grounding`; Codex: native screenshot understanding or `ask_cua.py`) to confirm:
1. The application is visible and in the correct screen/view
2. Real data is loaded and visible
3. The agent would know what to do from the screenshot alone

### 6.7 Fix Issues and Restart

When you find issues:

1. Identify the problem from screenshots or logs
2. Edit the relevant script
3. `env.close()`
4. Restart and test again

### 6.8 Debugging: Check Logs

```python
# Check installation log
ssh.exec_command('cat /home/ga/env_setup_pre_start.log')

# Check setup log
ssh.exec_command('cat /home/ga/env_setup_post_start.log')

# Check if app is running
ssh.exec_command('ps aux | grep <app>')

# List windows
ssh.exec_command('DISPLAY=:1 wmctrl -l')
```

### 6.9 Common Issues

| Issue | Solution |
|-------|----------|
| GNOME Activities triggers | Avoid top-left corner; use keyboard shortcuts |
| Menu clicks not working | Use `alt+<key>` for menu access |
| App not visible | Check DISPLAY=:1; add sleep after launch |
| Coordinates wrong | Scale normalized 1280x720 coords to actual resolution |

See `03_interactive_testing.md` for comprehensive details.

---

## Phase 7: Final Testing

After all issues are fixed, perform a clean final test:

### 7.1 Clean Test Without Cache

```python
from gym_anything.api import from_config

# Fresh start
env = from_config("benchmarks/cua_world/environments/<app>_env", task_id="<task_name>")
obs = env.reset(seed=42, use_cache=False)

# Verify everything works
ssh_port = env._runner.ssh_port
print(f"Environment started on SSH port {ssh_port}")
```

### 7.2 Verify Checklist

Some example points:

- [ ] Installation script completes without errors
- [ ] Setup script completes without errors
- [ ] Application is visible in screenshot
- [ ] Application is in correct initial state with real data loaded
- [ ] Task setup runs without errors
- [ ] Task start state is correct (verified via screenshot grounding: Claude `visual_grounding`; Codex native/`ask_cua.py`)
- [ ] Sufficient evidence that task is completable end-to-end (e.g., screenshots showing key steps work, correct start state, data is present and accessible)

**CRITICAL**: 
1. These are only some sample points, that have to be fixed at any cost. These have to run in actual environment.
2. You are also supposed to create evidence_docs folder inside the environment directory, containing the final screenshots as evidence of the checklist items. Along with photos, show exact outputs (or snippets) from the task/env setup logs. No mock or fake data allowed here. You can also include Readme.md file detailing all documentations. 

### 7.3 Document Learnings

Create notes in `extras/research/software_as_env/creation_audit/memory/env_creation_notes/specific_env_notes/<env_name>/`:

- Installation quirks
- Service timing issues
- Database schema notes
- Verification gotchas

### 7.4 Cleanup

```python
env.close()
```

---

## Common Patterns Reference

> **For comprehensive cross-cutting patterns (service readiness, dialog suppression, process detection, verification anti-gaming, Docker gotchas, snap package issues, coordinate scaling, and more), see `extras/research/software_as_env/creation_audit/memory/env_creation_notes/10_cross_cutting_patterns.md`.** The patterns below are quick-reference templates; the cross-cutting doc explains *why* each pattern exists and what goes wrong without it.

### Web Application with Docker

```bash
# In install script — IMPORTANT: use docker-compose-plugin (v2), NOT docker-compose (v1)
apt-get install -y docker.io docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# In setup script
cd /home/ga/app
docker-compose up -d

# Wait for services
wait_for_service() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if curl -s http://localhost/ > /dev/null 2>&1; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}
wait_for_service

# Query database
docker exec myapp-db mysql -u user -ppass dbname -N -e "SELECT COUNT(*) FROM table"
```

### Firefox with Pre-configured Profile

```bash
# Create profile directory
mkdir -p /home/ga/.mozilla/firefox/default.profile

# Configure user.js to disable first-run
cat > /home/ga/.mozilla/firefox/default.profile/user.js << 'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("security.enterprise_roots.enabled", true);
EOF

# Create profiles.ini
cat > /home/ga/.mozilla/firefox/profiles.ini << 'EOF'
[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1
EOF

chown -R ga:ga /home/ga/.mozilla

# Launch Firefox with profile
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/default.profile http://localhost/ &"
```

### Permission-Safe File Writing

```bash
# Always use temp file first
TEMP=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP" << EOF
{"data": "value"}
EOF

# Remove old file with fallbacks
rm -f /tmp/final.json 2>/dev/null || sudo rm -f /tmp/final.json 2>/dev/null || true

# Copy new file with fallbacks
cp "$TEMP" /tmp/final.json 2>/dev/null || sudo cp "$TEMP" /tmp/final.json

# Set permissions
chmod 666 /tmp/final.json 2>/dev/null || sudo chmod 666 /tmp/final.json 2>/dev/null || true

# Cleanup temp
rm -f "$TEMP"
```

---

## Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| "Permission denied" writing files | Use temp file pattern with sudo fallback |
| App not in correct start state | Fix setup_task.sh to position app correctly |
| Service not starting | Add polling loop with timeout |
| App not visible in screenshot | Check DISPLAY=:1, add sleep after launch |
| Script not found | Check mount paths in env.json |
| Hook not running | Verify hook path in env.json/task.json |
| JSON parse error | Escape special characters in bash strings |

---

## Summary Checklist

1. [ ] **Understand framework**: Read core files (api.py, env.py, specs.py, runners/)
2. [ ] **Research application**: Understand installation requirements and dependencies
3. [ ] **Source realistic data**: Find real datasets, generators, or official samples (NOT handwritten toy data)
4. [ ] **Study existing envs**: Read similar environments and documentation
5. [ ] **Plan implementation**: Define directory structure and hook responsibilities
6. [ ] **Write env.json**: Base image, resources, mounts, hooks
7. [ ] **Write install script**: Dependencies and software installation
8. [ ] **Write setup script**: Service startup and configuration
9. [ ] **Write task files**: task.json, setup_task.sh, stub verifier.py
10. [ ] **Make executable**: chmod +x all scripts
11. [ ] **Test interactively**: Start VM, SSH, use screenshot grounding (Claude `visual_grounding`; Codex native/`ask_cua.py`), check logs, fix issues
12. [ ] **Verify task start state**: Confirm correct app state with real data via screenshot grounding
13. [ ] **Final test**: Clean start to confirm everything works
14. [ ] **Document**: Record learnings for future reference

## Navigating the Folder

The folder contains various general and task specific notes, that would be useful thorughout out complete job of setting up the environment. Almost all files are in markdown. It is STRONGLY advised to read full files. However, if reading full files takes times, you can use grep patterns (such as "## ") to figure out headings and sections, so you can directly jump to them.

### Key Files in `extras/research/software_as_env/creation_audit/memory/env_creation_notes/`

| File | What It Covers |
|------|---------------|
| `getting_started.md` | Framework overview, env/task structure, API usage |
| `01_environment_structure.md` | Directory layout and env.json fields |
| `02_common_errors.md` | Error-by-error troubleshooting guide |
| `03_interactive_testing.md` | Screenshot-based testing workflow |
| `04_installation_scripts.md` | pre_start hook templates and patterns |
| `06_env_creation_checklist.md` | Step-by-step creation checklist |
| `07_web_applications_docker.md` | Docker-in-QEMU patterns for web apps |
| `08_synthea_data_conversion.md` | Healthcare data generation |
| **`10_cross_cutting_patterns.md`** | **ESSENTIAL: 30 patterns from 100+ envs — service readiness, dialog suppression, process detection, verification anti-gaming, Docker v2, snap gotchas, coordinate scaling, setsid, pgrep bugs, XAUTHORITY, and more** |
| **`11_windows_environments.md`** | **Windows apps: Session 0, schtasks /IT, Win32 vs PyAutoGUI, Office installs, PowerShell gotchas** |
| `specific_env_notes/<env>/` | App-specific notes (install paths, dialog coords, data formats) |
