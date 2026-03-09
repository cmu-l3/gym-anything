#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Automate Build Workflow Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Create BUILD_STEPS.txt documenting the manual workflow
cat > "$WORKSPACE_DIR/BUILD_STEPS.txt" << 'EOF'
# Manual Build Workflow

Run these commands in order before deployment:

1. Clean previous build artifacts
   rm -rf dist/ *.pyc __pycache__

2. Validate input data against schema
   python validate_data.py --strict --input data/input.csv

3. Process data and generate outputs
   python process_data.py --input data/input.csv --output dist/

4. Create deployment package
   tar -czf deploy.tar.gz dist/

Note: Must run from project root directory
EOF

# Create validate_data.py
cat > "$WORKSPACE_DIR/validate_data.py" << 'EOF'
#!/usr/bin/env python3
import argparse
import json
import sys

def validate_data(input_file, strict=False):
    print(f"[VALIDATION] Checking {input_file}...")
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    if len(lines) < 2:
        print("[VALIDATION] ERROR: No data rows found")
        sys.exit(1)
    
    print(f"[VALIDATION] ✓ Found {len(lines)-1} data rows")
    print("[VALIDATION] ✓ Validation passed")
    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--strict', action='store_true')
    args = parser.parse_args()
    
    validate_data(args.input, args.strict)
EOF

chmod +x "$WORKSPACE_DIR/validate_data.py"

# Create process_data.py
cat > "$WORKSPACE_DIR/process_data.py" << 'EOF'
#!/usr/bin/env python3
import argparse
import os
import csv
import json

def process_data(input_file, output_dir):
    print(f"[PROCESSING] Reading {input_file}...")
    
    os.makedirs(output_dir, exist_ok=True)
    
    with open(input_file, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    output_file = os.path.join(output_dir, 'processed_data.json')
    
    with open(output_file, 'w') as f:
        json.dump(rows, f, indent=2)
    
    print(f"[PROCESSING] ✓ Processed {len(rows)} rows")
    print(f"[PROCESSING] ✓ Output saved to {output_file}")
    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    
    process_data(args.input, args.output)
EOF

chmod +x "$WORKSPACE_DIR/process_data.py"

# Create sample input data
cat > "$WORKSPACE_DIR/data/input.csv" << 'EOF'
id,name,value
1,alpha,100
2,beta,200
3,gamma,300
4,delta,400
5,epsilon,500
EOF

# Create schema.json for realism
cat > "$WORKSPACE_DIR/data/schema.json" << 'EOF'
{
  "type": "object",
  "required": ["id", "name", "value"],
  "properties": {
    "id": {"type": "integer"},
    "name": {"type": "string"},
    "value": {"type": "number"}
  }
}
EOF

# Create a README for context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Data Pipeline Project

This project processes CSV data through validation and transformation steps.

## Current Workflow

See BUILD_STEPS.txt for the manual build process.

## TODO

Automate the build workflow using VSCode tasks to save time!
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open BUILD_STEPS.txt for reference
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/BUILD_STEPS.txt'" || true
sleep 1

echo "=== Automate Build Workflow Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read BUILD_STEPS.txt to understand the manual workflow"
echo "  2. Create .vscode/tasks.json in the workspace root"
echo "  3. Define a task that runs all 4 steps in sequence:"
echo "     - Clean: rm -rf dist/"
echo "     - Validate: python validate_data.py --strict --input data/input.csv"
echo "     - Process: python process_data.py --input data/input.csv --output dist/"
echo "     - Package: tar -czf deploy.tar.gz dist/"
echo "  4. Set it as the default build task"
echo "  5. Save the tasks.json file"