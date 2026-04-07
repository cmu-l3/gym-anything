#!/bin/bash
echo "=== Exporting duplicate_quote results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/duplicate_quote_final.png

# Retrieve quote data securely using python
python3 - <<'EOF'
import json
import subprocess

def run_query(query):
    cmd = ["docker", "exec", "suitecrm-db", "mysql", "-u", "suitecrm", "-psuitecrm_pass", "suitecrm", "-N", "-e", query]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return ""

quotes_raw = run_query("SELECT id, name, stage, expiration, term_conditions, deleted FROM aos_quotes WHERE name LIKE 'Office Network Upgrade%'")

quotes = []
if quotes_raw:
    for line in quotes_raw.split('\n'):
        parts = line.split('\t')
        if len(parts) >= 6:
            qid = parts[0]
            name = parts[1]
            stage = parts[2]
            exp = parts[3]
            term = parts[4]
            deleted = parts[5]
            
            # Fetch line items for this quote
            lines_raw = run_query(f"SELECT name, product_qty FROM aos_products_quotes WHERE parent_id='{qid}' AND deleted=0")
            line_items = []
            if lines_raw:
                for l in lines_raw.split('\n'):
                    lparts = l.split('\t')
                    if len(lparts) >= 2:
                        try:
                            qty = float(lparts[1])
                        except ValueError:
                            qty = 0
                        line_items.append({
                            "name": lparts[0],
                            "product_qty": qty
                        })
                        
            try:
                del_val = int(deleted)
            except ValueError:
                del_val = 0
                
            quotes.append({
                "id": qid,
                "name": name,
                "stage": stage,
                "expiration": exp,
                "term_conditions": term,
                "deleted": del_val,
                "line_items": line_items
            })

with open('temp_result.json', 'w') as f:
    json.dump({"quotes": quotes}, f)
EOF

safe_write_result "/tmp/duplicate_quote_result.json" "$(cat temp_result.json)"
rm -f temp_result.json

echo "Result saved to /tmp/duplicate_quote_result.json"
cat /tmp/duplicate_quote_result.json
echo "=== duplicate_quote export complete ==="