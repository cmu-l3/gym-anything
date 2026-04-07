#!/usr/bin/env python3
"""
Verifier for theme_park_maintenance_terminal@1

Criteria (100 points total, pass >= 70):
1. Folder Structure (15 pts): 4 specified folders created.
2. Bookmark Sorting (15 pts): Technical bookmarks sorted correctly.
3. Non-Work Bookmarks Purged (10 pts): No entertainment domains in bookmarks.
4. History Purged (20 pts): Non-work history entries deleted.
5. Technical History Preserved (10 pts): Legit history wasn't wiped out via 'Clear All'.
6. Display Font Size (10 pts): Set to 24 in Preferences.
7. Custom Search Engine (10 pts): Keyword 'part' mapped to Grainger.
8. Startup Pages (10 pts): Set to radar and osha URLs.
"""

import os
import json
import sqlite3
import tempfile
import logging
from typing import Dict, List, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _copy_file(copy_from_env, container_paths: List[str], suffix: str = '.db'):
    """Copy a file from the container, trying multiple candidate paths."""
    temp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp.name
    temp.close()

    for cpath in container_paths:
        try:
            copy_from_env(cpath, temp_path)
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 10:
                return temp_path
        except Exception:
            pass

    if os.path.exists(temp_path):
        os.unlink(temp_path)
    return None

def check_bookmarks(bookmarks_data: Dict) -> tuple:
    if not bookmarks_data:
        return 0, "Bookmarks file not found", 0, "Bookmarks file not found", 0, "Bookmarks file not found"
    
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    # Check Folders
    expected_folders = ["Schematics & Manuals", "Safety & Logs", "Part Suppliers", "Sensors & Weather"]
    found_folders = {}
    for child in children:
        if child.get('type') == 'folder':
            found_folders[child.get('name')] = child
            
    folder_score = 0
    for ef in expected_folders:
        if ef in found_folders:
            folder_score += 3.75
            
    folder_fb = f"Found {len(found_folders)}/4 expected folders."
    
    # Get all URLs recursively
    def get_all_urls(node):
        urls = []
        if node.get('type') == 'url':
            urls.append(node.get('url', '').lower())
        for c in node.get('children', []):
            urls.extend(get_all_urls(c))
        return urls
        
    all_urls = get_all_urls(bookmarks_data.get('roots', {}))
    nonwork_domains = ["youtube.com", "espn.com", "reddit.com", "netflix.com", "x.com", "tiktok.com", "instagram.com", "hulu.com", "disneyplus.com", "bleacherreport.com"]
    
    nonwork_found = [d for d in nonwork_domains if any(d in u for u in all_urls)]
    nonwork_score = 10 if len(nonwork_found) == 0 else max(0, 10 - len(nonwork_found))
    nonwork_fb = f"{len(nonwork_found)} non-work domains found in bookmarks."
    
    # Check sorting
    expected_mapping = {
        "Schematics & Manuals": ["astm.org", "rockwellautomation.com", "siemens.com", "nfpacatalog.org", "skf.com", "fluke.com", "wago.com", "schneider-electric.us"],
        "Safety & Logs": ["osha.gov", "saferparks.org", "naarso.com", "iaapa.org"],
        "Part Suppliers": ["mcmaster.com", "grainger.com", "fastenal.com", "motionindustries.com"],
        "Sensors & Weather": ["weather.gov", "lightningmaps.org", "mesowest.utah.edu"]
    }
    
    correct_sorts = 0
    total_expected = sum(len(v) for v in expected_mapping.values())
    
    for fname, urls in expected_mapping.items():
        if fname in found_folders:
            folder_urls = get_all_urls(found_folders[fname])
            for u in urls:
                if any(u in fu for fu in folder_urls):
                    correct_sorts += 1
                    
    sorting_score = int((correct_sorts / total_expected) * 15)
    sorting_fb = f"Correctly sorted {correct_sorts}/{total_expected} bookmarks."
    
    return int(folder_score), folder_fb, sorting_score, sorting_fb, nonwork_score, nonwork_fb

def check_history(history_path: str) -> tuple:
    if not history_path:
        return 0, "History DB not found.", 0, "History DB not found."
    
    try:
        conn = sqlite3.connect(history_path)
        c = conn.cursor()
        c.execute("SELECT url FROM urls")
        urls = [row[0].lower() for row in c.fetchall()]
        conn.close()
    except Exception as e:
        return 0, f"Error reading History: {e}", 0, f"Error reading History: {e}"
        
    nonwork_domains = ["youtube.com", "espn.com", "reddit.com", "netflix.com", "x.com", "tiktok.com", "instagram.com", "hulu.com", "disneyplus.com", "bleacherreport.com"]
    tech_domains = ["rockwellautomation.com", "osha.gov", "mcmaster.com", "grainger.com", "weather.gov", "wago.com", "fluke.com", "astm.org"]
    
    nonwork_found = [d for d in nonwork_domains if any(d in u for u in urls)]
    tech_found = [d for d in tech_domains if any(d in u for u in urls)]
    
    if len(nonwork_found) == 0:
        purge_score = 20
        purge_fb = "All non-work history purged."
    else:
        purge_score = max(0, 20 - (len(nonwork_found) * 2))
        purge_fb = f"Found {len(nonwork_found)} non-work domains still in history."
        
    if len(tech_found) >= len(tech_domains) * 0.8:
        preserve_score = 10
        preserve_fb = "Technical history preserved."
    elif len(tech_found) > 0:
        preserve_score = 5
        preserve_fb = "Partial technical history preserved."
    else:
        preserve_score = 0
        preserve_fb = "Technical history was deleted (failed selective purge)."
        
    return purge_score, purge_fb, preserve_score, preserve_fb

def check_preferences(prefs_data: Dict) -> tuple:
    if not prefs_data:
        return 0, "No preferences data.", 0, "No preferences data."
        
    font_score = 0
    webkit_prefs = prefs_data.get('webkit', {}).get('webprefs', {})
    font_size = webkit_prefs.get('default_font_size', 16)
    
    if font_size == 24:
        font_score = 10
        font_fb = "Font size correctly set to 24."
    elif font_size >= 20:
        font_score = 5
        font_fb = f"Font size increased to {font_size}, but not exactly 24."
    else:
        font_score = 0
        font_fb = f"Font size is {font_size}."
        
    startup_score = 0
    session = prefs_data.get('session', {})
    restore_behavior = session.get('restore_on_startup', 0)
    startup_urls = session.get('startup_urls', [])
    
    radar_found = any('radar.weather.gov' in u.lower() for u in startup_urls)
    osha_found = any('osha.gov/amusement-parks' in u.lower() for u in startup_urls)
    
    if restore_behavior == 4:
        if radar_found and osha_found:
            startup_score = 10
            startup_fb = "Startup behavior correctly set to specific pages."
        elif radar_found or osha_found:
            startup_score = 5
            startup_fb = "Startup behavior partially configured."
        else:
            startup_score = 0
            startup_fb = "Startup behavior set to specific pages, but incorrect URLs."
    else:
        startup_score = 0
        startup_fb = "Startup behavior not set to specific pages."
        
    return font_score, font_fb, startup_score, startup_fb

def check_search_engine(web_data_path: str) -> tuple:
    if not web_data_path: 
        return 0, "Web Data file not found"
    try:
        conn = sqlite3.connect(web_data_path)
        c = conn.cursor()
        c.execute("SELECT keyword, url FROM keywords")
        for row in c.fetchall():
            keyword, url = row
            if keyword == 'part' and 'grainger.com' in url.lower():
                return 10, "Custom search engine 'part' for Grainger found."
        return 0, "Custom search engine 'part' not found in Web Data."
    except Exception as e:
        return 0, f"Error reading Web Data: {e}"

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available"}

    try:
        # 1. Fetch Bookmarks
        bm_path = _copy_file(copy_from_env, [
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ], '.json')
        bookmarks_data = {}
        if bm_path:
            with open(bm_path, 'r') as f:
                bookmarks_data = json.load(f)
            os.unlink(bm_path)

        # 2. Fetch History DB
        history_path = _copy_file(copy_from_env, [
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ], '.db')

        # 3. Fetch Preferences
        pref_path = _copy_file(copy_from_env, [
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ], '.json')
        prefs_data = {}
        if pref_path:
            with open(pref_path, 'r') as f:
                prefs_data = json.load(f)
            os.unlink(pref_path)

        # 4. Fetch Web Data DB (for Search Engines)
        web_data_path = _copy_file(copy_from_env, [
            "/home/ga/.config/google-chrome-cdp/Default/Web Data",
            "/home/ga/.config/google-chrome/Default/Web Data"
        ], '.db')

        score = 0
        feedback_parts = []

        # Evaluate criteria
        f_score, f_fb, s_score, s_fb, nw_score, nw_fb = check_bookmarks(bookmarks_data)
        score += f_score + s_score + nw_score
        feedback_parts.extend([f_fb, s_fb, nw_fb])

        hp_score, hp_fb, pr_score, pr_fb = check_history(history_path)
        score += hp_score + pr_score
        feedback_parts.extend([hp_fb, pr_fb])

        font_score, font_fb, start_score, start_fb = check_preferences(prefs_data)
        score += font_score + start_score
        feedback_parts.extend([font_fb, start_fb])

        se_score, se_fb = check_search_engine(web_data_path)
        score += se_score
        feedback_parts.append(se_fb)

        # Cleanup DB files
        if history_path and os.path.exists(history_path):
            os.unlink(history_path)
        if web_data_path and os.path.exists(web_data_path):
            os.unlink(web_data_path)

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {str(e)}"
        }