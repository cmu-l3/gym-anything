#!/bin/bash
echo "=== Setting up create_multicurrency_portfolio task ==="

source /workspace/scripts/task_utils.sh

# Mark task start time
mark_task_start

# 1. Clean up ALL existing portfolio data to ensure a fresh start
# We want the agent to create the file from scratch
echo "Cleaning portfolio data directory..."
rm -rf /home/ga/Documents/PortfolioData/*
mkdir -p /home/ga/Documents/PortfolioData
chown ga:ga /home/ga/Documents/PortfolioData

# 2. Ensure Portfolio Performance is running and ready
echo "Checking Portfolio Performance status..."
if ! wait_for_pp_window 5; then
    echo "Starting Portfolio Performance..."
    su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"
    
    # Wait for window to appear
    wait_for_pp_window 60
else
    echo "Portfolio Performance is already running."
fi

# 3. Ensure window is maximized and focused
WID=$(wmctrl -l | grep -i "Portfolio Performance\|PortfolioPerformance\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 4. Close any open files (if the app was already running with a file open)
# We simulate pressing Ctrl+W (Close) a few times to ensure we are at the welcome screen/empty state
# This is safer than killing the process if it's already running to avoid lock file issues
echo "Ensuring empty workspace..."
for i in {1..3}; do
    xdotool key --window "$WID" ctrl+w 2>/dev/null || true
    sleep 0.5
done
# Dismiss any potential "Save changes?" dialogs with "No" (usually Alt+N or Esc, sticking to Esc for safety)
xdotool key --window "$WID" Escape 2>/dev/null || true
sleep 1

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="