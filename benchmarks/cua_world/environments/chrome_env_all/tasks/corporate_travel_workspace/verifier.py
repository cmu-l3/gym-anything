#!/usr/bin/env python3
"""
Verifier for Corporate Travel Workspace Task (corporate_travel_workspace@1)

Verifies:
1. Bookmark Folders Created (10 pts)
2. Airline/Hotel Sorting (20 pts)
3. Global Security Settings (15 pts)
4. Site-Specific Cookie Exceptions (15 pts)
5. Site-Specific Popup Exceptions (15 pts)
6. Custom Search Engine in Web Data (15 pts)
7. Startup Behavior (10 pts)
"""

import os
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Domain mapping for verification
EXPECTED_SORTING = {
    "oneworld": ["aa.com", "britishairways.com", "qantas.com", "cathaypacific.com", "jal.co.jp", "finnair.com", "iberia.com"],
    "skyteam": ["delta.com", "airfrance.com", "klm.com", "koreanair.com", "aeromexico.com", "virginatlantic.com", "ita-airways.com"],
    "star alliance": ["united.com", "lufthansa.com", "ana.co.jp", "aircanada.com", "singaporeair.com", "flytap.com", "evaair.com", "swiss.com", "flyasiana.com"],
    "hotels": ["marriott.com", "hilton.com", "hyatt.com", "ihg.com", "radissonhotels.com", "wyndhamhotels.com", "choicehotels.com"]
}

def _copy_file_from_container(copy_from_env, container_paths: list, suffix: str = '') -> str:
    """Attempts to copy a file from multiple candidate paths and returns the local temp path."""
    temp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp.name
    temp.close()

    for cpath in container_paths:
        try:
            copy_from_env(cpath, temp_path)
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                return temp_path
        except Exception:
            continue

    if os.path.exists(temp_path):
        os.unlink(temp_path)
    return None

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define candidate paths (handling default and cdp profiles)
    bm_paths = [
        "/home/ga/.config/google-chrome/Default/Bookmarks",
        "/home/ga/.config/google-chrome-cdp/Default/Bookmarks"
    ]
    prefs_paths = [
        "/home/ga/.config/google-chrome/Default/Preferences",
        "/home/ga/.config/google-chrome-cdp/Default/Preferences"
    ]
    webdata_paths = [
        "/home/ga/.config/google-chrome/Default/Web Data",
        "/home/ga/.config/google-chrome-cdp/Default/Web Data"
    ]

    bm_local = _copy_file_from_container(copy_from_env, bm_paths, '.json')
    prefs_local = _copy_file_from_container(copy_from_env, prefs_paths, '.json')
    webdata_local = _copy_file_from_container(copy_from_env, webdata_paths, '.sqlite')
    result_local = _copy_file_from_container(copy_from_env, ["/tmp/task_result.json"], '.json')

    score = 0
    feedback = []
    
    # Check Anti-gaming (Timestamps)
    try:
        with open(result_local, 'r') as f:
            res_data = json.load(f)
            task_start = res_data.get('task_start', 0)
    except:
        task_start = 0

    # Parse Bookmarks
    bookmarks = {}
    if bm_local:
        try:
            with open(bm_local, 'r', encoding='utf-8') as f:
                bookmarks = json.load(f)
        except Exception as e:
            logger.error(f"Failed to parse bookmarks: {e}")
        finally:
            os.unlink(bm_local)

    # Parse Preferences
    prefs = {}
    if prefs_local:
        try:
            with open(prefs_local, 'r', encoding='utf-8') as f:
                prefs = json.load(f)
        except Exception as e:
            logger.error(f"Failed to parse preferences: {e}")
        finally:
            os.unlink(prefs_local)

    # 1. Bookmark Folders (10 pts) & 2. Airline/Hotel Sorting (20 pts)
    folder_score = 0
    sorting_score = 0
    b_bar = bookmarks.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    
    found_folders = {}
    for item in b_bar:
        if item.get('type') == 'folder':
            name = item.get('name', '').strip().lower()
            found_folders[name] = item.get('children', [])

    for expected_folder, domains in EXPECTED_SORTING.items():
        if expected_folder in found_folders:
            folder_score += 2.5  # 4 folders = 10 pts
            
            # Check domains inside
            children_urls = [c.get('url', '').lower() for c in found_folders[expected_folder] if c.get('type') == 'url']
            matched = sum(1 for d in domains if any(d in url for url in children_urls))
            
            # Allow 80% threshold for full credit per folder (5 pts per folder)
            if matched >= len(domains) * 0.8:
                sorting_score += 5
            elif matched > 0:
                sorting_score += int((matched / len(domains)) * 5)

    score += folder_score
    score += sorting_score
    feedback.append(f"Bookmark Folders: {folder_score}/10 pts")
    feedback.append(f"Bookmark Sorting: {sorting_score}/20 pts")

    # 3. Global Security Settings (15 pts)
    sec_score = 0
    profile = prefs.get('profile', {})
    
    # Third-party cookies blocked
    if profile.get('cookie_controls_mode') == 1:
        sec_score += 5
    
    # Popups blocked
    if profile.get('default_content_setting_values', {}).get('popups') == 2:
        sec_score += 5
        
    # Passwords disabled
    if not profile.get('password_manager_enabled', True) or not prefs.get('credentials_enable_service', True):
        sec_score += 5

    score += sec_score
    feedback.append(f"Global Security Settings: {sec_score}/15 pts")

    # 4 & 5. Site-Specific Exceptions (15 pts Cookies, 15 pts Popups)
    exceptions = profile.get('content_settings', {}).get('exceptions', {})
    
    def check_exceptions(setting_dict, targets):
        pts = 0
        for target in targets:
            # Look for the target domain in the keys of the exception dictionary
            for key, val in setting_dict.items():
                if target in key and val.get('setting') == 1: # 1 means Allow
                    pts += 7.5
                    break
        return pts

    cookie_pts = check_exceptions(exceptions.get('cookies', {}), ['concursolutions.com', 'amadeus.com'])
    popup_pts = check_exceptions(exceptions.get('popups', {}), ['concursolutions.com', 'amadeus.com'])
    
    score += cookie_pts
    score += popup_pts
    feedback.append(f"Cookie Exceptions: {cookie_pts}/15 pts")
    feedback.append(f"Popup Exceptions: {popup_pts}/15 pts")

    # 6. Custom Search Engine (15 pts) - Requires reading Web Data SQLite DB
    search_score = 0
    if webdata_local:
        try:
            conn = sqlite3.connect(webdata_local)
            cursor = conn.cursor()
            cursor.execute("SELECT url FROM keywords WHERE keyword='fa'")
            row = cursor.fetchone()
            if row and 'flightaware.com' in row[0].lower() and '%s' in row[0]:
                search_score = 15
            conn.close()
        except Exception as e:
            logger.error(f"SQLite DB error: {e}")
        finally:
            os.unlink(webdata_local)
    
    score += search_score
    feedback.append(f"Search Engine: {search_score}/15 pts")

    # 7. Startup Behavior (10 pts)
    startup_score = 0
    if prefs.get('session', {}).get('restore_on_startup') == 1:
        startup_score = 10
        
    score += startup_score
    feedback.append(f"Startup Behavior: {startup_score}/10 pts")

    # Final Evaluation
    passed = score >= 75 and folder_score > 0 and (cookie_pts > 0 or popup_pts > 0)
    
    if os.path.exists(result_local):
        os.unlink(result_local)

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }