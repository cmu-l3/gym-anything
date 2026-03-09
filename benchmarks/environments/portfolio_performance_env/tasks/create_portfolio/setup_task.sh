#!/bin/bash
echo "=== Setting up create_portfolio task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files from other tasks (create_portfolio starts from scratch)
clean_portfolio_data ""

# Record initial state - count existing portfolio files
INITIAL_FILE_COUNT=$(find /home/ga/Documents/PortfolioData -name "*.xml" -o -name "*.portfolio" 2>/dev/null | wc -l)
printf '%s' "$INITIAL_FILE_COUNT" > /tmp/initial_file_count

# Ensure Portfolio Performance is running and focused
# PP should already be running from post_start hook
if ! wait_for_pp_window 10; then
    echo "PP not running, relaunching..."
    su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"
    sleep 15
    wait_for_pp_window 60
fi

# Focus and maximize the PP window
WID=$(wmctrl -l | grep -i "Portfolio Performance\|PortfolioPerformance\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

echo "Initial file count: $INITIAL_FILE_COUNT"
echo "=== Task setup complete ==="
