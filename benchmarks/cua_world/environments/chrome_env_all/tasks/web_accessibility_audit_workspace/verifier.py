#!/usr/bin/env python3
"""
Verifier for web_accessibility_audit_workspace@1

Checks configuration of Chrome for Accessibility Auditing:
1. Font Sizes (15 points)
2. Chrome Flags (15 points)
3. Bookmark Folders (15 points)
4. Bookmark Categorization (20 points)
5. Custom Search Engines (10 points)
6. Download Settings (15 points)
7. Privacy Settings (10 points)
8. VLM Trajectory (Anti-Gaming Check) - overrides to 0 if UI wasn't used.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

# Safely try to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DOMAIN_MAP = {
    "Standards": ["w3.org/WAI/standards", "section508", "ada.gov", "webaim"],
    "Evaluation Tools": ["wave", "deque", "lighthouse", "accessibilityinsights", "paciellogroup"],
    "Assistive Tech": ["nvaccess", "freedomscientific", "apple", "support.google"],
    "ARIA & Patterns": ["w3.org/WAI/ARIA", "developer.mozilla", "inclusive-components", "a11yproject"],
    "Personal": ["youtube", "netflix", "reddit", "twitter", "spotify"]
}


def _copy_and_parse_json(copy_from_env, container_path: str) -> Dict[str, Any]:
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(container_path, temp.name)
        if os.path.exists(temp.name) and os.path.getsize(temp.name) > 0:
            with open(temp.name, 'r', encoding='utf-8') as f:
                return json.load(f)
    except Exception as e:
        logger.warning(f"Failed to parse {container_path}: {e}")
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)
    return {}


def verify_accessibility_workspace(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Extract required files
    bookmarks = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks")
    prefs = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences")
    local_state = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome/Local State")
    search_engines = _copy_and_parse_json(copy_from_env, "/tmp/search_engines.json")

    score = 0
    feedback = []

    # 1. Font Sizes (15 pts)
    webkit_prefs = prefs.get("webkit", {}).get("webprefs", {})
    default_font = webkit_prefs.get("default_font_size", 16)
    min_font = webkit_prefs.get("minimum_font_size", 0)
    
    f_score = 0
    if default_font >= 22:
        f_score += 8
        feedback.append(f"✅ Default font size configured ({default_font})")
    else:
        feedback.append(f"❌ Default font size too small ({default_font})")
        
    if min_font >= 18:
        f_score += 7
        feedback.append(f"✅ Minimum font size configured ({min_font})")
    else:
        feedback.append(f"❌ Minimum font size too small ({min_font})")
    score += f_score

    # 2. Chrome Flags (15 pts: 5 pts each)
    flags = local_state.get("browser", {}).get("enabled_labs_experiments", [])
    fl_score = 0
    if any("enable-force-dark@1" in f for f in flags):
        fl_score += 5
        feedback.append("✅ Auto Dark Mode enabled")
    if any("smooth-scrolling@2" in f for f in flags):
        fl_score += 5
        feedback.append("✅ Smooth Scrolling disabled")
    if any("enable-experimental-web-platform-features@1" in f for f in flags):
        fl_score += 5
        feedback.append("✅ Experimental Web Platform features enabled")
    score += fl_score

    if fl_score < 15:
        feedback.append(f"❌ Missing some Chrome Flags. Found: {flags}")

    # 3 & 4. Bookmark Organization (35 pts total)
    bookmark_bar = bookmarks.get("roots", {}).get("bookmark_bar", {}).get("children", [])
    folders = {child.get("name"): child.get("children", []) for child in bookmark_bar if child.get("type") == "folder"}
    
    expected_folders = ["Standards & Guidelines", "Evaluation Tools", "Assistive Tech", "ARIA & Patterns", "Personal"]
    folders_found = [f for f in expected_folders if f in folders]
    
    score += len(folders_found) * 3  # Up to 15 pts for folders
    if len(folders_found) == 5:
        feedback.append("✅ All 5 bookmark folders created")
    else:
        feedback.append(f"❌ Missing folders. Found: {folders_found}")

    cat_score = 0
    for target_folder, expected_domains in DOMAIN_MAP.items():
        if target_folder not in folders:
            continue
        urls_in_folder = [bm.get("url", "").lower() for bm in folders[target_folder] if bm.get("type") == "url"]
        
        matches = 0
        for domain in expected_domains:
            if any(domain in url for url in urls_in_folder):
                matches += 1
        
        # Proportional scoring (4 pts per folder max)
        folder_pts = (matches / len(expected_domains)) * 4
        cat_score += folder_pts
    
    score += int(cat_score)
    feedback.append(f"ℹ️ Bookmark categorization score: {int(cat_score)}/20")

    # 5. Search Engines (10 pts)
    if isinstance(search_engines, list):
        keywords = [se.get("keyword", "").lower() for se in search_engines]
        se_score = 0
        if "wcag" in keywords: se_score += 5
        if "mdn" in keywords: se_score += 5
        score += se_score
        if se_score == 10:
            feedback.append("✅ Search shortcuts created")
        else:
            feedback.append(f"❌ Missing search shortcuts. Found: {keywords}")

    # 6. Download Settings (15 pts)
    dl_dir = prefs.get("download", {}).get("default_directory", "")
    dl_prompt = prefs.get("download", {}).get("prompt_for_download", False)
    dl_score = 0
    
    if "WCAG_Audits" in dl_dir:
        dl_score += 8
        feedback.append("✅ Download directory configured")
    if dl_prompt:
        dl_score += 7
        feedback.append("✅ Prompt for download configured")
    score += dl_score

    # 7. Privacy Settings (10 pts)
    cookie_mode = prefs.get("profile", {}).get("cookie_controls_mode", 0)
    if cookie_mode == 1:
        score += 10
        feedback.append("✅ Third-party cookies blocked")
    else:
        feedback.append("❌ Third-party cookies not blocked")

    # 8. Anti-Gaming VLM Trajectory check
    # We want to ensure the agent actually used the UI for settings/flags
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Look at these browser screenshots. 
            Did the agent ever navigate to Chrome's internal settings pages (like chrome://settings, chrome://flags, or the Settings/Appearance menu) to configure the browser?
            Respond in JSON: {"used_settings_ui": true/false}"""
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success"):
                used_ui = vlm_res.get("parsed", {}).get("used_settings_ui", False)
                if not used_ui:
                    feedback.append("🚨 ANTI-GAMING TRIGGERED: No evidence of Settings/Flags UI usage in trajectory.")
                    score = min(score, 20) # severely cap score if they edited JSON blindly
            
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }