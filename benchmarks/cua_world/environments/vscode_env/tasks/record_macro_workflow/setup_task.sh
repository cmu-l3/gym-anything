#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Record Macro Workflow Task ==="

WORKSPACE_DIR="/home/ga/workspace/macro_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create Python file with 20 repetitive functions
cat > "$WORKSPACE_DIR/data_processors.py" << 'EOF'
"""Data transformation functions for legacy ETL pipeline"""

def process_user_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_order_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_product_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_inventory_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_shipping_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_payment_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_customer_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_vendor_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_warehouse_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_category_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_tag_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_review_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_rating_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_comment_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_feedback_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_analytics_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_metrics_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_report_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_export_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned

def process_import_data(raw_data):
    cleaned = raw_data.strip().lower()
    return cleaned
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the file
echo "Opening VSCode with data_processors.py..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/data_processors.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Record Macro Workflow Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Add 'import logging' at the top of the file"
echo "  2. Transform all 20 functions with:"
echo "     - Type hints: (raw_data: str) -> str"
echo "     - Logging statement: logging.info(f'Processing {name} data')"
echo "     - Try-except wrapper with error logging"
echo "  3. Use multi-cursor (Alt+Click) or find-replace (Ctrl+H) for efficiency"
echo "  4. Save file (Ctrl+S) when complete"
echo ""
echo "File location: $WORKSPACE_DIR/data_processors.py"