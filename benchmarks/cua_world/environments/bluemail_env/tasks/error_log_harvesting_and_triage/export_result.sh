#!/bin/bash
echo "=== Exporting Error Log Harvesting results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state visual
take_screenshot /tmp/task_final.png

# 2. Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Python script to analyze filesystem and Maildir
# We do this in Python to handle text parsing and matching robustly
python3 << 'PYEOF'
import os
import json
import glob
import time

# Configuration
DOCS_DIR = "/home/ga/Documents"
LOGS_DIR = os.path.join(DOCS_DIR, "ErrorLogs")
MAILDIR = "/home/ga/Maildir"
PROCESSED_FOLDER = os.path.join(MAILDIR, ".Processed-Logs")
INBOX_FOLDER = os.path.join(MAILDIR, "cur")

task_start = 0
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(float(f.read().strip()))
except:
    pass

result = {
    "logs_dir_exists": False,
    "processed_folder_exists": False,
    "files_created": [],
    "file_count": 0,
    "clean_root_docs": True,
    "processed_email_count": 0,
    "content_verification": []
}

# Check 1: Directory Creation
if os.path.isdir(LOGS_DIR):
    result["logs_dir_exists"] = True
    
    # Check files
    files = [f for f in os.listdir(LOGS_DIR) if os.path.isfile(os.path.join(LOGS_DIR, f))]
    result["file_count"] = len(files)
    
    for fname in files:
        fpath = os.path.join(LOGS_DIR, fname)
        stats = os.stat(fpath)
        
        # Read content snippet
        try:
            with open(fpath, 'r', errors='ignore') as f:
                content = f.read().strip()
        except:
            content = ""
            
        is_new = stats.st_mtime > task_start
        
        file_info = {
            "name": fname,
            "created_during_task": is_new,
            "size": len(content),
            "snippet": content[:100] if content else ""
        }
        result["files_created"].append(file_info)

# Check 2: Cleanliness (did they dump files in root Documents?)
root_files = [f for f in os.listdir(DOCS_DIR) if os.path.isfile(os.path.join(DOCS_DIR, f))]
if len(root_files) > 0:
    result["clean_root_docs"] = False

# Check 3: Maildir Folder Creation
if os.path.isdir(PROCESSED_FOLDER):
    result["processed_folder_exists"] = True
    # Count emails
    cur_path = os.path.join(PROCESSED_FOLDER, "cur")
    new_path = os.path.join(PROCESSED_FOLDER, "new")
    count = 0
    if os.path.isdir(cur_path): count += len(os.listdir(cur_path))
    if os.path.isdir(new_path): count += len(os.listdir(new_path))
    result["processed_email_count"] = count

# Check 4: Content Cross-Reference (Anti-Hallucination)
# For each created file, search for its snippet in the Maildir (Processed-Logs or Inbox)
# We prioritize Processed-Logs because the email SHOULD be there.

def search_in_maildir(search_text, folders):
    if len(search_text) < 15: return "text_too_short"
    
    # Normalize whitespace for search
    search_text = " ".join(search_text.split())[:100] # search first 100 chars
    
    for folder in folders:
        for subdir in ["cur", "new"]:
            path = os.path.join(folder, subdir)
            if not os.path.isdir(path): continue
            
            for email_file in os.listdir(path):
                try:
                    with open(os.path.join(path, email_file), 'r', errors='ignore') as f:
                        email_content = f.read()
                        # Simple normalization
                        email_content = " ".join(email_content.split())
                        
                        if search_text in email_content:
                            return folder # Return where it was found
                except:
                    continue
    return None

search_folders = []
if result["processed_folder_exists"]: search_folders.append(PROCESSED_FOLDER)
search_folders.append(MAILDIR) # Search inbox/root as fallback

for file_info in result["files_created"]:
    snippet = file_info["snippet"]
    found_location = search_in_maildir(snippet, search_folders)
    
    verification = {
        "filename": file_info["name"],
        "valid_source": False,
        "location_found": None
    }
    
    if found_location:
        verification["valid_source"] = True
        if ".Processed-Logs" in found_location:
            verification["location_found"] = "Processed-Logs"
        else:
            verification["location_found"] = "Inbox/Other"
    
    result["content_verification"].append(verification)

# Save Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions so agent/verifier can read it
chmod 666 /tmp/task_result.json

echo "Result generated at /tmp/task_result.json"
echo "=== Export complete ==="