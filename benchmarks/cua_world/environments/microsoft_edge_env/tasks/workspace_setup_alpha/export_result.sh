#!/bin/bash
# Export script for Workspace Setup task
# Exports browser state (Bookmarks, Preferences) and exported HTML file info.

echo "=== Exporting Workspace Setup Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# 2. Kill Edge to ensure preferences/bookmarks are flushed to disk
echo "Closing Edge to flush state..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# 3. Analyze state with Python
python3 << 'PYEOF'
import json
import os
import time

result = {}

# --- Load Task Start Time ---
try:
    with open("/tmp/task_start_ts.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

result["task_start"] = task_start

# --- Analyze Bookmarks ---
bookmarks_path = "/home/ga/.config/microsoft-edge/Default/Bookmarks"
dev_tools_folder = None
bookmarks_found = []

if os.path.exists(bookmarks_path):
    try:
        with open(bookmarks_path, "r", encoding="utf-8") as f:
            bm_data = json.load(f)
        
        # Helper to traverse bookmarks
        def find_folder(node, target_name):
            if node.get("type") == "folder" and node.get("name") == target_name:
                return node
            for child in node.get("children", []):
                res = find_folder(child, target_name)
                if res:
                    return res
            return None

        # Specifically look in bookmark_bar
        roots = bm_data.get("roots", {})
        bar = roots.get("bookmark_bar", {})
        
        # Find 'Dev Tools' folder inside bookmark_bar
        # We look for direct child or nested. Task says "on the Favorites Bar", usually meaning top level,
        # but nested is often accepted if visible. We'll strict check top level of bookmark_bar first.
        
        target_folder = None
        # Check direct children of bar
        for child in bar.get("children", []):
            if child.get("type") == "folder" and child.get("name") == "Dev Tools":
                target_folder = child
                break
        
        if target_folder:
            dev_tools_folder = {
                "name": target_folder.get("name"),
                "children_count": len(target_folder.get("children", []))
            }
            # Extract children details
            for child in target_folder.get("children", []):
                if child.get("type") == "url":
                    bookmarks_found.append({
                        "name": child.get("name"),
                        "url": child.get("url")
                    })
    except Exception as e:
        print(f"Error parsing bookmarks: {e}")

result["dev_tools_folder"] = dev_tools_folder
result["bookmarks_found"] = bookmarks_found

# --- Analyze Preferences (Startup Settings) ---
prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
startup_config = {
    "restore_on_startup": None,
    "startup_urls": []
}

if os.path.exists(prefs_path):
    try:
        with open(prefs_path, "r", encoding="utf-8") as f:
            prefs_data = json.load(f)
        
        session = prefs_data.get("session", {})
        startup_config["restore_on_startup"] = session.get("restore_on_startup")
        startup_config["startup_urls"] = session.get("startup_urls", [])
    except Exception as e:
        print(f"Error parsing preferences: {e}")

result["startup_config"] = startup_config

# --- Analyze Exported HTML File ---
export_path = "/home/ga/Documents/initial_setup.html"
export_info = {
    "exists": False,
    "created_after_start": False,
    "content_valid": False
}

if os.path.exists(export_path):
    stat = os.stat(export_path)
    export_info["exists"] = True
    export_info["size"] = stat.st_size
    # Check creation/modification time
    if stat.st_mtime > task_start:
        export_info["created_after_start"] = True
    
    # Check content for our specific bookmarks
    try:
        with open(export_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            # Check for the specific folder and titles
            has_folder = "Dev Tools" in content
            has_repo = ">Repo<" in content or "Repo" in content
            has_help = ">Help<" in content or "Help" in content
            has_build = ">Build<" in content or "Build" in content
            
            if has_folder and has_repo and has_help and has_build:
                export_info["content_valid"] = True
    except:
        pass

result["export_info"] = export_info

# Save Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result generated.")
PYEOF

echo "=== Export Complete ==="