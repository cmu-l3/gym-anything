#!/usr/bin/env python3
"""
Verifier for broadcast_meteorologist_workspace@1

Validates:
1. Bookmark Folders & Categorization (25 pts)
2. Live Broadcast Settings (Notifications, Pop-ups, Location Exception) (15 pts)
3. Instant Downloads (10 pts)
4. Custom Search Engine (METAR) (10 pts)
5. Startup Pages (10 pts)
6. Credential Security (10 pts)
7. VLM Trajectory Check (20 pts) - Agent actually performed actions
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are auditing a computer agent's trajectory for a browser configuration task.
The agent was asked to organize bookmarks into folders, configure Chrome Site Settings (Location, Notifications, Pop-ups), set download preferences, and create a search engine.

Review the provided sequence of screenshots from the agent's workflow.
Did the agent actively open Chrome Settings, the Bookmark Manager, or actively navigate menus to configure the browser?

Answer ONLY in JSON format:
{
    "agent_used_settings_ui": true/false,
    "agent_organized_bookmarks": true/false,
    "reasoning": "Brief explanation of visible actions"
}
"""

def _copy_json(copy_from_env, path: str) -> Dict:
    """Helper to copy and parse JSON from the container."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.debug(f"Failed to copy/parse {path}: {e}")
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def check_bookmarks(bookmarks_data: Dict) -> tuple[int, str]:
    """Check folders and categorization (25 pts)"""
    score = 0
    feedback = []
    
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    expected_folders = {
        "Live Radar": ["radar.weather.gov", "weather.com/weather/radar", "accuweather.com", "radarscope.app", "wunderground.com/radar", "intelliweather.com", "myradar.com"],
        "Satellite Imaging": ["goes.gsfc.nasa.gov", "star.nesdis.noaa.gov", "rammb-slider.cira", "zoom.earth", "weather.cod.edu", "realearth.ssec"],
        "Forecast Models": ["pivotalweather.com", "tropicaltidbits.com", "mag.ncep.noaa.gov", "spc.noaa.gov", "windy.com", "models.weatherbell.com"],
        "Off-Air": ["youtube.com", "facebook.com", "twitter.com", "cnn.com", "espn.com", "netflix.com", "amazon.com"]
    }
    
    actual_folders = {}
    for c in children:
        if c.get('type') == 'folder':
            actual_folders[c.get('name')] = c.get('children', [])
            
    # Check Folders (10 pts)
    folders_found = sum(1 for f in expected_folders.keys() if f in actual_folders)
    f_score = int((folders_found / 4) * 10)
    score += f_score
    feedback.append(f"Bookmark folders found: {folders_found}/4 ({f_score} pts)")
    
    # Check Categorization (15 pts)
    correct_urls = 0
    total_expected = sum(len(urls) for urls in expected_folders.values()) # 26
    
    for folder_name, expected_url_fragments in expected_folders.items():
        if folder_name in actual_folders:
            folder_urls = [bm.get('url', '').lower() for bm in actual_folders[folder_name] if bm.get('type') == 'url']
            for fragment in expected_url_fragments:
                if any(fragment in u for u in folder_urls):
                    correct_urls += 1
                    
    c_score = int((correct_urls / total_expected) * 15) if total_expected > 0 else 0
    score += c_score
    feedback.append(f"Bookmarks correctly categorized: {correct_urls}/{total_expected} ({c_score} pts)")
    
    return score, " | ".join(feedback)

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Gather Data
    prefs = _copy_json(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences")
    bookmarks = _copy_json(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks")
    search_engines = _copy_json(copy_from_env, "/tmp/search_engines.json")
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Bookmarks (25 pts) ---
    b_score, b_feedback = check_bookmarks(bookmarks)
    score += b_score
    feedback_parts.append(b_feedback)
    
    # --- Criterion 2: Live Broadcast Settings (15 pts) ---
    lb_score = 0
    
    # Location Exception
    exceptions = prefs.get('profile', {}).get('content_settings', {}).get('exceptions', {})
    geo_exceptions = exceptions.get('geolocation', {})
    radar_allowed = False
    for pattern, val in geo_exceptions.items():
        if 'radar.weather.gov' in pattern and val.get('setting') == 1:
            radar_allowed = True
            break
            
    if radar_allowed:
        lb_score += 5
        feedback_parts.append("Location exception allowed for radar (5 pts)")
    else:
        feedback_parts.append("Location exception missing for radar (0 pts)")
        
    # Global Notifications and Popups
    defaults = prefs.get('profile', {}).get('default_content_setting_values', {})
    if defaults.get('notifications') == 2:
        lb_score += 5
        feedback_parts.append("Notifications blocked (5 pts)")
    else:
        feedback_parts.append("Notifications NOT blocked (0 pts)")
        
    if defaults.get('popups') == 2:
        lb_score += 5
        feedback_parts.append("Popups blocked (5 pts)")
    else:
        feedback_parts.append("Popups NOT blocked (0 pts)")
        
    score += lb_score
    
    # --- Criterion 3: Instant Downloads (10 pts) ---
    dl_score = 0
    dl_prefs = prefs.get('download', {})
    
    if 'Weather_Graphics' in dl_prefs.get('default_directory', ''):
        dl_score += 5
        feedback_parts.append("Download directory correct (5 pts)")
    else:
        feedback_parts.append("Download directory incorrect (0 pts)")
        
    if dl_prefs.get('prompt_for_download') is False:
        dl_score += 5
        feedback_parts.append("Download prompt disabled (5 pts)")
    else:
        feedback_parts.append("Download prompt NOT disabled (0 pts)")
        
    score += dl_score
    
    # --- Criterion 4: Search Engine (10 pts) ---
    se_score = 0
    metar_found = False
    if isinstance(search_engines, list):
        for se in search_engines:
            if se.get('keyword') == 'metar' and 'aviationweather.gov' in se.get('url', ''):
                metar_found = True
                break
                
    if metar_found:
        se_score += 10
        feedback_parts.append("METAR search engine configured (10 pts)")
    else:
        feedback_parts.append("METAR search engine missing (0 pts)")
    score += se_score
    
    # --- Criterion 5: Startup Pages (10 pts) ---
    su_score = 0
    session = prefs.get('session', {})
    
    if session.get('restore_on_startup') == 4:
        su_score += 4
        urls = session.get('startup_urls', [])
        found_radar = any('radar.weather.gov' in u for u in urls)
        found_goes = any('star.nesdis.noaa.gov' in u for u in urls)
        
        if found_radar: su_score += 3
        if found_goes: su_score += 3
        
        feedback_parts.append(f"Startup pages configured ({su_score} pts)")
    else:
        feedback_parts.append("Startup behavior not set to specific pages (0 pts)")
    score += su_score
    
    # --- Criterion 6: Credential Security (10 pts) ---
    cs_score = 0
    if prefs.get('profile', {}).get('password_manager_enabled') is False:
        cs_score += 4
    if prefs.get('autofill', {}).get('profile_enabled') is False:
        cs_score += 3
    if prefs.get('autofill', {}).get('credit_card_enabled') is False:
        cs_score += 3
        
    score += cs_score
    feedback_parts.append(f"Credential security configured ({cs_score} pts)")

    # --- Criterion 7: VLM Trajectory (20 pts) Anti-Gaming ---
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if frames and final:
            vlm_res = query_vlm(images=frames + [final], prompt=VLM_PROMPT)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('agent_used_settings_ui'):
                    vlm_score += 10
                if parsed.get('agent_organized_bookmarks'):
                    vlm_score += 10
                feedback_parts.append(f"VLM trajectory verification: {parsed.get('reasoning')} ({vlm_score} pts)")
            else:
                feedback_parts.append("VLM query failed, 0 pts")
        else:
            feedback_parts.append("Missing trajectory frames for VLM, 0 pts")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification exception (0 pts)")
        
    score += vlm_score

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }