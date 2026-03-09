#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract from Massive Log Task ==="

WORKSPACE_DIR="/home/ga/workspace/incident_logs"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Create workspace settings (empty initially - task is to configure this)
cat > "$WORKSPACE_DIR/.vscode/settings.json" << 'EOF'
{
}
EOF

# Create urgent README from SRE team
cat > "$WORKSPACE_DIR/URGENT_README.txt" << 'EOF'
PRODUCTION INCIDENT - PRIORITY 1

Timeline: 06:00 - 14:00 today
Service: payment-gateway-api
Issue: Intermittent payment failures

The production_dump.log contains 8 hours of logs (~450MB).
We need ALL occurrences of:
  "CRITICAL: Payment gateway timeout - transaction failed"

Extract these with context (2 lines before and after) to understand the pattern.
Time is critical - merchants are losing revenue!

Save results to: payment_failures.log

- SRE Team
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Generate large synthetic log file with critical errors
echo "Generating 450MB log file with critical errors (this may take 30-60 seconds)..."

python3 << 'PYTHON_SCRIPT'
import random
import datetime
from pathlib import Path

output_file = Path("/home/ga/workspace/incident_logs/production_dump.log")
target_size_mb = 450
critical_error_count = 0
target_critical_errors = 34

print("Generating large log file with synthetic data...")

# Pre-generate some data to speed up
services = ["payment-gateway-api", "user-auth-service", "order-processing", "inventory-service", "notification-service"]
log_levels = ["INFO", "DEBUG", "WARN", "ERROR"]

normal_templates = [
    "Request processed successfully in {ms}ms",
    "Cache hit for key: user_{id}",
    "API call to /api/v1/{endpoint} returned 200",
    "Database query completed in {ms}ms",
    "User authentication successful for session {id}",
    "Payment processed: amount ${amount} USD",
    "Order created: ORDER-{id}",
    "Inventory check: item {id} - {qty} units available",
    "Rate limit checked: {req} requests in window",
    "Health check: all dependencies healthy",
    "Session initialized for user {id}",
    "Cache miss, fetching from database",
    "Background job completed: task_{id}",
    "WebSocket connection established",
    "Email notification sent to user_{id}",
    "Scheduled task executed successfully",
    "Memory usage: {percent}%",
    "CPU load average: {load}",
    "Disk I/O operation completed",
    "Network latency: {ms}ms"
]

with open(output_file, 'w') as f:
    current_size = 0
    target_size_bytes = target_size_mb * 1024 * 1024
    
    start_time = datetime.datetime(2024, 12, 15, 6, 0, 0)
    current_time = start_time
    
    line_counter = 0
    
    while current_size < target_size_bytes:
        line_counter += 1
        timestamp = current_time.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        service = random.choice(services)
        
        # Calculate progress
        progress = current_size / target_size_bytes
        errors_so_far_expected = int(progress * target_critical_errors)
        
        # Decide if this should be a critical error
        # Distribute errors throughout the file
        inject_critical = (
            critical_error_count < target_critical_errors and 
            random.random() < 0.00012 and
            critical_error_count <= errors_so_far_expected + 3 and
            service == "payment-gateway-api"
        )
        
        if inject_critical:
            # Write context BEFORE error (2 lines)
            f.write(f"{timestamp} INFO payment-gateway-api Request received from merchant_id={random.randint(1000,9999)} amount=${random.randint(10,5000)}\n")
            current_time += datetime.timedelta(milliseconds=random.randint(50, 300))
            timestamp = current_time.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
            
            f.write(f"{timestamp} DEBUG payment-gateway-api Initiating transaction: TX{random.randint(100000,999999)} via stripe_gateway\n")
            current_time += datetime.timedelta(milliseconds=random.randint(50, 300))
            timestamp = current_time.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
            
            # THE CRITICAL ERROR
            f.write(f"{timestamp} CRITICAL payment-gateway-api Payment gateway timeout - transaction failed\n")
            critical_error_count += 1
            current_time += datetime.timedelta(milliseconds=random.randint(10, 100))
            timestamp = current_time.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
            
            # Write context AFTER error (2 lines)
            f.write(f"{timestamp} ERROR payment-gateway-api Rolling back transaction TX{random.randint(100000,999999)}\n")
            current_time += datetime.timedelta(milliseconds=random.randint(50, 200))
            timestamp = current_time.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
            
            f.write(f"{timestamp} WARN payment-gateway-api Retry scheduled: attempt 1 of 3 in {random.randint(5,30)}s\n")
            current_time += datetime.timedelta(milliseconds=random.randint(100, 500))
            
        else:
            # Normal log line
            level = random.choice(log_levels)
            template = random.choice(normal_templates)
            message = template.format(
                ms=random.randint(5, 500),
                id=random.randint(1000, 9999),
                endpoint=random.choice(["users", "orders", "payments", "inventory"]),
                amount=random.randint(10, 5000),
                qty=random.randint(1, 100),
                req=random.randint(1, 1000),
                percent=random.randint(20, 90),
                load=round(random.uniform(0.5, 8.0), 2)
            )
            
            line = f"{timestamp} {level} {service} {message}\n"
            f.write(line)
            
            # Advance time
            current_time += datetime.timedelta(milliseconds=random.randint(10, 1000))
        
        current_size = f.tell()
        
        # Progress indicator
        if line_counter % 100000 == 0:
            progress_pct = (current_size / target_size_bytes) * 100
            print(f"Progress: {progress_pct:.1f}% ({current_size / (1024*1024):.1f}MB) - {critical_error_count} critical errors")

final_size_mb = current_size / (1024 * 1024)
print(f"✓ Generated {output_file}: {final_size_mb:.1f}MB with {critical_error_count} critical errors")
PYTHON_SCRIPT

if [ $? -ne 0 ]; then
    echo "❌ Failed to generate log file"
    exit 1
fi

# Fix permissions
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Clear bash history so agent starts fresh
sudo -u ga bash -c "echo '' > ~/.bash_history"

# Open VSCode with workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the README file to show instructions
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/URGENT_README.txt'" || true
sleep 1

echo "=== Extract from Massive Log Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  - Workspace: $WORKSPACE_DIR"
echo "  - Large log: production_dump.log (~450MB with ~34 critical errors)"
echo "  - README: URGENT_README.txt (opened in editor)"
echo ""
echo "📋 Instructions:"
echo "  1. Configure VSCode: Set 'files.maxMemoryForLargeFilesMB' >= 1024"
echo "  2. Open integrated terminal (Ctrl+\`)"
echo "  3. Extract errors: grep -B 2 -A 2 'CRITICAL: Payment gateway timeout - transaction failed' production_dump.log > payment_failures.log"
echo "  4. Verify: Open payment_failures.log in VSCode"
echo ""
echo "⚠️  DO NOT open production_dump.log directly - it will freeze VSCode!"