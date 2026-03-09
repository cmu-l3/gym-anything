# System Advisor Model Environment - Testing Plan

## Current Status

**Completed Phases:**
- ✅ Phase 1: Framework Understanding
- ✅ Phase 2: Research Target Application
- ✅ Phase 3: Study Existing Environments
- ✅ Phase 4: Implementation Plan
- ✅ Phase 5: Write Environment Files
- ⏳ Phase 6: Interactive Testing (IN PROGRESS)
- ⏳ Phase 7: Final Testing & Evidence Collection (PENDING)

**Environment Started:** The environment is currently booting in the background. Initial VM boot + SAM installation takes approximately 10-15 minutes.

## Phase 6: Interactive Testing Steps

### 6.1 Wait for Environment to Start
```bash
# Monitor startup progress
tail -f /tmp/claude-2710891/.../tasks/bbd8e58.output

# Once started, connection info will be in:
cat /tmp/sam_env_connection.txt
```

### 6.2 Run Initial Tests
```bash
cd /scratch/pranjala/gym_anything_clean/Gym-Anything_for_cmu
python3 /scratch/pranjala/tmp/test_sam_env.py
```

This will verify:
- SAM installation at `/opt/SAM/sam`
- Installation logs in `/home/ga/env_setup_pre_start.log`
- Setup logs in `/home/ga/env_setup_post_start.log`
- SAM Projects directory exists
- Desktop screenshot capability
- Window list via wmctrl

### 6.3 Connect via SSH
```bash
# Get SSH port from connection file
SSH_PORT=$(grep SSH_PORT /tmp/sam_env_connection.txt | cut -d= -f2)

# Connect
ssh -p $SSH_PORT ga@localhost
# Password: password123
```

### 6.4 Interactive Task Completion

**Objective:** Create a 5kW residential PV system in Phoenix, AZ

**Steps:**
1. Take initial screenshot
```bash
DISPLAY=:1 import -window root /tmp/step1_initial.png
```

2. Launch SAM (if not already running)
```bash
DISPLAY=:1 /opt/SAM/sam &
sleep 5
```

3. Use ask_cua.py to find UI elements
```bash
# Download screenshot to host
scp -P $SSH_PORT ga@localhost:/tmp/step1_initial.png /scratch/pranjala/tmp/

# Ask CUA for coordinates
cd /scratch/pranjala/gym_anything_clean/Gym-Anything_for_cmu
python ask_cua.py \
    --question "Where is the 'File' menu or 'New Project' button? Give me coordinates." \
    --screenshot_path /scratch/pranjala/tmp/step1_initial.png
```

4. Click to create new project
```bash
# Scale coordinates from 1280x720 to 1920x1080
# If CUA returns (x=100, y=50):
ACTUAL_X=$((100 * 1920 / 1280))
ACTUAL_Y=$((50 * 1080 / 720))

DISPLAY=:1 xdotool mousemove $ACTUAL_X $ACTUAL_Y click 1
sleep 1
```

5. Select "Residential PV" template
```bash
# Take screenshot, ask CUA, click on template
DISPLAY=:1 import -window root /tmp/step2_template.png
# ... repeat ask_cua.py and xdotool process
```

6. Configure location (Phoenix, AZ)
7. Set system size (5.0 kW)
8. Configure tilt (20 degrees)
9. Set azimuth (180 degrees)
10. Save project as "Phoenix_Residential_5kW.sam"

### 6.5 Verify Task Completion

After completing the task manually:

```bash
# Run export script
bash /workspace/tasks/create_residential_pv_system/export_result.sh

# Check result
cat /tmp/task_result.json

# Should show:
# - file_exists: true
# - file_modified: true
# - location_info: contains "Phoenix"
# - dc_size: ~5.0
# - tilt: ~20
# - azimuth: ~180
```

### 6.6 Test Verifier

From host machine (Python):
```python
# The environment should still be running
result = env.verify()
print(f"Passed: {result['passed']}")
print(f"Score: {result['score']}")
print(f"Feedback: {result['feedback']}")

# Expected: passed=True, score >= 75
```

## Phase 7: Evidence Collection

### 7.1 Screenshots to Collect

From VM (via SSH):
```bash
# 1. Desktop with SAM running
DISPLAY=:1 import -window root /tmp/evidence_desktop.png

# 2. SAM main window
DISPLAY=:1 import -window root /tmp/evidence_sam_window.png

# 3. New project dialog (if still visible)
DISPLAY=:1 import -window root /tmp/evidence_new_project.png

# 4. Configured PV system (showing parameters)
DISPLAY=:1 import -window root /tmp/evidence_configured.png

# 5. File save dialog or file browser showing saved project
DISPLAY=:1 import -window root /tmp/evidence_saved_file.png

# 6. Final state after task completion
DISPLAY=:1 import -window root /tmp/evidence_final.png

# Download all to host
scp -P $SSH_PORT ga@localhost:'/tmp/evidence_*.png' \
    benchmarks/environments/system_advisor_model_env/evidence/
```

### 7.2 Logs to Collect

```bash
# Installation log
scp -P $SSH_PORT ga@localhost:/home/ga/env_setup_pre_start.log \
    benchmarks/environments/system_advisor_model_env/evidence/

# Setup log
scp -P $SSH_PORT ga@localhost:/home/ga/env_setup_post_start.log \
    benchmarks/environments/system_advisor_model_env/evidence/

# Task setup log (if exists)
scp -P $SSH_PORT ga@localhost:/home/ga/task_pre_task.log \
    benchmarks/environments/system_advisor_model_env/evidence/ 2>/dev/null || true

# Export result JSON
scp -P $SSH_PORT ga@localhost:/tmp/task_result.json \
    benchmarks/environments/system_advisor_model_env/evidence/
```

### 7.3 Project File to Collect

```bash
# Copy the actual SAM project file
scp -P $SSH_PORT ga@localhost:/home/ga/Documents/SAM_Projects/Phoenix_Residential_5kW.sam \
    benchmarks/environments/system_advisor_model_env/evidence/
```

### 7.4 Verification Results

Save to `benchmarks/environments/system_advisor_model_env/evidence/verification_result.json`:
```json
{
  "passed": true,
  "score": 95,
  "feedback": "✓ Project file 'Phoenix_Residential_5kW.sam' exists | ✓ File was created/modified during task | ✓ File size reasonable (15234 bytes) | ✓ Location 'Phoenix' found in project | ✓ DC size correct: 5.0 kW | ✓ Tilt angle correct: 20° | ✓ Azimuth correct: 180° (South-facing)"
}
```

### 7.5 Create Evidence README

Document in `benchmarks/environments/system_advisor_model_env/evidence/EVIDENCE.md`:

```markdown
# Testing Evidence for SAM Environment

## Test Date
[Current date/time]

## Environment Details
- SAM Version: 2025.4.16 Revision 1
- Base Image: ubuntu-gnome-systemd_highres (1920x1080)
- VM Resources: 4 CPU, 8GB RAM

## Installation Evidence
- ✅ SAM installed to `/opt/SAM/sam`
- ✅ Installation log shows successful completion
- ✅ SAM directories created correctly

[Include snippets from installation log]

## Setup Evidence
- ✅ Desktop started successfully
- ✅ SAM Projects directory created
- ✅ First launch completed
- ✅ Startup dialogs dismissed

[Include snippets from setup log]

## Task Execution Evidence
- ✅ SAM launched and visible
- ✅ New project created from Residential PV template
- ✅ Location set to Phoenix, Arizona
- ✅ System configured: 5kW, 20° tilt, 180° azimuth
- ✅ Project saved as Phoenix_Residential_5kW.sam

[Include screenshots showing each step]

## Verification Evidence
- ✅ Export script ran successfully
- ✅ Result JSON contains correct values
- ✅ Verifier passed with score 95/100

[Include verification result JSON]

## Files Collected
1. evidence_desktop.png - Desktop screenshot
2. evidence_sam_window.png - SAM application window
3. evidence_configured.png - Configured PV system
4. evidence_saved_file.png - Saved project file
5. env_setup_pre_start.log - Installation log
6. env_setup_post_start.log - Setup log
7. task_result.json - Export result
8. Phoenix_Residential_5kW.sam - Actual project file
9. verification_result.json - Verifier output
```

## Expected Timeline

- **Environment Boot**: 3-5 minutes
- **SAM Installation** (pre_start hook): 2-3 minutes
- **Setup** (post_start hook): 1-2 minutes
- **Task Setup** (pre_task hook): 30 seconds
- **Manual Task Completion**: 5-10 minutes (depending on familiarity)
- **Verification**: 10 seconds
- **Evidence Collection**: 2-3 minutes

**Total**: Approximately 15-25 minutes

## Troubleshooting

If issues occur:

### SAM Won't Launch
```bash
# Check installation
ls -l /opt/SAM/sam

# Check logs
cat /home/ga/env_setup_pre_start.log
cat /home/ga/env_setup_post_start.log

# Try launching manually
DISPLAY=:1 /opt/SAM/sam
```

### GUI Not Visible
```bash
# Check X server
ps aux | grep X11

# Check display
echo $DISPLAY  # Should be :1

# List windows
DISPLAY=:1 wmctrl -l
```

### Task Setup Fails
```bash
# Check script exists
ls -l /workspace/tasks/create_residential_pv_system/setup_task.sh

# Run manually with verbose output
bash -x /workspace/tasks/create_residential_pv_system/setup_task.sh
```

### Verification Fails
```bash
# Run export script manually
bash /workspace/tasks/create_residential_pv_system/export_result.sh

# Check result
cat /tmp/task_result.json

# Verify project file exists
ls -l /home/ga/Documents/SAM_Projects/Phoenix_Residential_5kW.sam

# Check file contents
head -20 /home/ga/Documents/SAM_Projects/Phoenix_Residential_5kW.sam
```

## Completion Checklist

- [ ] Environment starts without errors
- [ ] SAM installs successfully
- [ ] Desktop is visible in screenshot
- [ ] SAM launches and window is visible
- [ ] Can create new project
- [ ] Can configure system parameters
- [ ] Can save project file
- [ ] Export script produces valid JSON
- [ ] Verifier passes with score >= 75
- [ ] All evidence files collected
- [ ] Evidence README written
- [ ] No mock/fake data used

## Next Steps After Testing

1. Update `evidence/README.md` with actual results
2. Include all collected screenshots and logs
3. Document any issues encountered and how they were resolved
4. Update environment notes if any quirks were discovered
5. Consider creating additional tasks (wind farm, CSP, battery storage, etc.)
