#!/bin/bash

echo "=== Exporting tax_lot_portfolio_tracking result ==="

RESULT_PATH="/tmp/tax_lot_portfolio_tracking_result.json"
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/Tax Lots 2024"
WATCHLIST_DIR="/home/ga/.jstock/1.0.7/UnitedState/watchlist/Tax Watch 2024"

# Kill JStock to flush all CSV data to disk
pkill -f "jstock" 2>/dev/null || true
sleep 4

python3 << PYEOF
import json, csv, os

result = {"task": "tax_lot_portfolio_tracking"}

portfolio_dir = "${PORTFOLIO_DIR}"
watchlist_dir = "${WATCHLIST_DIR}"

result["portfolio_exists"] = os.path.isdir(portfolio_dir)
result["watchlist_exists"] = os.path.isdir(watchlist_dir)

def read_csv_entries(filepath):
    entries = []
    if not os.path.isfile(filepath):
        return entries
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            lines = f.readlines()
        data_lines = [l for l in lines if not l.strip().startswith('"timestamp=')]
        reader = csv.reader(data_lines)
        headers = None
        for row in reader:
            if not headers:
                headers = [h.strip().strip('"') for h in row]
                continue
            if not row or not any(r.strip().strip('"') for r in row):
                continue
            entry = {}
            for i, h in enumerate(headers):
                entry[h] = row[i].strip().strip('"') if i < len(row) else ""
            entries.append(entry)
    except Exception as e:
        pass
    return entries

# Buy portfolio — multiple lots per code
buy_entries = read_csv_entries(os.path.join(portfolio_dir, "buyportfolio.csv"))
result["buy_entries"] = buy_entries
result["buy_count"] = len(buy_entries)

# Separate lots by code
result["cost_lots"] = [e for e in buy_entries if e.get("Code", "").upper() == "COST"]
result["meta_lots"] = [e for e in buy_entries if e.get("Code", "").upper() == "META"]
result["amzn_lots"] = [e for e in buy_entries if e.get("Code", "").upper() == "AMZN"]

# Sell portfolio
sell_entries = read_csv_entries(os.path.join(portfolio_dir, "sellportfolio.csv"))
result["sell_entries"] = sell_entries
result["sell_count"] = len(sell_entries)
cost_sells = [e for e in sell_entries if e.get("Code", "").upper() == "COST"]
result["cost_sell"] = cost_sells[-1] if cost_sells else None

# Tax Watch 2024 watchlist alerts for META and AMZN
watch_entries = read_csv_entries(os.path.join(watchlist_dir, "realtimestock.csv"))
result["watch_entries"] = watch_entries

def find_watch(entries, code):
    for e in entries:
        if e.get("Code", "").upper() == code.upper():
            return e
    return None

result["watch_meta"] = find_watch(watch_entries, "META")
result["watch_amzn"] = find_watch(watch_entries, "AMZN")

with open("${RESULT_PATH}", "w") as f:
    json.dump(result, f, indent=2)

print(f"Portfolio exists: {result['portfolio_exists']}, Buy count: {result['buy_count']}")
print(f"COST lots: {len(result['cost_lots'])}, META lots: {len(result['meta_lots'])}, AMZN lots: {len(result['amzn_lots'])}")
print(f"Sell count: {result['sell_count']}, COST sell: {result['cost_sell'] is not None}")
print(f"Watchlist exists: {result['watchlist_exists']}, META alerts: {result['watch_meta'] is not None}, AMZN alerts: {result['watch_amzn'] is not None}")
print(f"Result written to ${RESULT_PATH}")
PYEOF

echo "=== tax_lot_portfolio_tracking export complete ==="
