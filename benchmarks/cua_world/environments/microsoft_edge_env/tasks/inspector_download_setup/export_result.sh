#!/bin/bash
# Export script for Inspector Download Station task

echo "=== Exporting Inspector Download Setup Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Kill Edge to flush preferences to disk
echo "Killing Edge to flush preferences..."
pkill -f "microsoft-edge" 2>/dev/null || true
sleep 2

# Parse results using Python
python3 << 'PYEOF'
import json, os, re, shutil, sqlite3, tempfile, glob

# Load task start time
try:
    with open("/tmp/task_start_ts_inspector_download_setup.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# 1. CHECK FILESYSTEM STRUCTURE
docs_root = "/home/ga/Documents/InspectionDocs"
structure = {
    "root_exists": os.path.isdir(docs_root),
    "osha_dir": os.path.isdir(os.path.join(docs_root, "OSHA")),
    "fema_dir": os.path.isdir(os.path.join(docs_root, "FEMA")),
    "general_dir": os.path.isdir(os.path.join(docs_root, "General"))
}

# 2. COUNT DOWNLOADED PDFS
def count_pdfs(path):
    if not os.path.isdir(path): return 0
    return len(glob.glob(os.path.join(path, "*.pdf"))) + len(glob.glob(os.path.join(path, "*.PDF")))

pdf_counts = {
    "osha": count_pdfs(os.path.join(docs_root, "OSHA")),
    "fema": count_pdfs(os.path.join(docs_root, "FEMA")),
    "general": count_pdfs(os.path.join(docs_root, "General")),
    "root": count_pdfs(docs_root) # Should be 0 if organized correctly, but we count anyway
}
total_pdfs = pdf_counts["osha"] + pdf_counts["fema"] + pdf_counts["general"] + pdf_counts["root"]

# Check file timestamps (anti-gaming)
valid_files = 0
all_pdfs = glob.glob(os.path.join(docs_root, "**/*.pdf"), recursive=True)
for p in all_pdfs:
    if os.path.getmtime(p) > task_start and os.path.getsize(p) > 10240: # >10KB
        valid_files += 1

# 3. CHECK EDGE PREFERENCES
prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
prefs_data = {}
try:
    with open(prefs_path, "r") as f:
        prefs_json = json.load(f)
        dl_settings = prefs_json.get("download", {})
        prefs_data = {
            "default_directory": dl_settings.get("default_directory", ""),
            "prompt_for_download": dl_settings.get("prompt_for_download", True)
        }
except Exception as e:
    prefs_data = {"error": str(e)}

# 4. CHECK MANIFEST FILE
manifest_path = "/home/ga/Desktop/download_manifest.txt"
manifest_data = {
    "exists": False,
    "content_valid": False,
    "mentions_osha": False,
    "mentions_fema": False
}

if os.path.exists(manifest_path):
    manifest_data["exists"] = True
    try:
        with open(manifest_path, "r", errors="ignore") as f:
            content = f.read()
            lower_content = content.lower()
            manifest_data["mentions_osha"] = "osha" in lower_content
            manifest_data["mentions_fema"] = "fema" in lower_content
            # Check length/substance
            if len(content) > 100:
                manifest_data["content_valid"] = True
    except:
        pass

# 5. CHECK HISTORY (VISITED SITES)
history_path = "/home/ga/.config/microsoft-edge/Default/History"
visited_sites = {"osha": False, "fema": False}

if os.path.exists(history_path):
    tmp_db = tempfile.mktemp()
    shutil.copy2(history_path, tmp_db)
    try:
        conn = sqlite3.connect(tmp_db)
        cur = conn.cursor()
        
        # Check OSHA
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%osha.gov%'")
        if cur.fetchone()[0] > 0: visited_sites["osha"] = True
        
        # Check FEMA
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%fema.gov%'")
        if cur.fetchone()[0] > 0: visited_sites["fema"] = True
        
        conn.close()
    except:
        pass
    finally:
        if os.path.exists(tmp_db): os.remove(tmp_db)

# COMPILE RESULT
result = {
    "structure": structure,
    "pdf_counts": pdf_counts,
    "total_pdfs": total_pdfs,
    "valid_new_pdfs": valid_files,
    "preferences": prefs_data,
    "manifest": manifest_data,
    "history": visited_sites,
    "task_start": task_start
}

with open("/tmp/inspector_download_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="