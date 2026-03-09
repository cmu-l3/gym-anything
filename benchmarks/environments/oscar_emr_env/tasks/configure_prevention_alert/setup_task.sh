#!/bin/bash
# Setup script for Configure Prevention Alert task

echo "=== Setting up Configure Prevention Alert Task ==="

source /workspace/scripts/task_utils.sh

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean up any existing rule with the target name to ensure fresh creation
# The table is typically 'prevention' in Oscar EMR
echo "Cleaning up any existing 'Senior Weight Monitor' rules..."
oscar_query "DELETE FROM prevention WHERE prevention_name LIKE 'Senior Weight Monitor%'" 2>/dev/null || true

# 3. Record initial count of prevention rules
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM prevention" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_prevention_count
echo "Initial prevention rule count: $INITIAL_COUNT"

# 4. Ensure Firefox is open on the login page
ensure_firefox_on_oscar

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Prevention Rule 'Senior Weight Monitor'"
echo "  - Age: >= 65"
echo "  - Frequency: Every 12 Months"
echo "  - Logic: Missing Weight recording"
echo "  - Alert: 'Monitor for unexpected weight loss'"