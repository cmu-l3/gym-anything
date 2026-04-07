#!/usr/bin/env python3
"""
Verifier for Field Terminal Browser Config (field_terminal_browser_config@1)

Validates 7 criteria based on the Remote Maintenance Terminal Configuration Standard:
1. Chrome flags enabled (15 pts)
2. Font size and zoom settings (15 pts)
3. Notification permissions (15 pts)
4. Geolocation permissions (10 pts)
5. Homepage and startup pages (15 pts)
6. Bookmark organization (15 pts)
7. Privacy and download settings (15 pts)

Includes anti-gaming checks to ensure preferences were actually modified during the task.
"""

import os
import sys
import json
import logging
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _copy_and_parse_json(copy_from_env, container_path: str) -> Dict[str, Any]:
    """Copy a JSON file from the container and parse it."""
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env(container_path, temp_path)
        if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
            with open(temp_path, 'r', encoding='utf-8') as f:
                return json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read/parse {container_path}: {e}")
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
    return {}


def _get_timestamp(copy_from_env, container_path: str) -> int:
    """Retrieve a timestamp from a text file in the container."""
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        copy_from_env(container_path, temp_path)
        if os.path.exists(temp_path):
            with open(temp_path, 'r') as f:
                content = f.read().strip()
                return int(content) if content.isdigit() else 0
    except Exception:
        pass
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
    return 0


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve data
    prefs = _copy_and_parse_json(copy_from_env, "/tmp/final_preferences.json")
    initial_prefs = _copy_and_parse_json(copy_from_env, "/tmp/initial_preferences.json")
    bookmarks = _copy_and_parse_json(copy_from_env, "/tmp/final_bookmarks.json")
    metadata = task_info.get('metadata', {})
    
    if not prefs:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve Chrome Preferences."}

    total_score = 0
    feedback = []
    
    # Anti-gaming: Ensure file was modified
    if json.dumps(prefs, sort_keys=True) == json.dumps(initial_prefs, sort_keys=True):
        return {"passed": False, "score": 0, "feedback": "Preferences were not modified. 'Do nothing' detected."}

    # ====================================================================
    # 1. Chrome Flags (15 pts)
    # ====================================================================
    enabled_flags = prefs.get("browser", {}).get("enabled_labs_experiments", [])
    expected_flags = metadata.get("expected_flags", ["smooth-scrolling", "enable-parallel-downloading", "back-forward-cache"])
    
    flags_found = 0
    for flag in expected_flags:
        if any(flag in enabled_flag for enabled_flag in enabled_flags):
            flags_found += 1
            
    c1_score = flags_found * 5
    total_score += c1_score
    feedback.append(f"Flags configured: {flags_found}/{len(expected_flags)} ({c1_score}/15 pts)")

    # ====================================================================
    # 2. Font size and zoom settings (15 pts)
    # ====================================================================
    c2_score = 0
    webkit_prefs = prefs.get("webkit", {}).get("webprefs", {})
    
    # Fonts
    if webkit_prefs.get("default_font_size") == 20:
        c2_score += 5
    if webkit_prefs.get("minimum_font_size") == 14:
        c2_score += 5
        
    # Zoom
    # Chrome stores 125% zoom as log(1.25)/log(1.2) ≈ 1.22 in default_zoom_level
    # We check if any default zoom level or partition zoom is in the expected elevated range (0.8 to 1.8)
    zoom_found = False
    partition = prefs.get("partition", {}).get("default_zoom_level", {})
    profile_zoom = prefs.get("profile", {}).get("default_zoom_level", 0)
    
    zoom_values = []
    if isinstance(partition, dict):
        zoom_values.extend(partition.values())
    if isinstance(profile_zoom, (int, float)):
        zoom_values.append(profile_zoom)
        
    for z in zoom_values:
        try:
            val = float(z)
            if 0.8 <= val <= 1.8:
                zoom_found = True
                break
        except (ValueError, TypeError):
            continue
            
    if zoom_found:
        c2_score += 5
        
    total_score += c2_score
    feedback.append(f"Display/Fonts configured ({c2_score}/15 pts)")

    # ====================================================================
    # 3. Notification Permissions (15 pts)
    # ====================================================================
    c3_score = 0
    profile = prefs.get("profile", {})
    defaults = profile.get("default_content_setting_values", {})
    exceptions = profile.get("content_settings", {}).get("exceptions", {})
    
    if defaults.get("notifications") == 2:
        c3_score += 5
        
    scada_allowed = 0
    notif_exceptions = exceptions.get("notifications", {})
    for domain in metadata.get("scada_domains", []):
        for key, val in notif_exceptions.items():
            if domain in key and val.get("setting") == 1:
                scada_allowed += 1
                break
                
    if scada_allowed >= 2:
        c3_score += 10
    elif scada_allowed == 1:
        c3_score += 5
        
    total_score += c3_score
    feedback.append(f"Notifications configured: Blocked={defaults.get('notifications')==2}, Exceptions={scada_allowed} ({c3_score}/15 pts)")

    # ====================================================================
    # 4. Geolocation Permissions (10 pts)
    # ====================================================================
    c4_score = 0
    weather_allowed = 0
    geo_exceptions = exceptions.get("geolocation", {})
    for domain in metadata.get("weather_domains", []):
        for key, val in geo_exceptions.items():
            if domain in key and val.get("setting") == 1:
                weather_allowed += 1
                break
                
    if weather_allowed >= 2:
        c4_score += 10
    elif weather_allowed == 1:
        c4_score += 5
        
    total_score += c4_score
    feedback.append(f"Geolocation exceptions configured: {weather_allowed} ({c4_score}/10 pts)")

    # ====================================================================
    # 5. Homepage and Startup (15 pts)
    # ====================================================================
    c5_score = 0
    homepage = prefs.get("homepage", "").lower()
    session = prefs.get("session", {})
    startup_urls = session.get("startup_urls", [])
    restore_on_startup = session.get("restore_on_startup")
    
    if "vestas.com" in homepage:
        c5_score += 5
        
    if restore_on_startup == 4:
        urls_str = " ".join(startup_urls).lower()
        if "vestas.com" in urls_str: c5_score += 4
        if "windy.com" in urls_str: c5_score += 3
        if "weather.gov" in urls_str: c5_score += 3
        
    total_score += c5_score
    feedback.append(f"Homepage/Startup configured ({c5_score}/15 pts)")

    # ====================================================================
    # 6. Bookmark Organization (15 pts)
    # ====================================================================
    c6_score = 0
    bookmark_bar = bookmarks.get("roots", {}).get("bookmark_bar", {})
    children = bookmark_bar.get("children", [])
    
    folders_found = []
    loose_bookmarks = 0
    
    for child in children:
        if child.get("type") == "folder":
            folders_found.append(child.get("name", "").lower())
        elif child.get("type") == "url":
            loose_bookmarks += 1
            
    # Check expected folders
    expected_folders = [f.lower() for f in metadata.get("bookmark_folders", [])]
    matched_folders = sum(1 for ef in expected_folders if any(ef in ff or ff in ef for ff in folders_found))
    
    if matched_folders >= 3:
        c6_score += 6
    elif matched_folders >= 1:
        c6_score += 3
        
    # Check contents of specific folders (heuristic based on folder names containing 'scada' or 'parts')
    scada_count, parts_count = 0, 0
    for child in children:
        if child.get("type") == "folder":
            name = child.get("name", "").lower()
            inner_urls = " ".join([c.get("url", "").lower() for c in child.get("children", []) if c.get("type") == "url"])
            if "scada" in name or "monitoring" in name:
                scada_count = sum(1 for d in ["ge.com", "vestas.com", "bazefield", "scada-international", "siemens"] if d in inner_urls)
            if "parts" in name or "doc" in name:
                parts_count = sum(1 for d in ["mcmaster", "grainger", "rs-online", "skf"] if d in inner_urls)
                
    if scada_count >= 3: c6_score += 3
    if parts_count >= 2: c6_score += 3
    if loose_bookmarks == 0 and matched_folders > 0: c6_score += 3
    
    # Cap at 15
    c6_score = min(15, c6_score)
    total_score += c6_score
    feedback.append(f"Bookmarks organized: {matched_folders} folders, {loose_bookmarks} loose ({c6_score}/15 pts)")

    # ====================================================================
    # 7. Privacy and Download Settings (15 pts)
    # ====================================================================
    c7_score = 0
    
    download = prefs.get("download", {})
    if "field_reports" in download.get("default_directory", "").lower():
        c7_score += 3
    if download.get("prompt_for_download"):
        c7_score += 3
        
    if not profile.get("password_manager_enabled", True) or not prefs.get("credentials_enable_service", True):
        c7_score += 3
        
    if prefs.get("enable_do_not_track", False):
        c7_score += 3
        
    if prefs.get("safebrowsing", {}).get("enhanced", False):
        c7_score += 3
        
    total_score += c7_score
    feedback.append(f"Privacy/Downloads configured ({c7_score}/15 pts)")

    # ====================================================================
    # Final Result
    # ====================================================================
    passed = total_score >= 65
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "c1_flags": c1_score,
            "c2_fonts": c2_score,
            "c3_notifications": c3_score,
            "c4_geolocation": c4_score,
            "c5_startup": c5_score,
            "c6_bookmarks": c6_score,
            "c7_privacy": c7_score
        }
    }