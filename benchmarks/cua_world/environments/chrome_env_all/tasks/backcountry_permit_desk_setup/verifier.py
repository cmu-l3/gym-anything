#!/usr/bin/env python3
"""
Verifier for Backcountry Permit Desk Setup Task (backcountry_permit_desk_setup@1)

Verifies 7 criteria for a total of 100 points:
1. Bookmark organization into 4 specific folders (20 pts)
2. Junk bookmarks deleted completely (15 pts)
3. History sanitization (junk deleted, work kept) (15 pts)
4. Low bandwidth preferences (15 pts)
5. Offline Chrome flags enabled (10 pts)
6. Custom search engine added (15 pts)
7. Downloads & Startup pages configured (10 pts)

Pass Threshold: 70/100
"""

import logging
import os
import json
import sqlite3
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants for domains
JUNK_DOMAINS = [
    "tiktok.com", "instagram.com", "steampowered.com", "reddit.com",
    "netflix.com", "twitch.tv", "spotify.com", "twitter.com", "x.com", 
    "pinterest.com", "facebook.com"
]

WORK_DOMAINS = [
    "recreation.gov", "weather.gov", "usgs.gov", "avalanche.org",
    "nps.gov", "caltopo.com", "lnt.org", "arcgis.com", 
    "gaiagps.com", "airnow.gov"
]

EXPECTED_FOLDERS = ["Permit Systems", "Weather & Hazards", "Mapping & Trails", "NPS Resources"]

