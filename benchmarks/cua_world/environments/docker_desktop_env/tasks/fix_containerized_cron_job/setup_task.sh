#!/bin/bash
set -e
echo "=== Setting up fix_containerized_cron_job ==="

# Source utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/Documents/recurring-report"
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/reports"

# 1. Generate Realistic Data
# Region NorthAmerica Total: 100.00 + 50.50 + 200.00 = 350.50
cat > "$PROJECT_DIR/data/transactions.csv" <<EOF
id,date,region,amount
TX1001,2023-10-01,NorthAmerica,100.00
TX1002,2023-10-01,Europe,200.00
TX1003,2023-10-01,NorthAmerica,50.50
TX1004,2023-10-01,Asia,100.00
TX1005,2023-10-02,NorthAmerica,200.00
TX1006,2023-10-02,Europe,150.00
TX1007,2023-10-02,Asia,300.00
EOF

# 2. Python Script (The Job)
# Relies on os.environ which cron doesn't have by default
cat > "$PROJECT_DIR/sales_report.py" <<EOF
import csv
import json
import os
import sys
from datetime import datetime

# This relies on the environment variable
target_region = os.environ.get('TARGET_REGION')

if not target_region:
    # Log to stderr which might be captured if setup is correct, or lost if not
    sys.stderr.write("Error: TARGET_REGION not set\n")
    sys.exit(1)

total = 0.0
count = 0

input_file = '/app/data/transactions.csv'
output_dir = '/app/reports'

try:
    with open(input_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['region'] == target_region:
                total += float(row['amount'])
                count += 1

    report = {
        'timestamp': datetime.now().isoformat(),
        'region': target_region,
        'transaction_count': count,
        'total_amount': total
    }

    # Use a timestamp in filename to avoid overwriting
    filename = f"{output_dir}/report_{datetime.now().strftime('%Y%m%d%H%M%S')}.json"
    with open(filename, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"Report generated: {filename}")

except Exception as e:
    sys.stderr.write(f"Failed: {e}\n")
    sys.exit(1)
EOF

# 3. Dockerfile
cat > "$PROJECT_DIR/Dockerfile" <<EOF
FROM python:3.9-slim

WORKDIR /app

# Install cron
RUN apt-get update && apt-get install -y cron && rm -rf /var/lib/apt/lists/*

COPY sales_report.py .
COPY crontab.txt /etc/cron.d/sales-cron
COPY entrypoint.sh .

# Give execution rights on the cron job
RUN chmod 0644 /etc/cron.d/sales-cron
RUN crontab /etc/cron.d/sales-cron
RUN chmod +x entrypoint.sh

# Create the reports directory
RUN mkdir -p /app/reports

ENTRYPOINT ["/app/entrypoint.sh"]
EOF

# 4. Docker Compose
cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
services:
  reporter:
    build: .
    container_name: sales-cron
    volumes:
      - ./data:/app/data:ro
      - ./reports:/app/reports
    environment:
      - TARGET_REGION=NorthAmerica
    restart: unless-stopped
EOF

# 5. Broken Crontab 
# - Uses 'python' which might not be in PATH
# - Doesn't redirect output (hard to debug)
cat > "$PROJECT_DIR/crontab.txt" <<EOF
# Run every minute
* * * * * python /app/sales_report.py
EOF

# 6. Broken Entrypoint (Does not export env vars)
cat > "$PROJECT_DIR/entrypoint.sh" <<EOF
#!/bin/bash
echo "Starting cron service..."
# Issue: Docker env vars are not visible to cron service unless explicitly dumped
cron -f
EOF

chown -R ga:ga "$PROJECT_DIR"

# Start the broken state
echo "Starting container..."
cd "$PROJECT_DIR"
su - ga -c "docker compose up -d --build"

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for container to be up
sleep 5

# Verify container is running
if ! docker ps | grep -q sales-cron; then
    echo "WARNING: sales-cron container failed to start initially"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="