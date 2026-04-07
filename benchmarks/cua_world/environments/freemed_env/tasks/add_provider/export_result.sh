#!/bin/bash
echo "=== Exporting add_provider Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_provider_end.png
sleep 1

# Extract the database state securely using Python
cat > /tmp/export_db.py << 'EOF'
import subprocess
import json

def run_query(query):
    try:
        cmd = ['mysql', '-u', 'freemed', '-pfreemed', 'freemed', '-N', '-e', query]
        output = subprocess.check_output(cmd, universal_newlines=True, stderr=subprocess.DEVNULL)
        return output.strip()
    except Exception as e:
        return ""

try:
    # Read initial state counts
    try:
        with open('/tmp/initial_physician_count', 'r') as f:
            initial_count = int(f.read().strip() or "0")
    except:
        initial_count = 0
        
    try:
        with open('/tmp/initial_max_physician_id', 'r') as f:
            initial_max_id = int(f.read().strip() or "0")
    except:
        initial_max_id = 0

    current_count_str = run_query("SELECT COUNT(*) FROM physician")
    current_count = int(current_count_str) if current_count_str else 0
    
    # Check for the inserted provider record
    query = "SELECT id, phyfname, phylname, phymname, phynpi, phydea, physpec, phycitya, phystatea, phyzipa, phyphonea, phyemail FROM physician WHERE phyfname='Maria' AND phylname='Rodriguez' ORDER BY id DESC LIMIT 1"
    
    raw_data = run_query(query)
    provider_found = False
    provider_data = {}
    
    if raw_data:
        provider_found = True
        parts = raw_data.split('\t')
        # Padding in case TSV output omits trailing empty fields
        parts += [''] * (12 - len(parts))
        
        provider_data = {
            "id": int(parts[0]) if parts[0].isdigit() else 0,
            "fname": parts[1].strip(),
            "lname": parts[2].strip(),
            "mname": parts[3].strip(),
            "npi": parts[4].strip(),
            "dea": parts[5].strip(),
            "specialty": parts[6].strip(),
            "city": parts[7].strip(),
            "state": parts[8].strip(),
            "zip": parts[9].strip(),
            "phone": parts[10].strip(),
            "email": parts[11].strip()
        }

    result = {
        "initial_count": initial_count,
        "initial_max_id": initial_max_id,
        "current_count": current_count,
        "provider_found": provider_found,
        "provider": provider_data
    }
    
    with open('/tmp/add_provider_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    # Error fallback
    with open('/tmp/add_provider_result.json', 'w') as f:
        json.dump({"error": str(e), "provider_found": False}, f)
EOF

python3 /tmp/export_db.py

# Finalize JSON permissions
chmod 666 /tmp/add_provider_result.json 2>/dev/null || sudo chmod 666 /tmp/add_provider_result.json 2>/dev/null || true

echo "Exported JSON data:"
cat /tmp/add_provider_result.json
echo "=== Export Complete ==="