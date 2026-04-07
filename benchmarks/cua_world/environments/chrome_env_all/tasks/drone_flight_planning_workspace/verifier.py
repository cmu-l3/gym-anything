#!/usr/bin/env python3
"""
Verifier for Drone Flight Planning Workspace (drone_flight_planning_workspace@1)

Verifies:
1. Bookmark Organization (25 pts)
2. Geolocation Allowances (20 pts)
3. Download Directory & Prompt OFF (15 pts)
4. Chrome Flags (15 pts)
5. Startup Pages (15 pts)
6. Custom Search Engine (10 pts)
"""

import json
import logging
import os
import sqlite3
import tempfile
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected Bookmark categorizations
EXPECTED_BMS = {
    "Airspace": ["faadronezone.faa.gov", "aloft.ai", "skyvector.com", "1800wxbrief.com", "notams.aim.faa.gov"],
    "Weather": ["uavforecast.com", "windy.com", "aviationweather.gov", "swpc.noaa.gov", "astrospheric.com"],
    "Photogrammetry": ["dronedeploy.com", "pix4d.com", "flylitchi.com", "ugcs.com", "measure.com"],
    "Hardware": ["enterprise.dji.com", "autelrobotics.com", "px4.io", "expresslrs.org", "betaflight.com"],
    "Off-Duty": ["netflix.com", "reddit.com", "spotify.com"]
}

