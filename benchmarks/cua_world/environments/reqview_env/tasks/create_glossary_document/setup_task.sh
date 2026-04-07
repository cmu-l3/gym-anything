#!/bin/bash
set -e
echo "=== Setting up create_glossary_document task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup a fresh project
# We use a custom function to copy and PRUNE the project to avoid Free Plan limits (max 3 docs).
# The default example has NEEDS, SRS, TESTS, ARCH (4 docs). We'll keep NEEDS and SRS.
PROJECT_PATH=$(setup_task_project "glossary_task")
echo "Project created at: $PROJECT_PATH"

# Remove TESTS and ARCH to make room for GLOSS
rm -f "$PROJECT_PATH/documents/TESTS.json"
rm -f "$PROJECT_PATH/documents/ARCH.json"

# Update project.json to remove references to deleted docs
# Using python for reliable JSON manipulation
python3 << PYEOF
import json, os
p_path = "$PROJECT_PATH/project.json"
try:
    with open(p_path) as f:
        data = json.load(f)
    
    # Filter documents list
    if 'documents' in data:
        data['documents'] = [d for d in data['documents'] if d not in ['TESTS', 'ARCH']]
    
    with open(p_path, 'w') as f:
        json.dump(data, f, indent=2)
    print("Pruned TESTS and ARCH from project configuration.")
except Exception as e:
    print(f"Error modifying project.json: {e}")
PYEOF

# 3. Create the input text file with terms
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/glossary_terms.txt << EOF
MQTT: Message Queuing Telemetry Transport, a lightweight messaging protocol.
Broker: A server that receives all messages from clients and then routes the messages to the appropriate destination clients.
Topic: A string used by the broker to filter messages for each connected client.
Publish: The action of sending a message to a topic.
Subscribe: The action of requesting messages from a topic.
EOF
chown ga:ga /home/ga/Documents/glossary_terms.txt
chmod 644 /home/ga/Documents/glossary_terms.txt

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch ReqView
launch_reqview_with_project "$PROJECT_PATH"

# 6. Final UI Prep
dismiss_dialogs
maximize_window

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="