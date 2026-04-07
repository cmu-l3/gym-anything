#!/bin/bash
# Export script for post_period_accruals task
echo "=== Exporting post_period_accruals Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Use Python to do complex multi-table extraction
python3 << 'PYEOF'
import subprocess, json

def q(sql):
    r = subprocess.run(
        ["docker", "exec", "idempiere-postgres", "psql",
         "-U", "adempiere", "-d", "idempiere", "-t", "-A", "-c", sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

# Read initial journal IDs
try:
    with open("/tmp/initial_journal_ids") as f:
        initial_journal_ids = set(l.strip() for l in f if l.strip().isdigit())
except:
    initial_journal_ids = set()

# Get all current GL journals for GardenWorld
rows = q("""
SELECT gl_journal_id, gl_journalbatch_id, documentno, docstatus, description
FROM gl_journal
WHERE ad_client_id=11
ORDER BY gl_journal_id
""")

new_journals = []
for row in rows.splitlines():
    if not row.strip():
        continue
    parts = row.split('|')
    if len(parts) >= 5:
        jid = parts[0].strip()
        if jid not in initial_journal_ids:
            new_journals.append({
                "gl_journal_id": int(jid),
                "gl_journalbatch_id": int(parts[1].strip() or 0),
                "documentno": parts[2].strip(),
                "docstatus": parts[3].strip(),
                "description": parts[4].strip()
            })

# Get lines for each new journal
journal_lines = {}
for jnl in new_journals:
    lines_raw = q(f"""
SELECT gll.account_id, ev.value as account_no, ev.name as account_name,
       ROUND(gll.amtacctdr::numeric, 2), ROUND(gll.amtacctcr::numeric, 2)
FROM gl_journalline gll
JOIN c_elementvalue ev ON gll.account_id = ev.c_elementvalue_id
WHERE gll.gl_journal_id={jnl['gl_journal_id']}
ORDER BY gll.line
""")
    lines = []
    for row in lines_raw.splitlines():
        if not row.strip():
            continue
        parts = row.split('|')
        if len(parts) >= 5:
            lines.append({
                "account_id":   int(parts[0].strip() or 0),
                "account_no":   parts[1].strip(),
                "account_name": parts[2].strip(),
                "dr": float(parts[3].strip() or 0),
                "cr": float(parts[4].strip() or 0)
            })
    journal_lines[jnl['gl_journal_id']] = lines

result = {
    "new_journals": new_journals,
    "journal_lines": {str(k): v for k, v in journal_lines.items()}
}

with open("/tmp/post_period_accruals_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Found {len(new_journals)} new journal(s)")
for jnl in new_journals:
    print(f"  Journal {jnl['gl_journal_id']}: status={jnl['docstatus']} desc='{jnl['description']}'")
    for line in journal_lines.get(jnl['gl_journal_id'], []):
        print(f"    {line['account_no']} {line['account_name']}: DR={line['dr']} CR={line['cr']}")
PYEOF

echo "=== Export Complete ==="
