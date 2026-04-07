#!/usr/bin/env python3
"""
Verifier for tax_season_workspace@1

Verification Criteria (100 points total):
1. Entertainment bookmarks removed (15 pts)
2. Bookmark folders created (15 pts)
3. Bookmarks correctly categorized (15 pts)
4. Search engine shortcuts configured (15 pts)
5. Homepage and startup pages (10 pts)
6. History & cookie sanitization (15 pts)
7. Security & download settings (15 pts)

Includes VLM trajectory verification as a baseline check.
"""

import os
import sys
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
ENTERTAINMENT_DOMAINS = [
    "youtube.com", "reddit.com", "spotify.com", "netflix.com",
    "tiktok.com", "instagram.com", "x.com", "discord.com",
    "twitch.tv", "pinterest.com", "amazon.com", "ebay.com",
    "steampowered.com", "espn.com", "weather.com"
]

TAX_DOMAINS = {
    "IRS Resources": ["irs.gov"],
    "State Tax Authorities": ["ftb.ca.gov", "tax.ny.gov", "comptroller.texas.gov", "floridarevenue.com"],
    "Professional & Standards": ["aicpa-cima.com", "taxfoundation.org", "natptax.com"],
    "Tax Software & Tools": ["drakesoftware.com", "taxact.com", "ssa.gov", "fincen.gov", "sec.gov"]
}


