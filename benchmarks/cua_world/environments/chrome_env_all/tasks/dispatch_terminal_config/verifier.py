#!/usr/bin/env python3
"""
Verifier for Dispatch Terminal Config Task (dispatch_terminal_config@1)

Validates 7 criteria across Bookmarks, Preferences, and Local State.
Uses copy_from_env to extract configuration files.

Criteria (100 points total):
1. Chrome flags enabled (15 pts)
2. Font size settings (10 pts)
3. Site-specific permissions (15 pts)
4. Bookmark folders created (15 pts)
5. Bookmarks correctly categorized (15 pts)
6. Homepage and startup pages (15 pts)
7. Download directory and credential settings (15 pts)

Pass threshold: 70
"""

import logging
import os
import json
import tempfile
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target domains for Categorization
EMERGENCY_DOMAINS = ["fema.gov", "ready.gov", "emergency.cdc.gov", "dhs.gov", "nfpa.org", "iafc.org", "apcointl.org"]
WEATHER_DOMAINS = ["weather.gov", "noaa.gov", "earthquake.usgs.gov"]
MAPPING_DOMAINS = ["maps.google.com", "bing.com/maps", "openstreetmap.org", "arcgis.com"]

def _copy_and_parse_json(copy_from_env, candidate_paths: List[str]) -> dict:
    """Attempts to copy a JSON file from container paths and parse it."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_path = tmp.name
    tmp.close()

    parsed = {}
    for path in candidate_paths:
        try:
            copy_from_env(path, tmp_path)
            if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 10:
                with open(tmp_path, 'r', encoding='utf-8') as f:
                    parsed = json.load(f)
                break
        except Exception:
            continue
            
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    return parsed

def _get_nested(d: dict, keys: str, default=None):
    """Safely get nested dictionary values using dot notation."""
    current = d
    for key in keys.split('.'):
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return default
    return current

def check_flags(local_state: dict, prefs: dict) -> tuple:
    """Check if required Chrome experiments are enabled."""
    score = 0
    feedback = []
    
    # Flags can be in Local State or Preferences depending on version
    experiments = _get_nested(local_state, "browser.enabled_labs_experiments", [])
    if not experiments:
        experiments = _get_nested(prefs, "browser.enabled_labs_experiments", [])
    
    required = ["smooth-scrolling", "enable-parallel-downloading", "enable-quic"]
    found_flags = set()
    
    for exp in experiments:
        for req in required:
            # Match flag name and ensure it doesn't explicitly denote default/disabled (like @0 or @2 in some contexts)
            # Typically enabled forms are name@1, name@2. We'll just check if the name is in the string and doesn't end with @0
            if req in exp and not exp.endswith("@0") and not exp.endswith("@2"): # @2 is usually disabled for tri-state
                found_flags.add(req)
                
    for req in required:
        if req in found_flags:
            score += 5
            feedback.append(f"Flag '{req}' enabled.")
        else:
            feedback.append(f"Flag '{req}' NOT enabled.")
            
    return score, " ".join(feedback)

def check_fonts(prefs: dict) -> tuple:
    """Verify font size settings."""
    score = 0
    feedback = []
    
    default_font = _get_nested(prefs, "webkit.webprefs.default_font_size", 16)
    min_font = _get_nested(prefs, "webkit.webprefs.minimum_font_size", 0)
    
    if default_font == 20:
        score += 5
        feedback.append("Default font size set to 20.")
    else:
        feedback.append(f"Default font size incorrect (found: {default_font}).")
        
    if min_font == 14:
        score += 5
        feedback.append("Minimum font size set to 14.")
    else:
        feedback.append(f"Minimum font size incorrect (found: {min_font}).")
        
    return score, " ".join(feedback)

def check_site_permissions(prefs: dict) -> tuple:
    """Verify geolocation and notification permissions."""
    score = 0
    feedback = []
    
    geo_exceptions = _get_nested(prefs, "profile.content_settings.exceptions.geolocation", {})
    notif_exceptions = _get_nested(prefs, "profile.content_settings.exceptions.notifications", {})
    
    # Check Geolocation
    geo_targets = ["maps.google.com", "arcgis.com", "openstreetmap.org"]
    geo_matches = 0
    for key, val in geo_exceptions.items():
        if isinstance(val, dict) and val.get("setting") == 1:
            for target in geo_targets:
                if target in key:
                    geo_matches += 1
                    
    if geo_matches >= 2:
        score += 7
        feedback.append(f"Geolocation allowed for mapping domains ({geo_matches}/3).")
    else:
        feedback.append(f"Geolocation missing for mapping domains ({geo_matches}/3 found).")
        
    # Check Notifications
    notif_targets = ["weather.gov", "earthquake.usgs.gov", "noaa.gov"]
    notif_matches = 0
    for key, val in notif_exceptions.items():
        if isinstance(val, dict) and val.get("setting") == 1:
            for target in notif_targets:
                if target in key:
                    notif_matches += 1
                    
    if notif_matches >= 2:
        score += 8
        feedback.append(f"Notifications allowed for alert domains ({notif_matches}/3).")
    else:
        feedback.append(f"Notifications missing for alert domains ({notif_matches}/3 found).")
        
    return score, " ".join(feedback)

def _get_folders(bookmarks: dict) -> dict:
    """Extract top-level folders from bookmark bar."""
    folders = {}
    bar_children = _get_nested(bookmarks, "roots.bookmark_bar.children", [])
    for child in bar_children:
        if child.get("type") == "folder":
            folders[child.get("name", "").lower()] = child
    return folders

def check_bookmark_folders(folders: dict) -> tuple:
    """Verify the 4 required folders exist."""
    score = 0
    feedback = []
    
    required = ["emergency services", "weather & hazards", "mapping & gis", "personal"]
    
    found = 0
    for req in required:
        # Flexible matching
        matched = False
        for fname in folders.keys():
            if req in fname or (req.replace("&", "and") in fname.replace("&", "and")):
                matched = True
                break
        if matched:
            found += 1
            
    score = min(15, found * 4)
    feedback.append(f"Found {found}/4 required bookmark folders.")
    return score, " ".join(feedback)

def check_bookmark_categorization(folders: dict) -> tuple:
    """Verify bookmarks are placed in correct folders."""
    score = 0
    feedback = []
    
    def count_matches(folder_kwd, expected_domains):
        matches = 0
        target_folder = None
        for k, v in folders.items():
            if folder_kwd in k or folder_kwd.replace("&", "and") in k.replace("&", "and"):
                target_folder = v
                break
                
        if not target_folder:
            return 0
            
        for child in target_folder.get("children", []):
            url = child.get("url", "").lower()
            for ed in expected_domains:
                if ed in url:
                    matches += 1
                    break
        return matches
        
    em_matches = count_matches("emergency", EMERGENCY_DOMAINS)
    if em_matches >= 6:
        score += 5
        feedback.append(f"Emergency Services populated correctly ({em_matches}).")
    else:
        feedback.append(f"Emergency Services underpopulated ({em_matches} < 6).")
        
    we_matches = count_matches("weather", WEATHER_DOMAINS)
    if we_matches >= 2:
        score += 5
        feedback.append(f"Weather & Hazards populated correctly ({we_matches}).")
    else:
        feedback.append(f"Weather & Hazards underpopulated ({we_matches} < 2).")
        
    ma_matches = count_matches("mapping", MAPPING_DOMAINS)
    if ma_matches >= 3:
        score += 5
        feedback.append(f"Mapping & GIS populated correctly ({ma_matches}).")
    else:
        feedback.append(f"Mapping & GIS underpopulated ({ma_matches} < 3).")
        
    return score, " ".join(feedback)

def check_homepage_startup(prefs: dict) -> tuple:
    """Verify homepage and startup URLs."""
    score = 0
    feedback = []
    
    # Homepage
    homepage = _get_nested(prefs, "homepage", "")
    if not homepage:
        homepage = _get_nested(prefs, "browser.homepage", "")
        
    if "weather.gov" in homepage.lower():
        score += 5
        feedback.append("Homepage correct.")
    else:
        feedback.append(f"Homepage incorrect: {homepage}.")
        
    # Startup Pages
    startup_type = _get_nested(prefs, "session.restore_on_startup", 0)
    startup_urls = _get_nested(prefs, "session.startup_urls", [])
    
    urls_str = " ".join(startup_urls).lower()
    
    if "weather.gov" in urls_str: score += 4
    if "earthquake.usgs.gov" in urls_str: score += 3
    if "fema.gov" in urls_str: score += 3
    
    feedback.append(f"Startup matching domains found in {len(startup_urls)} URLs.")
    return score, " ".join(feedback)

def check_downloads_creds(prefs: dict) -> tuple:
    """Verify download and credential security settings."""
    score = 0
    feedback = []
    
    dl_dir = _get_nested(prefs, "download.default_directory", "")
    dl_prompt = _get_nested(prefs, "download.prompt_for_download", False)
    
    if "Dispatch_Records" in dl_dir: score += 4
    if dl_prompt: score += 3
    
    pw_enabled = _get_nested(prefs, "credentials_enable_service", True)
    if not pw_enabled: score += 3
    
    addr_enabled = _get_nested(prefs, "autofill.profile_enabled", True)
    if not addr_enabled: score += 3
    
    cc_enabled = _get_nested(prefs, "autofill.credit_card_enabled", True)
    if not cc_enabled: score += 2
    
    feedback.append(f"DL dir/prompt check: {'Dispatch_Records' in dl_dir}, {dl_prompt}. "
                    f"Creds (PW/Addr/CC) disabled: {not pw_enabled}, {not addr_enabled}, {not cc_enabled}.")
    return score, " ".join(feedback)

def verify_task(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function missing"}

    # 1. Check if the task result export file shows modification
    export_data = _copy_and_parse_json(copy_from_env, ["/tmp/task_result.json"])
    if not export_data.get("modified_during_task", False):
        logger.warning("Agent did not appear to modify Chrome settings files.")
        
    # 2. Extract Data Files
    # We check CDP profile first because our launch script uses it
    local_state = _copy_and_parse_json(copy_from_env, [
        "/home/ga/.config/google-chrome-cdp/Local State",
        "/home/ga/.config/google-chrome/Local State"
    ])
    prefs = _copy_and_parse_json(copy_from_env, [
        "/home/ga/.config/google-chrome-cdp/Default/Preferences",
        "/home/ga/.config/google-chrome/Default/Preferences"
    ])
    bookmarks = _copy_and_parse_json(copy_from_env, [
        "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
        "/home/ga/.config/google-chrome/Default/Bookmarks"
    ])
    
    total_score = 0
    feedback_log = []
    
    # Eval Criteria
    c1, f1 = check_flags(local_state, prefs)
    total_score += c1; feedback_log.append(f"[Flags] {c1}/15: {f1}")
    
    c2, f2 = check_fonts(prefs)
    total_score += c2; feedback_log.append(f"[Fonts] {c2}/10: {f2}")
    
    c3, f3 = check_site_permissions(prefs)
    total_score += c3; feedback_log.append(f"[Permissions] {c3}/15: {f3}")
    
    folders = _get_folders(bookmarks)
    c4, f4 = check_bookmark_folders(folders)
    total_score += c4; feedback_log.append(f"[Folders] {c4}/15: {f4}")
    
    c5, f5 = check_bookmark_categorization(folders)
    total_score += c5; feedback_log.append(f"[Categorization] {c5}/15: {f5}")
    
    c6, f6 = check_homepage_startup(prefs)
    total_score += c6; feedback_log.append(f"[Startup] {c6}/15: {f6}")
    
    c7, f7 = check_downloads_creds(prefs)
    total_score += c7; feedback_log.append(f"[Security/DL] {c7}/15: {f7}")
    
    passed = total_score >= 70
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_log)
    }