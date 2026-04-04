#!/bin/bash
# Export script for Regulatory Guidance Research task

echo "=== Exporting Regulatory Guidance Research Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, re, shutil, sqlite3, tempfile, glob

task_start = 0
try:
    task_start = int(open("/tmp/task_start_timestamp").read().strip())
except:
    pass

def read_baseline(path, default=0):
    try:
        return int(open(path).read().strip())
    except:
        return default

initial_fda = read_baseline("/tmp/rgr_initial_fda")
initial_downloads = read_baseline("/tmp/rgr_initial_downloads")

# Query Edge history
def query_history(query):
    history_path = "/home/ga/.config/microsoft-edge/Default/History"
    if not os.path.exists(history_path):
        return []
    tmp = tempfile.mktemp(suffix=".sqlite3")
    try:
        shutil.copy2(history_path, tmp)
        conn = sqlite3.connect(tmp)
        rows = conn.execute(query).fetchall()
        conn.close()
        return rows
    except:
        return []
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

# Count FDA.gov visits
fda_rows = query_history("SELECT COUNT(*) FROM urls WHERE url LIKE '%fda.gov%'")
fda_count = fda_rows[0][0] if fda_rows else 0
fda_new = fda_count > initial_fda

# Count visits to FDA guidance-specific pages
fda_guidance_rows = query_history(
    "SELECT COUNT(*) FROM urls WHERE url LIKE '%fda.gov%' AND (url LIKE '%guidance%' OR url LIKE '%drugs%' OR url LIKE '%regulatory%')"
)
fda_guidance_count = fda_guidance_rows[0][0] if fda_guidance_rows else 0

# Get sample FDA URLs visited
fda_urls = query_history(
    "SELECT url FROM urls WHERE url LIKE '%fda.gov%' ORDER BY last_visit_time DESC LIMIT 10"
)
fda_url_samples = [row[0] for row in fda_urls]

# Check downloads directory for PDF files
downloads_dir = "/home/ga/Downloads"
pdf_files = []
other_files = []
if os.path.exists(downloads_dir):
    for f in os.listdir(downloads_dir):
        fpath = os.path.join(downloads_dir, f)
        if os.path.isfile(fpath):
            stat = os.stat(fpath)
            ext = os.path.splitext(f)[1].lower()
            file_info = {
                "name": f,
                "ext": ext,
                "size": stat.st_size,
                "mtime": int(stat.st_mtime),
                "new": int(stat.st_mtime) > task_start
            }
            if ext == ".pdf":
                pdf_files.append(file_info)
            else:
                other_files.append(file_info)

new_pdfs = [f for f in pdf_files if f["new"]]
has_new_pdfs = len(new_pdfs) > 0

# Check download history for FDA source
dl_history = query_history(
    "SELECT target_path, site_url, tab_url, mime_type FROM downloads WHERE state = 1"
)
fda_downloads = []
for row in dl_history:
    target, site_url, tab_url, mime_type = row
    src = (site_url or "") + " " + (tab_url or "")
    if "fda.gov" in src:
        fda_downloads.append({
            "file": (target or "")[-80:],
            "source": src.strip()[:200],
            "mime": mime_type or ""
        })

# Parse Edge Bookmarks for "FDA Guidance" folder
bookmarks_path = "/home/ga/.config/microsoft-edge/Default/Bookmarks"
fda_folder_exists = False
fda_bookmark_count = 0
fda_bookmark_urls = []

def search_bookmarks(node, folder_name):
    if node.get("type") == "folder" and node.get("name", "").strip().lower() == folder_name.lower():
        return node.get("children", [])
    for child in node.get("children", []):
        result = search_bookmarks(child, folder_name)
        if result is not None:
            return result
    return None

if os.path.exists(bookmarks_path):
    try:
        with open(bookmarks_path, "r", encoding="utf-8") as f:
            bk_data = json.load(f)
        roots = bk_data.get("roots", {})
        for root_key in ["bookmark_bar", "other", "synced"]:
            root_node = roots.get(root_key, {})
            folder_children = search_bookmarks(root_node, "FDA Guidance")
            if folder_children is not None:
                fda_folder_exists = True
                url_children = [c for c in folder_children if c.get("type") == "url"]
                fda_bookmark_count = len(url_children)
                fda_bookmark_urls = [c.get("url", "") for c in url_children[:5]]
                break
    except Exception as e:
        print(f"Bookmarks parse error: {e}")

fda_bookmarks_have_fda = any("fda.gov" in u for u in fda_bookmark_urls)

# Analyze the research summary
summary_path = "/home/ga/Desktop/fda_research_summary.txt"
summary_exists = os.path.exists(summary_path)
summary_size = 0
summary_mtime = 0
summary_modified_after_start = False
summary_has_fda_vocab = False
summary_vocab_found = []

FDA_VOCAB = [
    "nda", "bla", "inda", "ind", "anda", "pharmacokinetics", "pharmacokinetic",
    "bioavailability", "bioequivalence", "ba/be", "drug-drug interaction", "ddi",
    "nme", "ich", "cmc", "clinical pharmacology", "hepatic impairment",
    "renal impairment", "cmax", "auc", "half-life", "food effect", "fasted",
    "21 cfr", "cfr part", "guidance", "draft guidance", "final guidance",
    "drug interaction", "pediatric", "geriatric", "special population"
]

if summary_exists:
    stat = os.stat(summary_path)
    summary_size = stat.st_size
    summary_mtime = int(stat.st_mtime)
    summary_modified_after_start = summary_mtime > task_start
    try:
        content = open(summary_path, "r", errors="replace").read().lower()
        for term in FDA_VOCAB:
            if term in content:
                summary_vocab_found.append(term)
        summary_has_fda_vocab = len(summary_vocab_found) >= 2
    except:
        pass

result = {
    "task": "regulatory_guidance_research",
    "task_start": task_start,
    "history": {
        "fda_new": fda_new,
        "fda_total": fda_count,
        "fda_guidance_pages": fda_guidance_count,
        "fda_url_samples": fda_url_samples[:5]
    },
    "downloads": {
        "new_pdfs": len(new_pdfs),
        "has_new_pdfs": has_new_pdfs,
        "fda_source_downloads": len(fda_downloads),
        "pdf_names": [f["name"] for f in new_pdfs[:5]]
    },
    "bookmarks": {
        "fda_folder_exists": fda_folder_exists,
        "fda_bookmark_count": fda_bookmark_count,
        "fda_bookmarks_have_fda": fda_bookmarks_have_fda,
        "fda_bookmark_urls": fda_bookmark_urls
    },
    "summary": {
        "exists": summary_exists,
        "size_bytes": summary_size,
        "modified_after_start": summary_modified_after_start,
        "has_fda_vocab": summary_has_fda_vocab,
        "vocab_found": summary_vocab_found[:10]
    }
}

with open("/tmp/regulatory_guidance_research_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"FDA visited: {fda_new} ({fda_count} total, {fda_guidance_count} guidance pages)")
print(f"New PDFs: {len(new_pdfs)}, FDA source downloads: {len(fda_downloads)}")
print(f"FDA Guidance folder: {fda_folder_exists} ({fda_bookmark_count} bookmarks)")
print(f"Summary: exists={summary_exists}, has_vocab={summary_has_fda_vocab}, terms={summary_vocab_found[:5]}")
PYEOF

echo "=== Export Complete ==="
