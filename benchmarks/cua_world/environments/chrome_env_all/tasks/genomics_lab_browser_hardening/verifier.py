#!/usr/bin/env python3
"""
Verifier for genomics_lab_browser_hardening@1.
Validates Chrome internal JSON configuration files against a security policy.
Employs trajectory VLM evaluation and timestamp integrity checks.
"""

import os
import json
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_browser_hardening(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # --- Step 1: Read extracted states from container ---
    def load_json_from_env(container_path: str) -> dict:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env(container_path, tmp.name)
            with open(tmp.name, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.warning(f"Failed to read {container_path}: {e}")
            return {}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    task_result = load_json_from_env("/tmp/task_result.json")
    prefs = load_json_from_env("/home/ga/.config/google-chrome-cdp/Default/Preferences")
    bookmarks = load_json_from_env("/home/ga/.config/google-chrome-cdp/Default/Bookmarks")
    local_state = load_json_from_env("/home/ga/.config/google-chrome-cdp/Local State")

    # --- Step 2: Anti-gaming Timestamp Checks (10 pts) ---
    start_time = task_result.get("task_start_time", 0)
    modified = 0
    
    for key in ["preferences_mtime", "bookmarks_mtime", "local_state_mtime"]:
        if task_result.get(key, 0) > start_time:
            modified += 1
            
    if modified >= 2:
        score += 10
        feedback_parts.append("✅ Configuration files modified during task")
    else:
        feedback_parts.append("❌ Anti-gaming check failed: configuration files were not updated during task time.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Step 3: Check Chrome Flags in Local State (15 pts) ---
    enabled_experiments = local_state.get("browser", {}).get("enabled_labs_experiments", [])
    expected_flags = metadata.get("expected_flags", [])
    flags_found = sum(1 for flag in expected_flags if flag in enabled_experiments)
    
    if flags_found == len(expected_flags):
        score += 15
        feedback_parts.append("✅ Chrome Flags configured correctly")
    elif flags_found > 0:
        score += 5
        feedback_parts.append(f"⚠️ Partial Chrome Flags: {flags_found}/{len(expected_flags)} found")
    else:
        feedback_parts.append("❌ Chrome Flags not enabled")

    # --- Step 4: Check DNS and Settings in Preferences (35 pts) ---
    dns_mode = prefs.get("dns_over_https", {}).get("mode", "")
    dns_template = prefs.get("dns_over_https", {}).get("templates", "")
    if dns_mode == metadata.get("expected_dns_mode") and metadata.get("expected_dns_template") in dns_template:
        score += 10
        feedback_parts.append("✅ DNS-over-HTTPS configured")
    else:
        feedback_parts.append("❌ DNS configuration incorrect")

    webprefs = prefs.get("webkit", {}).get("webprefs", {})
    expected_fonts = metadata.get("expected_fonts", {})
    if (webprefs.get("default_font_size", 0) >= expected_fonts["default"] and
        webprefs.get("default_fixed_font_size", 0) >= expected_fonts["fixed"] and
        webprefs.get("minimum_font_size", 0) >= expected_fonts["min"]):
        score += 10
        feedback_parts.append("✅ Font accessibility adjusted")
    else:
        feedback_parts.append("❌ Font sizes incorrect")

    dl_dir = prefs.get("download", {}).get("default_directory", "")
    dl_prompt = prefs.get("download", {}).get("prompt_for_download", False)
    if metadata.get("download_dir") in dl_dir and dl_prompt:
        score += 10
        feedback_parts.append("✅ Download policy configured")
    else:
        feedback_parts.append("❌ Download policy incorrect")

    startup_mode = prefs.get("session", {}).get("restore_on_startup", 0)
    if startup_mode == metadata.get("startup_mode"):
        score += 5
        feedback_parts.append("✅ Startup behavior configured")
    else:
        feedback_parts.append("❌ Startup behavior incorrect")

    # --- Step 5: Check Bookmarks (10 pts) ---
    bookmark_children = bookmarks.get("roots", {}).get("bookmark_bar", {}).get("children", [])
    folders_found = 0
    
    for expected_folder in metadata.get("expected_folders", []):
        for item in bookmark_children:
            if item.get("type") == "folder" and item.get("name") == expected_folder:
                # Check if there are actual URLs inside to prove agent didn't just make empty folders
                if len(item.get("children", [])) >= 3:
                    folders_found += 1
                break
                
    if folders_found == len(metadata.get("expected_folders", [])):
        score += 10
        feedback_parts.append("✅ Bookmark organization correct")
    elif folders_found > 0:
        score += 5
        feedback_parts.append(f"⚠️ Partial bookmarks organized ({folders_found}/{len(metadata.get('expected_folders', []))})")
    else:
        feedback_parts.append("❌ Bookmarks unorganized")

    # --- Step 6: Site Permissions / Notifications (10 pts) ---
    exceptions = prefs.get("profile", {}).get("content_settings", {}).get("exceptions", {}).get("notifications", {})
    default_notif = prefs.get("profile", {}).get("default_content_setting_values", {}).get("notifications", 0)
    
    allowed = metadata.get("allowed_notifications", [])
    notif_allow_count = sum(1 for pattern, payload in exceptions.items() 
                            if any(domain in pattern for domain in allowed) and payload.get("setting") == 1)
                            
    if default_notif == 2 and notif_allow_count >= len(allowed):
        score += 10
        feedback_parts.append("✅ Notification policy strictness verified")
    else:
        feedback_parts.append("❌ Notification policy incorrect")

    # --- Step 7: VLM Trajectory Verification (10 pts) ---
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """You are analyzing a sequence of screenshots from a browser automation task.
        Did the agent actually navigate the Chrome Settings interface (chrome://settings) OR Chrome Flags (chrome://flags) to configure the browser?
        Return a JSON object: {"configured_settings_ui": true/false}"""
        
        vlm_result = query_vlm(images=images, prompt=prompt)
        if vlm_result.get("success") and vlm_result.get("parsed", {}).get("configured_settings_ui", False):
            score += 10
            feedback_parts.append("✅ VLM confirmed trajectory interaction with Chrome Settings")
        else:
            feedback_parts.append("❌ VLM did not observe settings navigation")
    except Exception as e:
        logger.warning(f"VLM Verification skipped/failed: {e}")

    # --- Final Assessment ---
    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }