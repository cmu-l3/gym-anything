#!/usr/bin/env python3
"""
Verifier for Multilingual Counter Setup (multilingual_counter_setup@1)

Verifies 7 criteria for a total of 100 points:
1. Preferred languages configured (20 pts)
2. Spell-check dictionaries enabled (15 pts)
3. Translation settings correct (15 pts)
4. Bookmark folders created and populated (15 pts)
5. Custom search engine shortcuts (15 pts)
6. Homepage and startup settings (10 pts)
7. Privacy and credential settings (10 pts)

Anti-gaming: Requires actual modification of the Preferences file.
"""

import os
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any, List

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_file_from_env(copy_from_env, container_path: str, suffix: str = ".json") -> str:
    """Helper to copy a file and return local path."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    try:
        copy_from_env(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
    except Exception as e:
        logger.error(f"Failed to copy {container_path}: {e}")
    
    if os.path.exists(tmp.name):
        os.unlink(tmp.name)
    return None


def verify_task(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    score = 0
    feedback_parts = []
    
    # Check anti-gaming (file modified)
    initial_prefs = get_file_from_env(copy_from_env, "/tmp/initial_prefs.json")
    final_prefs = get_file_from_env(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences")
    
    if not final_prefs:
        return {"passed": False, "score": 0, "feedback": "Could not extract Chrome Preferences. Did Chrome crash?"}

    with open(final_prefs, "r") as f:
        prefs_data = json.load(f)
        
    initial_prefs_data = {}
    if initial_prefs:
        try:
            with open(initial_prefs, "r") as f:
                initial_prefs_data = json.load(f)
        except:
            pass
            
    if prefs_data == initial_prefs_data:
        return {"passed": False, "score": 0, "feedback": "Preferences file was completely unmodified. Task not attempted."}

    bookmarks_path = get_file_from_env(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks")
    web_data_path = get_file_from_env(copy_from_env, "/tmp/Web_Data_Export", suffix=".sqlite")

    # =========================================================================
    # 1. Preferred Languages (20 pts)
    # =========================================================================
    accept_languages = prefs_data.get("intl", {}).get("accept_languages", "")
    has_en = "en" in accept_languages.split(",") or "en-US" in accept_languages.split(",")
    has_es = any(lang.startswith("es") for lang in accept_languages.split(","))
    
    c1_score = 0
    if has_en: c1_score += 10
    if has_es: c1_score += 10
    score += c1_score
    feedback_parts.append(f"Languages (EN/ES): {c1_score}/20 pts")

    # =========================================================================
    # 2. Spell-check Dictionaries (15 pts)
    # =========================================================================
    spellcheck_dicts = prefs_data.get("spellcheck", {}).get("dictionaries", [])
    sc_en = any(d.startswith("en") for d in spellcheck_dicts)
    sc_es = any(d.startswith("es") for d in spellcheck_dicts)
    
    c2_score = 0
    if sc_en: c2_score += 7
    if sc_es: c2_score += 8
    score += c2_score
    feedback_parts.append(f"Spellcheck (EN/ES): {c2_score}/15 pts")

    # =========================================================================
    # 3. Translation Settings (15 pts)
    # =========================================================================
    translate_enabled = prefs_data.get("translate", {}).get("enabled", True)
    blocked_langs = prefs_data.get("translate_blocked_languages", [])
    
    c3_score = 0
    if translate_enabled: c3_score += 5
    if "en" in blocked_langs: c3_score += 5
    if not any(l.startswith("es") for l in blocked_langs): c3_score += 5
    score += c3_score
    feedback_parts.append(f"Translation Config: {c3_score}/15 pts")

    # =========================================================================
    # 4. Bookmarks (15 pts)
    # =========================================================================
    c4_score = 0
    if bookmarks_path:
        with open(bookmarks_path, "r") as f:
            bookmarks = json.load(f)
            
        bookmark_bar = bookmarks.get("roots", {}).get("bookmark_bar", {}).get("children", [])
        
        folders_found = []
        for child in bookmark_bar:
            if child.get("type") == "folder":
                name = child.get("name", "").lower()
                urls = [c.get("url", "") for c in child.get("children", []) if c.get("type") == "url"]
                
                if "fleet" in name:
                    folders_found.append("fleet")
                    if sum(1 for u in urls if any(d in u for d in ["enterprise", "hertz", "avis", "sixt", "turo"])) >= 3:
                        c4_score += 3
                elif "insurance" in name or "compliance" in name:
                    folders_found.append("insurance")
                    if sum(1 for u in urls if any(d in u for d in ["geico", "progressive", "nhtsa", "flhsmv"])) >= 2:
                        c4_score += 3
                elif "tourism" in name:
                    folders_found.append("tourism")
                elif "personal" in name:
                    folders_found.append("personal")
                    
        # 3 pts for having at least 3 of the 4 required folders
        if len(set(folders_found).intersection({"fleet", "insurance", "tourism", "personal"})) >= 3:
            c4_score += 9
            
    score += c4_score
    feedback_parts.append(f"Bookmarks Organization: {c4_score}/15 pts")

    # =========================================================================
    # 5. Search Engines (15 pts)
    # =========================================================================
    c5_score = 0
    found_vin, found_res, found_plate = False, False, False
    
    if web_data_path:
        try:
            conn = sqlite3.connect(web_data_path)
            c = conn.cursor()
            c.execute("SELECT keyword, url FROM keywords")
            rows = c.fetchall()
            for kw, url in rows:
                if not kw or not url: continue
                kw = kw.lower()
                if "vin" in kw and "nhtsa" in url.lower(): found_vin = True
                if "res" in kw and "enterprise" in url.lower(): found_res = True
                if "plate" in kw and "flhsmv" in url.lower(): found_plate = True
            conn.close()
        except Exception as e:
            logger.warning(f"Failed to read Web Data SQLite: {e}")
            
    if found_vin: c5_score += 5
    if found_res: c5_score += 5
    if found_plate: c5_score += 5
    score += c5_score
    feedback_parts.append(f"Search Engines: {c5_score}/15 pts")

    # =========================================================================
    # 6. Homepage & Startup (10 pts)
    # =========================================================================
    c6_score = 0
    homepage = prefs_data.get("homepage", "")
    if "enterprise.com" in homepage: c6_score += 4
    
    session_restore = prefs_data.get("session", {}).get("restore_on_startup", 0)
    if session_restore == 1: c6_score += 3
    
    download_dir = prefs_data.get("download", {}).get("default_directory", "")
    if "Rental_Agreements" in download_dir: c6_score += 3
    
    score += c6_score
    feedback_parts.append(f"Homepage/Startup/Downloads: {c6_score}/10 pts")

    # =========================================================================
    # 7. Privacy & Credentials (10 pts)
    # =========================================================================
    c7_score = 0
    # Third party cookies blocked (cookie_controls_mode == 1, or block_third_party_cookies == True)
    cookie_controls = prefs_data.get("profile", {}).get("cookie_controls_mode", 0)
    block_3rd = prefs_data.get("profile", {}).get("block_third_party_cookies", False)
    if cookie_controls == 1 or block_3rd:
        c7_score += 4
        
    pw_enabled = prefs_data.get("profile", {}).get("password_manager_enabled", True)
    credentials_enabled = prefs_data.get("credentials_enable_service", True)
    if not pw_enabled or not credentials_enabled:
        c7_score += 3
        
    autofill_profile = prefs_data.get("autofill", {}).get("profile_enabled", True)
    if not autofill_profile:
        c7_score += 3
        
    score += c7_score
    feedback_parts.append(f"Privacy/Credentials: {c7_score}/10 pts")

    # Cleanup temp files
    for p in [initial_prefs, final_prefs, bookmarks_path, web_data_path]:
        if p and os.path.exists(p):
            try: os.unlink(p)
            except: pass

    # Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }