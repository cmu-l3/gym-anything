#!/bin/bash
echo "=== Exporting create_structured_inventory result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as proof of task completion
take_screenshot /tmp/task_final_state.png

# Collect data securely using Python to ensure valid JSON representation of DB state
cat > /tmp/export_data.py << 'EOF'
import sys
import json
import subprocess

def db_query(query):
    # Use json_agg to ensure DB outputs perfectly formatted JSON
    json_query = f"SELECT json_agg(t) FROM ({query}) t;"
    cmd = f'docker exec scinote_db psql -U postgres -d scinote_production -t -c "{json_query}"'
    try:
        result = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        if not result or result == '' or result == 'null':
            return []
        return json.loads(result)
    except Exception as e:
        return []

def main():
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            task_start = int(f.read().strip())
    except:
        task_start = 0

    try:
        with open('/tmp/initial_repo_count.txt', 'r') as f:
            initial_repo_count = int(f.read().strip())
    except:
        initial_repo_count = 0
        
    current_repo_count_res = db_query("SELECT COUNT(*) as count FROM repositories")
    current_repo_count = int(current_repo_count_res[0]['count']) if current_repo_count_res else 0

    # Locate the inventory
    repo_data = db_query("SELECT id, name FROM repositories WHERE LOWER(TRIM(name)) = 'chemical compounds library' LIMIT 1")
    if not repo_data:
        repo_data = db_query("SELECT id, name FROM repositories WHERE LOWER(name) LIKE '%chemical%compound%librar%' LIMIT 1")
        
    repo_found = len(repo_data) > 0
    
    result = {
        "task_start": task_start,
        "initial_repo_count": initial_repo_count,
        "current_repo_count": current_repo_count,
        "repository_found": repo_found,
        "repository": None
    }
    
    if repo_found:
        repo_id = repo_data[0]['id']
        repo_name = repo_data[0]['name']
        
        # Pull Custom Columns
        columns = db_query(f"SELECT id, name, data_type as type FROM repository_columns WHERE repository_id={repo_id}")
        
        # Pull Rows
        rows = db_query(f"SELECT id, name FROM repository_rows WHERE repository_id={repo_id}")
        
        # Populate each row with its cell values
        for r in rows:
            row_id = r['id']
            cells = []
            
            # Fetch text values
            text_cells = db_query(f"SELECT rc.repository_column_id as column_id, rtv.data as value FROM repository_cells rc JOIN repository_text_values rtv ON rc.value_type='RepositoryTextValue' AND rc.value_id=rtv.id WHERE rc.repository_row_id={row_id}")
            for tc in text_cells:
                tc['type'] = 'text'
                cells.append(tc)
                
            # Fetch number values
            num_cells = db_query(f"SELECT rc.repository_column_id as column_id, rnv.data as value FROM repository_cells rc JOIN repository_number_values rnv ON rc.value_type='RepositoryNumberValue' AND rc.value_id=rnv.id WHERE rc.repository_row_id={row_id}")
            for nc in num_cells:
                nc['type'] = 'number'
                cells.append(nc)
                
            r['cells'] = cells
            
        result["repository"] = {
            "id": repo_id,
            "name": repo_name,
            "columns": columns,
            "rows": rows
        }
        
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=4)

if __name__ == "__main__":
    main()
EOF

python3 /tmp/export_data.py
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="