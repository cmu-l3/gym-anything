#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Cleanup Python Imports Task ==="

WORKSPACE_DIR="/home/ga/workspace/cleanup_imports_task"
PROJECT_DIR="$WORKSPACE_DIR/myproject"

# Create workspace and project structure
sudo -u ga mkdir -p "$PROJECT_DIR"

# Create the messy Python file with unused imports
cat > "$PROJECT_DIR/data_processor.py" << 'EOF'
import os
import sys
import json
from typing import List, Dict
import pandas as pd
import numpy as np
from datetime import datetime
import requests
import matplotlib.pyplot as plt
from collections import defaultdict
import re
from pathlib import Path
import logging
from .utils import validate_data, format_output
from .config import DATABASE_URL
import yaml
import csv
import time

def process_dataset(file_path: str) -> Dict:
    """Process a dataset file and return statistics."""
    data = pd.read_csv(file_path)
    
    # Validate input
    if not validate_data(data):
        logging.error("Invalid data format")
        return {}
    
    # Calculate statistics
    stats = {
        'row_count': len(data),
        'mean': np.mean(data['values']),
        'timestamp': datetime.now().isoformat()
    }
    
    # Format and return
    return format_output(stats)

def load_config() -> Dict:
    """Load configuration from JSON file."""
    config_path = Path(__file__).parent / 'config.json'
    with open(config_path, 'r') as f:
        return json.load(f)

def main():
    config = load_config()
    result = process_dataset(config['input_file'])
    print(result)

if __name__ == '__main__':
    main()
EOF

# Create package __init__.py
cat > "$PROJECT_DIR/__init__.py" << 'EOF'
"""MyProject package"""
EOF

# Create dummy utils module
cat > "$PROJECT_DIR/utils.py" << 'EOF'
"""Utility functions for data processing"""

def validate_data(data):
    """Validate data format"""
    return True

def format_output(stats):
    """Format statistics output"""
    return stats
EOF

# Create dummy config module
cat > "$PROJECT_DIR/config.py" << 'EOF'
"""Configuration constants"""

DATABASE_URL = "sqlite:///db.sqlite"
API_KEY = "dummy_key"
EOF

# Create a sample config.json
cat > "$PROJECT_DIR/config.json" << 'EOF'
{
  "input_file": "data.csv"
}
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace and file
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$PROJECT_DIR/data_processor.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 3
focus_vscode_window

echo "=== Cleanup Python Imports Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. File opened: $PROJECT_DIR/data_processor.py"
echo "  2. Remove ALL unused imports (look for grayed-out imports)"
echo "  3. Organize remaining imports by PEP 8:"
echo "     - Standard library (json, logging, etc.)"
echo "     - Third-party (pandas, numpy)"
echo "     - Local (from .utils, from .config)"
echo "  4. Save the file (Ctrl+S)"
echo ""
echo "Hint: VSCode's Python extension highlights unused imports in gray"