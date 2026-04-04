#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diagnose Library Behavior Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_pipeline"
VENV_DIR="/home/ga/.venv_datamorph"
SITE_PACKAGES="$VENV_DIR/lib/python3.10/site-packages"

# Clean up any existing setup
sudo -u ga rm -rf "$WORKSPACE_DIR" "$VENV_DIR" 2>/dev/null || true

# Create workspace
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create virtual environment
echo "Creating virtual environment..."
sudo -u ga python3 -m venv "$VENV_DIR"

# Create the mock datamorph library in site-packages
DATAMORPH_DIR="$SITE_PACKAGES/datamorph"
sudo -u ga mkdir -p "$DATAMORPH_DIR"

# Create __init__.py
cat > "$DATAMORPH_DIR/__init__.py" << 'EOF'
"""
datamorph - A fictional ETL utility library
"""
from .core import transform_batch

__version__ = "0.3.2"
__all__ = ['transform_batch']
EOF

# Create config.py
cat > "$DATAMORPH_DIR/config.py" << 'EOF'
"""
Configuration loader for datamorph.
Looks for .datamorph.config in project root.
"""
import json
import os
from pathlib import Path

def load_config():
    """
    Load configuration from .datamorph.config file.
    Searches from current working directory upward.
    
    Returns:
        dict: Configuration dictionary
    """
    config_name = '.datamorph.config'
    current_dir = Path.cwd()
    
    # Search for config file
    for parent in [current_dir] + list(current_dir.parents):
        config_path = parent / config_name
        if config_path.exists():
            print(f"[datamorph] Found config at {config_path}")
            try:
                with open(config_path) as f:
                    return json.load(f)
            except Exception as e:
                print(f"[datamorph] Error loading config: {e}")
                return {}
    
    print(f"[datamorph] No {config_name} found, using defaults")
    return {}
EOF

# Create parallel.py
cat > "$DATAMORPH_DIR/parallel.py" << 'EOF'
"""
Parallel processing implementation for datamorph.
"""
import time

class ParallelProcessor:
    def __init__(self, workers=1):
        self.workers = workers
    
    def process(self, records, operation):
        print(f"[datamorph] Processing {len(records)} records with {self.workers} workers")
        time.sleep(0.1)  # Simulate processing
        return [r for r in records]

class SerialProcessor:
    def process(self, records, operation):
        print(f"[datamorph] Processing {len(records)} records serially")
        time.sleep(0.1)  # Simulate processing
        return [r for r in records]
EOF

# Create core.py
cat > "$DATAMORPH_DIR/core.py" << 'EOF'
"""
Core transformation functions for datamorph.
"""
from .config import load_config
from .parallel import ParallelProcessor, SerialProcessor

def transform_batch(records, operation='normalize', workers=1):
    """
    Transform a batch of records.
    
    Args:
        records: List of records to transform
        operation: Type of transformation
        workers: Number of parallel workers (IGNORED unless config enabled)
    
    Returns:
        Transformed records
    """
    config = load_config()
    
    # Check if parallel processing is enabled in config
    if config.get('parallel_enabled', False):
        # Use workers from config if available, otherwise use parameter
        worker_count = config.get('workers', workers)
        processor = ParallelProcessor(workers=worker_count)
        print(f"[datamorph] Using parallel processing with {worker_count} workers")
    else:
        # Default to serial processing
        processor = SerialProcessor()
        print("[datamorph] Using serial processing (parallel disabled in config)")
    
    return processor.process(records, operation)
EOF

# Set ownership
sudo chown -R ga:ga "$DATAMORPH_DIR"

# Create the main project files
cat > "$WORKSPACE_DIR/process.py" << 'EOF'
"""
Data processing script using datamorph library.
Performance is unexpectedly slow despite library claiming parallel processing.
"""
import sys
sys.path.insert(0, '/home/ga/.venv_datamorph/lib/python3.10/site-packages')

from datamorph import transform_batch
import json

def main():
    with open('input_data.json') as f:
        data = json.load(f)
    
    # This should process in parallel but seems serial
    result = transform_batch(
        data['records'],
        operation='normalize',
        workers=4  # This argument is being ignored!
    )
    
    print(f"Processed {len(result)} records")
    return result

if __name__ == '__main__':
    main()
EOF

# Create input data
cat > "$WORKSPACE_DIR/input_data.json" << 'EOF'
{
  "records": [
    {"id": 1, "value": 100},
    {"id": 2, "value": 200},
    {"id": 3, "value": 300},
    {"id": 4, "value": 400}
  ]
}
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
datamorph==0.3.2
EOF

# Create README explaining the problem
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Data Pipeline Project

This project uses the `datamorph` library for data transformation.

## Problem

The `transform_batch()` function is supposed to support parallel processing,
but it seems to be running serially despite passing `workers=4` parameter.

The library documentation is sparse - only basic examples in the package README.

## Task

Investigate the library source code to understand why parallel processing
isn't working and fix the configuration.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode with project..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/process.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Diagnose Library Behavior Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Examine process.py to understand the problem"
echo "  2. Use 'Go to Definition' (F12) on transform_batch to jump into library code"
echo "  3. Read datamorph/core.py to see how parallel processing works"
echo "  4. Follow the code to config.py to discover config file requirement"
echo "  5. Create .datamorph.config in project root with correct JSON structure"
echo "  6. Config should enable parallel processing"
echo ""
echo "Project location: $WORKSPACE_DIR"
echo "Library location: $DATAMORPH_DIR"