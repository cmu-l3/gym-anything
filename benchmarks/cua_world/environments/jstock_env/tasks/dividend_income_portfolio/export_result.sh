#!/bin/bash

echo "=== Exporting dividend_income_portfolio result ==="

RESULT_PATH="/tmp/dividend_income_portfolio_result.json"
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/Income Portfolio"

# Kill JStock to flush all CSV data to disk
pkill -f "jstock" 2>/dev/null || true
sleep 4

python3 << PYEOF
import json, csv, os

result = {"task": "dividend_income_portfolio"}

portfolio_dir = "${PORTFOLIO_DIR}"

# Check if "Income Portfolio" directory exists
result["portfolio_exists"] = os.path.isdir(portfolio_dir)

def read_csv_entries(filepath):
    """Read a JStock CSV file and return list of row dicts."""
    entries = []
    if not os.path.isfile(filepath):
        return entries
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
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

# Buy portfolio
buy_entries = read_csv_entries(os.path.join(portfolio_dir, "buyportfolio.csv"))
result["buy_entries"] = buy_entries
result["buy_count"] = len(buy_entries)
result["buy_t"] = find_entry(buy_entries, "T")
result["buy_vz"] = find_entry(buy_entries, "VZ")
result["buy_ko"] = find_entry(buy_entries, "KO")
result["buy_o"] = find_entry(buy_entries, "O")

# Dividend summary
div_entries = read_csv_entries(os.path.join(portfolio_dir, "dividendsummary.csv"))
result["div_entries"] = div_entries
result["div_count"] = len(div_entries)

def find_div(entries, code):
    matches = [e for e in entries if e.get("Code", "").upper() == code.upper()]
    return matches[-1] if matches else None

result["div_t"] = find_div(div_entries, "T")
result["div_o"] = find_div(div_entries, "O")

with open("${RESULT_PATH}", "w") as f:
    json.dump(result, f, indent=2)

print(f"Portfolio exists: {result['portfolio_exists']}")
print(f"Buy entries: {result['buy_count']} — T:{result['buy_t'] is not None}, VZ:{result['buy_vz'] is not None}, KO:{result['buy_ko'] is not None}, O:{result['buy_o'] is not None}")
print(f"Dividend entries: {result['div_count']} — T:{result['div_t'] is not None}, O:{result['div_o'] is not None}")
print(f"Result written to ${RESULT_PATH}")
PYEOF

echo "=== dividend_income_portfolio export complete ==="
