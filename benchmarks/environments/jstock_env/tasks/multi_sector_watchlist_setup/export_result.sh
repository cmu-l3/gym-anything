#!/bin/bash

echo "=== Exporting multi_sector_watchlist_setup result ==="

RESULT_PATH="/tmp/multi_sector_watchlist_setup_result.json"
JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState/watchlist"

# Kill JStock to flush all CSV data to disk
pkill -f "jstock" 2>/dev/null || true
sleep 4

python3 << PYEOF
import json, csv, os

result = {"task": "multi_sector_watchlist_setup"}

def read_watchlist(watchlist_name):
    """Read a watchlist CSV and return list of {Code, Fall Below, Rise Above}."""
    base = "/home/ga/.jstock/1.0.7/UnitedState/watchlist"
    csv_path = os.path.join(base, watchlist_name, "realtimestock.csv")
    entries = []
    if not os.path.isfile(csv_path):
        return None, entries
    try:
        with open(csv_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        # Skip "timestamp=0" header line
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
        return True, entries
    except Exception as e:
        return False, []

# Technology_Coverage
tech_exists, tech_entries = read_watchlist("Technology_Coverage")
result["tech_watchlist_exists"] = bool(tech_exists)
result["tech_entries"] = tech_entries

# Healthcare_Coverage
health_exists, health_entries = read_watchlist("Healthcare_Coverage")
result["health_watchlist_exists"] = bool(health_exists)
result["health_entries"] = health_entries

# Energy_Coverage
energy_exists, energy_entries = read_watchlist("Energy_Coverage")
result["energy_watchlist_exists"] = bool(energy_exists)
result["energy_entries"] = energy_entries

# Helper: find entry for code
def find_entry(entries, code):
    for e in entries:
        if e.get("Code", "").upper() == code.upper():
            return e
    return None

result["tech_aapl"] = find_entry(tech_entries, "AAPL")
result["tech_googl"] = find_entry(tech_entries, "GOOGL")
result["tech_msft"] = find_entry(tech_entries, "MSFT")
result["health_jnj"] = find_entry(health_entries, "JNJ")
result["health_unh"] = find_entry(health_entries, "UNH")
result["health_pfe"] = find_entry(health_entries, "PFE")
result["energy_xom"] = find_entry(energy_entries, "XOM")
result["energy_cvx"] = find_entry(energy_entries, "CVX")
result["energy_cop"] = find_entry(energy_entries, "COP")

with open("${RESULT_PATH}", "w") as f:
    json.dump(result, f, indent=2)

print(f"Tech watchlist exists: {tech_exists}, entries: {len(tech_entries)}")
print(f"Health watchlist exists: {health_exists}, entries: {len(health_entries)}")
print(f"Energy watchlist exists: {energy_exists}, entries: {len(energy_entries)}")
print(f"Result written to ${RESULT_PATH}")
PYEOF

echo "=== multi_sector_watchlist_setup export complete ==="