def _copy_file(copy_from_env, container_paths: list, suffix: str = '') -> Optional[str]:
    """Helper to copy a file from the container, trying multiple fallback paths."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp_path = tmp.name
    tmp.close()
    
    for path in container_paths:
        try:
            copy_from_env(path, tmp_path)
            if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 0:
                return tmp_path
        except Exception:
            continue
            
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    return None

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}
        
    score = 0
    feedback_parts = []
    
    # Define paths
    pref_paths = ["/home/ga/.config/google-chrome/Default/Preferences", "/home/ga/.config/google-chrome-cdp/Default/Preferences"]
    bm_paths = ["/home/ga/.config/google-chrome/Default/Bookmarks", "/home/ga/.config/google-chrome-cdp/Default/Bookmarks"]
    ls_paths = ["/home/ga/.config/google-chrome/Local State", "/home/ga/.config/google-chrome-cdp/Local State"]
    wd_paths = ["/home/ga/.config/google-chrome/Default/Web Data", "/home/ga/.config/google-chrome-cdp/Default/Web Data"]
    
    prefs_local = _copy_file(copy_from_env, pref_paths, '.json')
    bms_local = _copy_file(copy_from_env, bm_paths, '.json')
    ls_local = _copy_file(copy_from_env, ls_paths, '.json')
    wd_local = _copy_file(copy_from_env, wd_paths, '.sqlite')
    
    prefs = {}
    if prefs_local:
        with open(prefs_local, 'r') as f:
            prefs = json.load(f)
            
    bms = {}
    if bms_local:
        with open(bms_local, 'r') as f:
            bms = json.load(f)
            
    local_state = {}
    if ls_local:
        with open(ls_local, 'r') as f:
            local_state = json.load(f)

    # 1. Bookmarks Check (25 pts)
    bm_score = 0
    found_folders = []
    if bms and "roots" in bms and "bookmark_bar" in bms["roots"]:
        children = bms["roots"]["bookmark_bar"].get("children", [])
        for child in children:
            if child.get("type") == "folder":
                name = child.get("name", "")
                if name in EXPECTED_BMS:
                    found_folders.append(name)
                    # Check if contents match
                    folder_urls = [c.get("url", "") for c in child.get("children", [])]
                    match_count = sum(1 for expected in EXPECTED_BMS[name] if any(expected in u for u in folder_urls))
                    if match_count >= len(EXPECTED_BMS[name]) * 0.8:
                        bm_score += 5
    score += bm_score
    feedback_parts.append(f"Bookmarks: {bm_score}/25 pts ({len(found_folders)}/5 folders found)")

    # 2. Geolocation (20 pts)
    geo_score = 0
    try:
        geo_exceptions = prefs.get("profile", {}).get("content_settings", {}).get("exceptions", {}).get("geolocation", {})
        aloft_allowed = False
        uav_allowed = False
        for k, v in geo_exceptions.items():
            if "aloft.ai" in k and v.get("setting") == 1:
                aloft_allowed = True
            if "uavforecast.com" in k and v.get("setting") == 1:
                uav_allowed = True
        if aloft_allowed: geo_score += 10
        if uav_allowed: geo_score += 10
    except Exception as e:
        logger.error(f"Error checking geolocation: {e}")
    score += geo_score
    feedback_parts.append(f"Geolocation: {geo_score}/20 pts (Aloft: {aloft_allowed}, UAV: {uav_allowed})")

    # 3. Downloads (15 pts)
    dl_score = 0
    try:
        downloads = prefs.get("download", {})
        if "Mission_Data/Raw_Images" in downloads.get("default_directory", ""):
            dl_score += 8
        if downloads.get("prompt_for_download", True) is False:
            dl_score += 7
    except Exception as e:
        logger.error(f"Error checking downloads: {e}")
    score += dl_score
    feedback_parts.append(f"Downloads: {dl_score}/15 pts")

    # 4. Chrome Flags (15 pts)
    flags_score = 0
    try:
        flags = local_state.get("browser", {}).get("enabled_labs_experiments", [])
        has_parallel = any("enable-parallel-downloading" in f for f in flags)
        has_webgl = any("enable-webgl-draft-extensions" in f for f in flags)
        if has_parallel: flags_score += 7.5
        if has_webgl: flags_score += 7.5
    except Exception as e:
        logger.error(f"Error checking flags: {e}")
    score += flags_score
    feedback_parts.append(f"Flags: {flags_score}/15 pts")

    # 5. Startup Pages (15 pts)
    startup_score = 0
    try:
        session = prefs.get("session", {})
        if session.get("restore_on_startup") == 4:
            urls = session.get("startup_urls", [])
            has_aloft = any("aloft.ai" in u for u in urls)
            has_uav = any("uavforecast.com" in u for u in urls)
            if has_aloft: startup_score += 7.5
            if has_uav: startup_score += 7.5
    except Exception as e:
        logger.error(f"Error checking startup pages: {e}")
    score += startup_score
    feedback_parts.append(f"Startup Pages: {startup_score}/15 pts")

    # 6. Custom Search Engine (10 pts)
    se_score = 0
    se_found = False
    
    # First check preferences
    try:
        search_providers = prefs.get("default_search_provider_data", {}).get("template_url_data", {})
        if "notam" in search_providers.get("keyword", "").lower():
            se_found = True
            se_score = 10
            
        custom_providers = prefs.get("profile", {}).get("custom_search_providers", {})
        if isinstance(custom_providers, list):
            for sp in custom_providers:
                if "notam" in sp.get("keyword", "").lower():
                    se_found = True
                    se_score = 10
    except Exception as e:
        logger.error(f"Error checking search engines in prefs: {e}")

    # Fallback to Web Data SQLite
    if not se_found and wd_local:
        try:
            conn = sqlite3.connect(wd_local)
            cursor = conn.cursor()
            cursor.execute("SELECT keyword, url FROM keywords WHERE keyword LIKE '%notam%'")
            rows = cursor.fetchall()
            for row in rows:
                if "notams.aim.faa.gov" in row[1]:
                    se_found = True
                    se_score = 10
                    break
            conn.close()
        except Exception as e:
            logger.error(f"Error querying SQLite Web Data: {e}")
            
    score += se_score
    feedback_parts.append(f"Custom Search Engine: {se_score}/10 pts")

    # Clean up temp files
    for path in [prefs_local, bms_local, ls_local, wd_local]:
        if path and os.path.exists(path):
            os.unlink(path)

    passed = score >= 70 and dl_score == 15 and geo_score == 20
    
    if not passed and score >= 70:
        feedback_parts.append("FAILED: Did not perfectly configure the critical Download and Geolocation settings.")

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }