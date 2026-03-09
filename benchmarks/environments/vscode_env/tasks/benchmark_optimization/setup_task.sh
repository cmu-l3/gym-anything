#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Benchmark Optimization Task ==="

WORKSPACE_DIR="/home/ga/workspace/benchmark_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create main data processor with original (slower) implementation
cat > "$WORKSPACE_DIR/data_processor.py" << 'EOF'
#!/usr/bin/env python3
"""Data processing script - current implementation"""
import json
import time
import sys

def transform_records(records):
    """Current implementation - potentially slow"""
    result = []
    for record in records:
        # Manual loop approach - less efficient
        total = 0
        for value in record['data']:
            total += value
        avg = total / len(record['data']) if record['data'] else 0
        
        processed_values = []
        for value in record['data']:
            processed_values.append(value * avg)
        
        result.append({
            'id': record['id'],
            'values': processed_values
        })
    return result

def main():
    if len(sys.argv) < 2:
        print("Usage: python data_processor.py <input_file>")
        sys.exit(1)
    
    start_time = time.time()
    
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    
    processed = transform_records(data['records'])
    
    with open('output.json', 'w') as f:
        json.dump({'processed': processed}, f, indent=2)
    
    elapsed = time.time() - start_time
    print(f"Processing completed in {elapsed:.3f} seconds")
    
    return elapsed

if __name__ == '__main__':
    main()
EOF

# Create optimized implementation file
cat > "$WORKSPACE_DIR/optimized_transform.py" << 'EOF'
"""Optimized implementation suggested by colleague"""

def transform_records(records):
    """Optimized implementation - uses built-in functions and list comprehension"""
    result = []
    for record in records:
        data = record['data']
        avg = sum(data) / len(data) if data else 0
        result.append({
            'id': record['id'],
            'values': [v * avg for v in data]
        })
    return result
EOF

# Generate test data (1000 records with 50 values each for noticeable timing difference)
echo "Generating test data..."
cat > "$WORKSPACE_DIR/generate_data.py" << 'EOF'
import json
import random

records = []
for i in range(1, 1001):
    data = [random.randint(1, 100) for _ in range(50)]
    records.append({'id': i, 'data': data})

with open('test_data.json', 'w') as f:
    json.dump({'records': records}, f)

print("Generated 1000 test records")
EOF

# Generate the test data
cd "$WORKSPACE_DIR"
sudo -u ga python3 generate_data.py
rm -f generate_data.py

# Create instructions file
cat > "$WORKSPACE_DIR/INSTRUCTIONS.txt" << 'EOF'
BENCHMARK OPTIMIZATION TASK
===========================

Your task is to empirically compare two implementations and keep the faster one.

Files:
- data_processor.py: Main script with current implementation
- optimized_transform.py: Suggested optimized function
- test_data.json: Test data (1000 records)

Steps:
1. Run: python data_processor.py test_data.json
2. Note the execution time printed
3. Backup output: cp output.json output_original.json
4. Replace transform_records() in data_processor.py with version from optimized_transform.py
5. Run again: python data_processor.py test_data.json
6. Note new execution time
7. Verify outputs match: diff output_original.json output.json
8. Create benchmark_report.txt with results (see format below)
9. Decision: Keep optimized if faster AND correct; otherwise revert

Report Format (create as benchmark_report.txt):
BENCHMARK RESULTS
=================
Original Time: X.XXX seconds
Optimized Time: Y.YYY seconds
Performance Improvement: Z.Z% faster/slower
Output Verification: PASS/FAIL
Decision: KEPT OPTIMIZED / REVERTED TO ORIGINAL
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open terminal in VSCode (Ctrl+`)
echo "Opening integrated terminal..."
su - ga -c "DISPLAY=:1 xdotool key ctrl+grave" || true
sleep 2

echo "=== Benchmark Optimization Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Workspace: $WORKSPACE_DIR"
echo "  1. Run: python data_processor.py test_data.json"
echo "  2. Note execution time"
echo "  3. Backup: cp output.json output_original.json"
echo "  4. Replace transform_records() with optimized version"
echo "  5. Run again and compare times"
echo "  6. Verify output matches"
echo "  7. Create benchmark_report.txt"
echo "  8. Keep faster version if correct"