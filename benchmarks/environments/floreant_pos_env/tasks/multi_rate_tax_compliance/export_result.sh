#!/bin/bash
# post_task hook for multi_rate_tax_compliance
# Queries Derby DB to extract tax and menu item data for verification

echo "=== Exporting multi_rate_tax_compliance result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/floreant_task_end.png

# Kill Floreant POS to release Derby file locks
kill_floreant
sleep 4

# Find Derby DB path
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_POSDB" ]; then
    DB_POSDB="/opt/floreantpos/database/derby-server/posdb"
fi
echo "Derby DB path: $DB_POSDB"

# Remove stale Derby lock files
rm -f "$DB_POSDB/db.lck" "$DB_POSDB/tmp/db.lck" 2>/dev/null || true

# Setup Derby tools (download if not present)
DERBY_TOOLS="/opt/floreant_derby_tools"
if [ ! -f "$DERBY_TOOLS/derby.jar" ] || [ ! -f "$DERBY_TOOLS/derbytools.jar" ]; then
    echo "Downloading Apache Derby tools..."
    mkdir -p "$DERBY_TOOLS"
    DERBY_ZIP="/tmp/derby_tools_dl.zip"
    wget -q --tries=3 --timeout=180 \
        "https://archive.apache.org/dist/db/derby/db-derby-10.14.2.0/db-derby-10.14.2.0-bin.zip" \
        -O "$DERBY_ZIP" 2>/dev/null || \
    wget -q --tries=3 --timeout=180 \
        "https://downloads.apache.org/db/derby/db-derby-10.15.2.0/db-derby-10.15.2.0-bin.zip" \
        -O "$DERBY_ZIP" 2>/dev/null
    if [ -f "$DERBY_ZIP" ] && [ -s "$DERBY_ZIP" ]; then
        cd /tmp && unzip -q "$DERBY_ZIP" -d /tmp/derby_extract 2>/dev/null
        find /tmp/derby_extract -name "derby.jar" | head -1 | xargs -I{} cp {} "$DERBY_TOOLS/" 2>/dev/null
        find /tmp/derby_extract -name "derbytools.jar" | head -1 | xargs -I{} cp {} "$DERBY_TOOLS/" 2>/dev/null
        rm -rf /tmp/derby_extract "$DERBY_ZIP"
        echo "Derby tools installed."
    else
        echo "WARNING: Could not download Derby tools."
    fi
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Query Derby and write result JSON
python3 << PYEOF
import subprocess, json, os, sys

DB_PATH = "$DB_POSDB"
DERBY_DIR = "$DERBY_TOOLS"
TASK_START = int("$TASK_START" or "0")

def run_ij(sql):
    """Run SQL via Derby ij and return stdout."""
    connect = f"connect 'jdbc:derby:{DB_PATH};readonly=true';"
    cmd_in = f"{connect}\n{sql}\nexit;\n"
    try:
        r = subprocess.run(
            ['java', '-cp', f'{DERBY_DIR}/derby.jar:{DERBY_DIR}/derbytools.jar',
             'org.apache.derby.tools.ij'],
            input=cmd_in, capture_output=True, text=True, timeout=60
        )
        return r.stdout
    except Exception as e:
        return f"ERROR: {e}"

def parse_rows(output):
    """Parse Derby ij multi-column SELECT output into list of value lists."""
    rows = []
    lines = output.split('\n')
    past_header = False
    past_sep = False
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        lower = line.lower()
        if 'ij>' in lower or 'ij version' in lower or 'apache derby' in lower:
            continue
        if 'rows selected' in lower or 'row selected' in lower:
            continue
        if 'error' in lower and 'sql' in lower:
            continue
        if '|' not in line:
            if past_header and not past_sep and set(line.replace('-','').replace('+','')) <= {''}:
                past_sep = True
            continue
        parts = [p.strip() for p in line.split('|')]
        parts = [p for p in parts if p is not None]
        if not past_header:
            past_header = True
            continue  # skip header
        if past_header and not past_sep:
            # Check if this is the separator dashes line
            stripped = line.replace('-', '').replace('+', '').replace('|', '').replace(' ', '')
            if stripped == '':
                past_sep = True
                continue
            else:
                past_sep = True  # First data row immediately after header
        rows.append(parts)
    return rows

derby_ok = os.path.exists(f"{DERBY_DIR}/derby.jar")

# Query taxes
tax_out = run_ij("SELECT ID, NAME, RATE FROM TAX ORDER BY NAME;")
taxes = parse_rows(tax_out)

# Query categories
cat_out = run_ij("SELECT ID, NAME FROM MENU_CATEGORY ORDER BY NAME;")
categories = parse_rows(cat_out)

# Query menu items with tax assignment (join through MENU_GROUP to reach MENU_CATEGORY)
item_out = run_ij("SELECT MI.ID, MI.NAME, MI.TAX_ID, MC.NAME AS CAT_NAME FROM MENU_ITEM MI LEFT JOIN MENU_GROUP MG ON MI.GROUP_ID = MG.ID LEFT JOIN MENU_CATEGORY MC ON MG.CATEGORY_ID = MC.ID ORDER BY MC.NAME, MI.NAME;")
items = parse_rows(item_out)

result = {
    "derby_tools_available": derby_ok,
    "task_start": TASK_START,
    "taxes": [
        {"id": r[0], "name": r[1], "rate": r[2]}
        for r in taxes if len(r) >= 3
    ],
    "categories": [
        {"id": r[0], "name": r[1]}
        for r in categories if len(r) >= 2
    ],
    "items_with_tax": [
        {"id": r[0], "name": r[1], "tax_id": r[2], "category": r[3] if len(r) > 3 else ""}
        for r in items if len(r) >= 3
    ],
    "raw_tax_output": tax_out[:2000],
}

out_path = '/tmp/multi_rate_tax_compliance_result.json'
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result written to {out_path}")
print(f"Taxes found: {len(result['taxes'])}")
print(f"Items found: {len(result['items_with_tax'])}")
for t in result['taxes']:
    print(f"  TAX: {t['name']} @ {t['rate']}%")
PYEOF

echo "=== Export complete ==="
