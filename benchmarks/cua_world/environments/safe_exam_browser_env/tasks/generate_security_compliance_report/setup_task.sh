#!/bin/bash
echo "=== Setting up generate_security_compliance_report task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create target directory and ensure correct permissions
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Wait for SEB Server database container to be ready
echo "Waiting for seb-server-mariadb container..."
for i in {1..30}; do
    if docker exec seb-server-mariadb mysqladmin ping -h localhost -uroot -psebserver123 2>/dev/null | grep -q "alive"; then
        echo "Database is ready."
        break
    fi
    sleep 2
done

# Seed the database dynamically with configurations
echo "Seeding SEB Server Database with Exam Configurations..."
python3 << 'PYEOF'
import subprocess
import json
import random

def db_query(query):
    result = subprocess.run(['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root', '-psebserver123', 'SEBServer', '-N', '-e', query], capture_output=True, text=True)
    return result.stdout.strip()

def db_exec(query):
    subprocess.run(['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root', '-psebserver123', 'SEBServer', '-e', query], capture_output=True)

# Discover schema configuration for value table
desc_val = db_query("DESCRIBE configuration_value")
use_config_id = 'configuration_id' in desc_val

# Ensure attributes exist
db_exec("INSERT IGNORE INTO configuration_attribute (name, type) VALUES ('allowVirtualMachine', 'BOOLEAN')")
db_exec("INSERT IGNORE INTO configuration_attribute (name, type) VALUES ('allowScreenSharing', 'BOOLEAN')")

attr_vm = db_query("SELECT id FROM configuration_attribute WHERE name='allowVirtualMachine' LIMIT 1")
attr_ss = db_query("SELECT id FROM configuration_attribute WHERE name='allowScreenSharing' LIMIT 1")

subjects = ["Math", "History", "Science", "Literature", "Art", "Physics", "Chemistry"]
random.shuffle(subjects)
num_configs = random.randint(4, 6)

ground_truth = {}

for i in range(num_configs):
    name = f"Config_{chr(65+i)}_{subjects[i]}"
    vm = random.choice(["true", "false"])
    ss = random.choice(["true", "false"])
    
    # 1. Insert Node
    db_exec(f"INSERT INTO configuration_node (name, type, active) VALUES ('{name}', 'EXAM_CONFIG', 1)")
    node_id = db_query(f"SELECT id FROM configuration_node WHERE name='{name}' ORDER BY id DESC LIMIT 1")
    
    # 2. Insert Values mapping (handles schema variations across SEB versions)
    if use_config_id:
        db_exec(f"INSERT IGNORE INTO configuration (configuration_node_id, active) VALUES ({node_id}, 1)")
        config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={node_id} ORDER BY id DESC LIMIT 1")
        if config_id:
            db_exec(f"INSERT INTO configuration_value (configuration_id, configuration_attribute_id, value) VALUES ({config_id}, {attr_vm}, '{vm}')")
            db_exec(f"INSERT INTO configuration_value (configuration_id, configuration_attribute_id, value) VALUES ({config_id}, {attr_ss}, '{ss}')")
    else:
        db_exec(f"INSERT INTO configuration_value (configuration_node_id, configuration_attribute_id, value) VALUES ({node_id}, {attr_vm}, '{vm}')")
        db_exec(f"INSERT INTO configuration_value (configuration_node_id, configuration_attribute_id, value) VALUES ({node_id}, {attr_ss}, '{ss}')")
        
    # Store ground truth for verification (hidden from agent)
    ground_truth[name] = {"allowVirtualMachine": vm, "allowScreenSharing": ss}

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

print(f"Seeded {num_configs} random configurations.")
PYEOF

# Ensure ground truth is not easily readable by non-root agents if possible, though /tmp is accessible
chmod 644 /tmp/ground_truth.json

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="