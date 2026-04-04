#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Import Errors Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_analysis"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create incomplete requirements.txt (missing requests, has wrong sklearn name)
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
pandas>=1.5.0
numpy>=1.23.0
matplotlib>=3.6.0
EOF

# Create the main analysis script with import errors
cat > "$WORKSPACE_DIR/analyze_data.py" << 'EOF'
#!/usr/bin/env python3
"""
Data Analysis Script
Analyzes sample dataset and generates visualizations
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import requests  # Missing from requirements.txt!
from sklearn.preprocessing import StandardScaler  # Wrong package name in requirements!

def fetch_data():
    """Fetch sample data from API"""
    response = requests.get('https://jsonplaceholder.typicode.com/users')
    return response.json()

def analyze_data():
    """Perform data analysis"""
    # Create sample dataset
    data = {
        'values': np.random.randn(100),
        'labels': np.random.choice(['A', 'B', 'C'], 100)
    }
    df = pd.DataFrame(data)
    
    # Standardize data
    scaler = StandardScaler()
    df['normalized'] = scaler.fit_transform(df[['values']])
    
    print(f"Analysis complete. Mean: {df['normalized'].mean():.2f}")
    print(f"Dataset shape: {df.shape}")
    return df

if __name__ == "__main__":
    print("Starting data analysis...")
    result = analyze_data()
    print("✓ Analysis completed successfully")
EOF

chmod +x "$WORKSPACE_DIR/analyze_data.py"

# Create a helper script to test imports
cat > "$WORKSPACE_DIR/test_imports.py" << 'EOF'
#!/usr/bin/env python3
"""Test if all required imports work"""
import sys

try:
    import pandas
    print("✓ pandas imported successfully")
except ImportError as e:
    print(f"✗ pandas import failed: {e}")
    sys.exit(1)

try:
    import numpy
    print("✓ numpy imported successfully")
except ImportError as e:
    print(f"✗ numpy import failed: {e}")
    sys.exit(1)

try:
    import matplotlib
    print("✓ matplotlib imported successfully")
except ImportError as e:
    print(f"✗ matplotlib import failed: {e}")
    sys.exit(1)

try:
    import requests
    print("✓ requests imported successfully")
except ImportError as e:
    print(f"✗ requests import failed: {e}")
    sys.exit(1)

try:
    from sklearn.preprocessing import StandardScaler
    print("✓ sklearn (scikit-learn) imported successfully")
except ImportError as e:
    print(f"✗ sklearn import failed: {e}")
    sys.exit(1)

print("\n✓✓✓ All imports successful! ✓✓✓")
sys.exit(0)
EOF

chmod +x "$WORKSPACE_DIR/test_imports.py"

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Data Analysis Project

## Setup