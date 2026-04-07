#!/bin/bash

echo "=== Exporting quarterly_portfolio_rebalance result ==="

RESULT_PATH="/tmp/quarterly_portfolio_rebalance_result.json"
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
WATCHLIST_DIR="/home/ga/.jstock/1.0.7/UnitedState/watchlist/Q1 Rebalance Watch"
EXPORT_FILE="/home/ga/Documents/portfolio_q1_export.csv"

# ============================================================
# 1. Kill JStock to flush all CSV data to disk
# ============================================================
pkill -f "jstock" 2>/dev/null || true
sleep 4

# ============================================================
# 2. Read task start timestamp
# ============================================================
TASK_START=$(cat /tmp/task_start_ts_quarterly_portfolio_rebalance 2>/dev/null || echo "0")

# ============================================================
# 3. Parse all relevant CSV files and build result JSON
# ============================================================
python3 << 'PYEOF'
import json, csv, os, sys

result = {"task": "quarterly_portfolio_rebalance"}

portfolio_dir = "/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
watchlist_dir = "/home/ga/.jstock/1.0.7/UnitedState/watchlist/Q1 Rebalance Watch"
export_file = "/home/ga/Documents/portfolio_q1_export.csv"
task_start = int(open("/tmp/task_start_ts_quarterly_portfolio_rebalance").read().strip()) if os.path.isfile("/tmp/task_start_ts_quarterly_portfolio_rebalance") else 0

result["task_start"] = task_start

# --- Helper: read CSV entries ---
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
        result.setdefault("errors", []).append(f"CSV parse error {filepath}: {e}")
    return entries

# --- Helper: find entries by code ---
def find_entries(entries, code):
    return [e for e in entries if e.get("Code", "").upper() == code.upper()]

def find_entry(entries, code):
    matches = find_entries(entries, code)
    return matches[-1] if matches else None

# ============================================================
# Buy portfolio
# ============================================================
buy_entries = read_csv_entries(os.path.join(portfolio_dir, "buyportfolio.csv"))
result["buy_entries"] = buy_entries
result["buy_count"] = len(buy_entries)

# Find new buy entries (XOM, KO, and new JNJ at ~$162.50)
result["buy_xom"] = find_entry(buy_entries, "XOM")
result["buy_ko"] = find_entry(buy_entries, "KO")

# For JNJ, find the NEW entry (price ~162.50, not the original at 160.00)
jnj_entries = find_entries(buy_entries, "JNJ")
result["buy_jnj_all"] = jnj_entries
result["buy_jnj_new"] = None
for e in jnj_entries:
    try:
        p = float(e.get("Purchase Price", "0") or "0")
        if abs(p - 162.50) < 2.0:  # new entry at ~$162.50, not the original $160.00
            result["buy_jnj_new"] = e
            break
    except ValueError:
        pass

# ============================================================
# Sell portfolio
# ============================================================
sell_entries = read_csv_entries(os.path.join(portfolio_dir, "sellportfolio.csv"))
result["sell_entries"] = sell_entries
result["sell_count"] = len(sell_entries)
result["sell_aapl"] = find_entry(sell_entries, "AAPL")
result["sell_nvda"] = find_entry(sell_entries, "NVDA")

# ============================================================
# Deposit summary
# ============================================================
deposit_entries = read_csv_entries(os.path.join(portfolio_dir, "depositsummary.csv"))
result["deposit_entries"] = deposit_entries
result["deposit_count"] = len(deposit_entries)

# Find the new $25K deposit (not the pre-existing $100K)
result["deposit_new"] = None
for e in deposit_entries:
    try:
        amt = float(e.get("Amount", "0") or "0")
        if abs(amt - 25000.0) < 2000.0:
            result["deposit_new"] = e
            break
    except ValueError:
        pass

# ============================================================
# Dividend summary
# ============================================================
dividend_entries = read_csv_entries(os.path.join(portfolio_dir, "dividendsummary.csv"))
result["dividend_entries"] = dividend_entries
result["dividend_count"] = len(dividend_entries)
result["dividend_aapl"] = find_entry(dividend_entries, "AAPL")

# ============================================================
# Watchlist: Q1 Rebalance Watch
# ============================================================
result["watchlist_exists"] = os.path.isdir(watchlist_dir)
watch_entries = read_csv_entries(os.path.join(watchlist_dir, "realtimestock.csv"))
result["watch_entries"] = watch_entries
result["watch_count"] = len(watch_entries)

for code in ["AAPL", "MSFT", "NVDA", "JNJ", "XOM", "KO"]:
    result[f"watch_{code.lower()}"] = find_entry(watch_entries, code)

# ============================================================
# Export file
# ============================================================
result["export_exists"] = os.path.isfile(export_file)
result["export_size"] = 0
result["export_is_new"] = False
result["export_symbols"] = []
if result["export_exists"]:
    result["export_size"] = os.path.getsize(export_file)
    mtime = os.path.getmtime(export_file)
    result["export_is_new"] = mtime > task_start
    # Check which stock symbols appear in the export
    try:
        with open(export_file, "r", encoding="utf-8") as ef:
            content = ef.read().upper()
        for sym in ["AAPL", "MSFT", "NVDA", "JNJ", "XOM", "KO"]:
            if sym in content:
                result["export_symbols"].append(sym)
    except Exception:
        pass

# ============================================================
# Write result JSON
# ============================================================
with open("/tmp/quarterly_portfolio_rebalance_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Buy entries: {result['buy_count']} — XOM:{result['buy_xom'] is not None}, KO:{result['buy_ko'] is not None}, JNJ new:{result['buy_jnj_new'] is not None}")
print(f"Sell entries: {result['sell_count']} — AAPL:{result['sell_aapl'] is not None}, NVDA:{result['sell_nvda'] is not None}")
print(f"Deposits: {result['deposit_count']} — new 25K:{result['deposit_new'] is not None}")
print(f"Dividends: {result['dividend_count']} — AAPL:{result['dividend_aapl'] is not None}")
print(f"Watchlist exists: {result['watchlist_exists']}, entries: {result['watch_count']}")
print(f"Export: exists={result['export_exists']}, size={result['export_size']}, symbols={result['export_symbols']}")
print(f"Result written to /tmp/quarterly_portfolio_rebalance_result.json")
PYEOF

echo "=== quarterly_portfolio_rebalance export complete ==="
