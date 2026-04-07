#!/usr/bin/env python3
"""
Verifier for construction_project_workspace@1

Checks that the agent successfully configured the browser per the construction IT spec:
1. Bookmark hierarchy (Summit Crossing, Archived, Personal)
2. Bookmark categorization
3. Search engines (Web Data SQLite DB or Preferences)
4. Homepage and startup pages
5. Download directory and prompt
6. Privacy and security settings
7. Notification permissions

Uses copy_from_env to retrieve files from the container for evaluation.
"""

import logging
import os
import json
import sqlite3
import tempfile
from typing import Dict, List, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Domain mappings for categorization checks ---
DOMAIN_MAP = {
    "codes": ['iccsafe.org', 'nfpa.org', 'astm.org', 'concrete.org', 'aisc.org'],
    "safety": ['osha.gov', 'cpwr.com'],
    "project management": ['procore.com', 'autodesk.com', 'plangrid.com', 'bluebeam.com', 'smartsheet.com'],
    "materials": ['grainger.com', 'fastenal.com', 'mcmaster.com'],
    "weather": ['weather.gov', 'wunderground.com'],
    "equipment": ['unitedrentals.com', 'sunbeltrentals.com', 'cat.com'],
    "personal": ['espn.com', 'amazon.com', 'youtube.com', 'nfl.com', 'basspro.com', 
                 'homedepot.com', 'zillow.com', 'bankofamerica.com', 'mail.google.com', 'facebook.com']
}


def _copy_file(copy_from_env, paths: List[str], suffix: str = '') -> Optional[str]:
    """Tries multiple paths to copy a file from the environment to a temporary local file."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp_path = tmp.name
    tmp.close()

    for p in paths:
        try:
            copy_from_env(p, tmp_path)
            if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 10:
                return tmp_path
        except Exception:
            pass

    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    return None


def _get_json_data(copy_from_env, paths: List[str]) -> Dict:
    local_path = _copy_file(copy_from_env, paths, suffix='.json')
    if not local_path:
        return {}
    try:
        with open(local_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        os.unlink(local_path)
        return data
    except Exception as e:
        logger.error(f"Error parsing JSON: {e}")
        if os.path.exists(local_path):
            os.unlink(local_path)
        return {}


def _collect_bookmarks(node: Dict, collection: List[Dict]):
    if isinstance(node, dict):
        if node.get('type') == 'url':
            collection.append(node)
        for child in node.get('children', []):
            _collect_bookmarks(child, collection)


def _find_folder(children: List[Dict], keywords: List[str]) -> Optional[Dict]:
    for child in children:
        if child.get('type') == 'folder':
            name = child.get('name', '').lower()
            if all(k in name for k in keywords):
                return child
    return None


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Evaluation error: copy_from_env unavailable."}

    # 1. Gather files
    bookmarks = _get_json_data(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Bookmarks",
        "/home/ga/.config/chromium/Default/Bookmarks"
    ])
    prefs = _get_json_data(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Preferences",
        "/home/ga/.config/chromium/Default/Preferences"
    ])
    
    # For custom search engines, check Web Data SQLite database
    web_data_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Web Data",
        "/home/ga/.config/chromium/Default/Web Data"
    ])

    score = 0
    feedback_parts = []
    
    # Anti-gaming: Ensure mass-deletion didn't happen
    all_bms = []
    _collect_bookmarks(bookmarks.get('roots', {}), all_bms)
    if len(all_bms) < 35:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Task Failed: Mass deletion detected. Only {len(all_bms)}/38 bookmarks remain."
        }

    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {}).get('children', [])

    # CRITERION 1: Summit Crossing Project & Subfolders (25 pts)
    summit_folder = _find_folder(bookmark_bar, ["summit"])
    if summit_folder:
        score += 5
        feedback_parts.append("[+] 'Summit Crossing' folder found (5/5 pts)")
        
        subfolder_score = 0
        sub_children = summit_folder.get('children', [])
        for cat, domains in DOMAIN_MAP.items():
            if cat == "personal": continue
            sf = _find_folder(sub_children, cat.split()[:1]) # match first word e.g. 'codes', 'safety'
            if sf:
                urls = []
                _collect_bookmarks(sf, urls)
                if any(any(d in u.get('url', '') for d in domains) for u in urls):
                    subfolder_score += 3.33
        
        score += min(20, subfolder_score)
        feedback_parts.append(f"[+] Subfolder categorization ({min(20, subfolder_score):.1f}/20 pts)")
    else:
        feedback_parts.append("[-] 'Summit Crossing' folder not found (0/25 pts)")

    # CRITERION 2: Archived Riverside Commons (15 pts)
    archived_folder = _find_folder(bookmark_bar, ["archived", "riverside"])
    if archived_folder:
        score += 5
        archived_urls = []
        _collect_bookmarks(archived_folder, archived_urls)
        rc_count = sum(1 for u in archived_urls if "rc-" in u.get('url', '').lower() or "riverside" in u.get('url', '').lower())
        rc_score = min(10, (rc_count / 8.0) * 10)
        score += rc_score
        feedback_parts.append(f"[+] Archived folder found and populated ({5 + rc_score:.1f}/15 pts)")
    else:
        feedback_parts.append("[-] 'Archived' folder not found (0/15 pts)")

    # CRITERION 3: Personal Folder & Isolation (10 pts)
    personal_folder = _find_folder(bookmark_bar, ["personal"])
    if personal_folder:
        score += 3
        pers_urls = []
        _collect_bookmarks(personal_folder, pers_urls)
        pers_count = sum(1 for u in pers_urls if any(d in u.get('url', '') for d in DOMAIN_MAP["personal"]))
        score += min(4, (pers_count / 10.0) * 4)
        
        # Check for loose personal bookmarks
        loose_pers = sum(1 for u in bookmark_bar if u.get('type') == 'url' and any(d in u.get('url', '') for d in DOMAIN_MAP["personal"]))
        if loose_pers == 0:
            score += 3
            feedback_parts.append(f"[+] Personal folder created and isolated ({3 + min(4, (pers_count/10.0)*4) + 3:.1f}/10 pts)")
        else:
            feedback_parts.append(f"[-] Personal folder exists, but {loose_pers} personal bookmarks left loose on bar")
    else:
        feedback_parts.append("[-] 'Personal' folder not found (0/10 pts)")

    # CRITERION 4: Custom Search Engines (15 pts)
    search_score = 0
    found_keywords = set()
    
    # Check Web Data (standard place for user-added search engines)
    if web_data_path:
        try:
            conn = sqlite3.connect(web_data_path)
            cursor = conn.cursor()
            cursor.execute("SELECT keyword FROM keywords")
            rows = cursor.fetchall()
            found_keywords.update(r[0].lower() for r in rows)
            conn.close()
        except Exception as e:
            logger.error(f"SQLite read error: {e}")
        finally:
            os.unlink(web_data_path)
    
    # Also check Preferences just in case
    overrides = prefs.get('search_provider_overrides', [])
    for ov in overrides:
        found_keywords.add(ov.get('keyword', '').lower())

    for kw in ['icc', 'osha', 'msds']:
        if kw in found_keywords:
            search_score += 5
            
    score += search_score
    feedback_parts.append(f"[+] Custom Search Engines ({search_score}/15 pts)")

    # CRITERION 5: Homepage & Startup (10 pts)
    hs_score = 0
    if "procore.com" in prefs.get("homepage", ""):
        hs_score += 4
    
    startup_urls = prefs.get("session", {}).get("startup_urls", [])
    if any("procore.com" in u for u in startup_urls): hs_score += 3
    if any("weather.gov" in u for u in startup_urls): hs_score += 3
    
    score += hs_score
    feedback_parts.append(f"[+] Homepage & Startup ({hs_score}/10 pts)")

    # CRITERION 6: Downloads (10 pts)
    dl_score = 0
    dl_dir = prefs.get("download", {}).get("default_directory", "")
    if "Summit_Crossing" in dl_dir: dl_score += 5
    if prefs.get("download", {}).get("prompt_for_download", False): dl_score += 5
    
    score += dl_score
    feedback_parts.append(f"[+] Downloads Config ({dl_score}/10 pts)")

    # CRITERION 7: Privacy & Security & Site Permissions (15 pts)
    priv_score = 0
    if prefs.get("profile", {}).get("cookie_controls_mode", 0) == 1: priv_score += 3
    if not prefs.get("credentials_enable_service", True): priv_score += 3
    if not prefs.get("autofill", {}).get("profile_enabled", True): priv_score += 3
    
    # Check Site Permissions
    notifications = prefs.get("profile", {}).get("content_settings", {}).get("exceptions", {}).get("notifications", {})
    if any("procore.com" in k and v.get("setting") == 1 for k, v in notifications.items()): priv_score += 3
    if any("smartsheet.com" in k and v.get("setting") == 1 for k, v in notifications.items()): priv_score += 3
    
    score += priv_score
    feedback_parts.append(f"[+] Privacy & Site Permissions ({priv_score}/15 pts)")

    total_score = round(score)
    passed = total_score >= 70

    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_parts)
    }