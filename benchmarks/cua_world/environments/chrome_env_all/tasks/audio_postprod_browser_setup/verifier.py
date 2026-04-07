#!/usr/bin/env python3
"""
Verifier for Audio Post-Production Browser Setup (audio_postprod_browser_setup@1)

Verifies:
1. Bookmark Organization (20 pts)
2. System Performance Settings (15 pts)
3. Global Mute & Notifications (15 pts)
4. Audio Site Whitelisting (20 pts)
5. Rapid Download Config (10 pts)
6. Selective Cookie Sanitization (20 pts)
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

# Domain Mappings
CATEGORIES = {
    "sfx": ["freesound.org", "sounddogs.com", "prosoundeffects.com", "boomlibrary.com", "soundsnap.com", "asoundeffect.com"],
    "ambience": ["quietplanet.com", "hissandaroar.com", "fieldsepulchra.com", "xeno-canto.org"],
    "instruments": ["splice.com", "loopmasters.com", "native-instruments.com", "arturia.com", "pluginboutique.com"],
    "licensing": ["epidemicsound.com", "artlist.io", "musicbed.com", "ascap.com", "bmi.com"],
    "personal": ["twitter.com", "reddit.com", "youtube.com", "instagram.com"]
}

WHITELIST_AUDIO_DOMAINS = ["freesound.org", "splice.com", "soundsnap.com", "epidemicsound.com"]

def _copy_file(copy_from_env, container_paths: List[str], suffix: str = '') -> Optional[str]:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    for cpath in container_paths:
        try:
            copy_from_env(cpath, tmp.name)
            if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
                return tmp.name
        except Exception:
            continue
    os.unlink(tmp.name)
    return None

def _collect_bookmarks_recursive(node: Dict, result: List[Dict]):
    if node.get('type') == 'url':
        result.append(node)
    for child in node.get('children', []):
        _collect_bookmarks_recursive(child, result)

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    feedback_parts = []
    total_score = 0
    details = {}

    # Copy necessary Chrome files
    bookmarks_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Bookmarks",
        "/home/ga/.config/google-chrome-cdp/Default/Bookmarks"
    ])
    prefs_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Preferences",
        "/home/ga/.config/google-chrome-cdp/Default/Preferences"
    ])
    local_state_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Local State"
    ])
    cookies_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Network/Cookies",
        "/home/ga/.config/google-chrome/Default/Cookies"
    ], suffix='.sqlite')

    bookmarks = {}
    prefs = {}
    local_state = {}

    if bookmarks_path:
        with open(bookmarks_path, 'r') as f: bookmarks = json.load(f)
    if prefs_path:
        with open(prefs_path, 'r') as f: prefs = json.load(f)
    if local_state_path:
        with open(local_state_path, 'r') as f: local_state = json.load(f)

    # 1. BOOKMARK ORGANIZATION (20 pts)
    bm_score = 0
    folder_hits = 0
    expected_folders = {"sfx": 0, "ambience": 0, "instruments": 0, "licensing": 0, "personal": 0}
    
    if bookmarks:
        bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
        for child in bookmark_bar.get('children', []):
            if child.get('type') == 'folder':
                fname = child.get('name', '').lower()
                urls = []
                _collect_bookmarks_recursive(child, urls)
                url_domains = [u.get('url', '').lower() for u in urls]
                
                # Check mappings
                if 'sfx' in fname or 'sound' in fname:
                    if any('freesound' in u for u in url_domains): expected_folders["sfx"] += 1
                if 'ambience' in fname or 'field' in fname:
                    if any('quietplanet' in u for u in url_domains): expected_folders["ambience"] += 1
                if 'instrument' in fname or 'plugin' in fname:
                    if any('splice' in u for u in url_domains): expected_folders["instruments"] += 1
                if 'licens' in fname or 'music' in fname:
                    if any('epidemic' in u for u in url_domains): expected_folders["licensing"] += 1
                if 'personal' in fname:
                    if any('youtube' in u for u in url_domains): expected_folders["personal"] += 1

    matched_folders = sum(1 for v in expected_folders.values() if v > 0)
    bm_score = matched_folders * 4
    total_score += bm_score
    feedback_parts.append(f"Bookmarks: {matched_folders}/5 categories correct ({bm_score}/20 pts)")
    details["bookmarks_matched"] = matched_folders

    # 2. SYSTEM PERFORMANCE (15 pts)
    sys_score = 0
    hw_accel_enabled = True
    bg_apps_enabled = True

    # Hardware acceleration is often stored in Local State
    hw_state_1 = local_state.get('hardware_acceleration_mode', {}).get('enabled', True)
    hw_state_2 = local_state.get('browser', {}).get('hardware_acceleration_mode', {}).get('enabled', True)
    if not hw_state_1 or not hw_state_2:
        hw_accel_enabled = False
        sys_score += 7.5

    # Background apps stored in Preferences
    if prefs.get('background_mode', {}).get('enabled', True) == False:
        bg_apps_enabled = False
        sys_score += 7.5
    
    total_score += sys_score
    feedback_parts.append(f"System: HW Accel Off={not hw_accel_enabled}, BG Apps Off={not bg_apps_enabled} ({sys_score}/15 pts)")

    # 3. GLOBAL MUTE & NOTIFICATIONS (15 pts)
    mute_score = 0
    sound_val = prefs.get('profile', {}).get('default_content_setting_values', {}).get('sound', 0)
    notif_val = prefs.get('profile', {}).get('default_content_setting_values', {}).get('notifications', 0)
    
    if sound_val == 2:
        mute_score += 5
    if notif_val == 2:
        mute_score += 10
    
    total_score += mute_score
    feedback_parts.append(f"Permissions: Global Sound Blocked={sound_val==2}, Global Notifs Blocked={notif_val==2} ({mute_score}/15 pts)")

    # 4. AUDIO SITE WHITELISTING (20 pts)
    whitelist_score = 0
    whitelisted = 0
    sound_exceptions = prefs.get('profile', {}).get('content_settings', {}).get('exceptions', {}).get('sound', {})
    
    for exc_pattern, exc_data in sound_exceptions.items():
        if exc_data.get('setting') == 1: # 1 = Allow
            for domain in WHITELIST_AUDIO_DOMAINS:
                if domain in exc_pattern:
                    whitelisted += 1
                    break
    
    # Cap at 4
    whitelisted = min(whitelisted, 4)
    whitelist_score = whitelisted * 5
    total_score += whitelist_score
    feedback_parts.append(f"Whitelists: {whitelisted}/4 audio domains allowed ({whitelist_score}/20 pts)")

    # 5. RAPID DOWNLOAD CONFIG (10 pts)
    dl_score = 0
    dl_dir = prefs.get('download', {}).get('default_directory', '')
    dl_prompt = prefs.get('download', {}).get('prompt_for_download', True)

    if 'Audio/SFX_Downloads' in dl_dir:
        dl_score += 5
    if dl_prompt == False:
        dl_score += 5
    
    total_score += dl_score
    feedback_parts.append(f"Downloads: Correct Dir={'Audio/SFX_Downloads' in dl_dir}, Prompt Off={not dl_prompt} ({dl_score}/10 pts)")

    # 6. SELECTIVE COOKIE SANITIZATION (20 pts)
    cookie_score = 0
    freesound_cleared = False
    control_preserved = False

    if cookies_path:
        try:
            conn = sqlite3.connect(cookies_path)
            c = conn.cursor()
            
            c.execute("SELECT host_key FROM cookies")
            all_hosts = [row[0] for row in c.fetchall()]
            
            # Check for corrupt cookies
            has_corrupted = any('freesound' in h or 'splice' in h for h in all_hosts)
            freesound_cleared = not has_corrupted
            
            # Check for control cookies
            control_preserved = any('youtube' in h for h in all_hosts)
            
            conn.close()
            
            if freesound_cleared and control_preserved:
                cookie_score = 20
            elif freesound_cleared and not control_preserved:
                cookie_score = 5 # Wiped all cookies (not selective)
            elif not freesound_cleared and control_preserved:
                cookie_score = 0 # Didn't do the task

        except Exception as e:
            feedback_parts.append(f"Cookie check error: {e}")
            
    total_score += cookie_score
    feedback_parts.append(f"Sanitization: Target Cleared={freesound_cleared}, Control Preserved={control_preserved} ({cookie_score}/20 pts)")

    # Cleanup temp files
    for p in [bookmarks_path, prefs_path, local_state_path, cookies_path]:
        if p and os.path.exists(p):
            try: os.unlink(p)
            except: pass

    # Combine VLM checks to verify agent didn't just python-script the JSON
    import sys
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
    try:
        from vlm_utils import sample_trajectory_frames, query_vlm, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if frames and final:
            vlm_prompt = "Looking at these trajectory frames, did the agent open Chrome Settings or the Chrome Bookmark Manager GUI to make changes, rather than exclusively using a terminal?"
            vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
            if vlm_res.get('success') and "no" in vlm_res.get('response', '').lower() and "yes" not in vlm_res.get('response', '').lower():
                feedback_parts.append("VLM Penalty: Agent did not use Chrome GUI.")
                total_score = max(0, total_score - 20)
    except Exception:
        pass # VLM check optional fallback

    passed = total_score >= 75 and cookie_score >= 10
    
    return {
        "passed": passed,
        "score": int(total_score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }