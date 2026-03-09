#!/bin/bash

echo "=== Exporting portfolio_rebalancing result ==="

RESULT_PATH="/tmp/portfolio_rebalancing_result.json"
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
DESKTOP_DIR="/home/ga/Desktop"

# Kill JStock gracefully to ensure all data is flushed to CSV
pkill -f "jstock" 2>/dev/null || true
sleep 4

# Read task start timestamp
TASK_START=$(cat /tmp/task_start_ts_portfolio_rebalancing 2>/dev/null || echo "0")

# Collect results using Python
python3 << PYEOF
import json, csv, os, time

result = {
    "task": "portfolio_rebalancing",
    "task_start": int("${TASK_START}"),
}

portfolio_dir = "${PORTFOLIO_DIR}"
desktop_dir = "${DESKTOP_DIR}"

# ----------------------------------------------------------------
# Read sell portfolio CSV
# ----------------------------------------------------------------
sell_csv = os.path.join(portfolio_dir, "sellportfolio.csv")
sell_entries = []
try:
    with open(sell_csv, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        headers = None
        for row in reader:
            if not headers:
                headers = [h.strip('"') for h in row]
                continue
            if not row or not any(r.strip().strip('"') for r in row):
                continue
            entry = {}
            for i, h in enumerate(headers):
                entry[h] = row[i].strip('"') if i < len(row) else ""
            sell_entries.append(entry)
    result["sell_entries"] = sell_entries
    result["sell_count"] = len(sell_entries)
except Exception as e:
    result["sell_entries"] = []
    result["sell_count"] = 0
    result["sell_error"] = str(e)

# ----------------------------------------------------------------
# Read buy portfolio CSV (check for new JNJ/XOM entries)
# ----------------------------------------------------------------
buy_csv = os.path.join(portfolio_dir, "buyportfolio.csv")
buy_entries = []
try:
    with open(buy_csv, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        headers = None
        for row in reader:
            if not headers:
                headers = [h.strip('"') for h in row]
                continue
            if not row or not any(r.strip().strip('"') for r in row):
                continue
            entry = {}
            for i, h in enumerate(headers):
                entry[h] = row[i].strip('"') if i < len(row) else ""
            buy_entries.append(entry)
    result["buy_entries"] = buy_entries
    result["buy_count"] = len(buy_entries)
except Exception as e:
    result["buy_entries"] = []
    result["buy_count"] = 0
    result["buy_error"] = str(e)

# ----------------------------------------------------------------
# Check for exported CSV on Desktop
# ----------------------------------------------------------------
export_path = os.path.join(desktop_dir, "rebalance_sells_feb2024.csv")
export_exists = os.path.isfile(export_path)
export_mtime = int(os.path.getmtime(export_path)) if export_exists else 0
export_size = os.path.getsize(export_path) if export_exists else 0

result["export_file_exists"] = export_exists
result["export_file_mtime"] = export_mtime
result["export_file_size"] = export_size
result["export_file_is_new"] = export_exists and export_mtime > result["task_start"]

# ----------------------------------------------------------------
# Summary of what was found
# ----------------------------------------------------------------
sell_codes = [e.get("Code", "") for e in sell_entries]
buy_codes = [e.get("Code", "") for e in buy_entries]
result["sell_codes"] = sell_codes
result["buy_codes"] = buy_codes

# Save result
with open("${RESULT_PATH}", "w") as f:
    json.dump(result, f, indent=2)

print(f"Sell entries: {len(sell_entries)}, codes: {sell_codes}")
print(f"Buy entries: {len(buy_entries)}, codes: {buy_codes}")
print(f"Export file exists: {export_exists}, size: {export_size}")
print("Result JSON written to ${RESULT_PATH}")
PYEOF

echo "=== portfolio_rebalancing export complete ==="
