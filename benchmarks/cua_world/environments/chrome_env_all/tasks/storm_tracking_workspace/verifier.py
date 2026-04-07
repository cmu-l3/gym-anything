#!/usr/bin/env python3
"""
Verifier for storm_tracking_workspace@1

Task: Reconfigure browser for severe weather monitoring.
Checks:
1. Operational bookmark folders created (20 pts)
2. Bookmarks correctly categorized (15 pts)
3. Personal bookmarks segregated (10 pts)
4. Search engine shortcuts configured (15 pts)
5. Homepage and startup pages (15 pts)
6. Privacy and download settings (15 pts)
7. Config handoff document written (10 pts)

Total: 100 points. Pass threshold: 70
"""

import json
import logging
import os
import sqlite3
import tempfile
import re
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected domain lists
DOMAINS_RADAR = ['radar.weather.gov', 'goes.noaa.gov', 'star.nesdis.noaa.gov', 'lightningmaps.org', 'aviationweather.gov', 'ocean.weather.gov', 'wpc.ncep.noaa.gov']
DOMAINS_MODEL = ['tropicaltidbits.com', 'pivotalweather.com', 'mag.ncep.noaa.gov', 'ncep.noaa.gov', 'ecmwf.int', 'weather.cod.edu']
DOMAINS_OBS = ['mesowest.utah.edu', 'rucsoundings.noaa.gov', 'ndbc.noaa.gov', 'weather.gov/wrh', 'madis-data.ncep.noaa.gov']
DOMAINS_PERSONAL = ['youtube.com', 'netflix.com', 'espn.com', 'amazon.com', 'reddit.com', 'spotify.com', 'instagram.com']

def _copy_file(copy_from_env, container_path: str, suffix: str = '') -> str:
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

def _extract_urls_from_folder(folder_node: dict) -> List[str]:
    urls = []
    for child in folder_node.get('children', []):
        if child.get('type') == 'url':
            urls.append(child.get('url', ''))
        elif child.get('type') == 'folder':
            urls.extend(_extract_urls_from_folder(child))
    return urls

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback = []
    
    # 1. Gather files
    bookmarks_path = _copy_file(copy_from_env, "/tmp/Bookmarks_export.json", ".json")
    prefs_path = _copy_file(copy_from_env, "/tmp/Preferences_export.json", ".json")
    webdata_path = _copy_file(copy_from_env, "/tmp/WebData_export.sqlite", ".sqlite")
    report_path = _copy_file(copy_from_env, "/home/ga/Desktop/config_handoff.txt", ".txt")
    initial_hash_path = _copy_file(copy_from_env, "/tmp/initial_bookmarks_hash.txt", ".txt")
    task_start_path = _copy_file(copy_from_env, "/tmp/task_start_time.txt", ".txt")
    
    if not bookmarks_path:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve Bookmarks file."}

    # Anti-Gaming: Check if bookmarks were modified at all
    bookmarks_modified = True
    if initial_hash_path:
        with open(initial_hash_path, 'r') as f:
            init_hash = f.read().strip()
        import hashlib
        with open(bookmarks_path, 'rb') as f:
            curr_hash = hashlib.md5(f.read()).hexdigest()
        if init_hash == curr_hash:
            bookmarks_modified = False

    try:
        with open(bookmarks_path, 'r') as f:
            bookmarks = json.load(f)
    except Exception:
        bookmarks = {}

    try:
        with open(prefs_path, 'r') as f:
            prefs = json.load(f)
    except Exception:
        prefs = {}

    # Read Bookmark Bar Children
    bb_children = bookmarks.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    folders = [c for c in bb_children if c.get('type') == 'folder']
    loose_urls = [c for c in bb_children if c.get('type') == 'url']

    # --- Criterion 1: Operational bookmark folders (20 pts) ---
    expected_folders = ["Radar & Satellite", "Model Data", "Observations", "Warning Coordination", "Climate & Verification"]
    found_operational_folders = []
    for ef in expected_folders:
        for folder in folders:
            # Flexible matching (remove spaces, symbols)
            n1 = re.sub(r'[^a-z]', '', ef.lower())
            n2 = re.sub(r'[^a-z]', '', folder.get('name', '').lower())
            if n1 == n2 or (n1 in n2) or (n2 in n1 and len(n2) > 5):
                found_operational_folders.append(folder)
                break
    
    c1_score = min(20, len(found_operational_folders) * 4)
    if c1_score == 20:
        feedback.append("✅ All 5 operational folders created.")
    else:
        feedback.append(f"⚠️ Found {len(found_operational_folders)}/5 operational folders ({c1_score}/20 pts).")
    score += c1_score

    # --- Criterion 2: Bookmarks categorized (15 pts) ---
    c2_score = 0
    radar_urls = []
    model_urls = []
    obs_urls = []
    
    for folder in found_operational_folders:
        fname = folder.get('name', '').lower()
        if 'radar' in fname: radar_urls.extend(_extract_urls_from_folder(folder))
        elif 'model' in fname: model_urls.extend(_extract_urls_from_folder(folder))
        elif 'obs' in fname: obs_urls.extend(_extract_urls_from_folder(folder))
        
    radar_matches = sum(1 for url in radar_urls if any(d in url for d in DOMAINS_RADAR))
    model_matches = sum(1 for url in model_urls if any(d in url for d in DOMAINS_MODEL))
    obs_matches = sum(1 for url in obs_urls if any(d in url for d in DOMAINS_OBS))
    
    if radar_matches >= 5: c2_score += 5
    if model_matches >= 4: c2_score += 5
    if obs_matches >= 3: c2_score += 5
    
    if c2_score == 15:
        feedback.append("✅ Operational bookmarks correctly categorized.")
    else:
        feedback.append(f"⚠️ Operational bookmarks partially categorized ({c2_score}/15 pts).")
    score += c2_score

    # --- Criterion 3: Personal bookmarks segregated (10 pts) ---
    c3_score = 0
    personal_folder = None
    for folder in folders:
        name = folder.get('name', '').lower()
        if 'off' in name or 'duty' in name or 'personal' in name:
            personal_folder = folder
            break
            
    loose_personal = sum(1 for url_node in loose_urls if any(d in url_node.get('url', '') for d in DOMAINS_PERSONAL))
    
    if personal_folder:
        c3_score += 3
        pers_urls = _extract_urls_from_folder(personal_folder)
        pers_matches = sum(1 for u in pers_urls if any(d in u for d in DOMAINS_PERSONAL))
        if pers_matches >= 5:
            c3_score += 7
        elif pers_matches > 0:
            c3_score += 3
            
    if loose_personal > 0:
        c3_score = max(0, c3_score - 5)
        feedback.append(f"❌ Found {loose_personal} personal bookmarks loose on bookmark bar.")
    else:
        feedback.append(f"✅ Personal bookmarks segregated ({c3_score}/10 pts).")
    score += c3_score

    # Anti-gaming: Mass deletion check
    all_urls = _extract_urls_from_folder(bookmarks.get('roots', {}).get('bookmark_bar', {}))
    if len(all_urls) < 15:
        score -= 20
        feedback.append("❌ ERROR: Mass deletion of bookmarks detected. Points deducted.")

    # --- Criterion 4: Search engines (15 pts) ---
    c4_score = 0
    found_keywords = set()
    # Check Preferences JSON
    for se in prefs.get('custom_search_providers', []):
        kw = se.get('keyword', '').lower()
        if kw in ['radar', 'spc', 'nhc']:
            found_keywords.add(kw)
    
    # Check SQLite Web Data as fallback
    if webdata_path:
        try:
            conn = sqlite3.connect(webdata_path)
            cursor = conn.cursor()
            cursor.execute("SELECT keyword FROM keywords")
            for row in cursor.fetchall():
                kw = row[0].lower() if row[0] else ""
                if kw in ['radar', 'spc', 'nhc']:
                    found_keywords.add(kw)
            conn.close()
        except Exception as e:
            logger.debug(f"SQLite check failed: {e}")
            
    c4_score = len(found_keywords) * 5
    if c4_score == 15:
        feedback.append("✅ All custom search engine shortcuts configured.")
    else:
        feedback.append(f"⚠️ Found {len(found_keywords)}/3 search engine shortcuts ({c4_score}/15 pts).")
    score += c4_score

    # --- Criterion 5: Homepage and startup (15 pts) ---
    c5_score = 0
    homepage = prefs.get('homepage', '').lower()
    if 'weather.gov' in homepage:
        c5_score += 5
        
    startup_urls = prefs.get('session', {}).get('startup_urls', [])
    startup_urls_str = " ".join(startup_urls).lower()
    if 'radar.weather.gov' in startup_urls_str: c5_score += 5
    if 'spc.noaa.gov' in startup_urls_str: c5_score += 5
    
    # restore_on_startup == 4 is specific pages
    if prefs.get('session', {}).get('restore_on_startup') != 4 and c5_score >= 10:
        c5_score -= 2 # Deduct slightly if they didn't set it to open the specific pages
        
    if c5_score >= 15:
        feedback.append("✅ Homepage and startup pages correctly configured.")
    else:
        feedback.append(f"⚠️ Homepage/startup partially configured ({c5_score}/15 pts).")
    score += c5_score

    # --- Criterion 6: Privacy and download settings (15 pts) ---
    c6_score = 0
    
    # Cookies
    cookies_setting = prefs.get('profile', {}).get('default_content_setting_values', {}).get('cookies')
    block_3rd_party = prefs.get('profile', {}).get('block_third_party_cookies')
    if cookies_setting == 1 or block_3rd_party is True:
        c6_score += 3
        
    # DNT
    if prefs.get('enable_do_not_track') is True:
        c6_score += 3
        
    # Download
    dl_dir = prefs.get('download', {}).get('default_directory', '')
    if 'Weather_Data' in dl_dir: c6_score += 3
    if prefs.get('download', {}).get('prompt_for_download') is True: c6_score += 3
        
    # Passwords
    if prefs.get('profile', {}).get('password_manager_enabled') is False or prefs.get('credentials_enable_service') is False:
        c6_score += 3
        
    if c6_score == 15:
        feedback.append("✅ Security, privacy, and download settings compliant.")
    else:
        feedback.append(f"⚠️ Security/privacy/download settings partially compliant ({c6_score}/15 pts).")
    score += c6_score

    # --- Criterion 7: Handoff document (10 pts) ---
    c7_score = 0
    if report_path:
        try:
            task_start_ts = 0
            if task_start_path:
                with open(task_start_path, 'r') as f:
                    task_start_ts = int(f.read().strip())
                    
            mtime = os.path.getmtime(report_path)
            if mtime >= task_start_ts:
                c7_score += 2
                with open(report_path, 'r', encoding='utf-8') as f:
                    content = f.read().lower()
                    if len(content) > 100: c7_score += 2
                    if 'radar' in content or 'folder' in content: c7_score += 2
                    if 'shortcut' in content or 'search' in content: c7_score += 2
                    if 'weather.gov' in content or 'home' in content: c7_score += 2
        except Exception:
            pass

    if c7_score == 10:
        feedback.append("✅ Shift handoff document written and substantive.")
    elif c7_score > 0:
        feedback.append(f"⚠️ Shift handoff document incomplete ({c7_score}/10 pts).")
    else:
        feedback.append("❌ Shift handoff document missing or invalid (0/10 pts).")
    score += c7_score

    # Anti-gaming 0 score check
    if not bookmarks_modified:
        score = 0
        feedback.append("❌ CRITICAL: Bookmarks were not modified at all. Do-nothing detected.")

    passed = score >= 70
    
    # Cleanup temps
    for p in [bookmarks_path, prefs_path, webdata_path, report_path, initial_hash_path, task_start_path]:
        if p and os.path.exists(p):
            try: os.unlink(p)
            except: pass

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }