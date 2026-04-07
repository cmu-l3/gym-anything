#!/usr/bin/env python3
"""
Verifier for kitchen_prep_station_setup@1

Verification Strategy:
1. Bookmarks: Parsed to ensure correct folders (Recipes, Safety, Suppliers, Office_Archive) and valid sorting.
2. Preferences (Font Size): Parsed to ensure default_font_size == 24.
3. Preferences (Downloads): Parsed for default_directory and prompt_for_download.
4. Preferences (Startup): Parsed for restore_on_startup and startup_urls.
5. Web Data (SQLite): Queried to verify custom search engines 'usda' and 'recipe'.
6. VLM Trajectory Check: Verifies that the agent actually interacted with Chrome Settings UI (anti-scripting/anti-gaming check).
"""

import json
import tempfile
import os
import sqlite3
import logging
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Domain mapping for verification
EXPECTED_DOMAINS = {
    "recipes": ["seriouseats.com", "chefsteps.com", "epicurious.com", "bonappetit.com", "foodnetwork.com", "americastestkitchen.com", "splendidtable.org", "saveur.com", "tastingtable.com", "thespruceeats.com"],
    "safety": ["fda.gov", "fsis.usda.gov", "servsafe.com", "foodsafety.gov", "cdc.gov", "ecfr.gov"],
    "suppliers": ["sysco.com", "usfoods.com", "gfs.com", "baldorfood.com", "restaurantequipment.com"],
    "office": ["quickbooks.intuit.com", "adp.com", "chase.com", "netflix.com", "facebook.com", "espn.com", "zillow.com", "amazon.com", "target.com"]
}

# VLM Prompt
VLM_PROMPT = """You are verifying an agent configuring Google Chrome. Look at these frames from the agent's screen during the task.
Did the agent open the Chrome Settings menu (chrome://settings) OR the Bookmark Manager (chrome://bookmarks)?
You should look for UI elements indicating they are configuring things like font size, search engines, download locations, or startup pages.
Respond in JSON format:
{
    "interacted_with_settings_or_bookmarks_ui": true/false,
    "reasoning": "Brief explanation of what is visible in the frames."
}"""


def _copy_file(copy_fn, src: str, dest_suffix: str = ".json") -> str:
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=dest_suffix)
    temp_file.close()
    try:
        copy_fn(src, temp_file.name)
        if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
            return temp_file.name
    except Exception as e:
        logger.error(f"Failed copying {src}: {e}")
    os.unlink(temp_file.name)
    return None


def verify_bookmarks(bookmarks_data: Dict) -> Tuple[int, str]:
    score = 0
    feedback = []
    
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    folders = {child.get('name', '').lower(): child.get('children', []) for child in bookmark_bar if child.get('type') == 'folder'}
    
    # Check Active Folders (15 pts)
    active_found = 0
    for target_name, domain_key in [("recipes & techniques", "recipes"), ("food safety & haccp", "safety"), ("suppliers & orders", "suppliers")]:
        matching_keys = [k for k in folders.keys() if k == target_name]
        if matching_keys:
            folder_urls = [bm.get('url', '').lower() for bm in folders[matching_keys[0]] if bm.get('type') == 'url']
            matched_domains = sum(1 for url in folder_urls if any(d in url for d in EXPECTED_DOMAINS[domain_key]))
            if matched_domains >= len(EXPECTED_DOMAINS[domain_key]) * 0.8:  # 80% tolerance
                active_found += 1
                feedback.append(f"Folder '{target_name}' correctly structured.")
            else:
                feedback.append(f"Folder '{target_name}' exists but missing expected domains.")
        else:
            feedback.append(f"Folder '{target_name}' not found.")
            
    score += (active_found * 5)
    
    # Check Office Archive (10 pts)
    archive_keys = [k for k in folders.keys() if "office" in k and "archive" in k]
    if archive_keys:
        folder_urls = [bm.get('url', '').lower() for bm in folders[archive_keys[0]] if bm.get('type') == 'url']
        matched_office = sum(1 for url in folder_urls if any(d in url for d in EXPECTED_DOMAINS["office"]))
        if matched_office >= 7:
            score += 10
            feedback.append("Office_Archive correctly configured.")
        else:
            score += 5
            feedback.append("Office_Archive found but missing expected office bookmarks.")
    else:
        feedback.append("Office_Archive folder not found.")
        
    return score, " | ".join(feedback)


def verify_preferences(prefs_data: Dict) -> Tuple[int, str]:
    score = 0
    feedback = []
    
    # Font Size (15 pts)
    font_size = prefs_data.get('webkit', {}).get('webprefs', {}).get('default_font_size', 16)
    if font_size == 24:
        score += 15
        feedback.append("Font size successfully set to Very Large (24).")
    elif font_size > 16:
        score += 5
        feedback.append(f"Font size increased to {font_size}, but not Very Large (24).")
    else:
        feedback.append("Font size not changed to Very Large.")
        
    # Downloads (15 pts)
    download_dir = prefs_data.get('download', {}).get('default_directory', '')
    prompt = prefs_data.get('download', {}).get('prompt_for_download', True)
    
    if "HACCP_Logs" in download_dir:
        score += 8
        feedback.append("Download directory correct.")
    else:
        feedback.append("Download directory incorrect.")
        
    if prompt is False:
        score += 7
        feedback.append("Download prompt disabled.")
    else:
        feedback.append("Download prompt not disabled.")
        
    # Startup (15 pts)
    startup_type = prefs_data.get('session', {}).get('restore_on_startup', 1)
    startup_urls = prefs_data.get('session', {}).get('startup_urls', [])
    startup_urls_str = " ".join(startup_urls).lower()
    
    if startup_type == 4:
        score += 5
        feedback.append("Startup behavior set to specific pages.")
    else:
        feedback.append("Startup behavior not set to specific pages.")
        
    if "sysco.com" in startup_urls_str and "servsafe.com" in startup_urls_str:
        score += 10
        feedback.append("Startup URLs successfully configured.")
    elif "sysco.com" in startup_urls_str or "servsafe.com" in startup_urls_str:
        score += 5
        feedback.append("Only one startup URL configured.")
    else:
        feedback.append("Startup URLs missing.")
        
    return score, " | ".join(feedback)


def verify_search_engines(web_data_path: str) -> Tuple[int, str]:
    if not web_data_path or not os.path.exists(web_data_path):
        return 0, "Web Data database not found."
        
    score = 0
    feedback = []
    found_usda = False
    found_recipe = False
    
    try:
        conn = sqlite3.connect(web_data_path)
        cursor = conn.cursor()
        cursor.execute("SELECT keyword, url FROM keywords")
        for keyword, url in cursor.fetchall():
            kw = str(keyword).lower()
            u = str(url).lower()
            if "usda" in kw and "fdc.nal.usda.gov" in u:
                found_usda = True
            if "recipe" in kw and "seriouseats.com" in u:
                found_recipe = True
        conn.close()
    except Exception as e:
        logger.error(f"Error reading SQLite Web Data: {e}")
        return 0, "Failed to query Search Engines from DB."
        
    if found_usda:
        score += 7
        feedback.append("USDA search engine found.")
    else:
        feedback.append("USDA search engine missing.")
        
    if found_recipe:
        score += 8
        feedback.append("Recipe search engine found.")
    else:
        feedback.append("Recipe search engine missing.")
        
    return score, " | ".join(feedback)


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    total_score = 0
    feedback_all = []

    # 1. Gather files
    bkmks_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks")
    prefs_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences")
    webdata_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Web Data", ".sqlite")
    meta_path = _copy_file(copy_from_env, "/tmp/task_result.json")

    # Anti-gaming check: Ensure files were modified during the task
    if meta_path:
        with open(meta_path, 'r') as f:
            meta = json.load(f)
        if meta.get('prefs_mtime', 0) <= meta.get('task_start', 0):
            feedback_all.append("WARNING: Preferences file was not modified during the task.")

    # 2. Score Bookmarks
    if bkmks_path:
        with open(bkmks_path, 'r') as f:
            bkmks_data = json.load(f)
        s, f_str = verify_bookmarks(bkmks_data)
        total_score += s
        feedback_all.append(f"[Bookmarks]: {f_str}")
        os.unlink(bkmks_path)
    else:
        feedback_all.append("[Bookmarks]: File missing.")

    # 3. Score Preferences
    if prefs_path:
        with open(prefs_path, 'r') as f:
            prefs_data = json.load(f)
        s, f_str = verify_preferences(prefs_data)
        total_score += s
        feedback_all.append(f"[Preferences]: {f_str}")
        os.unlink(prefs_path)
    else:
        feedback_all.append("[Preferences]: File missing.")

    # 4. Score Search Engines
    if webdata_path:
        s, f_str = verify_search_engines(webdata_path)
        total_score += s
        feedback_all.append(f"[SearchEngines]: {f_str}")
        os.unlink(webdata_path)
    else:
        feedback_all.append("[SearchEngines]: DB missing.")
        
    # 5. VLM Trajectory Check (15 pts)
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            frames.append(get_final_screenshot(traj))
            # Remove Nones
            frames = [fr for fr in frames if fr is not None]
            
            if frames:
                vlm_resp = query_vlm(prompt=VLM_PROMPT, images=frames)
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("interacted_with_settings_or_bookmarks_ui", False):
                    vlm_score = 15
                    feedback_all.append("[VLM]: Agent interaction with UI verified.")
                else:
                    feedback_all.append("[VLM]: No UI interaction observed.")
            else:
                feedback_all.append("[VLM]: No frames available.")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_all.append(f"[VLM]: Check failed - {e}")
            
    total_score += vlm_score

    # Cleanup meta
    if meta_path:
        os.unlink(meta_path)

    # Key criteria: Must have setup fonts and downloads properly to count as useful
    passed = (total_score >= 75)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_all)
    }