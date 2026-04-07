#!/bin/bash
echo "=== Exporting add_progress_note task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# We will use Python to safely query the FreeMED database and dump results to JSON
# This avoids bash quoting hell and allows us to easily gather all note text
cat > /tmp/export_db.py << 'EOF'
import subprocess
import json
import os

def query_db(sql):
    try:
        res = subprocess.run(["mysql", "-u", "freemed", "-pfreemed", "freemed", "-N", "-e", sql], 
                             capture_output=True, text=True, timeout=10)
        return res.stdout.strip()
    except Exception as e:
        return ""

def main():
    result = {
        "task_start": 0,
        "task_end": 0,
        "maria_id": "",
        "notes_table": "",
        "initial_notes_count": 0,
        "current_notes_count": 0,
        "new_notes_count": 0,
        "notes_for_maria": 0,
        "combined_note_text": "",
        "app_was_running": False
    }

    # Load timestamps
    try:
        with open("/tmp/task_start_time.txt") as f:
            result["task_start"] = int(f.read().strip())
    except: pass
    
    result["task_end"] = int(os.popen("date +%s").read().strip())
    
    # Check if FreeMED/Apache is running
    app_running = subprocess.run(["pgrep", "-f", "apache2"], capture_output=True).returncode == 0
    result["app_was_running"] = app_running

    # Load initial state
    try:
        with open("/tmp/maria_patient_id.txt") as f:
            result["maria_id"] = f.read().strip()
        with open("/tmp/pnotes_table_name.txt") as f:
            result["notes_table"] = f.read().strip()
        with open("/tmp/initial_pnotes_count.txt") as f:
            result["initial_notes_count"] = int(f.read().strip())
    except: pass

    notes_table = result.get("notes_table")
    maria_id = result.get("maria_id")

    if notes_table:
        # Get current total notes count
        current_count_str = query_db(f"SELECT COUNT(*) FROM {notes_table}")
        result["current_notes_count"] = int(current_count_str) if current_count_str.isdigit() else 0
        result["new_notes_count"] = result["current_notes_count"] - result["initial_notes_count"]

        # Find the patient column dynamically 
        cols_raw = query_db(f"SHOW COLUMNS FROM {notes_table}")
        cols = [line.split('\t')[0] for line in cols_raw.split('\n') if line.strip()]
        
        pat_col = None
        for c in ["pnotespat", "pnotespatient", "patient_id", "patientid", "patient", "pat"]:
            if c in cols:
                pat_col = c
                break
        
        # Find text columns
        text_cols = []
        for line in cols_raw.split('\n'):
            if not line.strip(): continue
            parts = line.split('\t')
            if len(parts) >= 2 and any(t in parts[1].lower() for t in ['text', 'varchar', 'char', 'blob']):
                text_cols.append(parts[0])

        if pat_col and maria_id:
            # Check how many notes Maria has now
            maria_notes_str = query_db(f"SELECT COUNT(*) FROM {notes_table} WHERE {pat_col}='{maria_id}'")
            result["notes_for_maria"] = int(maria_notes_str) if maria_notes_str.isdigit() else 0
            
            # Combine all text from Maria's notes created during task
            all_text = []
            for t_col in text_cols:
                # We fetch the newest notes for Maria
                txt = query_db(f"SELECT GROUP_CONCAT({t_col} SEPARATOR ' ') FROM {notes_table} WHERE {pat_col}='{maria_id}' ORDER BY id DESC LIMIT 5")
                if txt: all_text.append(txt)
            
            result["combined_note_text"] = " ".join(all_text)
        else:
            # Fallback: grab all new text in the table
            all_text = []
            for t_col in text_cols:
                txt = query_db(f"SELECT GROUP_CONCAT({t_col} SEPARATOR ' ') FROM {notes_table} ORDER BY id DESC LIMIT {max(1, result['new_notes_count'])}")
                if txt: all_text.append(txt)
            result["combined_note_text"] = " ".join(all_text)

    # Write out to JSON
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f)

main()
EOF

python3 /tmp/export_db.py

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="