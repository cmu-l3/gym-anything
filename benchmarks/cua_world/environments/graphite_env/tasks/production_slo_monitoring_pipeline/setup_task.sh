#!/bin/bash
echo "=== Setting up production_slo_monitoring_pipeline task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 180

# Remove stale result files from any previous runs
rm -f /tmp/production_slo_monitoring_pipeline_result.json 2>/dev/null || true
rm -f /tmp/production_slo_monitoring_pipeline_dashboards.json 2>/dev/null || true
rm -f /tmp/production_slo_monitoring_pipeline_metrics.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name and clean whisper files
docker exec graphite python3 - << 'PYEOF'
import sqlite3, os, shutil
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Payment Service SLO'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Payment Service SLO' dashboard")
except Exception as e:
    print(f"Note (Dashboard Cleanup): {e}")

try:
    whisper_dir = '/opt/graphite/storage/whisper/apps'
    if os.path.exists(whisper_dir):
        shutil.rmtree(whisper_dir)
        print("Cleaned up existing apps whisper files")
except Exception as e:
    print(f"Note (Whisper Cleanup): {e}")
PYEOF

# Rebuild index after cleanup
docker exec graphite /opt/graphite/bin/build-index.sh 2>/dev/null || true

# Generate the payment service telemetry data file
echo "Generating payment service telemetry data..."
python3 /workspace/scripts/generate_payment_data.py \
    --output /opt/graphite_real_data/payment_service_metrics.txt \
    --days 3 --interval 300

if [ -f /opt/graphite_real_data/payment_service_metrics.txt ]; then
    LINE_COUNT=$(wc -l < /opt/graphite_real_data/payment_service_metrics.txt)
    echo "Data file generated: ${LINE_COUNT} lines"
else
    echo "WARNING: Data file generation failed!"
fi

# Verify infrastructure metrics exist (fed by feed_real_data.py during env setup)
echo "Checking infrastructure metrics..."
if metric_exists "servers.ec2_instance_1.cpu.utilization"; then
    echo "  Found: servers.ec2_instance_1.cpu.utilization"
else
    echo "  WARNING: Missing: servers.ec2_instance_1.cpu.utilization"
fi

# Record task start timestamp
date +%s > /tmp/production_slo_monitoring_pipeline_start_ts

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Open terminal for agent to use (this task requires CLI work)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Take initial screenshot
take_screenshot /tmp/production_slo_monitoring_pipeline_start_screenshot.png

echo "=== production_slo_monitoring_pipeline setup complete ==="
