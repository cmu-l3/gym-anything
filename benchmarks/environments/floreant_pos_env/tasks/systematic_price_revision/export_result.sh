#!/bin/bash
# post_task hook for systematic_price_revision

echo "=== Exporting systematic_price_revision result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/floreant_task_end.png

kill_floreant
sleep 4

DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
[ -z "$DB_POSDB" ] && DB_POSDB="/opt/floreantpos/database/derby-server/posdb"

rm -f "$DB_POSDB/db.lck" "$DB_POSDB/tmp/db.lck" 2>/dev/null || true

DERBY_TOOLS="/opt/floreant_derby_tools"
if [ ! -f "$DERBY_TOOLS/derby.jar" ] || [ ! -f "$DERBY_TOOLS/derbytools.jar" ]; then
    echo "Downloading Derby tools..."
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
        echo "Derby tools ready."
    fi
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

python3 << PYEOF
import subprocess, json, os

DB_PATH = "$DB_POSDB"
DERBY_DIR = "$DERBY_TOOLS"
TASK_START = int("$TASK_START" or "0")

def run_ij(sql):
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
        if '|' not in line:
            continue
        parts = [p.strip() for p in line.split('|')]
        parts = [p for p in parts if p is not None]
        if not past_header:
            past_header = True
            continue
        if past_header and not past_sep:
            stripped = line.replace('-','').replace('+','').replace('|','').replace(' ','')
            if stripped == '':
                past_sep = True
                continue
            else:
                past_sep = True
        rows.append(parts)
    return rows

derby_ok = os.path.exists(f"{DERBY_DIR}/derby.jar")

# Query all menu items with prices (actual table: MENU_ITEM)
item_out = run_ij("SELECT ID, NAME, PRICE FROM MENU_ITEM ORDER BY NAME;")
items = parse_rows(item_out)

# Query categories (actual table: MENU_CATEGORY)
cat_out = run_ij("SELECT ID, NAME FROM MENU_CATEGORY ORDER BY NAME;")
categories = parse_rows(cat_out)

result = {
    "derby_tools_available": derby_ok,
    "task_start": TASK_START,
    "items": [
        {"id": r[0], "name": r[1], "price": r[2], "category_id": r[3] if len(r) > 3 else ""}
        for r in items if len(r) >= 3
    ],
    "categories": [{"id": r[0], "name": r[1]} for r in categories if len(r) >= 2],
}

# Find specific items
for target_name in ["HAMMER COFFEE", "SMK HOUS B FAST", "OLD TIMER B FAST",
                    "WAGYU BEEF BURGER", "TRUFFLE FRIES", "ARTISAN CHEESE PLATE"]:
    found = None
    for item in result["items"]:
        if item["name"].strip().upper() == target_name.upper():
            found = item
            break
    result[f"item_{target_name.replace(' ', '_').lower()}"] = found

out_path = '/tmp/systematic_price_revision_result.json'
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result written: {out_path}")
print(f"Items in DB: {len(result['items'])}")
print(f"Categories: {len(result['categories'])}")
for name in ["HAMMER COFFEE", "SMK HOUS B FAST", "OLD TIMER B FAST"]:
    key = f"item_{name.replace(' ', '_').lower()}"
    item = result.get(key)
    print(f"  {name}: price={item['price'] if item else 'NOT FOUND'}")
PYEOF

echo "=== Export complete ==="
