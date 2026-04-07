#!/usr/bin/env python3
"""
Verifier for solar_farm_rugged_terminal@1

Criteria evaluated (100 points total, pass >= 75):
1. Bookmark Organization (20 pts)
2. Personal Bookmarks Deleted (10 pts)
3. Font Size Accessibility (15 pts)
4. Touch-Optimized Flags (15 pts)
5. Fault Code Search Engine (15 pts)
6. Homepage & Downloads (15 pts)
7. Shared Device Privacy (10 pts)
"""

import json
import logging
import os
import tempfile
import sqlite3
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PERSONAL_DOMAINS = ["reddit.com", "netflix.com", "espn.com", "amazon.com", "facebook.com", "twitter.com"]
EXPECTED_FOLDERS = ["SCADA & Telemetry", "Weather & Irradiance", "Grid Market Data", "Equipment Docs"]

def _copy_file(copy_from_env, container_paths: List[str], suffix: str = '.json') -> Optional[str]:
    """Helper to copy a file from the container, trying multiple candidate paths."""
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

def _get_all_urls(node: Dict, urls: List[str]):
    if node.get('type') == 'url':
        urls.append(node.get('url', '').lower())
    for child in node.get('children', []):
        _get_all_urls(child, urls)

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []

    try:
        # Extract files
        bookmarks_file = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Default/Bookmarks"])
        prefs_file = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Default/Preferences"])
        local_state_file = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Local State"])
        web_data_file = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Default/Web Data"], suffix='.sqlite')

        # Load JSON data
        bookmarks = json.load(open(bookmarks_file)) if bookmarks_file else {}
        prefs = json.load(open(prefs_file)) if prefs_file else {}
        local_state = json.load(open(local_state_file)) if local_state_file else {}

        # -------------------------------------------------------------
        # 1. Bookmark Organization (20 pts)
        # -------------------------------------------------------------
        b_score = 0
        bbar_children = bookmarks.get('roots', {}).get('bookmark_bar', {}).get('children', [])
        found_folders = [c.get('name', '').strip() for c in bbar_children if c.get('type') == 'folder']
        
        for ef in EXPECTED_FOLDERS:
            # Case insensitive match for folders
            if any(ef.lower() in f.lower() for f in found_folders):
                b_score += 5
        score += b_score
        feedback.append(f"[Bookmark Folders] Found {int(b_score/5)}/4 expected folders (+{b_score} pts)")

        # -------------------------------------------------------------
        # 2. Personal Bookmarks Deleted (10 pts)
        # -------------------------------------------------------------
        all_urls = []
        _get_all_urls(bookmarks.get('roots', {}), all_urls)
        
        personal_found = False
        for url in all_urls:
            if any(p in url for p in PERSONAL_DOMAINS):
                personal_found = True
                break
        
        if not personal_found and len(all_urls) > 0:
            score += 10
            feedback.append("[Data Hygiene] Personal bookmarks successfully deleted (+10 pts)")
        else:
            feedback.append("[Data Hygiene] Personal bookmarks were not completely deleted (0 pts)")

        # -------------------------------------------------------------
        # 3. Font Size Accessibility (15 pts)
        # -------------------------------------------------------------
        font_size = prefs.get('webkit', {}).get('webprefs', {}).get('default_font_size', 16)
        if font_size == 22:
            score += 15
            feedback.append("[Font Size] Font size correctly set to 22 (+15 pts)")
        else:
            feedback.append(f"[Font Size] Font size is {font_size}, expected 22 (0 pts)")

        # -------------------------------------------------------------
        # 4. Touch-Optimized Flags (15 pts)
        # -------------------------------------------------------------
        flags = local_state.get('browser', {}).get('enabled_labs_experiments', [])
        flag_score = 0
        if any('overlay-scrollbars' in f.lower() for f in flags): flag_score += 7.5
        if any('smooth-scrolling' in f.lower() for f in flags): flag_score += 7.5
        score += flag_score
        feedback.append(f"[Chrome Flags] Touch-optimized flags score (+{flag_score} pts)")

        # -------------------------------------------------------------
        # 5. Fault Code Search Engine (15 pts)
        # -------------------------------------------------------------
        se_found = False
        # First check SQLite Web Data (where Chrome typically writes them)
        if web_data_file:
            try:
                conn = sqlite3.connect(web_data_file)
                cursor = conn.cursor()
                cursor.execute("SELECT keyword, url FROM keywords")
                for row in cursor.fetchall():
                    kw, url = row[0], row[1]
                    if kw and 'fault' in kw.lower() and 'inverter-faults-db.com' in url:
                        se_found = True
                        break
                conn.close()
            except Exception as e:
                logger.debug(f"SQLite check failed: {e}")

        # Fallback check inside preferences (sync data)
        if not se_found:
            custom_providers = prefs.get('profile', {}).get('custom_search_providers', [])
            for p in custom_providers:
                if 'fault' in p.get('keyword', '').lower() and 'inverter-faults-db' in p.get('url', ''):
                    se_found = True
                    break

        if se_found:
            score += 15
            feedback.append("[Search Shortcut] Custom 'fault' search engine configured (+15 pts)")
        else:
            feedback.append("[Search Shortcut] Custom search engine not found (0 pts)")

        # -------------------------------------------------------------
        # 6. Homepage & Downloads (15 pts)
        # -------------------------------------------------------------
        hd_score = 0
        homepage = prefs.get('homepage', '')
        if 'caiso.com' in homepage.lower():
            hd_score += 5
        
        dl_dir = prefs.get('download', {}).get('default_directory', '')
        if 'SCADA_Exports' in dl_dir:
            hd_score += 5
            
        dl_prompt = prefs.get('download', {}).get('prompt_for_download', False)
        if dl_prompt is True:
            hd_score += 5
            
        score += hd_score
        feedback.append(f"[Homepage & Downloads] Configured correctly (+{hd_score} pts)")

        # -------------------------------------------------------------
        # 7. Shared Device Privacy (10 pts)
        # -------------------------------------------------------------
        priv_score = 0
        pwd_mgr = prefs.get('profile', {}).get('password_manager_enabled', True)
        if pwd_mgr is False:
            priv_score += 5
            
        autofill = prefs.get('autofill', {}).get('profile_enabled', True)
        if autofill is False:
            priv_score += 5
            
        score += priv_score
        feedback.append(f"[Privacy] Credential/Autofill caching disabled (+{priv_score} pts)")

    finally:
        # Clean up temp files safely
        for f in [bookmarks_file, prefs_file, local_state_file, web_data_file]:
            if f and os.path.exists(f):
                os.unlink(f)

    # Determine passing state
    key_criteria_met = (b_score == 20) and (flag_score == 15)
    passed = (score >= 75) and key_criteria_met

    if not passed and score >= 75:
        feedback.append("\nFAILED: Score met threshold, but key criteria (Folders and Flags) were missing.")
    elif passed:
        feedback.append("\nPASSED: Terminal correctly configured for field deployment.")

    return {
        "passed": passed,
        "score": int(score),
        "feedback": "\n".join(feedback)
    }