def _copy_file(copy_from_env, container_path: str, suffix: str = '') -> str:
    """Helper to copy a file to a temp file safely."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    try:
        copy_from_env(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
    except Exception as e:
        logger.debug(f"Failed to copy {container_path}: {e}")
    
    if os.path.exists(tmp.name):
        os.unlink(tmp.name)
    return None

def _extract_all_urls(node, urls_list):
    """Recursively extract all URLs from bookmark tree."""
    if node.get('type') == 'url':
        urls_list.append(node.get('url', '').lower())
    for child in node.get('children', []):
        _extract_all_urls(child, urls_list)

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    scores = {}
    feedback_parts = []
    total_score = 0
    
    # --- 1. Fetch Files ---
    bookmarks_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks", ".json")
    history_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/History", ".sqlite")
    prefs_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences", ".json")
    local_state_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Local State", ".json")

    # Parse JSONs safely
    bookmarks = {}
    if bookmarks_path:
        try:
            with open(bookmarks_path, 'r') as f: bookmarks = json.load(f)
        except: pass

    prefs = {}
    if prefs_path:
        try:
            with open(prefs_path, 'r') as f: prefs = json.load(f)
        except: pass

    local_state = {}
    if local_state_path:
        try:
            with open(local_state_path, 'r') as f: local_state = json.load(f)
        except: pass

    # --- Criterion 1: Bookmark Organization (20 pts) ---
    c1_score = 0
    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
    found_folders = [c.get('name') for c in bookmark_bar.get('children', []) if c.get('type') == 'folder']
    
    matched_folders = 0
    for expected in EXPECTED_FOLDERS:
        # Case insensitive substring match is forgiving but accurate
        if any(expected.lower() in f.lower() for f in found_folders):
            matched_folders += 1
            
    c1_score = matched_folders * 5
    scores['bookmark_org'] = c1_score
    feedback_parts.append(f"Bookmark Folders: {matched_folders}/{len(EXPECTED_FOLDERS)} found ({c1_score}/20 pts)")

    # --- Criterion 2: Junk Bookmarks Removed (15 pts) ---
    c2_score = 0
    all_bm_urls = []
    _extract_all_urls(bookmarks.get('roots', {}), all_bm_urls)
    
    junk_found = 0
    for url in all_bm_urls:
        if any(j in url for j in JUNK_DOMAINS):
            junk_found += 1
            
    if junk_found == 0 and len(all_bm_urls) > 0:
        c2_score = 15
        feedback_parts.append("Junk Bookmarks: All removed (15/15 pts)")
    else:
        feedback_parts.append(f"Junk Bookmarks: {junk_found} still remain (0/15 pts)")
    scores['junk_bookmarks'] = c2_score

    # --- Criterion 3: History Sanitization (15 pts) ---
    c3_score = 0
    history_junk_count = 0
    history_work_count = 0
    
    if history_path:
        try:
            conn = sqlite3.connect(history_path)
            c = conn.cursor()
            c.execute("SELECT url FROM urls")
            for row in c.fetchall():
                url = row[0].lower()
                if any(j in url for j in JUNK_DOMAINS):
                    history_junk_count += 1
                if any(w in url for w in WORK_DOMAINS):
                    history_work_count += 1
            conn.close()
            
            if history_junk_count == 0 and history_work_count >= 5:
                c3_score = 15
                feedback_parts.append(f"History Sanitization: Perfect ({history_work_count} legit kept, 0 junk) (15/15 pts)")
            elif history_junk_count == 0 and history_work_count < 5:
                # Mass deletion penalty
                c3_score = 5
                feedback_parts.append("History Sanitization: Junk deleted, but legitimate history was ALSO mass-deleted (5/15 pts)")
            else:
                feedback_parts.append(f"History Sanitization: {history_junk_count} junk entries remain (0/15 pts)")
        except Exception as e:
            feedback_parts.append(f"History Sanitization: Error reading DB ({e})")
    else:
        feedback_parts.append("History Sanitization: DB not found")
    scores['history'] = c3_score

    # --- Criterion 4: Low Bandwidth Prefs (15 pts) ---
    c4_score = 0
    preload_mode = prefs.get('net', {}).get('network_prediction_options', -1)
    bg_sync = prefs.get('profile', {}).get('default_content_setting_values', {}).get('background_sync', -1)
    
    if preload_mode == 2: c4_score += 7.5
    if bg_sync == 2: c4_score += 7.5
    
    scores['low_bandwidth'] = c4_score
    feedback_parts.append(f"Low Bandwidth Prefs: Preload={preload_mode==2}, BgSync={bg_sync==2} ({c4_score}/15 pts)")

    # --- Criterion 5: Offline Flags (10 pts) ---
    c5_score = 0
    experiments = local_state.get('browser', {}).get('enabled_labs_experiments', [])
    has_saved_copy = any('show-saved-copy' in x for x in experiments)
    has_offline_reload = any('enable-offline-auto-reload' in x for x in experiments)
    
    if has_saved_copy: c5_score += 5
    if has_offline_reload: c5_score += 5
    
    scores['offline_flags'] = c5_score
    feedback_parts.append(f"Offline Flags: SavedCopy={has_saved_copy}, AutoReload={has_offline_reload} ({c5_score}/10 pts)")

    # --- Criterion 6: Custom Search Engine (15 pts) ---
    c6_score = 0
    prefs_str = json.dumps(prefs).lower()
    
    # Robust check looking at the whole preferences payload for the custom URL and keyword
    if 'trail' in prefs_str and 'nps.gov/subjects/trails/search.htm' in prefs_str:
        c6_score = 15
        feedback_parts.append("Custom Search: 'trail' engine configured (15/15 pts)")
    else:
        feedback_parts.append("Custom Search: Not found or incorrect (0/15 pts)")
    scores['search_engine'] = c6_score

    # --- Criterion 7: Downloads & Startup (10 pts) ---
    c7_score = 0
    dl_dir = prefs.get('download', {}).get('default_directory', '')
    dl_prompt = prefs.get('download', {}).get('prompt_for_download', True)
    startup_urls = prefs.get('session', {}).get('startup_urls', [])
    
    if 'Issued_Permits' in dl_dir and dl_prompt is False:
        c7_score += 5
    
    if any('weather.gov' in u for u in startup_urls) and any('recreation.gov' in u for u in startup_urls):
        c7_score += 5
        
    scores['dl_startup'] = c7_score
    feedback_parts.append(f"Downloads & Startup: correctly set ({c7_score}/10 pts)")

    # Cleanup temp files
    for p in [bookmarks_path, history_path, prefs_path, local_state_path]:
        if p and os.path.exists(p):
            try: os.unlink(p)
            except: pass

    # Compute total
    total_score = sum(scores.values())
    passed = total_score >= 70 and c3_score >= 15 and c4_score >= 7.5
    
    return {
        "passed": passed,
        "score": int(total_score),
        "feedback": "\n".join(feedback_parts)
    }