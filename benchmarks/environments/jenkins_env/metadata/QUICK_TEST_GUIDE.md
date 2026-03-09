# Jenkins Environment - Quick Test Guide

**Current Status:** Boot test ✅ | Task tests ready 🔄

---

## Prerequisites

- Boot test has passed (jenkins_initial_state.png captured)
- VNC viewer installed (e.g., `vncviewer` or TigerVNC)
- Python environment with paramiko installed

---

## Task 1: Create Freestyle Job

### Step 1: Run Test Script

```bash
cd /scratch/pranjala/gym_anything_clean/Gym-Anything_for_cmu
python3 test_jenkins_task1_freestyle.py
```

**Wait for:** "MANUAL TASK EXECUTION REQUIRED" message

### Step 2: Connect via VNC

```bash
# In a new terminal
vncviewer localhost:6024
```

**Password:** `password`

### Step 3: Complete Task in Jenkins UI

1. **Click** "Create a job" (or "New Item" in sidebar)
2. **Enter name:** `HelloWorld-Build`
3. **Select:** "Freestyle project"
4. **Click** OK
5. **Scroll down** to "Build" section
6. **Click** "Add build step" → "Execute shell"
7. **Enter command:** `echo 'Hello from Jenkins!'`
8. **Click** Save

### Step 4: Return to Test Terminal

**Press** Enter to continue the test script

### Step 5: Verify Results

```bash
# Check captured evidence
ls -lh benchmarks/environments/jenkins_env/evidence/task1_freestyle/

# Expected files:
# - initial_state.png
# - final_state.png
# - result.json
# - setup_task.log
# - export_result.log

# View result JSON
cat benchmarks/environments/jenkins_env/evidence/task1_freestyle/result.json
```

### Step 6: Test Verifier

```bash
python3 test_jenkins_verifier.py create_freestyle_job \
  benchmarks/environments/jenkins_env/evidence/task1_freestyle/result.json
```

**Expected output:** Score: 1.00, Success: True

---

## Task 2: Create Pipeline Job

### Step 1: Run Test Script

```bash
# Similar to Task 1, but for pipeline job
python3 test_jenkins_task2_pipeline.py  # (create this script if needed)
```

### Step 2: Complete Task in Jenkins UI

1. **Click** "New Item"
2. **Enter name:** `Maven-Build-Pipeline`
3. **Select:** "Pipeline"
4. **Click** OK
5. **Scroll to** "Pipeline" section
6. **Select** "Pipeline script from SCM"
7. **SCM:** Git
8. **Repository URL:** `https://github.com/jenkins-docs/simple-java-maven-app`
9. **Script Path:** `Jenkinsfile` (should be default)
10. **Click** Save

### Step 3: Verify

```bash
python3 test_jenkins_verifier.py create_pipeline_job \
  benchmarks/environments/jenkins_env/evidence/task2_pipeline/result.json
```

---

## Task 3: Trigger Build

### Step 1: Run Test Script

```bash
python3 test_jenkins_task3_trigger.py  # (create this script if needed)
```

**Note:** Setup script creates "Test-Job-For-Build" automatically

### Step 2: Trigger Build in Jenkins UI

1. **Click** "Test-Job-For-Build" in dashboard
2. **Click** "Build Now" in sidebar
3. **Wait** for build to complete (watch build queue/executor)
4. **Verify** build shows success (blue ball)

### Step 3: Verify

```bash
python3 test_jenkins_verifier.py trigger_build \
  benchmarks/environments/jenkins_env/evidence/task3_trigger/result.json
```

---

## Troubleshooting

### VNC Won't Connect

```bash
# Check VNC port from test output
# Look for line: "VNC: 6024"
# Try different port if shown differently
```

### Jenkins Not Responding

```bash
# Connect via SSH
ssh ga@localhost -p 2326
# Password: password123

# Check Jenkins container
docker ps

# Check Jenkins logs
docker logs jenkins-server

# Restart if needed
docker restart jenkins-server
```

### Export Script Fails

```bash
# Connect via SSH
ssh ga@localhost -p 2326

# Run export script manually
bash /workspace/tasks/create_freestyle_job/export_result.sh

# Check output
cat /tmp/create_freestyle_job_result.json
```

### Verifier Fails

```bash
# Check JSON format
cat benchmarks/environments/jenkins_env/evidence/task1_freestyle/result.json | python3 -m json.tool

# Run verifier with detailed output
python3 test_jenkins_verifier.py create_freestyle_job \
  benchmarks/environments/jenkins_env/evidence/task1_freestyle/result.json
```

---

## Quick Commands Reference

### Check Environment Status

```bash
# From test script output or SSH
docker ps
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080
```

### Capture Manual Screenshot

```bash
# Via SSH
ssh ga@localhost -p 2326
DISPLAY=:1 import -window root /tmp/manual_screenshot.png
exit

# Copy to host
scp -P 2326 ga@localhost:/tmp/manual_screenshot.png .
```

### View Jenkins Logs

```bash
# Via SSH
ssh ga@localhost -p 2326
docker logs jenkins-server | tail -50
```

### Reset Environment

```bash
# Close current environment (in Python script or Ctrl+C)
# Start fresh
python3 test_jenkins_task1_freestyle.py
```

---

## Success Criteria

### Task 1: Create Freestyle Job ✅

- [ ] Initial screenshot captured
- [ ] Job created with exact name
- [ ] Build step added with exact command
- [ ] Final screenshot shows job in list
- [ ] Export JSON contains all required fields
- [ ] Verifier score: 1.00

### Task 2: Create Pipeline Job ✅

- [ ] Initial screenshot captured
- [ ] Pipeline job created
- [ ] SCM configured to GitHub repo
- [ ] Jenkinsfile path set
- [ ] Final screenshot shows job in list
- [ ] Export JSON contains all required fields
- [ ] Verifier score: 1.00

### Task 3: Trigger Build ✅

- [ ] Initial screenshot captured
- [ ] Test job exists (from setup)
- [ ] Build triggered successfully
- [ ] Build completed
- [ ] Build result is SUCCESS
- [ ] Export JSON shows build data
- [ ] Verifier score: 1.00

---

## Evidence Checklist

After completing all tasks, verify these files exist:

```
benchmarks/environments/jenkins_env/evidence/
├── screenshots/
│   └── jenkins_initial_state.png ✅
├── logs/
│   ├── env_setup_pre_start.log ✅
│   ├── env_setup_post_start.log ✅
│   └── firefox_jenkins.log ✅
├── task1_freestyle/
│   ├── initial_state.png
│   ├── final_state.png
│   ├── result.json
│   ├── setup_task.log
│   └── export_result.log
├── task2_pipeline/
│   ├── initial_state.png
│   ├── final_state.png
│   ├── result.json
│   ├── setup_task.log
│   └── export_result.log
└── task3_trigger/
    ├── initial_state.png
    ├── final_state.png
    ├── result.json
    ├── setup_task.log
    └── export_result.log
```

---

## Next Steps After All Tests Pass

1. Update evidence/TESTING_EVIDENCE.md with all results
2. Update STATUS.md to "Production Ready"
3. Update AUDIT_RESPONSE.md with completion status
4. Create final summary document
5. Archive all evidence
6. Mark environment as validated

---

**Quick Start:** `python3 test_jenkins_task1_freestyle.py`
**VNC:** `vncviewer localhost:6024` (password: `password`)
**SSH:** `ssh ga@localhost -p 2326` (password: `password123`)
