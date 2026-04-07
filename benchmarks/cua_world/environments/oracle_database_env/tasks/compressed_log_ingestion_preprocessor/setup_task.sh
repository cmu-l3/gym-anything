#!/bin/bash
# Setup for Compressed Log Ingestion task
# Generates synthetic firewall log data and ensures environment is clean

set -e

echo "=== Setting up Compressed Log Ingestion Task ==="

source /workspace/scripts/task_utils.sh

# --- 1. Clean up previous artifacts ---
echo "Cleaning up..."
rm -rf /home/ga/log_warehouse
rm -f /home/ga/Desktop/blocked_report.txt
rm -f /workspace/data/firewall_trace.csv.gz
mkdir -p /workspace/data

# Drop table and directory if they exist
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE hr.firewall_logs_ext';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP VIEW hr.blocked_traffic_summary';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP DIRECTORY log_dir';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "system" "OraclePassword123" > /dev/null 2>&1 || true

# --- 2. Generate Synthetic Data ---
echo "Generating synthetic firewall logs..."
python3 << 'PYEOF'
import csv
import gzip
import random
import datetime

output_file = "/workspace/data/firewall_trace.csv.gz"
row_count = 5000
start_time = datetime.datetime(2023, 10, 1, 0, 0, 0)

actions = ["ALLOW", "ALLOW", "ALLOW", "BLOCK", "DROP"]
src_subnets = ["192.168.1", "10.0.0", "172.16.5", "203.0.113", "198.51.100"]

print(f"Generating {row_count} rows to {output_file}...")

with gzip.open(output_file, "wt", newline="") as f:
    writer = csv.writer(f)
    # No header for external table simplicity usually, but we'll exclude it in task description or handle it
    # Let's write NO header to match standard external table default behavior unless specified
    
    for i in range(1, row_count + 1):
        log_id = i
        ts = start_time + datetime.timedelta(seconds=i*2)
        timestamp = ts.strftime("%Y-%m-%d %H:%M:%S")
        
        subnet = random.choice(src_subnets)
        src_ip = f"{subnet}.{random.randint(1, 254)}"
        dest_ip = f"10.20.30.{random.randint(1, 50)}"
        action = random.choice(actions)
        bytes_transferred = random.randint(64, 4096) if action == "ALLOW" else 0
        
        writer.writerow([log_id, timestamp, src_ip, dest_ip, action, bytes_transferred])

print("Data generation complete.")
PYEOF

# Set permissions so GA can read it but maybe not write
chown ga:ga /workspace/data/firewall_trace.csv.gz
chmod 644 /workspace/data/firewall_trace.csv.gz

# --- 3. Pre-flight DB check ---
echo "Checking database..."
wait_for_window "Oracle" 1 # Dummy check, rely on Docker
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "Starting Oracle..."
    # Rely on hook, but wait a bit
    sleep 5
fi

# Ensure HR user has CREATE ANY DIRECTORY or specific grant
# Standard HR user might not have CREATE DIRECTORY
oracle_query "GRANT CREATE ANY DIRECTORY TO hr;" "system" "OraclePassword123"
oracle_query "GRANT EXECUTE ON SYS.UTL_FILE TO hr;" "system" "OraclePassword123"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Data available at: /workspace/data/firewall_trace.csv.gz"