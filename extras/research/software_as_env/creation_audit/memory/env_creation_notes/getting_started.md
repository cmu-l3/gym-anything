# Getting Started with gym_anything Environment Creation

## CRITICAL: Interactive Testing Only

**All testing must be done interactively in the live environment.** Do NOT write test scripts or use mock data.

The correct workflow is:
1. Start the environment
2. Take screenshots
3. Use screenshot-based UI grounding to decide the next action (Claude: `visual_grounding` MCP tool; Codex: native screenshot understanding or `python ask_cua.py --question ... --screenshot_path ...`)
4. Execute actions with xdotool
5. Repeat until task is complete
6. Run verification

See `03_interactive_testing.md` for the complete workflow.

---

## Overview

gym_anything is a framework for creating sandboxed desktop environments where AI agents can interact with real software through mouse/keyboard actions. Environments run in QEMU virtual machines (via Apptainer) or Docker containers, providing isolated, reproducible testing grounds.

This guide covers everything you need to know to create new environments and tasks.

---

## Repository Structure

```
gym-anything/
├── src/gym_anything/                # Core framework package (importable as `gym_anything`)
│   ├── api.py                       # Main API (make, from_config)
│   ├── env.py                       # GymAnythingEnv class
│   ├── specs.py                     # EnvSpec, TaskSpec dataclasses
│   ├── contracts.py                 # SessionInfo, RunnerRuntimeInfo (stable runtime contracts)
│   ├── runtime/runners/             # Container/VM runners
│   │   ├── qemu_apptainer.py        # QEMU+Apptainer runner (HPC/SLURM)
│   │   ├── docker.py                # Docker runner
│   │   └── base.py                  # Base runner interface
│   ├── presets/                     # Base image presets
│   │   └── ubuntu-gnome-systemd_highres.json
│   └── verification/                # Verification runner (stub — VLM verification is external)
├── benchmarks/cua_world/
│   ├── environments/                # Environment definitions live here
│   │   ├── vlc_media_player_env/    # Example: VLC environment
│   │   ├── chrome_env_all/          # Example: Chrome environment
│   │   ├── openemr_env/             # Example: OpenEMR (web app with Docker)
│   │   └── ...
│   ├── splits/                      # Named task lists (train/test/all/verified)
│   └── registry/                    # Split-loading helpers
├── extras/research/software_as_env/creation_audit/memory/env_creation_notes/  # Documentation for env creation
└── agents/                          # Reference agents (agents/, evaluation/, shared/)
```

---

## Core Concepts

### 1. Environment (env.json)

An environment defines a sandboxed desktop with specific software installed. Key components:

- **Base image**: Ubuntu with GNOME desktop (usually `ubuntu-gnome-systemd_highres`)
- **Scripts**: Installation and setup hooks
- **Mounts**: Files/directories to mount into the container
- **Resources**: CPU, memory, network requirements

### 2. Task (task.json)

A task is a specific objective within an environment (e.g., "Add a patient to OpenEMR"). Key components:

- **Description**: What the agent should accomplish
- **Hooks**: Setup and export scripts
- **Verification**: How to check if the task succeeded

### 3. Hooks

Scripts that run at different lifecycle stages:

| Hook | When it runs | Purpose |
|------|--------------|---------|
| `pre_start` | After VM starts, before desktop | Install software, dependencies |
| `post_start` | After desktop is ready | Configure app, load data, start services |
| `pre_task` | Before agent starts | Task-specific setup |
| `post_task` | After agent finishes | Export data for verification |

### 4. Verification

Verification is handled externally via VLM evaluators. The `verifier.py` file is a stub kept for framework compatibility. Focus your effort on ensuring the correct task start state and realistic data.

---

## Environment Structure

Every environment follows this structure:

```
benchmarks/cua_world/environments/<env_name>/
├── env.json                         # Environment specification
├── scripts/
│   ├── install_<app>.sh             # pre_start hook - installs application
│   └── setup_<app>.sh               # post_start hook - configures app
├── config/                          # Configuration files to mount
├── tasks/
│   └── <task_name>/
│       ├── task.json                # Task specification
│       ├── verifier.py              # Stub verifier (VLM verification is external)
│       └── setup_task.sh            # pre_task hook — ensures correct start state
└── utils/                           # Shared utilities
```

---

## env.json Specification

### Minimal Example

```json
{
  "id": "myapp_env@0.1",
  "version": "0.1",
  "base": "ubuntu-gnome-systemd_highres",
  "description": "MyApp environment description",
  "resources": {
    "cpu": 4,
    "mem_gb": 4,
    "gpu": 0,
    "net": true
  },
  "mounts": [
    {"source": "benchmarks/cua_world/environments/myapp_env/scripts", "target": "/workspace/scripts", "mode": "ro"},
    {"source": "benchmarks/cua_world/environments/myapp_env/tasks", "target": "/workspace/tasks", "mode": "ro"}
  ],
  "hooks": {
    "pre_start": "/workspace/scripts/install_myapp.sh",
    "post_start": "/workspace/scripts/setup_myapp.sh"
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

### Full Specification

See `benchmarks/cua_world/environments/vlc_media_player_env/env.json` for a complete example with all fields:

- `observation`: Screen capture settings (resolution, fps)
- `action`: Input types (mouse, keyboard)
- `security`: Container security settings
- `recording`: Video recording settings
- `vnc`: VNC access settings

---

## task.json Specification

```json
{
  "id": "add_patient@1",
  "version": "1.0",
  "env_id": "openemr_env@0.1",
  "description": "Add a new patient with name John TestPatient...",
  "init": {
    "timeout_sec": 180,
    "max_steps": 30,
    "reward_type": "sparse"
  },
  "hooks": {
    "pre_task": "/workspace/tasks/add_patient/setup_task.sh"
  },
  "success": {
    "mode": "program",
    "spec": {
      "program": "verifier.py::verify_add_patient"
    }
  }
}
```

---

## Installation Scripts

### pre_start (install_<app>.sh)

Runs as root. Install software and dependencies:

```bash
#!/bin/bash
set -e

echo "=== Installing MyApp ==="

# Update package lists
apt-get update

# Install dependencies
apt-get install -y dependency1 dependency2

# Install application
apt-get install -y myapp
# OR download and install manually:
# wget https://example.com/myapp.deb
# dpkg -i myapp.deb

echo "=== MyApp installation complete ==="
```

### post_start (setup_<app>.sh)

Runs after desktop is ready. Configure application:

```bash
#!/bin/bash
set -e

echo "=== Setting up MyApp ==="

# Wait for desktop to be ready
sleep 5

# Configure application
mkdir -p /home/ga/.config/myapp
cp /workspace/config/settings.conf /home/ga/.config/myapp/

# Start application (if needed)
su - ga -c "DISPLAY=:1 myapp &"

# Wait for app to start
sleep 3

echo "=== MyApp setup complete ==="
```

---

## Verification

Verification is handled externally via VLM evaluators. The `verifier.py` file in each task directory is a **stub** kept for framework compatibility:

```python
#!/usr/bin/env python3
"""Stub verifier — actual verification is done via external VLM evaluation."""

def verify_task(traj, env_info, task_info):
    return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}
```

**Focus your effort on ensuring the correct task start state and realistic data instead.**

---

## Interactive Testing

### Starting an Environment

```python
from gym_anything.api import from_config

# Create environment (optionally with task)
env = from_config("benchmarks/cua_world/environments/myapp_env", task_id="my_task")

# Reset - starts VM, runs hooks
obs = env.reset(seed=42, use_cache=False)

# Get connection info via the stable SessionInfo contract.
# (env._runner.ssh_port still works but bypasses the public API.)
session = env.get_session_info()
ssh_port = session.ssh_port
vnc_port = session.vnc_port
print(f"SSH: {ssh_port}, VNC: {vnc_port}")
```

### Connecting via SSH

```python
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('localhost', port=ssh_port, username='ga', password='password123')

# Run commands
stdin, stdout, stderr = ssh.exec_command('ls -la')
print(stdout.read().decode())

# Check logs
stdin, stdout, stderr = ssh.exec_command('cat /home/ga/env_setup_post_start.log')
print(stdout.read().decode())

ssh.close()
```

### Taking Screenshots

```python
# Via SSH
ssh.exec_command('DISPLAY=:1 import -window root /tmp/screenshot.png')

# Download
sftp = ssh.open_sftp()
sftp.get('/tmp/screenshot.png', 'local_screenshot.png')
sftp.close()
```

### Using exec_capture (Framework method)

```python
# Run command in container
output = env._runner.exec_capture('ls -la /home/ga')
print(output)
```

### Cleanup

```python
env.close()
```

---

## Web Application Pattern (Docker inside QEMU)

For complex web applications (like OpenEMR), use Docker containers inside the QEMU VM:

### install_app.sh
```bash
#!/bin/bash
# Install Docker
apt-get update
apt-get install -y docker.io docker-compose
systemctl enable docker
systemctl start docker
usermod -aG docker ga
```

### setup_app.sh
```bash
#!/bin/bash
# Start Docker containers
mkdir -p /home/ga/myapp
cp /workspace/config/docker-compose.yml /home/ga/myapp/
cd /home/ga/myapp
docker-compose up -d

# Wait for services
wait_for_service() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if curl -s http://localhost/ > /dev/null; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}
wait_for_service
```

### Database Queries (via Docker)
```bash
docker exec myapp-db mysql -u user -ppass dbname -N -e "SELECT * FROM table"
```

---

## Key Files to Reference

| File | Purpose |
|------|---------|
| `src/gym_anything/api.py` | Main API functions (make, from_config) |
| `src/gym_anything/env.py` | GymAnythingEnv class implementation |
| `src/gym_anything/specs.py` | EnvSpec and TaskSpec definitions |
| `benchmarks/cua_world/environments/vlc_media_player_env/` | Complete desktop app example |
| `benchmarks/cua_world/environments/openemr_env/` | Web app with Docker example |
| `extras/research/software_as_env/creation_audit/memory/env_creation_notes/getting_started.md` | Getting started guide |
| `extras/research/software_as_env/creation_audit/memory/env_creation_notes/07_web_applications_docker.md` | Docker web apps guide |
| **`extras/research/software_as_env/creation_audit/memory/env_creation_notes/10_cross_cutting_patterns.md`** | **Hard-won lessons from 100+ envs: service readiness, dialog suppression, process detection, verification anti-gaming, Docker/snap gotchas, coordinate scaling, setsid, pgrep bugs, XAUTHORITY, verify-against-user-flow, follow-conventions, probe-before-speculating, and more** |
| **`extras/research/software_as_env/creation_audit/memory/env_creation_notes/11_windows_environments.md`** | **Windows apps: Session 0 isolation, schtasks /IT, Win32 vs PyAutoGUI, Office installs, PowerShell gotchas** |
| **`extras/research/software_as_env/creation_audit/memory/env_creation_notes/12_macos_environments.md`** | **macOS apps via `UseComputerRunner` (use.computer fleet): `/Users/lume/workspace` (SIP read-only root), Rosetta, DMG / .pkg install patterns, TCC over SSH, VNC URL handling, no checkpoint caching** |
| `extras/research/software_as_env/creation_audit/memory/env_creation_notes/specific_env_notes/<env>/` | App-specific notes for similar environments |

---

## Common Patterns

### 1. Desktop Application
- Install via apt-get or .deb package
- Configure via dotfiles in home directory
- Ensure correct start state via setup_task.sh

### 2. Web Application (Docker)
- Install Docker in pre_start
- Run docker-compose in post_start
- Ensure correct start state with real data loaded

### 3. Browser-Based Task
- Install Firefox with pre-configured profile
- Set homepage to application URL
- Disable first-run dialogs and popups

---

## Troubleshooting

### Scripts not running
```bash
chmod +x benchmarks/cua_world/environments/myapp_env/scripts/*.sh
chmod +x benchmarks/cua_world/environments/myapp_env/tasks/*/*.sh
```

### Check hook logs
```bash
cat /home/ga/env_setup_pre_start.log
cat /home/ga/env_setup_post_start.log
```

### Permission denied when writing files
Use temp file pattern with sudo fallback (use `mktemp`, then `cp` with `sudo` fallback).

### Database query returns nothing but UI shows data
Use case-insensitive matching:
```sql
WHERE LOWER(TRIM(field)) = 'value'
```

---

## Next Steps

1. Go through relevant referenced files and notes to understand the gym anything framework and how environments/tasks work.
2. **Read `extras/research/software_as_env/creation_audit/memory/env_creation_notes/10_cross_cutting_patterns.md`** — 37 generalizable patterns distilled from 100+ environments. Covers the most common pitfalls (service readiness, first-run dialogs, Docker v2 vs v1, snap gotchas, verification anti-gaming, setsid, pgrep bugs, XAUTHORITY, etc.) **plus three agent-discipline patterns** (#35 verify-against-user-flow, #36 follow-prior-conventions, #37 probe-before-speculating). Read this BEFORE writing any scripts.
3. **If building a Windows app:** Read `extras/research/software_as_env/creation_audit/memory/env_creation_notes/11_windows_environments.md` — Session 0 isolation, schtasks /IT, Win32 vs PyAutoGUI automation, Office install patterns.
4. **If building a macOS app:** Read `extras/research/software_as_env/creation_audit/memory/env_creation_notes/12_macos_environments.md` — UseComputerRunner / use.computer fleet, `/Users/lume/workspace` (SIP makes / read-only), Rosetta, DMG / .pkg install, TCC over SSH, VNC URL handling, no checkpoint caching today.
5. Study existing environments in `benchmarks/cua_world/environments/` and `benchmarks/cua_world-macos/environments/`.
6. Check `extras/research/software_as_env/creation_audit/memory/env_creation_notes/specific_env_notes/<env_name>/` for app-specific notes on similar environments — **these are authoritative defaults; deviations need justification (pattern #36)**.
7. Check other notes in `extras/research/software_as_env/creation_audit/memory/env_creation_notes/` for specific topics