def _copy_file(copy_from_env, path: str, suffix: str) -> Optional[str]:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    try:
        copy_from_env(path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
    except Exception as e:
        logger.error(f"Failed to copy {path}: {e}")
    
    if os.path.exists(tmp.name):
        os.unlink(tmp.name)
    return None


def _get_all_urls(bookmark_node: dict, urls: List[str] = None) -> List[str]:
    if urls is None:
        urls = []
    if bookmark_node.get('type') == 'url':
        urls.append(bookmark_node.get('url', ''))
    for child in bookmark_node.get('children', []):
        _get_all_urls(child, urls)
    return urls


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    feedback = []
    score = 0
    
    # Check if agent did ANY visual work using VLM (Anti-gaming check)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                vlm_res = query_vlm(
                    prompt="Does this trajectory show someone interacting with Chrome's Settings, History, or Bookmark Manager? Respond with a JSON object containing a single boolean field 'interacted'.",
                    images=frames
                )
                if not vlm_res.get('parsed', {}).get('interacted', False):
                    feedback.append("VLM Verification Warning: Trajectory does not clearly show interaction with Chrome internals.")
        except Exception as e:
            logger.warning(f"VLM trajectory check skipped: {e}")

    # 1. Fetch Files
    bm_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks", ".json")
    prefs_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences", ".json")
    hist_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/History", ".sqlite")
    cookie_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Cookies", ".sqlite")

    try:
        # --- Bookmark Verification ---
        bms = {}
        if bm_path:
            with open(bm_path, 'r') as f:
                bms = json.load(f)
        
        all_urls = _get_all_urls(bms.get('roots', {}).get('bookmark_bar', {}))
        total_bms = len(all_urls)
        
        # Anti-gaming: mass deletion check
        if total_bms < 5:
            feedback.append("❌ Mass deletion detected. Tax bookmarks missing.")
        else:
            # Criterion 1: Entertainment domains removed (15 pts)
            ent_count = sum(1 for url in all_urls if any(d in url for d in ENTERTAINMENT_DOMAINS))
            if ent_count == 0:
                score += 15
                feedback.append("✅ Entertainment bookmarks removed.")
            elif ent_count <= 3:
                score += 8
                feedback.append(f"⚠️ Most entertainment bookmarks removed ({ent_count} left).")
            else:
                feedback.append(f"❌ Entertainment bookmarks not fully removed ({ent_count} left).")
            
            # Criterion 2: Folders created (15 pts)
            children = bms.get('roots', {}).get('bookmark_bar', {}).get('children', [])
            folders_found = [c.get('name') for c in children if c.get('type') == 'folder']
            expected_folders = task_info.get('metadata', {}).get('expected_folders', [])
            matched_folders = [f for f in expected_folders if any(f.lower() in fn.lower() for fn in folders_found)]
            
            folder_score = min(15, len(matched_folders) * 4)
            score += folder_score
            if folder_score == 15:
                feedback.append("✅ Bookmark folders correctly created.")
            else:
                feedback.append(f"⚠️ Bookmark folders partially created ({len(matched_folders)}/4).")

            # Criterion 3: Categorization (15 pts)
            cat_score = 0
            for child in children:
                if child.get('type') == 'folder':
                    fname = child.get('name', '')
                    f_urls = _get_all_urls(child)
                    
                    if "IRS" in fname:
                        if sum(1 for u in f_urls if "irs.gov" in u) >= 6: cat_score += 5
                    elif "State" in fname:
                        if sum(1 for u in f_urls if any(d in u for d in TAX_DOMAINS["State Tax Authorities"])) >= 3: cat_score += 5
                    elif "Software" in fname or "Tools" in fname:
                        if sum(1 for u in f_urls if any(d in u for d in TAX_DOMAINS["Tax Software & Tools"])) >= 3: cat_score += 5
            score += cat_score
            if cat_score == 15:
                feedback.append("✅ Bookmarks correctly categorized.")
            else:
                feedback.append(f"⚠️ Bookmarks partially categorized ({cat_score}/15).")

        # --- Preferences Verification ---
        prefs = {}
        if prefs_path:
            with open(prefs_path, 'r') as f:
                prefs = json.load(f)
        
        # Criterion 4: Search Shortcuts (15 pts)
        kw_found = 0
        search_engines = prefs.get('default_search_provider_data', {}).get('template_url_data', {})
        overrides = prefs.get('search_provider_overrides', [])
        all_kws = str(search_engines) + str(overrides) + str(prefs.get('profile', {}).get('custom_search_providers', []))
        for kw in ["irs", "pub", "ssa"]:
            if f"\"{kw}\"" in all_kws or f"'{kw}'" in all_kws:
                kw_found += 1
        score += (kw_found * 5)
        if kw_found == 3:
            feedback.append("✅ Search engine shortcuts configured.")
        else:
            feedback.append(f"⚠️ Search engine shortcuts partially configured ({kw_found}/3).")

        # Criterion 5: Homepage & Startup (10 pts)
        hp_score = 0
        homepage = prefs.get('homepage', '')
        if 'irs.gov' in homepage:
            hp_score += 4
        
        startup_urls = prefs.get('session', {}).get('startup_urls', [])
        if any('irs.gov' in u for u in startup_urls): hp_score += 3
        if any('drakesoftware.com' in u for u in startup_urls): hp_score += 3
        
        score += hp_score
        if hp_score == 10:
            feedback.append("✅ Homepage and startup URLs correctly set.")
        else:
            feedback.append(f"⚠️ Homepage/startup URLs partially set ({hp_score}/10).")

        # Criterion 7: Security & Downloads (15 pts)
        sec_score = 0
        if not prefs.get('profile', {}).get('password_manager_enabled', True): sec_score += 3
        if not prefs.get('autofill', {}).get('profile_enabled', True): sec_score += 3
        if not prefs.get('autofill', {}).get('credit_card_enabled', True): sec_score += 2
        
        cookie_controls = prefs.get('profile', {}).get('cookie_controls_mode', 0)
        if cookie_controls == 1 or prefs.get('profile', {}).get('default_content_setting_values', {}).get('cookies') == 2:
            sec_score += 2
            
        if prefs.get('safebrowsing', {}).get('enhanced', False): sec_score += 2
        
        dl_dir = prefs.get('download', {}).get('default_directory', '')
        if 'Client_Tax_Files' in dl_dir: sec_score += 2
        if prefs.get('download', {}).get('prompt_for_download', False): sec_score += 1
        
        score += sec_score
        if sec_score >= 12:
            feedback.append("✅ Privacy, security, and download settings properly hardened.")
        else:
            feedback.append(f"⚠️ Security settings partially configured ({sec_score}/15).")

        # --- DB Verification ---
        # Criterion 6: History and Cookies (15 pts)
        db_score = 0
        if hist_path:
            try:
                conn = sqlite3.connect(hist_path)
                c = conn.cursor()
                
                # Check entertainment removed
                ent_hist = 0
                for d in ENTERTAINMENT_DOMAINS:
                    c.execute("SELECT COUNT(*) FROM urls WHERE url LIKE ?", (f"%{d}%",))
                    ent_hist += c.fetchone()[0]
                
                # Check tax preserved
                tax_hist = 0
                for d in TAX_DOMAINS["State Tax Authorities"] + TAX_DOMAINS["Tax Software & Tools"]:
                    c.execute("SELECT COUNT(*) FROM urls WHERE url LIKE ?", (f"%{d}%",))
                    tax_hist += c.fetchone()[0]
                    
                if ent_hist <= 5: db_score += 5
                if tax_hist >= 5: db_score += 5  # Allow for some natural deletion but ensure preserve
                
                conn.close()
            except Exception as e:
                logger.error(f"History DB Error: {e}")

        if cookie_path:
            try:
                conn = sqlite3.connect(cookie_path)
                c = conn.cursor()
                
                ent_cookies = 0
                for d in ENTERTAINMENT_DOMAINS:
                    c.execute("SELECT COUNT(*) FROM cookies WHERE host_key LIKE ?", (f"%{d}%",))
                    ent_cookies += c.fetchone()[0]
                    
                if ent_cookies <= 2: db_score += 5
                
                conn.close()
            except Exception as e:
                logger.error(f"Cookie DB Error: {e}")
                
        score += db_score
        if db_score == 15:
            feedback.append("✅ History and Cookies successfully sanitized.")
        else:
            feedback.append(f"⚠️ History/Cookies partially sanitized ({db_score}/15).")

    finally:
        # Cleanup
        for p in [bm_path, prefs_path, hist_path, cookie_path]:
            if p and os.path.exists(p):
                os.unlink(p)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }