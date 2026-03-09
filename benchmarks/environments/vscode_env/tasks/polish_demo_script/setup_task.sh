#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Polish Demo Script Task ==="

WORKSPACE_DIR="/home/ga/workspace/demo_prep"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy Python script
cat > "$WORKSPACE_DIR/data_processor.py" << 'EOF'
import pandas as pd
import json

# df = pd.read_csv('old_data.csv')  # old approach didn't work
# print("DEBUG: loaded data")

def process_orders(input_file):
    # TODO: add docstring later
    df = pd.read_csv(input_file)
    print(f"DEBUG: Loaded {len(df)} rows")
    
    # Filter valid orders
    df2 = df[df['status'] == 'completed']
    # df2 = df[df['amount'] > 0]  # tried this but broke things
    print(f"DEBUG: Filtered to {len(df2)} rows")
    
    # Apply discount tiers
    # This is the complex part - different discounts for different order sizes
    temp_x = []
    for idx, row in df2.iterrows():
        if row['amount'] > 1000:
            disc = row['amount'] * 0.15
        elif row['amount'] > 500:
            disc = row['amount'] * 0.10
        elif row['amount'] > 100:
            disc = row['amount'] * 0.05
        else:
            disc = 0
        temp_x.append(disc)
    
    df2['discount'] = temp_x
    df2['final_amount'] = df2['amount'] - df2['discount']
    
    # print(df2.head())  # debug
    
    # Filter recent orders (last 30 days)
    df2['order_date'] = pd.to_datetime(df2['order_date'])
    data_final_v3 = df2[df2['order_date'] >= pd.Timestamp.now() - pd.Timedelta(days=30)]
    
    print(f"DEBUG: Final dataset has {len(data_final_v3)} rows")
    # print(data_final_v3.describe())  # more debug stuff
    
    return data_final_v3

# Test code - remove before demo
# if __name__ == '__main__':
#     result = process_orders('test_data.csv')
#     print(result)
EOF

# Create sample data file with recent dates
cat > "$WORKSPACE_DIR/sample_orders.csv" << 'EOF'
order_id,status,amount,order_date,customer_id
1001,completed,1200.00,2024-01-15,C001
1002,completed,450.00,2024-01-16,C002
1003,pending,800.00,2024-01-17,C003
1004,completed,150.00,2024-01-18,C004
1005,completed,2500.00,2024-01-19,C005
1006,completed,75.00,2024-01-20,C006
1007,completed,600.00,2024-01-21,C007
1008,completed,250.00,2024-01-22,C008
EOF

# Ensure pandas is available
sudo -u ga bash -c "python3 -m pip install --user pandas --quiet" 2>/dev/null || true

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace and file
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/data_processor.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Polish Demo Script Task Setup Complete ==="
echo "📝 Task: Clean up data_processor.py for professional demo"
echo "   - File location: $WORKSPACE_DIR/data_processor.py"
echo "   - Remove debug artifacts (commented code, DEBUG prints)"
echo "   - Rename variables (df2, temp_x, data_final_v3)"
echo "   - Extract magic numbers to constants"
echo "   - Add documentation (docstring, inline comments)"
echo "   - Ensure script still works"