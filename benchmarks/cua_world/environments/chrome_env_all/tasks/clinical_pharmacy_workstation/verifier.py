#!/usr/bin/env python3
"""
Verifier for Clinical Pharmacy Workstation Task (clinical_pharmacy_workstation@1)

Evaluates:
1. Clinical Bookmark Folders (20 pts)
2. Bookmark Sorting Accuracy (15 pts)
3. Quarantine Personal Links (15 pts)
4. Custom Search Engines (15 pts)
5. Homepage Configuration (10 pts)
6. HIPAA Privacy Settings (15 pts)
7. Download Configuration (10 pts)
"""

import json
import logging
import os
import sqlite3
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected domains for mapping checks
DRUG_INFO_DOMAINS = [
    "dailymed.nlm.nih.gov", "epocrates.com", "lexi.com", "micromedexsolutions.com",
    "drugs.com", "medscape.com", "pdr.net", "rxlist.com", "mayoclinic.org",
    "webmd.com", "medlineplus.gov", "merckmanuals.com"
]

SHORTAGES_DOMAINS = [
    "accessdata.fda.gov/scripts/drugshortages", "ashp.org", "fda.gov/safety/recalls",
    "emergency.cdc.gov", "ismp.org"
]

REGULATORY_DOMAINS = [
    "accessdata.fda.gov/scripts/cder/ob", "deadiversion.usdoj.gov",
    "cdc.gov/infectioncontrol", "pubmed.ncbi.nlm.nih.gov", "nabp.pharmacy"
]

PERSONAL_DOMAINS = [
    "amazon.com", "ebay.com", "facebook.com", "youtube.com", "netflix.com",
    "spotify.com", "espn.com", "pinterest.com", "x.com", "weather.com"
]


def _copy_file(copy_from_env, container_paths: List[str], suffix: str = '.json') -> str:
    """Attempts to copy a file from multiple container paths. Returns local path or None."""
    temp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp.name
    temp.close()

    for cpath in container_paths:
        try:
            copy_from_env(cpath, temp_path)
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                return temp_path
        except Exception:
            pass
            
    if os.path.exists(temp_path):
        os.unlink(temp_path)
    return None


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Retrieve files from container
    # ---------------------------------------------------------
    bookmarks_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Bookmarks",
        "/home/ga/.config/google-chrome-cdp/Default/Bookmarks"
    ], ".json")
    
    prefs_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Preferences",
        "/home/ga/.config/google-chrome-cdp/Default/Preferences"
    ], ".json")

    web_data_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Web Data",
        "/home/ga/.config/google-chrome-cdp/Default/Web Data"
    ], ".sqlite")

    bookmarks = {}
    if bookmarks_path:
        try:
            with open(bookmarks_path, 'r', encoding='utf-8') as f:
                bookmarks = json.load(f)
        except Exception as e:
            logger.error(f"Failed to parse Bookmarks: {e}")

    prefs = {}
    if prefs_path:
        try:
            with open(prefs_path, 'r', encoding='utf-8') as f:
                prefs = json.load(f)
        except Exception as e:
            logger.error(f"Failed to parse Preferences: {e}")

    bookmark_bar = bookmarks.get("roots", {}).get("bookmark_bar", {})
    bar_children = bookmark_bar.get("children", [])

    # ---------------------------------------------------------
    # 1. Clinical Bookmark Folders (20 pts)
    # ---------------------------------------------------------
    expected_folders = {
        "drug information": False,
        "shortages & recalls": False,
        "regulatory & guidelines": False,
        "unauthorized_personal": False
    }
    
    actual_folders = {}
    for child in bar_children:
        if child.get("type") == "folder":
            name = child.get("name", "").lower().strip()
            actual_folders[name] = child
            for req in expected_folders.keys():
                if req in name or req.replace("_", " ") in name:
                    expected_folders[req] = True
    
    found_count = sum(expected_folders.values())
    c1_score = found_count * 5
    score += c1_score
    feedback_parts.append(f"[1] Folders Found: {found_count}/4 ({c1_score}/20 pts)")

    # ---------------------------------------------------------
    # 2. Bookmark Sorting Accuracy (15 pts) & 3. Quarantine (15 pts)
    # ---------------------------------------------------------
    # Check what domains exist in which folders
    c2_score = 0
    c3_score = 0
    
    loose_personal = 0
    correct_clinical = 0
    total_clinical = len(DRUG_INFO_DOMAINS) + len(SHORTAGES_DOMAINS) + len(REGULATORY_DOMAINS)
    
    # helper to check domain in list
    def _in_list(url, domain_list):
        return any(d in url for d in domain_list)

    # Check loose items on bar
    for child in bar_children:
        if child.get("type") == "url":
            url = child.get("url", "").lower()
            if _in_list(url, PERSONAL_DOMAINS):
                loose_personal += 1

    # Check inside folders
    for folder_name, folder_node in actual_folders.items():
        children = folder_node.get("children", [])
        for item in children:
            if item.get("type") == "url":
                url = item.get("url", "").lower()
                
                if "drug" in folder_name and _in_list(url, DRUG_INFO_DOMAINS):
                    correct_clinical += 1
                elif "shortage" in folder_name or "recall" in folder_name:
                    if _in_list(url, SHORTAGES_DOMAINS):
                        correct_clinical += 1
                elif "regulatory" in folder_name or "guideline" in folder_name:
                    if _in_list(url, REGULATORY_DOMAINS):
                        correct_clinical += 1

    # Sorting Score
    if correct_clinical >= total_clinical * 0.8:
        c2_score = 15
    elif correct_clinical >= total_clinical * 0.5:
        c2_score = 7
    score += c2_score
    feedback_parts.append(f"[2] Sorting Accuracy: {correct_clinical}/{total_clinical} clinical links sorted ({c2_score}/15 pts)")

    # Quarantine Score
    if loose_personal == 0 and expected_folders["unauthorized_personal"]:
        c3_score = 15
    elif loose_personal == 0:
        c3_score = 10
    score += c3_score
    feedback_parts.append(f"[3] Quarantine: {loose_personal} loose personal links found ({c3_score}/15 pts)")

    # ---------------------------------------------------------
    # 4. Custom Search Engines (15 pts)
    # ---------------------------------------------------------
    c4_score = 0
    found_ndc = False
    found_fda = False
    
    # Check Web Data SQLite if available
    if web_data_path:
        try:
            conn = sqlite3.connect(web_data_path)
            cursor = conn.cursor()
            cursor.execute("SELECT keyword, url FROM keywords")
            rows = cursor.fetchall()
            for kw, url in rows:
                if kw and url:
                    if kw.lower() == 'ndc' and 'dailymed' in url.lower():
                        found_ndc = True
                    if kw.lower() == 'fda' and ('fda.gov' in url.lower() or 'accessdata' in url.lower()):
                        found_fda = True
            conn.close()
        except Exception as e:
            logger.debug(f"SQLite search engine check failed: {e}")

    # Fallback: check preferences JSON for custom search providers
    # In some Chrome versions, they appear in default_search_provider_data or search_provider_overrides
    prefs_str = json.dumps(prefs).lower()
    if not found_ndc and 'ndc' in prefs_str and 'dailymed' in prefs_str:
        found_ndc = True
    if not found_fda and 'fda' in prefs_str and 'accessdata' in prefs_str:
        found_fda = True

    if found_ndc: c4_score += 7.5
    if found_fda: c4_score += 7.5
    score += int(c4_score)
    feedback_parts.append(f"[4] Custom Search Engines: ndc={found_ndc}, fda={found_fda} ({int(c4_score)}/15 pts)")

    # ---------------------------------------------------------
    # 5. Homepage Configuration (10 pts)
    # ---------------------------------------------------------
    c5_score = 0
    homepage = prefs.get('homepage', '').lower()
    session = prefs.get('session', {})
    startup_urls = session.get('startup_urls', [])
    
    is_home = 'dailymed.nlm.nih.gov' in homepage
    is_startup = any('dailymed.nlm.nih.gov' in u.lower() for u in startup_urls)
    
    if is_home or is_startup:
        c5_score = 10
    score += c5_score
    feedback_parts.append(f"[5] Homepage Set: {'Yes' if c5_score else 'No'} ({c5_score}/10 pts)")

    # ---------------------------------------------------------
    # 6. HIPAA Privacy Settings (15 pts)
    # ---------------------------------------------------------
    c6_score = 0
    prof = prefs.get('profile', {})
    autofill = prefs.get('autofill', {})
    
    pw_enabled = prof.get('password_manager_enabled', True)
    address_enabled = autofill.get('profile_enabled', True)
    payment_enabled = autofill.get('credit_card_enabled', True)
    
    # 3rd party cookies blocking (cookie_controls_mode: 1 = block 3rd party)
    cookie_mode = prof.get('cookie_controls_mode', 0)
    block_3p = prof.get('block_third_party_cookies', False)
    cookies_blocked = (cookie_mode == 1) or block_3p
    
    if not pw_enabled: c6_score += 5
    if not address_enabled and not payment_enabled: c6_score += 5
    if cookies_blocked: c6_score += 5
    score += c6_score
    feedback_parts.append(f"[6] HIPAA Privacy: PW={not pw_enabled}, Autofill={not address_enabled}, Cookies={cookies_blocked} ({c6_score}/15 pts)")

    # ---------------------------------------------------------
    # 7. Download Configuration (10 pts)
    # ---------------------------------------------------------
    c7_score = 0
    dl_prefs = prefs.get('download', {})
    dl_dir = dl_prefs.get('default_directory', '')
    dl_prompt = dl_prefs.get('prompt_for_download', False)
    
    if 'Rx_Transfers' in dl_dir:
        c7_score += 5
    if dl_prompt is True:
        c7_score += 5
    
    score += c7_score
    feedback_parts.append(f"[7] Downloads: Dir={c7_score >= 5}, Prompt={dl_prompt} ({c7_score}/10 pts)")

    # ---------------------------------------------------------
    # Cleanup & Final Evaluation
    # ---------------------------------------------------------
    for p in [bookmarks_path, prefs_path, web_data_path]:
        if p and os.path.exists(p):
            try: os.unlink(p)
            except: pass

    passed = score >= 70 and expected_folders["unauthorized_personal"] and c6_score == 15
    
    return {
        "passed": bool(passed),
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }