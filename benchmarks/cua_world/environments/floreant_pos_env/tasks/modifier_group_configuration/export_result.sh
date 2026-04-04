#!/bin/bash
# post_task hook for modifier_group_configuration

echo "=== Exporting modifier_group_configuration result ==="

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

# Try multiple possible table names for modifier groups
modifier_group_out = run_ij("SELECT ID, NAME FROM MENU_MODIFIER_GROUP ORDER BY NAME;")
modifier_groups = parse_rows(modifier_group_out)
if not modifier_groups:
    modifier_group_out = run_ij("SELECT ID, NAME FROM MENUMODIFIERGROUP ORDER BY NAME;")
    modifier_groups = parse_rows(modifier_group_out)
if not modifier_groups:
    modifier_group_out = run_ij("SELECT ID, NAME FROM MODIFIER_GROUP ORDER BY NAME;")
    modifier_groups = parse_rows(modifier_group_out)

# Query modifiers (actual columns: PRICE, GROUP_ID)
modifier_out = run_ij("SELECT ID, NAME, PRICE, GROUP_ID FROM MENU_MODIFIER ORDER BY NAME;")
modifiers = parse_rows(modifier_out)

# Check pizza item modifier assignments via MENUITEM_MODIFIERGROUP join table
# Actual FK columns: MENUITEM_ID (to MENU_ITEM) and MODIFIER_GROUP_ID (to MENU_MODIFIER_GROUP)
pizza_assign_out = run_ij("SELECT MI.ID, MI.NAME, MG.NAME AS MOD_GROUP FROM MENU_ITEM MI JOIN MENUITEM_MODIFIERGROUP MIMG ON MI.ID = MIMG.MENUITEM_ID JOIN MENU_MODIFIER_GROUP MG ON MIMG.MODIFIER_GROUP_ID = MG.ID WHERE MG.NAME LIKE '%PIZZA%' OR MG.NAME LIKE '%TOPPING%';")
pizza_assignments = parse_rows(pizza_assign_out)
if not pizza_assignments:
    # Fallback: try MODIFIER_GROUP column name (older schema variant)
    pizza_assign_out2 = run_ij("SELECT MI.ID, MI.NAME, MG.NAME AS MOD_GROUP FROM MENU_ITEM MI JOIN MENUITEM_MODIFIERGROUP MIMG ON MI.ID = MIMG.MENUITEM_ID JOIN MENU_MODIFIER_GROUP MG ON MIMG.MODIFIER_GROUP = MG.ID WHERE MG.NAME LIKE '%PIZZA%' OR MG.NAME LIKE '%TOPPING%';")
    pizza_assignments = parse_rows(pizza_assign_out2)

show_out = ""

result = {
    "derby_tools_available": derby_ok,
    "task_start": TASK_START,
    "modifier_groups": [{"id": r[0], "name": r[1]} for r in modifier_groups if len(r) >= 2],
    "modifiers": [
        {"id": r[0], "name": r[1], "price": r[2] if len(r) > 2 else "", "group_id": r[3] if len(r) > 3 else ""}
        for r in modifiers if len(r) >= 2
    ],
    "pizza_topping_assignments": [
        {"item_id": r[0], "item_name": r[1], "modifier_group": r[2] if len(r) > 2 else ""}
        for r in pizza_assignments if len(r) >= 2
    ],
    "show_tables_snippet": show_out[:3000],
    "modifier_group_query_output": modifier_group_out[:1000],
    "modifier_query_output": modifier_out[:1000],
}

out_path = '/tmp/modifier_group_configuration_result.json'
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result: {out_path}")
print(f"Modifier groups: {len(result['modifier_groups'])}")
print(f"Modifiers: {len(result['modifiers'])}")
print(f"Pizza assignments: {len(result['pizza_topping_assignments'])}")
for g in result['modifier_groups']:
    print(f"  Group: {g['name']}")
PYEOF

echo "=== Export complete ==="
