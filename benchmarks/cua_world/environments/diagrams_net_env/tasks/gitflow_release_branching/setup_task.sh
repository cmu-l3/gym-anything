#!/bin/bash
set -e
echo "=== Setting up GitFlow Release Branching Task ==="

# 1. Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. Create the Scenario File
SCENARIO_FILE="/home/ga/Desktop/release_scenario.txt"
cat > "$SCENARIO_FILE" << 'EOF'
============================================================
  CloudStore API Platform — Release v2.4.0 GitFlow Scenario
============================================================

PROJECT CONTEXT:
  CloudStore API Platform is a microservices-based e-commerce
  backend. The team follows the GitFlow branching model.
  The current production version is v2.3.1 on the main branch.

DIAGRAM CONVENTIONS (MUST FOLLOW):
  - Time flows LEFT to RIGHT
  - main branch: TOP of diagram, BLUE (#2196F3) color
  - develop branch: BELOW main, GREEN (#4CAF50) color
  - feature/* branches: BELOW develop, ORANGE (#FF9800) color
  - release/* branches: BETWEEN main and develop, PURPLE (#9C27B0) color
  - hotfix/* branches: BETWEEN main and develop, RED (#F44336) color
  - Commits: small filled circles on branch lines
  - Merges: arrows from source branch to target branch
  - Version tags: rectangle labels on main branch at release points
  - Branch creation: arrow from parent branch to new branch start

TIMELINE OF EVENTS (CHRONOLOGICAL ORDER):
------------------------------------------

[T1] Starting state:
     - main branch has tag v2.3.1
     - develop branch is active, branched from main after v2.3.1

[T2] feature/user-preferences branch created from develop
     - Commit C1: "Add user preference model"
     - Commit C2: "Implement preference API endpoints"

[T3] feature/payment-retry branch created from develop
     - Commit C3: "Add payment retry logic"
     - Commit C4: "Add exponential backoff"
     - Commit C5: "Add retry configuration"

[T4] feature/user-preferences merged back into develop

[T5] feature/audit-logging branch created from develop
     - Commit C6: "Implement audit log middleware"

[T6] feature/payment-retry merged back into develop

[T7] feature/audit-logging merged back into develop

[T8] release/2.4.0 branch created from develop
     - Commit C7: "Bump version to 2.4.0-rc1"
     - Commit C8: "Fix migration script ordering"

[T9] CRITICAL: hotfix/2.3.2 branch created from main
     - Commit C9: "Fix critical auth token expiry bug"
     - hotfix/2.3.2 merged into main → tag v2.3.2
     - hotfix/2.3.2 merged into develop

[T10] release/2.4.0 continues:
      - Commit C10: "Fix integration test failures"
      - release/2.4.0 merged into main → tag v2.4.0
      - release/2.4.0 merged back into develop

SUMMARY OF BRANCHES (7 total):
  1. main
  2. develop
  3. feature/user-preferences
  4. feature/payment-retry
  5. feature/audit-logging
  6. release/2.4.0
  7. hotfix/2.3.2

REQUIRED OUTPUTS:
  1. Save source to ~/Diagrams/gitflow_release.drawio
  2. Export image to ~/Diagrams/gitflow_release.png
EOF
chown ga:ga "$SCENARIO_FILE"

# 3. Clean up previous artifacts
rm -f /home/ga/Diagrams/gitflow_release.drawio
rm -f /home/ga/Diagrams/gitflow_release.png

# 4. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io
echo "Launching draw.io..."
# Kill any existing instances
pkill -f "drawio" 2>/dev/null || true
sleep 1

# Launch
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /tmp/drawio.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done
sleep 3

# 6. Handle Update Dialog (Aggressive Dismissal)
echo "Dismissing potential update dialogs..."
for i in {1..5}; do
    # Try Escape
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    # Try Tab+Enter (Cancel)
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
    sleep 0.5
    # Click common Cancel location
    DISPLAY=:1 xdotool mousemove 1050 580 click 1 2>/dev/null || true
done

# 7. Maximize Window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Open the scenario file text editor alongside (optional but helpful)
# We won't force it open to avoid clutter, the agent can open it.
# But we will ensure the file is visible on the desktop by refreshing? No need.

# 9. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="