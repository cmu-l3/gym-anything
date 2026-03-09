#!/bin/bash
set -e
echo "=== Setting up populate_watchlist_from_memo task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous state
# Kill JStock if running
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# Remove the specific watchlist if it exists from a previous run
# Note: JStock directory structure is ~/.jstock/<version>/<Country>/watchlist/<Name>/
rm -rf "/home/ga/.jstock/1.0.7/UnitedState/watchlist/Big Banks" 2>/dev/null || true

# 2. Create the Memo File
mkdir -p /home/ga/Documents
cat > "/home/ga/Documents/morning_memo.txt" << 'EOF'
From: Portfolio Manager
Date: Oct 24, 2024
Subject: Banking Sector Watchlist

Please set up a new JStock watchlist called 'Big Banks'. 
We need to monitor the consumer giants: 
- JPMorgan Chase (JPM)
- Bank of America (BAC)
- Wells Fargo (WFC)
- Citigroup (C)

Note: We are dropping coverage on Goldman Sachs (GS) and Morgan Stanley (MS), 
so please exclude them for now even if they appear in other lists.

Thanks.
EOF

# Set permissions
chown ga:ga "/home/ga/Documents/morning_memo.txt"
chmod 644 "/home/ga/Documents/morning_memo.txt"

# 3. Launch JStock
# Using the standard launch script provided in the environment
echo "Launching JStock..."
if [ -f "/usr/local/bin/launch-jstock" ]; then
    su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock.log 2>&1 &"
else
    # Fallback if custom launcher isn't there (should be in this env)
    su - ga -c "DISPLAY=:1 java -jar /opt/jstock/jstock.jar &"
fi

# Wait for JStock window
echo "Waiting for JStock window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Maximize JStock window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# 4. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="