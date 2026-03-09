#!/bin/bash
# Export script for Employment Data Research task

echo "=== Exporting Employment Data Research Result ==="

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

initial_bls = read_baseline("/tmp/edr_initial_bls")
initial_fred = read_baseline("/tmp/edr_initial_fred")
initial_census = read_baseline("/tmp/edr_initial_census")
initial_downloads = read_baseline("/tmp/edr_initial_downloads")

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

bls_visits = query_history("SELECT COUNT(*) FROM urls WHERE url LIKE '%bls.gov%'")
bls_count = bls_visits[0][0] if bls_visits else 0

fred_visits = query_history("SELECT COUNT(*) FROM urls WHERE url LIKE '%fred.stlouisfed.org%'")
fred_count = fred_visits[0][0] if fred_visits else 0

census_visits = query_history("SELECT COUNT(*) FROM urls WHERE url LIKE '%census.gov%'")
census_count = census_visits[0][0] if census_visits else 0

bls_new = bls_count > initial_bls
fred_new = fred_count > initial_fred
census_new = census_count > initial_census
visited_official = bls_new or fred_new or census_new

# Check downloads directory for data files
downloads_dir = "/home/ga/Downloads"
current_downloads = []
if os.path.exists(downloads_dir):
    for f in os.listdir(downloads_dir):
        fpath = os.path.join(downloads_dir, f)
        if os.path.isfile(fpath):
            stat = os.stat(fpath)
            ext = os.path.splitext(f)[1].lower()
            current_downloads.append({
                "name": f,
                "ext": ext,
                "size": stat.st_size,
                "mtime": int(stat.st_mtime)
            })

new_data_files = [
    d for d in current_downloads
    if d["mtime"] > task_start
    and d["ext"] in [".csv", ".xlsx", ".xls", ".txt", ".json", ".zip", ".gz"]
]
has_new_downloads = len(new_data_files) > 0

# Check download history for source URLs
dl_history = query_history(
    "SELECT target_path, site_url, tab_url FROM downloads WHERE state = 1"
)
official_downloads = []
for row in dl_history:
    target, site_url, tab_url = row
    src = (site_url or "") + " " + (tab_url or "")
    if any(d in src for d in ["bls.gov", "fred.stlouisfed.org", "census.gov", "stlouisfed.org"]):
        official_downloads.append({"file": target, "source": src.strip()[:200]})

# Parse Edge Bookmarks for "Labor Market Data" folder
bookmarks_path = "/home/ga/.config/microsoft-edge/Default/Bookmarks"
labor_market_folder_exists = False
labor_market_bookmark_count = 0
labor_market_has_official = False

def search_bookmarks(node, folder_name):
    """Recursively search for a folder by name and return its children."""
    if node.get("type") == "folder" and node.get("name", "").strip().lower() == folder_name.lower():
        return node.get("children", [])
    children = node.get("children", [])
    for child in children:
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
            folder_children = search_bookmarks(root_node, "Labor Market Data")
            if folder_children is not None:
                labor_market_folder_exists = True
                labor_market_bookmark_count = len([c for c in folder_children if c.get("type") == "url"])
                official_domains = ["bls.gov", "fred.stlouisfed.org", "census.gov", "stlouisfed.org", "bea.gov"]
                for child in folder_children:
                    url = child.get("url", "")
                    if any(d in url for d in official_domains):
                        labor_market_has_official = True
                        break
    except Exception as e:
        print(f"Bookmarks parse error: {e}")

# Analyze the briefing file
briefing_path = "/home/ga/Desktop/labor_briefing.txt"
briefing_exists = os.path.exists(briefing_path)
briefing_size = 0
briefing_mtime = 0
briefing_modified_after_start = False
has_percentage = False
has_unemployment = False
has_payroll = False
has_participation = False

if briefing_exists:
    stat = os.stat(briefing_path)
    briefing_size = stat.st_size
    briefing_mtime = int(stat.st_mtime)
    briefing_modified_after_start = briefing_mtime > task_start
    try:
        content = open(briefing_path, "r", errors="replace").read()
        lower = content.lower()
        # Check for percentage value (e.g., "4.1%", "62.5%")
        has_percentage = bool(re.search(r'\d+\.\d+\s*%|\d+\s*%', content))
        # Check for indicator mentions
        has_unemployment = any(w in lower for w in ["unemployment", "jobless", "unemployed"])
        has_payroll = any(w in lower for w in ["payroll", "nonfarm", "non-farm", "employment change", "jobs added"])
        has_participation = any(w in lower for w in ["participation", "labor force", "labour force", "lfpr"])
    except:
        pass

result = {
    "task": "employment_data_research",
    "task_start": task_start,
    "history": {
        "bls_new": bls_new,
        "fred_new": fred_new,
        "census_new": census_new,
        "visited_official": visited_official
    },
    "downloads": {
        "new_data_files": len(new_data_files),
        "has_new_downloads": has_new_downloads,
        "official_source_downloads": len(official_downloads),
        "file_names": [d["name"] for d in new_data_files[:5]]
    },
    "bookmarks": {
        "labor_market_folder_exists": labor_market_folder_exists,
        "labor_market_bookmark_count": labor_market_bookmark_count,
        "labor_market_has_official": labor_market_has_official
    },
    "briefing": {
        "exists": briefing_exists,
        "size_bytes": briefing_size,
        "modified_after_start": briefing_modified_after_start,
        "has_percentage": has_percentage,
        "has_unemployment": has_unemployment,
        "has_payroll": has_payroll,
        "has_participation": has_participation
    }
}

with open("/tmp/employment_data_research_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Official visited: {visited_official} (BLS={bls_new}, FRED={fred_new})")
print(f"New data files: {len(new_data_files)}")
print(f"Labor Market Data folder: {labor_market_folder_exists} ({labor_market_bookmark_count} bookmarks)")
print(f"Briefing: exists={briefing_exists}, size={briefing_size}, has_pct={has_percentage}")
PYEOF

echo "=== Export Complete ==="
