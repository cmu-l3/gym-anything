#!/usr/bin/env python3
"""
Verifier for Port Control Terminal Setup Task (port_control_terminal_setup@1)
"""

import logging
import os
import json
import sqlite3
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _copy_file(copy_from_env, container_paths: List[str], suffix: str = '') -> str:
    """Helper to copy a file from the container, trying multiple candidate paths."""
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

def _get_all_bookmark_urls(node: dict) -> List[str]:
    """Recursively extract all URLs from a bookmark tree node."""
    urls = []
    if node.get('type') == 'url':
        urls.append(node.get('url', '').lower())
    for child in node.get('children', []):
        urls.extend(_get_all_bookmark_urls(child))
    return urls

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    personal_domains = metadata.get('personal_domains', [])
    maritime_domains = metadata.get('maritime_domains', [])

    # Paths to check (CDP profile is primary in this environment)
    profiles = [
        "/home/ga/.config/google-chrome-cdp/Default",
        "/home/ga/.config/google-chrome/Default"
    ]

    bm_paths = [f"{p}/Bookmarks" for p in profiles]
    hist_paths = [f"{p}/History" for p in profiles]
    prefs_paths = [f"{p}/Preferences" for p in profiles]
    webdata_paths = [f"{p}/Web Data" for p in profiles]
    localstate_paths = ["/home/ga/.config/google-chrome-cdp/Local State", "/home/ga/.config/google-chrome/Local State"]

    # Copy files
    bm_file = _copy_file(copy_from_env, bm_paths, ".json")
    hist_file = _copy_file(copy_from_env, hist_paths, ".sqlite")
    prefs_file = _copy_file(copy_from_env, prefs_paths, ".json")
    webdata_file = _copy_file(copy_from_env, webdata_paths, ".sqlite")
    localstate_file = _copy_file(copy_from_env, localstate_paths, ".json")

    score = 0
    feedback = []

    try:
        # =====================================================================
        # 1 & 2. Bookmark Organization (20 pts) & Sanitization (15 pts)
        # =====================================================================
        bms = {}
        if bm_file:
            with open(bm_file, 'r', encoding='utf-8') as f:
                bms = json.load(f)
        
        bb = bms.get('roots', {}).get('bookmark_bar', {})
        children = bb.get('children', [])
        
        # Check folders
        found_folders = [c.get('name') for c in children if c.get('type') == 'folder']
        expected_folders = ["AIS & Tracking", "Metocean Data", "Port Operations", "Emergency & USCG"]
        folders_matched = sum(1 for f in expected_folders if f in found_folders)
        
        c1_score = folders_matched * 5
        score += c1_score
        feedback.append(f"Bookmark folders: {folders_matched}/{len(expected_folders)} found ({c1_score}/20 pts)")

        # Check sanitization
        all_urls = _get_all_bookmark_urls(bms.get('roots', {}))
        personal_found = sum(1 for url in all_urls if any(pd in url for pd in personal_domains))
        
        if personal_found == 0 and len(all_urls) > 0:
            score += 15
            feedback.append("Bookmark sanitization: 0 personal bookmarks found (15/15 pts)")
        elif personal_found > 0:
            feedback.append(f"Bookmark sanitization: {personal_found} personal bookmarks still exist (0/15 pts)")
        else:
            feedback.append("Bookmark sanitization: No bookmarks found at all (0/15 pts)")

        # =====================================================================
        # 3. History Sanitization (15 pts)
        # =====================================================================
        c3_score = 0
        if hist_file:
            conn = sqlite3.connect(hist_file)
            c = conn.cursor()
            c.execute("SELECT url FROM urls")
            rows = c.fetchall()
            conn.close()
            
            hist_urls = [r[0].lower() for r in rows]
            pers_hist = sum(1 for url in hist_urls if any(pd in url for pd in personal_domains))
            mari_hist = sum(1 for url in hist_urls if any(md in url for md in maritime_domains))
            
            if pers_hist == 0 and mari_hist >= 10:
                c3_score = 15
                feedback.append(f"History sanitization: Personal purged, Maritime preserved ({mari_hist} entries) (15/15 pts)")
            elif pers_hist == 0 and mari_hist < 10:
                feedback.append("History sanitization: Both personal and maritime history appear deleted (0/15 pts)")
            else:
                feedback.append(f"History sanitization: {pers_hist} personal history entries remain (0/15 pts)")
        else:
            feedback.append("History sanitization: Could not read History database (0/15 pts)")
        score += c3_score

        # =====================================================================
        # Parse Preferences & Local State
        # =====================================================================
        prefs = {}
        if prefs_file:
            with open(prefs_file, 'r', encoding='utf-8') as f:
                prefs = json.load(f)
                
        lstate = {}
        if localstate_file:
            with open(localstate_file, 'r', encoding='utf-8') as f:
                lstate = json.load(f)

        # =====================================================================
        # 4. Startup Pages (10 pts)
        # =====================================================================
        startup_urls = prefs.get('session', {}).get('startup_urls', [])
        restore_val = prefs.get('session', {}).get('restore_on_startup', 0)
        
        startup_found = 0
        if "https://www.marinetraffic.com" in startup_urls or "https://www.marinetraffic.com/" in startup_urls:
            startup_found += 5
        if "https://tidesandcurrents.noaa.gov" in startup_urls or "https://tidesandcurrents.noaa.gov/" in startup_urls:
            startup_found += 5
            
        if restore_val == 4 and startup_found > 0:
            score += startup_found
            feedback.append(f"Startup pages configured correctly ({startup_found}/10 pts)")
        else:
            feedback.append(f"Startup pages missing or restore_on_startup not set to specific pages (0/10 pts)")

        # =====================================================================
        # 5. Vessel Search Engine (15 pts)
        # =====================================================================
        search_engine_found = False
        if webdata_file:
            try:
                conn = sqlite3.connect(webdata_file)
                c = conn.cursor()
                c.execute("SELECT keyword, url FROM keywords")
                for kw, url in c.fetchall():
                    if kw == 'imo' and 'vesselfinder.com' in url and '%s' in url:
                        search_engine_found = True
                        break
                conn.close()
            except sqlite3.Error:
                pass
                
        # Also check prefs just in case
        if not search_engine_found:
            custom_searches = prefs.get('profile', {}).get('custom_search_providers', [])
            for csp in custom_searches:
                if csp.get('keyword') == 'imo' and 'vesselfinder.com' in csp.get('url', ''):
                    search_engine_found = True
                    break

        if search_engine_found:
            score += 15
            feedback.append("Vessel search engine configured correctly (15/15 pts)")
        else:
            feedback.append("Vessel search engine not found (0/15 pts)")

        # =====================================================================
        # 6. Anti-Throttling Flag (15 pts)
        # =====================================================================
        experiments = lstate.get('browser', {}).get('enabled_labs_experiments', [])
        if "intensive-wake-up-throttling@2" in experiments:
            score += 15
            feedback.append("Anti-throttling flag disabled correctly (15/15 pts)")
        else:
            feedback.append("Anti-throttling flag not disabled (0/15 pts)")

        # =====================================================================
        # 7. Downloads & Notifications (10 pts)
        # =====================================================================
        dl_dir = prefs.get('download', {}).get('default_directory', '')
        notif_setting = prefs.get('profile', {}).get('default_content_setting_values', {}).get('notifications', 0)
        
        c7_score = 0
        if "Vessel_Manifests" in dl_dir:
            c7_score += 5
        if notif_setting == 2:
            c7_score += 5
            
        score += c7_score
        feedback.append(f"Downloads and notifications configured ({c7_score}/10 pts)")

    finally:
        # Cleanup temp files
        for f in [bm_file, hist_file, prefs_file, webdata_file, localstate_file]:
            if f and os.path.exists(f):
                os.unlink(f)

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }