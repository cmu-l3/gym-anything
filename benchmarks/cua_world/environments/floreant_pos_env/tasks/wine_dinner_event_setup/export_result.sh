#!/bin/bash
echo "=== Exporting wine_dinner_event_setup result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot before killing app
take_screenshot /tmp/task_final.png

# 2. Kill Floreant to unlock the embedded Derby database
kill_floreant
sleep 4

# 3. Locate Derby database path
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
[ -z "$DB_POSDB" ] && DB_POSDB="/opt/floreantpos/database/derby-server/posdb"
echo "Derby DB: $DB_POSDB"

# NOTE: Do NOT remove db.lck or log files — Derby needs them for recovery after unclean shutdown.

# 4. Ensure Derby tools are available
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

# 5. Read task start timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 6. Write SQL query file — all queries in a single ij session
cat > /tmp/wine_dinner_queries.sql << EOSQL
connect 'jdbc:derby:$DB_POSDB';
SELECT '---M_TAX---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT ID, NAME, RATE FROM TAX ORDER BY NAME;
SELECT '---M_CATEGORY---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT ID, NAME FROM MENU_CATEGORY ORDER BY NAME;
SELECT '---M_GROUP---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT MG.ID, MG.NAME, MG.CATEGORY_ID, MC.NAME AS CAT_NAME FROM MENU_GROUP MG LEFT JOIN MENU_CATEGORY MC ON MG.CATEGORY_ID = MC.ID ORDER BY MG.NAME;
SELECT '---M_ITEM---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT MI.ID, MI.NAME, MI.PRICE, MI.TAX_ID, MI.GROUP_ID, T.NAME AS TAX_NAME, MG.NAME AS GROUP_NAME FROM MENU_ITEM MI LEFT JOIN TAX T ON MI.TAX_ID = T.ID LEFT JOIN MENU_GROUP MG ON MI.GROUP_ID = MG.ID ORDER BY MI.NAME;
SELECT '---M_MODGROUP---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT ID, NAME, ENABLED FROM MENU_MODIFIER_GROUP ORDER BY NAME;
SELECT '---M_MODIFIER---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT MM.ID, MM.NAME, MM.PRICE, MM.GROUP_ID, MMG.NAME AS GROUP_NAME FROM MENU_MODIFIER MM LEFT JOIN MENU_MODIFIER_GROUP MMG ON MM.GROUP_ID = MMG.ID ORDER BY MM.NAME;
SELECT '---M_LINK---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT MIG.MENUITEM_MODIFIERGROUP_ID AS ITEM_ID, MIG.MODIFIER_GROUP AS GROUP_ID, MIG.MIN_QUANTITY, MIG.MAX_QUANTITY, MI.NAME AS ITEM_NAME, MMG.NAME AS GROUP_NAME FROM MENUITEM_MODIFIERGROUP MIG LEFT JOIN MENU_ITEM MI ON MIG.MENUITEM_MODIFIERGROUP_ID = MI.ID LEFT JOIN MENU_MODIFIER_GROUP MMG ON MIG.MODIFIER_GROUP = MMG.ID ORDER BY MIG.ID;
SELECT '---M_TICKET---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT ID, TICKET_TYPE, SETTLED, PAID, TOTAL_PRICE, CREATE_DATE FROM TICKET WHERE SETTLED = 1 ORDER BY ID DESC;
SELECT '---M_TICKETITEM---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT TICKET_ID, NAME, ITEM_PRICE, ITEM_COUNT FROM TICKET_ITEM ORDER BY TICKET_ID, NAME;
SELECT '---M_TRANSACTION---' AS M FROM SYSIBM.SYSDUMMY1;
SELECT TICKET_ID, PAYMENT_TYPE, AMOUNT, TRANSACTION_TYPE FROM TRANSACTIONS ORDER BY TICKET_ID;
exit;
EOSQL

# 7. Run ij against the SQL file and capture output
java -cp "$DERBY_TOOLS/derby.jar:$DERBY_TOOLS/derbytools.jar" \
    org.apache.derby.tools.ij /tmp/wine_dinner_queries.sql \
    > /tmp/wine_dinner_ij_output.txt 2>&1

# 8. Write the Python parser to /tmp (since /workspace is a read-only mount that may be stale)
cp /workspace/tasks/wine_dinner_event_setup/parse_export.py /tmp/parse_export_wd.py 2>/dev/null || \
cat > /tmp/parse_export_wd.py << 'PYEOF'
import json, re, sys

def split_sections(text):
    sections, key, lines = {}, None, []
    for line in text.split("\n"):
        m = re.search(r"---M_(\w+)---", line)
        if m:
            if key: sections[key] = "\n".join(lines)
            key, lines = m.group(1), []
        else:
            lines.append(line)
    if key: sections[key] = "\n".join(lines)
    return sections

def parse_rows(text):
    rows, hdr, sep = [], False, False
    for raw in text.split("\n"):
        line = raw.strip()
        if not line: continue
        lo = line.lower()
        if "ij version" in lo or "apache derby" in lo: continue
        if "ij>" in lo:
            line = re.sub(r"(?i)ij>\s*", "", line).strip()
            if not line: continue
        if "rows selected" in lo or "row selected" in lo:
            hdr, sep = False, False; continue
        if "error" in lo or "url attribute" in lo: continue
        if "|" not in line: continue
        parts = [p.strip() for p in line.split("|")]
        if not hdr: hdr = True; continue
        if hdr and not sep:
            if line.replace("-","").replace("+","").replace("|","").replace(" ","") == "":
                sep = True; continue
            else: sep = True
        rows.append(parts)
    return rows

with open(sys.argv[1]) as f: text = f.read()
ts = int(sys.argv[2]) if len(sys.argv) > 2 else 0
out = sys.argv[3] if len(sys.argv) > 3 else "/tmp/wine_dinner_result.json"
s = split_sections(text)
def g(k): return parse_rows(s.get(k, ""))
def mk(r, *ks):
    return {ks[i]: r[i] if i < len(r) else "" for i in range(len(ks))}

result = {
    "task_start": ts,
    "taxes": [mk(r,"id","name","rate") for r in g("TAX") if len(r)>=3],
    "categories": [mk(r,"id","name") for r in g("CATEGORY") if len(r)>=2],
    "groups": [mk(r,"id","name","category_id","category_name") for r in g("GROUP") if len(r)>=3],
    "items": [mk(r,"id","name","price","tax_id","group_id","tax_name","group_name") for r in g("ITEM") if len(r)>=3],
    "modifier_groups": [mk(r,"id","name","enabled") for r in g("MODGROUP") if len(r)>=2],
    "modifiers": [mk(r,"id","name","price","group_id","group_name") for r in g("MODIFIER") if len(r)>=2],
    "item_modifier_links": [mk(r,"item_id","group_id","min_quantity","max_quantity","item_name","group_name") for r in g("LINK")],
    "tickets": [mk(r,"id","type","settled","paid","total_price","create_date") for r in g("TICKET") if len(r)>=1],
    "ticket_items": [mk(r,"ticket_id","name","price","count") for r in g("TICKETITEM") if len(r)>=1],
    "transactions": [mk(r,"ticket_id","payment_type","amount","type") for r in g("TRANSACTION") if len(r)>=1],
    "screenshot_path": "/tmp/task_final.png",
}
with open(out, "w") as f: json.dump(result, f, indent=2)
for k in ["taxes","categories","groups","items","modifier_groups","modifiers","item_modifier_links","tickets","ticket_items","transactions"]:
    print(f"{k}: {len(result[k])}")
PYEOF

python3 /tmp/parse_export_wd.py \
    /tmp/wine_dinner_ij_output.txt "$TASK_START" /tmp/wine_dinner_result.json

echo "=== Export complete ==="
