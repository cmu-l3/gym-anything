#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Offline Mode Task ==="

WORKSPACE_DIR="/home/ga/workspace/offline_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a sample Python data science project
cat > "$WORKSPACE_DIR/analysis.py" << 'EOF'
import pandas as pd
import numpy as np

def load_data(filepath):
    """Load CSV data for analysis."""
    return pd.read_csv(filepath)

def compute_statistics(data):
    """Compute basic statistics."""
    return {
        'mean': data.mean(),
        'median': data.median(),
        'std': data.std()
    }

def main():
    # TODO: Load data.csv and compute statistics
    pass

if __name__ == "__main__":
    main()
EOF

# Create sample CSV data
cat > "$WORKSPACE_DIR/data.csv" << 'EOF'
timestamp,temperature,humidity,pressure
2024-01-01 00:00:00,22.5,45.2,1013.2
2024-01-01 01:00:00,21.8,46.1,1013.5
2024-01-01 02:00:00,21.2,47.3,1013.8
2024-01-01 03:00:00,20.9,48.5,1014.1
2024-01-01 04:00:00,20.5,49.2,1014.3
EOF

# Create requirements file
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
pandas>=2.0.0
numpy>=1.24.0
matplotlib>=3.7.0
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Weather Data Analysis

A simple Python project for analyzing weather sensor data.

## Setup
