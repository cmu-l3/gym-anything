#!/bin/bash
set -e
echo "=== Setting up task: link_dangling_tasks_schedule_integrity ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create projects directory
mkdir -p /home/ga/Projects
chown -R ga:ga /home/ga/Projects

# Clean up previous runs
rm -f /home/ga/Projects/renovation_fixed.xml

# Generate the renovation project XML with dangling tasks
# Structure:
# 10 (Landscaping) -> Dangling
# 11 (Security System) -> Dangling
# 12 (Project Completion) -> Only linked to 9 currently
cat > /home/ga/Projects/renovation_project.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Project xmlns="http://schemas.microsoft.com/project">
  <Name>Community Center Renovation</Name>
  <Title>Renovation Schedule</Title>
  <StartDate>2025-04-01T08:00:00</StartDate>
  <Tasks>
    <Task><UID>0</UID><ID>0</ID><Name>Community Center Renovation</Name><Summary>1</Summary></Task>
    <Task><UID>1</UID><ID>1</ID><Name>Project Start</Name><Duration>PT0H0M0S</Duration><Milestone>1</Milestone><Start>2025-04-01T08:00:00</Start><Finish>2025-04-01T08:00:00</Finish></Task>
    
    <Task><UID>2</UID><ID>2</ID><Name>Demolition</Name><Duration>PT40H0M0S</Duration><Start>2025-04-01T08:00:00</Start><Finish>2025-04-07T17:00:00</Finish>
        <PredecessorLink><PredecessorUID>1</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <Task><UID>3</UID><ID>3</ID><Name>Foundation Repairs</Name><Duration>PT24H0M0S</Duration><Start>2025-04-08T08:00:00</Start><Finish>2025-04-10T17:00:00</Finish>
        <PredecessorLink><PredecessorUID>2</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <Task><UID>4</UID><ID>4</ID><Name>Structural Framing</Name><Duration>PT80H0M0S</Duration><Start>2025-04-11T08:00:00</Start><Finish>2025-04-24T17:00:00</Finish>
        <PredecessorLink><PredecessorUID>3</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <Task><UID>5</UID><ID>5</ID><Name>Electrical Rough-in</Name><Duration>PT32H0M0S</Duration><Start>2025-04-25T08:00:00</Start><Finish>2025-04-30T17:00:00</Finish>
        <PredecessorLink><PredecessorUID>4</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <Task><UID>6</UID><ID>6</ID><Name>Plumbing Rough-in</Name><Duration>PT32H0M0S</Duration><Start>2025-04-25T08:00:00</Start><Finish>2025-04-30T17:00:00</Finish>
        <PredecessorLink><PredecessorUID>4</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <Task><UID>7</UID><ID>7</ID><Name>Drywall Installation</Name><Duration>PT40H0M0S</Duration><Start>2025-05-01T08:00:00</Start><Finish>2025-05-07T17:00:00</Finish>
        <PredecessorLink><PredecessorUID>5</PredecessorUID><Type>1</Type></PredecessorLink>
        <PredecessorLink><PredecessorUID>6</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <Task><UID>8</UID><ID>8</ID><Name>Paint &amp; Finish</Name><Duration>PT40H0M0S</Duration><Start>2025-05-08T08:00:00</Start><Finish>2025-05-14T17:00:00</Finish>
        <PredecessorLink><PredecessorUID>7</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <Task><UID>9</UID><ID>9</ID><Name>Flooring</Name><Duration>PT24H0M0S</Duration><Start>2025-05-15T08:00:00</Start><Finish>2025-05-19T17:00:00</Finish>
        <PredecessorLink><PredecessorUID>8</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <!-- DANGLING TASK 1 -->
    <Task><UID>10</UID><ID>10</ID><Name>Landscaping</Name><Duration>PT40H0M0S</Duration><Start>2025-05-01T08:00:00</Start><Finish>2025-05-07T17:00:00</Finish>
        <!-- Starts after Framing, but no successor! -->
        <PredecessorLink><PredecessorUID>4</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <!-- DANGLING TASK 2 -->
    <Task><UID>11</UID><ID>11</ID><Name>Security System Install</Name><Duration>PT16H0M0S</Duration><Start>2025-05-15T08:00:00</Start><Finish>2025-05-16T17:00:00</Finish>
        <!-- Starts after Paint, but no successor! -->
        <PredecessorLink><PredecessorUID>8</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
    
    <Task><UID>12</UID><ID>12</ID><Name>Project Completion</Name><Duration>PT0H0M0S</Duration><Milestone>1</Milestone><Start>2025-05-20T08:00:00</Start><Finish>2025-05-20T08:00:00</Finish>
        <!-- Currently only linked to Flooring (9) -->
        <PredecessorLink><PredecessorUID>9</PredecessorUID><Type>1</Type></PredecessorLink>
    </Task>
  </Tasks>
</Project>
EOF

chown ga:ga /home/ga/Projects/renovation_project.xml

# Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Launch ProjectLibre with the renovation project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre /home/ga/Projects/renovation_project.xml > /tmp/projectlibre.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ProjectLibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Dismiss tips/dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="