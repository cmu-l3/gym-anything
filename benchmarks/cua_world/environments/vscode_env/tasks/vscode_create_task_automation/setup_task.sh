#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up VSCode Task Automation Task ==="

WORKSPACE_DIR="/home/ga/workspace/sales_analysis"
VSCODE_DIR="${WORKSPACE_DIR}/.vscode"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create Python analysis script
cat > "$WORKSPACE_DIR/analyze_sales.py" << 'EOF'
#!/usr/bin/env python3
"""
Sales data analysis script
Analyzes sales data and generates JSON report
"""
import argparse
import json
import sys
import csv

def main():
    parser = argparse.ArgumentParser(description='Analyze sales data')
    parser.add_argument('--input', required=True, help='Input CSV file with sales data')
    parser.add_argument('--output', required=True, help='Output JSON file for results')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose output')
    
    args = parser.parse_args()
    
    if args.verbose:
        print(f"[INFO] Reading sales data from: {args.input}")
        print(f"[INFO] Results will be written to: {args.output}")
    
    try:
        # Read and process CSV data
        total_sales = 0
        transaction_count = 0
        
        with open(args.input, 'r') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                if 'amount' in row:
                    total_sales += float(row['amount'])
                    transaction_count += 1
        
        # Calculate statistics
        avg_sale = total_sales / transaction_count if transaction_count > 0 else 0
        
        results = {
            "total_sales": round(total_sales, 2),
            "num_transactions": transaction_count,
            "average_sale": round(avg_sale, 2),
            "status": "success"
        }
        
        # Write results
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        
        if args.verbose:
            print(f"[INFO] Processed {transaction_count} transactions")
            print(f"[INFO] Total sales: ${total_sales:.2f}")
            print(f"[INFO] Average sale: ${avg_sale:.2f}")
        
        print("✅ Analysis complete!")
        return 0
        
    except FileNotFoundError:
        print(f"❌ Error: Input file '{args.input}' not found", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"❌ Error during analysis: {str(e)}", file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
EOF

chmod +x "$WORKSPACE_DIR/analyze_sales.py"

# Create sample CSV data file
cat > "$WORKSPACE_DIR/sales_data.csv" << 'EOF'
date,product,amount,customer
2024-01-15,Widget A,120.00,ACME Corp
2024-01-16,Widget B,95.50,Tech Solutions
2024-01-17,Widget A,200.00,Global Industries
2024-01-18,Widget C,150.75,StartUp Inc
2024-01-19,Widget B,89.99,ACME Corp
2024-01-20,Widget A,175.00,Tech Solutions
2024-01-21,Widget C,210.50,Enterprise LLC
2024-01-22,Widget B,99.99,Global Industries
EOF

# Ensure .vscode directory does NOT exist (agent must create it)
if [ -d "$VSCODE_DIR" ]; then
    echo "Removing existing .vscode directory..."
    rm -rf "$VSCODE_DIR"
fi

# Set proper ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode to this workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== VSCode Task Automation Setup Complete ==="
echo "📝 Workspace: $WORKSPACE_DIR"
echo "📝 Files created:"
echo "   - analyze_sales.py (Python script)"
echo "   - sales_data.csv (sample data)"
echo ""
echo "📋 Task Instructions:"
echo "  1. Create .vscode directory in the workspace"
echo "  2. Create tasks.json file inside .vscode/"
echo "  3. Define a task that runs: python analyze_sales.py --input sales_data.csv --output report.json --verbose"
echo "  4. Task should have type 'shell', command 'python', and appropriate args"
echo "  5. Save the file"
echo ""
echo "💡 Hint: Use Command Palette (Ctrl+Shift+P) → 'Tasks: Configure Task'"