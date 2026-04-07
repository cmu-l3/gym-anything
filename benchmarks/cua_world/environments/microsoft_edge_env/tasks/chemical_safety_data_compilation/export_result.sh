#!/bin/bash
# export_result.sh - Post-task hook for chemical_safety_data_compilation
set -e

echo "=== Exporting Chemical Safety Data Results ==="

# Load task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_DIR="/home/ga/Documents/Safety_Data"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Use Python to gather comprehensive evidence
python3 << PYEOF
import json
import os
import sys
import glob
import re

task_start = int("$TASK_START")
target_dir = "$TARGET_DIR"
bookmarks_file = "/home/ga/.config/microsoft-edge/Default/Bookmarks"
summary_file = os.path.join(target_dir, "first_aid_summary.txt")

result = {
    "task_start": task_start,
    "dir_exists": False,
    "files": {},
    "bookmarks": {
        "folder_found": False,
        "valid_links_count": 0,
        "links": []
    },
    "summary_content": {
        "exists": False,
        "size": 0,
        "has_keywords": False,
        "mentions_chemicals": False,
        "content_preview": ""
    }
}

# --- Check File System ---
if os.path.exists(target_dir):
    result["dir_exists"] = True
    
    # Check PDF files
    for chemicals in ["ammonia", "chlorine", "formaldehyde"]:
        fname = f"{chemicals}.pdf"
        fpath = os.path.join(target_dir, fname)
        if os.path.exists(fpath):
            stat = os.stat(fpath)
            result["files"][fname] = {
                "exists": True,
                "size": stat.st_size,
                "mtime": int(stat.st_mtime),
                "created_during_task": int(stat.st_mtime) > task_start
            }
        else:
            result["files"][fname] = {"exists": False}

    # Check Summary File
    if os.path.exists(summary_file):
        stat = os.stat(summary_file)
        result["summary_content"]["exists"] = True
        result["summary_content"]["size"] = stat.st_size
        
        try:
            with open(summary_file, 'r', errors='ignore') as f:
                content = f.read()
                result["summary_content"]["content_preview"] = content[:200]
                
                # Check keywords
                keywords = ["irrigate", "wash", "soap", "water", "attention", "medical", "flush"]
                found_keywords = [k for k in keywords if k in content.lower()]
                result["summary_content"]["has_keywords"] = len(found_keywords) >= 3
                
                # Check chemicals
                chems = ["ammonia", "chlorine", "formaldehyde"]
                found_chems = [c for c in chems if c in content.lower()]
                result["summary_content"]["mentions_chemicals"] = len(found_chems) >= 3
        except Exception as e:
            print(f"Error reading summary: {e}")

# --- Check Bookmarks ---
try:
    if os.path.exists(bookmarks_file):
        with open(bookmarks_file, 'r') as f:
            bk_data = json.load(f)
        
        def find_folder(node, name):
            if node.get("type") == "folder" and node.get("name", "").lower() == name.lower():
                return node
            for child in node.get("children", []):
                res = find_folder(child, name)
                if res: return res
            return None

        roots = bk_data.get("roots", {})
        emergency_folder = None
        
        # Search in all root folders
        for root in roots.values():
            emergency_folder = find_folder(root, "Emergency Protocols")
            if emergency_folder: break
            
        if emergency_folder:
            result["bookmarks"]["folder_found"] = True
            children = emergency_folder.get("children", [])
            for child in children:
                if child.get("type") == "url":
                    url = child.get("url", "")
                    result["bookmarks"]["links"].append(url)
                    if "cdc.gov/niosh/npg" in url:
                        result["bookmarks"]["valid_links_count"] += 1
except Exception as e:
    print(f"Error parsing bookmarks: {e}")

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)

print("Export complete.")
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json