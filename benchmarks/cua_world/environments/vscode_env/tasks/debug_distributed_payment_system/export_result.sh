#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Debug Distributed Payment System Result ==="

WORKSPACE_DIR="/home/ga/workspace/payment_service"
RESULT_FILE="/tmp/payment_system_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove stale result
rm -f "$RESULT_FILE"

# Collect all service files into a single JSON for the verifier
python3 << 'EXPORT_SCRIPT'
import json
import os

workspace = "/home/ga/workspace/payment_service"
files_to_export = [
    "services/payment_processor.py",
    "services/currency_converter.py",
    "services/transaction_validator.py",
    "services/ledger.py",
    "services/idempotency.py",
]

result = {}
for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    try:
        with open(full_path, "r") as f:
            result[rel_path] = f.read()
    except Exception as e:
        result[rel_path] = f"ERROR: {e}"

with open("/tmp/payment_system_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Exported files:")
for k in result:
    status = "OK" if not result[k].startswith("ERROR") else result[k]
    print(f"  {k}: {status}")
EXPORT_SCRIPT

if [ -f "$RESULT_FILE" ]; then
    echo "Export complete: $RESULT_FILE"
else
    echo "Warning: Export script did not produce $RESULT_FILE"
fi
