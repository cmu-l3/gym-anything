#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Triage Production Logs Task ==="

WORKSPACE_DIR="/home/ga/workspace/incident_logs"
TASK_ASSETS="/workspace/tasks/triage_production_logs/assets"

# Create workspace
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Generate production log file if not already present
if [ ! -f "$TASK_ASSETS/production_payment_service.log" ]; then
    echo "Generating production log file..."
    sudo -u ga mkdir -p "$TASK_ASSETS"
    sudo -u ga python3 /workspace/tasks/triage_production_logs/generate_log.py "$TASK_ASSETS/production_payment_service.log"
fi

# Copy log file and README to workspace
echo "Copying log file to workspace..."
sudo -u ga cp "$TASK_ASSETS/production_payment_service.log" "$WORKSPACE_DIR/"

# Create README with task instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Production Incident - 2024-01-15

## Background
Payment service experiencing elevated error rates starting ~03:15 UTC.
Customer support receiving complaints about failed checkouts.

## Your Task
Analyze the `production_payment_service.log` file and create a triage summary.

## Requirements
Create `triage_summary.md` in this directory with:
- Error type counts (e.g., "ERR_PAYMENT_TIMEOUT: 23 occurrences")
- List of affected transaction IDs (at least 10)
- Incident timeline/timestamp range
- Patterns observed (e.g., specific gateway affected)
- Recommended actions

## Log Format