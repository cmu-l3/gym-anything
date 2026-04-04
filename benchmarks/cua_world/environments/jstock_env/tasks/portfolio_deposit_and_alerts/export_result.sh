#!/bin/bash

echo "=== Exporting portfolio_deposit_and_alerts result ==="

RESULT_PATH="/tmp/portfolio_deposit_and_alerts_result.json"
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/Fund Alpha"
WATCHLIST_DIR="/home/ga/.jstock/1.0.7/UnitedState/watchlist/Fund Alpha Watch"

# Kill JStock to flush all CSV data to disk
pkill -f "jstock" 2>/dev/null || true
sleep 4

python3 << PYEOF
import json, csv, os

result = {"task": "portfolio_deposit_and_alerts"}

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

def find_entry(entries, code):
    matches = [e for e in entries if e.get("Code", "").upper() == code.upper()]
    return matches[-1] if matches else None

# Deposit summary
deposit_entries = read_csv_entries(os.path.join(portfolio_dir, "depositsummary.csv"))
result["deposit_entries"] = deposit_entries
result["deposit_count"] = len(deposit_entries)
result["deposit_first"] = deposit_entries[0] if deposit_entries else None

# Buy portfolio
buy_entries = read_csv_entries(os.path.join(portfolio_dir, "buyportfolio.csv"))
result["buy_entries"] = buy_entries
result["buy_count"] = len(buy_entries)
result["buy_spy"] = find_entry(buy_entries, "SPY")
result["buy_brkb"] = find_entry(buy_entries, "BRK.B")

# Fund Alpha Watch watchlist
watch_entries = read_csv_entries(os.path.join(watchlist_dir, "realtimestock.csv"))
result["watch_entries"] = watch_entries
result["watch_count"] = len(watch_entries)
result["watch_spy"] = find_entry(watch_entries, "SPY")
result["watch_qqq"] = find_entry(watch_entries, "QQQ")
result["watch_brkb"] = find_entry(watch_entries, "BRK.B")
result["watch_gld"] = find_entry(watch_entries, "GLD")
result["watch_tlt"] = find_entry(watch_entries, "TLT")
result["watch_vti"] = find_entry(watch_entries, "VTI")

with open("${RESULT_PATH}", "w") as f:
    json.dump(result, f, indent=2)

print(f"Portfolio exists: {result['portfolio_exists']}")
print(f"Deposit entries: {result['deposit_count']}")
print(f"Buy entries: {result['buy_count']} — SPY:{result['buy_spy'] is not None}, BRK.B:{result['buy_brkb'] is not None}")
print(f"Watchlist exists: {result['watchlist_exists']}, Watch entries: {result['watch_count']}")
print(f"Watch alerts: SPY:{result['watch_spy'] is not None}, QQQ:{result['watch_qqq'] is not None}, BRK.B:{result['watch_brkb'] is not None}")
print(f"Result written to ${RESULT_PATH}")
PYEOF

echo "=== portfolio_deposit_and_alerts export complete ==="
