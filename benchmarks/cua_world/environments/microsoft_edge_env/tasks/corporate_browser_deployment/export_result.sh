#!/bin/bash
# Export script for Corporate Browser Deployment task
# Collects browser state (Bookmarks, Preferences) and output file info.

echo "=== Exporting Corporate Browser Deployment Result ==="

TASK_NAME="corporate_browser_deployment"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
RESULT_FILE="/tmp/task_result.json"

# 1. Take final screenshot while Edge is still running
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Kill Edge to flush preferences and bookmarks to disk
echo "Closing Edge to flush state..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Analyze state with Python
python3 << 'PYEOF'
import json
import os

result = {}

# --- Load Task Start Time ---
task_start = 0
try:
    with open("/tmp/task_start_ts_corporate_browser_deployment.txt", "r") as f:
        task_start = int(f.read().strip())
except Exception:
    pass
result["task_start"] = task_start

# --- Analyze Bookmarks ---
bookmarks_path = "/home/ga/.config/microsoft-edge/Default/Bookmarks"
folders_found = []

if os.path.exists(bookmarks_path):
    try:
        with open(bookmarks_path, "r", encoding="utf-8") as f:
            bm_data = json.load(f)

        bar = bm_data.get("roots", {}).get("bookmark_bar", {})

        # Extract all folders and their bookmarks from the Favorites Bar
        for child in bar.get("children", []):
            if child.get("type") == "folder":
                folder_info = {
                    "name": child.get("name", ""),
                    "bookmarks": []
                }
                for bm in child.get("children", []):
                    if bm.get("type") == "url":
                        folder_info["bookmarks"].append({
                            "name": bm.get("name", ""),
                            "url": bm.get("url", "")
                        })
                folders_found.append(folder_info)
    except Exception as e:
        print(f"Error parsing bookmarks: {e}")

result["bookmark_folders"] = folders_found

# --- Analyze Preferences ---
prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
settings = {}

if os.path.exists(prefs_path):
    try:
        with open(prefs_path, "r", encoding="utf-8") as f:
            prefs = json.load(f)

        # Startup configuration
        session = prefs.get("session", {})
        settings["restore_on_startup"] = session.get("restore_on_startup")
        settings["startup_urls"] = session.get("startup_urls", [])

        # Home button
        browser = prefs.get("browser", {})
        settings["show_home_button"] = browser.get("show_home_button", False)
        settings["home_page"] = prefs.get("homepage", "")
        settings["home_page_is_new_tab"] = prefs.get("homepage_is_newtabpage", True)

        # Tracking prevention
        tp = prefs.get("tracking_prevention", {})
        settings["tracking_prevention_enabled"] = tp.get("enabled", False)
        settings["tracking_prevention_level"] = tp.get("tracking_prevention_level", None)

        # Password saving
        settings["credentials_enable_service"] = prefs.get("credentials_enable_service", True)

        # Autofill
        af = prefs.get("autofill", {})
        settings["autofill_profile_enabled"] = af.get("profile_enabled", True)
        settings["autofill_credit_card_enabled"] = af.get("credit_card_enabled", True)

        # Do Not Track
        settings["enable_do_not_track"] = prefs.get("enable_do_not_track", False)

        # Default search provider
        dsp = prefs.get("default_search_provider", {})
        settings["default_search_provider_name"] = dsp.get("name", "")
        settings["default_search_provider_keyword"] = dsp.get("keyword", "")
        settings["default_search_provider_search_url"] = dsp.get("search_url", "")

        # Download directory
        sf = prefs.get("savefile", {})
        settings["download_directory"] = sf.get("default_directory", "")

        # Also check download.default_directory (some Edge versions)
        dl = prefs.get("download", {})
        settings["download_default_directory"] = dl.get("default_directory", "")

    except Exception as e:
        print(f"Error parsing preferences: {e}")

result["settings"] = settings

# --- Check Export File ---
export_path = "/home/ga/Documents/browser_config_export.html"
export_info = {
    "exists": False,
    "size_bytes": 0,
    "modified_after_start": False,
    "contains_bookmark_data": False
}

if os.path.exists(export_path):
    stat = os.stat(export_path)
    export_info["exists"] = True
    export_info["size_bytes"] = stat.st_size
    export_info["modified_after_start"] = stat.st_mtime > task_start

    try:
        with open(export_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read().lower()
            # Check if export contains any of the expected folder/bookmark names
            has_market_data = "market data" in content
            has_regulatory = "regulatory" in content
            has_internal_tools = "internal tools" in content
            export_info["contains_bookmark_data"] = has_market_data or has_regulatory or has_internal_tools
            export_info["has_market_data"] = has_market_data
            export_info["has_regulatory"] = has_regulatory
            export_info["has_internal_tools"] = has_internal_tools
    except Exception:
        pass

result["export_file"] = export_info

# --- Check Deployment Log ---
log_path = "/home/ga/Desktop/deployment_log.txt"
log_info = {
    "exists": False,
    "size_bytes": 0,
    "modified_after_start": False,
    "content_keywords": {}
}

if os.path.exists(log_path):
    stat = os.stat(log_path)
    log_info["exists"] = True
    log_info["size_bytes"] = stat.st_size
    log_info["modified_after_start"] = stat.st_mtime > task_start

    try:
        with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read().lower()
            # Check for mentions of key settings
            log_info["content_keywords"] = {
                "mentions_tracking": any(w in content for w in ["tracking", "strict"]),
                "mentions_password": any(w in content for w in ["password", "credential"]),
                "mentions_autofill": "autofill" in content,
                "mentions_duckduckgo": "duckduckgo" in content,
                "mentions_download": "download" in content,
                "mentions_startup": "startup" in content,
                "mentions_home": "home" in content,
                "mentions_do_not_track": any(w in content for w in ["do not track", "dnt", "donottrack"]),
                "mentions_bookmarks": any(w in content for w in ["bookmark", "favorite", "folder"]),
                "mentions_export": "export" in content,
            }
    except Exception:
        pass

result["deployment_log"] = log_info

# --- Save Result ---
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result exported successfully.")
print(f"Bookmark folders found: {len(folders_found)}")
print(f"Settings: {json.dumps(settings, indent=2)}")
print(f"Export file exists: {export_info['exists']}")
print(f"Deployment log exists: {log_info['exists']}")
PYEOF

echo "=== Export Complete ==="
