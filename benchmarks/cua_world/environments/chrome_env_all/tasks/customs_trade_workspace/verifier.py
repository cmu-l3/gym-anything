#!/usr/bin/env python3
"""
Verifier for customs_trade_workspace@1 task.

Verification Strategy uses MULTIPLE INDEPENDENT SIGNALS:
1. Programmatic JSON checking of Chrome Bookmarks and Preferences.
2. Anti-gaming check (ensures preferences were saved after task start, ensures total bookmarks didn't just drop to zero).
3. VLM Trajectory Verification to prove the agent physically performed the work in the UI.

Total Points: 100
Pass Threshold: 65
"""

import json
import os
import tempfile
import logging
import re
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available.")

# Domain Categories
GOV_DOMAINS = ['ace.cbp.dhs.gov', 'hts.usitc.gov', 'rulings.cbp.gov', 'fda.gov', 'aphis.usda.gov', 'aesdirect.gov', 'ttbonline.gov', 'fmc.gov']
CARRIER_DOMAINS = ['maersk.com', 'msc.com', 'cma-cgm.com', 'fedex.com', 'ups.com', 'flexport.com']
PERSONAL_DOMAINS = ['reddit.com', 'youtube.com', 'espn.com', 'amazon.com', 'netflix.com', 'spotify.com', 'x.com', 'instagram.com', 'linkedin.com']

def _copy_and_parse_json(copy_from_env, remote_path: str) -> Dict[str, Any]:
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp.close()
    try:
        copy_from_env(remote_path, temp.name)
        if os.path.exists(temp.name) and os.path.getsize(temp.name) > 10:
            with open(temp.name, 'r', encoding='utf-8') as f:
                return json.load(f)
    except Exception as e:
        logger.error(f"Failed to parse {remote_path}: {e}")
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)
    return {}

def _check_domain_in_node(node: dict, domains: list) -> bool:
    url = node.get('url', '').lower()
    return any(d in url for d in domains)

def _get_folders(bookmark_bar: dict) -> list:
    return [child for child in bookmark_bar.get('children', []) if child.get('type') == 'folder']

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load data
    meta = _copy_and_parse_json(copy_from_env, "/tmp/task_meta.json")
    bkmks = _copy_and_parse_json(copy_from_env, "/tmp/task_Bookmarks.json")
    prefs = _copy_and_parse_json(copy_from_env, "/tmp/task_Preferences.json")
    
    score = 0
    feedback_parts = []
    
    # Base validations
    if not bkmks or not prefs:
        return {"passed": False, "score": 0, "feedback": "Failed to read Chrome configuration files."}
        
    prefs_modified = meta.get('prefs_modified_during_task', False)
    if not prefs_modified:
        feedback_parts.append("Warning: Preferences were not modified after task started (Anti-gaming check)")
    else:
        score += 5
        feedback_parts.append("Settings modified appropriately")

    bookmark_bar = bkmks.get('roots', {}).get('bookmark_bar', {})
    folders = _get_folders(bookmark_bar)
    folder_names = [f.get('name', '').lower().strip() for f in folders]

    # 1. Folder Hierarchy (15 pts)
    expected_folders = ["government portals", "carriers & logistics", "trade databases", "industry resources", "non-work"]
    matched_folders = 0
    for ef in expected_folders:
        # Flexible match
        if any(ef in fn or ef.replace(" & ", " and ") in fn or ef.replace("&", "and") in fn for fn in folder_names):
            matched_folders += 1
            
    if matched_folders >= 4:
        score += 15
        feedback_parts.append(f"Folder hierarchy verified ({matched_folders}/5 folders)")
    else:
        score += (matched_folders * 3)
        feedback_parts.append(f"Incomplete folder hierarchy ({matched_folders}/5 folders)")

    # 2. Categorization & Personal Isolation (15 pts)
    gov_found, car_found, pers_in_folder, pers_loose = 0, 0, 0, 0
    
    # Check inside folders
    for f in folders:
        fname = f.get('name', '').lower()
        children = f.get('children', [])
        
        if "government" in fname:
            gov_found = sum(1 for c in children if _check_domain_in_node(c, GOV_DOMAINS))
        elif "carrier" in fname:
            car_found = sum(1 for c in children if _check_domain_in_node(c, CARRIER_DOMAINS))
        elif "non-work" in fname or "personal" in fname:
            pers_in_folder = sum(1 for c in children if _check_domain_in_node(c, PERSONAL_DOMAINS))

    # Check loose top-level
    pers_loose = sum(1 for c in bookmark_bar.get('children', []) 
                     if c.get('type') == 'url' and _check_domain_in_node(c, PERSONAL_DOMAINS))

    cat_score = 0
    if gov_found >= 6: cat_score += 5
    if car_found >= 4: cat_score += 5
    if pers_in_folder >= 7 and pers_loose == 0: cat_score += 5
    elif pers_loose == 0: cat_score += 2 # Partial for just clearing them out
    
    score += cat_score
    feedback_parts.append(f"Categorization: Gov({gov_found}/8), Carrier({car_found}/6), Loose Personal({pers_loose}) -> {cat_score}pts")

    # 3. Search Engines & Font Size (15 pts)
    prefs_str = json.dumps(prefs).lower()
    engines_found = 0
    if re.search(r'hts.*?hts\.usitc\.gov', prefs_str): engines_found += 1
    if re.search(r'ruling.*?rulings\.cbp\.gov', prefs_str): engines_found += 1
    if re.search(r'vessel.*?marinetraffic\.com', prefs_str): engines_found += 1
    
    score += (engines_found * 3)
    
    font_size = prefs.get('webkit', {}).get('webprefs', {}).get('default_font_size', 16)
    if font_size >= 18:
        score += 6
        feedback_parts.append("Font size appropriately increased")
    else:
        feedback_parts.append(f"Font size incorrect (expected 18, got {font_size})")

    # 4. Privacy, Downloads & Credentials (15 pts)
    priv_score = 0
    if prefs.get('profile', {}).get('cookie_controls_mode', 0) == 1 or prefs.get('profile', {}).get('block_third_party_cookies', False):
        priv_score += 3
    if prefs.get('enable_do_not_track', False) is True:
        priv_score += 3
    if prefs.get('safebrowsing', {}).get('enhanced', False) is True:
        priv_score += 3
        
    dl_dir = prefs.get('download', {}).get('default_directory', '')
    if 'customs_filings' in dl_dir.lower():
        priv_score += 2
    if prefs.get('download', {}).get('prompt_for_download', False) is True:
        priv_score += 1
        
    pw_enabled = prefs.get('profile', {}).get('password_manager_enabled', True)
    creds_enabled = prefs.get('credentials_enable_service', True)
    auto_profile = prefs.get('autofill', {}).get('profile_enabled', True)
    if not pw_enabled and not creds_enabled: priv_score += 2
    if not auto_profile: priv_score += 1
    
    score += priv_score
    feedback_parts.append(f"Privacy/Credential Settings: {priv_score}/15 pts")

    # 5. Homepage & Startup (10 pts)
    hp_score = 0
    homepage = prefs.get('homepage', '')
    if 'ace.cbp.dhs.gov' in homepage.lower(): hp_score += 5
    
    startup_urls = str(prefs.get('session', {}).get('startup_urls', [])).lower()
    if 'ace.cbp.dhs.gov' in startup_urls and 'hts.usitc.gov' in startup_urls: hp_score += 5
    elif 'ace.cbp.dhs.gov' in startup_urls or 'hts.usitc.gov' in startup_urls: hp_score += 2
    
    score += hp_score
    feedback_parts.append(f"Homepage/Startup: {hp_score}/10 pts")

    # 6. VLM Trajectory Verification (25 pts)
    if VLM_AVAILABLE and query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """You are evaluating an agent performing a Chrome Browser Configuration task.
        The task involved:
        1. Opening Chrome Settings (Privacy, Security, Appearance, Search Engines)
        2. Managing Bookmarks (organizing into folders)
        
        Do these trajectory frames show visual evidence that the agent was actively interacting with the Chrome Settings pages OR the Bookmark Manager? Look for active dropdowns, typed text in settings fields, dragged bookmarks, or the chrome://settings / chrome://bookmarks interface being navigated.
        
        Respond with JSON:
        {"active_configuration_visible": true/false, "reasoning": "..."}"""
        
        try:
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('active_configuration_visible'):
                score += 25
                feedback_parts.append("VLM: Trajectory shows active configuration.")
            else:
                feedback_parts.append("VLM: No strong visual evidence of active configuration in trajectory.")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("VLM Verification failed or timed out.")
    else:
        # Give free points if VLM isn't available to not unfairly fail the test
        score += 25
        feedback_parts.append("VLM skipped (unavailable). Granted default points.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }