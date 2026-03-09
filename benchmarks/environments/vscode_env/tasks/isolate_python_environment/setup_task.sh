#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Isolate Python Environment Task ==="

WORKSPACE_DIR="/home/ga/workspace/sales_analysis"

# Clean any existing workspace
rm -rf "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"

# Create requirements.txt with specific versions
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
pandas==1.5.3
numpy==1.23.5
matplotlib==3.6.0
EOF

# Create main Python script that requires these packages
cat > "$WORKSPACE_DIR/analyze_sales.py" << 'EOF'
#!/usr/bin/env python3
"""
Sales analysis script - requires specific pandas/numpy versions
"""
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

def analyze_sales(csv_path):
    """Load and analyze sales data"""
    print("Loading sales data...")
    df = pd.read_csv(csv_path)
    print(f"Loaded {len(df)} sales records")
    
    # Calculate statistics
    total_sales = df['amount'].sum()
    avg_sales = df['amount'].mean()
    std_sales = df['amount'].std()
    
    print(f"\n=== Sales Analysis ===")
    print(f"Total sales: ${total_sales:,.2f}")
    print(f"Average sale: ${avg_sales:,.2f}")
    print(f"Std deviation: ${std_sales:,.2f}")
    
    # Find top product
    top_product = df.groupby('product')['amount'].sum().idxmax()
    print(f"Top product: {top_product}")
    
    return df

if __name__ == "__main__":
    import os
    csv_file = "data/sales_q4.csv"
    if os.path.exists(csv_file):
        df = analyze_sales(csv_file)
        print("\n✅ Analysis complete!")
    else:
        print(f"❌ Error: {csv_file} not found")
EOF

# Create sample CSV data
cat > "$WORKSPACE_DIR/data/sales_q4.csv" << 'EOF'
date,product,amount,region
2023-10-01,Widget A,1250.00,North
2023-10-02,Widget B,890.50,South
2023-10-03,Widget A,1450.00,East
2023-10-05,Widget C,2100.00,West
2023-10-07,Widget B,750.00,North
2023-10-09,Widget A,1680.00,South
2023-10-12,Widget C,2300.00,East
2023-10-15,Widget B,920.00,West
2023-10-18,Widget A,1150.00,North
2023-10-20,Widget C,1890.00,South
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Sales Analysis Project

Quick data analysis tool for Q4 2023 sales data.

## Requirements

- Python 3.10+
- pandas 1.5.3
- numpy 1.23.5
- matplotlib 3.6.0

## Setup

1. Create virtual environment: