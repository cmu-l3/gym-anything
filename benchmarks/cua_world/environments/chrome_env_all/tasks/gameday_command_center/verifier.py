#!/usr/bin/env python3
"""
Verifier for gameday_command_center@1

Uses multi-signal verification:
1. Bookmarks JSON (Categorization & Folders)
2. CDP Tabs JSON (Live workspace)
3. Preferences (Fonts, Startup, Download, Privacy, Autofill)
4. Local State (Chrome Flags)
5. Filesystem (Checklist file)
6. VLM (Trajectory verification for anti-gaming)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any, Tuple

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _copy_and_parse_json(copy_from_env, container_path: str) -> dict:
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(container_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/parse {container_path}: {e}")
        return {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

def _copy_text_file(copy_from_env, container_path: str) -> str:
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(container_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            return f.read()
    except Exception:
        return ""
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

def get_bookmark_folders(bookmarks_data: dict) -> dict:
    """Extract all folders and their child URLs from the bookmark bar."""
    folders = {}
    try:
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
        for child in bookmark_bar.get('children', []):
            if child.get('type') == 'folder':
                name = child.get('name', '').lower()
                urls = []
                for item in child.get('children', []):
                    if item.get('type') == 'url':
                        urls.append(item.get('url', '').lower())
                folders[name] = urls
    except Exception:
        pass
    return folders

def check_bookmarks(bookmarks_data: dict) -> Tuple[int, str]:
    score = 0
    feedback = []
    
    folders = get_bookmark_folders(bookmarks_data)
    folder_keys = list(folders.keys())
    
    # 1. Folders exist (10 pts)
    required = ["advanced analytics", "live scoring", "historical reference", "scouting", "league operations", "personal"]
    found_count = sum(1 for req in required if any(req in k for k in folder_keys))
    folder_score = min(10, int((found_count / len(required)) * 10))
    score += folder_score
    feedback.append(f"Bookmark folders found: {found_count}/{len(required)} ({folder_score}/10 pts)")
    
    # 2. Categorization Check (10 pts)
    adv_urls = next((v for k, v in folders.items() if "advanced" in k), [])
    live_urls = next((v for k, v in folders.items() if "live scoring" in k), [])
    
    adv_match = sum(1 for u in adv_urls if any(d in u for d in ['fangraphs.com', 'baseballsavant', 'brooksbaseball', 'tangotiger', 'baseballprospectus', 'baseball-reference']))
    live_match = sum(1 for u in live_urls if any(d in u for d in ['mlb.com/scores', 'espn.com', 'cbssports', 'yahoo', 'milb.com/scores']))
    
    cat_score = 0
    if adv_match >= 4: cat_score += 5
    if live_match >= 3: cat_score += 5
    score += cat_score
    feedback.append(f"Categorization accuracy: {cat_score}/10 pts")
    
    # 3. Personal isolated (5 pts)
    personal_urls = next((v for k, v in folders.items() if "personal" in k), [])
    personal_match = sum(1 for u in personal_urls if any(d in u for d in ['youtube.com', 'reddit.com', 'twitter', 'instagram', 'twitch', 'spotify', 'amazon']))
    
    # Check if personal loose on bar
    loose_personal = 0
    try:
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
        for child in bookmark_bar.get('children', []):
            if child.get('type') == 'url':
                if any(d in child.get('url','').lower() for d in ['youtube.com', 'reddit.com', 'twitter', 'instagram', 'twitch', 'spotify', 'amazon']):
                    loose_personal += 1
    except Exception:
        pass
        
    pers_score = 0
    if personal_match >= 4 and loose_personal == 0:
        pers_score = 5
    elif personal_match >= 2 and loose_personal <= 2:
        pers_score = 2
    score += pers_score
    feedback.append(f"Personal bookmarks isolated: {pers_score}/5 pts")
    
    return score, " | ".join(feedback)

def verify_gameday_command_center(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    total_score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. BOOKMARKS (25 points)
    # ---------------------------------------------------------
    bookmarks_data = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks")
    if not bookmarks_data:
        bookmarks_data = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome-cdp/Default/Bookmarks")
        
    bm_score, bm_fb = check_bookmarks(bookmarks_data)
    total_score += bm_score
    feedback_parts.append(bm_fb)
    
    # ---------------------------------------------------------
    # 2. OPEN TABS VIA CDP (15 points)
    # ---------------------------------------------------------
    tabs_data = _copy_and_parse_json(copy_from_env, "/tmp/cdp_tabs.json")
    open_urls = [t.get('url', '').lower() for t in tabs_data if isinstance(t, dict)]
    
    required_tabs = ['fangraphs.com', 'baseballsavant.mlb.com', 'mlb.com/scores', 'milb.com/scores', 'baseball-reference.com']
    found_tabs = sum(1 for req in required_tabs if any(req in u for u in open_urls))
    
    tab_score = found_tabs * 3 # up to 15
    total_score += tab_score
    feedback_parts.append(f"Live workspace tabs open: {found_tabs}/5 ({tab_score}/15 pts)")
    
    # ---------------------------------------------------------
    # 3. SETTINGS & PREFERENCES (25 points)
    # ---------------------------------------------------------
    prefs_data = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences")
    if not prefs_data:
        prefs_data = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome-cdp/Default/Preferences")
    
    # Fonts (5 pts)
    font_size = prefs_data.get('webkit', {}).get('webprefs', {}).get('default_font_size', 16)
    if font_size >= 20:
        total_score += 5
        feedback_parts.append("Font size adjusted (5/5 pts)")
    elif font_size >= 18:
        total_score += 2
        feedback_parts.append("Font size slightly adjusted (2/5 pts)")
    else:
        feedback_parts.append("Font size not adjusted (0/5 pts)")
        
    # Homepage/Startup (10 pts)
    homepage = prefs_data.get('homepage', '').lower()
    startup = prefs_data.get('session', {}).get('restore_on_startup', 0)
    
    hs_score = 0
    if 'mlb.com' in homepage: hs_score += 5
    if startup == 1: hs_score += 5
    total_score += hs_score
    feedback_parts.append(f"Homepage/Startup settings: {hs_score}/10 pts")
    
    # Privacy, Download, Autofill (10 pts)
    dl_dir = prefs_data.get('download', {}).get('default_directory', '').lower()
    dl_prompt = prefs_data.get('download', {}).get('prompt_for_download', False)
    pw_manager = prefs_data.get('profile', {}).get('password_manager_enabled', True)
    
    priv_score = 0
    if 'gameday_data' in dl_dir and dl_prompt: priv_score += 5
    if not pw_manager: priv_score += 5
    total_score += priv_score
    feedback_parts.append(f"Privacy/Downloads/Autofill: {priv_score}/10 pts")
    
    # ---------------------------------------------------------
    # 4. CHROME FLAGS (Local State) (5 points)
    # ---------------------------------------------------------
    local_state = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome/Local State")
    if not local_state:
        local_state = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome-cdp/Local State")
        
    flags = local_state.get('browser', {}).get('enabled_labs_experiments', [])
    flag_score = 0
    if any('enable-parallel-downloading@1' in f for f in flags): flag_score += 2.5
    if any('smooth-scrolling@2' in f for f in flags): flag_score += 2.5
    total_score += int(flag_score)
    feedback_parts.append(f"Chrome Flags: {int(flag_score)}/5 pts")
    
    # ---------------------------------------------------------
    # 5. CHECKLIST FILE (10 points)
    # ---------------------------------------------------------
    checklist_txt = _copy_text_file(copy_from_env, "/home/ga/Desktop/pregame_checklist.txt").lower()
    chk_score = 0
    if checklist_txt:
        chk_score += 4
        keywords = ['bookmark', 'tab', 'flag', 'privacy', 'download', 'font']
        k_found = sum(1 for k in keywords if k in checklist_txt)
        if k_found >= 3:
            chk_score += 6
        elif k_found >= 1:
            chk_score += 3
    total_score += chk_score
    feedback_parts.append(f"Pre-game Checklist: {chk_score}/10 pts")

    # ---------------------------------------------------------
    # 6. VLM TRAJECTORY VERIFICATION (20 points)
    # ---------------------------------------------------------
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = """You are auditing a workflow trajectory of a computer agent setting up Chrome for a sports analyst.
Look at these sampled frames from the workflow.
1. Did the agent actively navigate Chrome Settings (appearance, downloads, privacy) or chrome://flags?
2. Did the agent actively use the Bookmark Manager or right-click context menus to organize folders?
3. Did the agent write the checklist file in a text editor?

If the agent actually did the work (not just a final static screen), answer YES to work_performed.
Provide confidence as high/medium/low.

Respond ONLY in JSON format:
{
    "work_performed": true/false,
    "confidence": "high",
    "reasoning": "saw settings menu open, saw text editor typing..."
}
"""
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("work_performed"):
                    conf = parsed.get("confidence", "low").lower()
                    if conf == "high": vlm_score = 20
                    elif conf == "medium": vlm_score = 15
                    else: vlm_score = 10
            feedback_parts.append(f"VLM Trajectory Verification: {vlm_score}/20 pts")
        else:
            feedback_parts.append("VLM Trajectory: No frames available (0/20 pts)")
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("VLM Check Failed (0/20 pts)")
        
    total_score += vlm_score

    # ---------------------------------------------------------
    # FINAL EVALUATION
    # ---------------------------------------------------------
    passed = total_score >= 70 and bm_score >= 10 and tab_score >= 9
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_parts)
    }