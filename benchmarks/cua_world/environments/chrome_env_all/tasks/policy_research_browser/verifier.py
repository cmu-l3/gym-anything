#!/usr/bin/env python3
"""
Verifier for policy_research_browser@1

Verification Strategy (100 Points):
1. Folders exist (15 pts) - Bookmarks JSON
2. Correct bookmark categorization (15 pts) - Bookmarks JSON
3. Multilingual Support (10 pts) - Preferences JSON
4. Chrome Experimental Flags (15 pts) - Local State JSON
5. Custom Search Engines (10 pts) - Web Data SQLite / Preferences
6. Homepage & Startup Pages (10 pts) - Preferences JSON
7. Privacy & Download Settings (10 pts) - Preferences JSON
8. VLM Trajectory Verification (15 pts) - Ensures workflow was executed, preventing static file drops.
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from typing import Dict, List, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected Categorizations
EXPECTED_CATEGORIES = {
    "international organizations": ["un.org", "worldbank.org", "oecd.org", "imf.org", "ilo.org"],
    "european union": ["europa.eu"],
    "latin america": ["cepal.org", "ibge.gov.br", "inegi.org.mx", "indec.gob.ar", "iadb.org"],
    "research databases": ["jstor.org", "scholar.google.com", "ssrn.com", "repec.org", "scopus.com", "webofscience.com", "pubmed.ncbi.nlm.nih.gov"],
    "data & visualization": ["ourworldindata.org", "tableau.com", "observablehq.com", "gapminder.org"]
}

VLM_PROMPT = """You are verifying a computer agent's trajectory.
The agent was asked to configure Chrome Settings, Chrome Flags (chrome://flags), Bookmark Manager, and Languages.
Look at these sampled frames from the agent's workflow (which may include the final state).

Did the agent actually navigate through Chrome's internal configuration pages (e.g., Settings menus, Flags page, or Bookmark Manager) during the task? 
Look for evidence of the Chrome settings UI, the flags interface with search bars/dropdowns, or the bookmark editing interfaces.

Respond in JSON format exactly like this:
{
    "interacted_with_settings_or_flags": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of the screens observed"
}
"""

def _copy_file(copy_from_env, container_paths: List[str], suffix: str = '') -> Optional[str]:
    """Tries multiple candidate paths to copy a file from the container."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp_path = tmp.name
    tmp.close()
    
    for cpath in container_paths:
        try:
            copy_from_env(cpath, tmp_path)
            if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 0:
                return tmp_path
        except Exception:
            continue
            
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    return None

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Fetch Data Files
    # ---------------------------------------------------------
    bookmarks_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Bookmarks",
        "/home/ga/.config/google-chrome-cdp/Default/Bookmarks"
    ], '.json')
    
    prefs_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Preferences",
        "/home/ga/.config/google-chrome-cdp/Default/Preferences"
    ], '.json')
    
    local_state_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Local State",
        "/home/ga/.config/google-chrome-cdp/Local State"
    ], '.json')
    
    web_data_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Web Data",
        "/home/ga/.config/google-chrome-cdp/Default/Web Data"
    ], '.sqlite')
    
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

    # ---------------------------------------------------------
    # 2. Verify Folders & Categorization (30 pts)
    # ---------------------------------------------------------
    found_folders = {}
    bookmark_bar = bookmarks.get("roots", {}).get("bookmark_bar", {}).get("children", [])
    
    for child in bookmark_bar:
        if child.get("type") == "folder":
            name = child.get("name", "").lower().strip()
            found_folders[name] = child.get("children", [])
            
    # Sub-criterion: Folders Exist (15 pts)
    folder_pts = 0
    for expected in EXPECTED_CATEGORIES.keys():
        if expected in found_folders:
            folder_pts += 3
    score += folder_pts
    feedback_parts.append(f"Bookmark Folders: {folder_pts}/15 pts")

    # Anti-gaming: Ensure no mass deletion
    total_bookmarks = 0
    for f_nodes in found_folders.values():
        total_bookmarks += len([n for n in f_nodes if n.get("type") == "url"])
    loose_bookmarks = len([n for n in bookmark_bar if n.get("type") == "url"])
    total_bookmarks += loose_bookmarks
    
    # Sub-criterion: Categorization (15 pts)
    cat_pts = 0
    if total_bookmarks >= 25:
        for folder_name, expected_domains in EXPECTED_CATEGORIES.items():
            if folder_name in found_folders:
                urls = [n.get("url", "").lower() for n in found_folders[folder_name]]
                matched = sum(1 for d in expected_domains if any(d in u for u in urls))
                if matched >= len(expected_domains) * 0.5: # 50% threshold per folder
                    cat_pts += 3
        score += cat_pts
        feedback_parts.append(f"Bookmark Categorization: {cat_pts}/15 pts")
    else:
        feedback_parts.append("Bookmark Categorization: 0/15 pts (Mass deletion detected)")

    # ---------------------------------------------------------
    # 3. Verify Multilingual Support (10 pts)
    # ---------------------------------------------------------
    lang_pts = 0
    accept_langs = prefs.get("intl", {}).get("accept_languages", "")
    spell_dicts = prefs.get("spellcheck", {}).get("dictionaries", [])
    
    if "es" in accept_langs and "fr" in accept_langs and ("pt-BR" in accept_langs or "pt" in accept_langs):
        lang_pts += 5
    if "es" in spell_dicts and "fr" in spell_dicts and ("pt-BR" in spell_dicts or "pt" in spell_dicts):
        lang_pts += 5
    score += lang_pts
    feedback_parts.append(f"Languages & Spellcheck: {lang_pts}/10 pts")

    # ---------------------------------------------------------
    # 4. Verify Chrome Experimental Flags (15 pts)
    # ---------------------------------------------------------
    flag_pts = 0
    experiments = local_state.get("browser", {}).get("enabled_labs_experiments", [])
    exp_str = " ".join(experiments)
    
    if "smooth-scrolling" in exp_str: flag_pts += 5
    if "enable-parallel-downloading" in exp_str: flag_pts += 5
    if "tab-scrolling" in exp_str: flag_pts += 5
    score += flag_pts
    feedback_parts.append(f"Chrome Flags: {flag_pts}/15 pts")

    # ---------------------------------------------------------
    # 5. Verify Custom Search Engines (10 pts)
    # ---------------------------------------------------------
    se_pts = 0
    found_keywords = []
    
    # Check Web Data SQLite if available
    if web_data_path:
        try:
            conn = sqlite3.connect(web_data_path)
            cursor = conn.cursor()
            cursor.execute("SELECT keyword FROM keywords")
            found_keywords = [row[0] for row in cursor.fetchall()]
            conn.close()
        except Exception as e:
            logger.warning(f"Failed reading Web Data: {e}")
            
    # Fallback to Preferences text mapping
    prefs_str = json.dumps(prefs)
    for kw in ["oecd", "scholar", "wb"]:
        if kw in found_keywords or f'"{kw}"' in prefs_str:
            se_pts += 3.33
            
    se_pts = min(10, int(round(se_pts)))
    score += se_pts
    feedback_parts.append(f"Custom Search Engines: {se_pts}/10 pts")

    # ---------------------------------------------------------
    # 6. Verify Homepage & Startup (10 pts)
    # ---------------------------------------------------------
    hp_pts = 0
    if "data.un.org" in prefs.get("homepage", ""):
        hp_pts += 4
        
    startup_urls = prefs.get("session", {}).get("startup_urls", [])
    startup_str = " ".join(startup_urls)
    matches = sum(1 for d in ["data.un.org", "stats.oecd.org", "scholar.google.com"] if d in startup_str)
    if matches >= 2: hp_pts += 6
    
    score += hp_pts
    feedback_parts.append(f"Homepage/Startup: {hp_pts}/10 pts")

    # ---------------------------------------------------------
    # 7. Verify Privacy & Downloads (10 pts)
    # ---------------------------------------------------------
    priv_pts = 0
    # Third party cookies
    if prefs.get("profile", {}).get("cookie_controls_mode", 0) == 1 or prefs.get("profile", {}).get("block_third_party_cookies", False):
        priv_pts += 3
    # Do not track
    if prefs.get("enable_do_not_track", False):
        priv_pts += 2
    # Downloads
    if "Research_Data" in prefs.get("download", {}).get("default_directory", ""):
        priv_pts += 3
    # Passwords
    if not prefs.get("profile", {}).get("password_manager_enabled", True) or not prefs.get("credentials_enable_service", True):
        priv_pts += 2
        
    score += priv_pts
    feedback_parts.append(f"Privacy/Downloads/Passwords: {priv_pts}/10 pts")

    # ---------------------------------------------------------
    # 8. VLM Trajectory Verification (15 pts)
    # ---------------------------------------------------------
    vlm_pts = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final: frames.append(final)
            
            if frames:
                vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
                parsed = vlm_result.get("parsed", {})
                if parsed.get("interacted_with_settings_or_flags", False):
                    confidence = parsed.get("confidence", "low").lower()
                    if confidence == "high":
                        vlm_pts = 15
                    elif confidence == "medium":
                        vlm_pts = 10
                    else:
                        vlm_pts = 5
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            
    score += vlm_pts
    feedback_parts.append(f"VLM Trajectory Auth: {vlm_pts}/15 pts")

    # Cleanup temp files
    for p in [bookmarks_path, prefs_path, local_state_path, web_data_path]:
        if p and os.path.exists(p):
            os.unlink(p)

    passed = score >= 70
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }