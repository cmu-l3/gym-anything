#!/usr/bin/env python3
"""
Verifier for E-sports Stage Admin Setup task.

Verification Strategy:
1. Parse Chrome's Bookmarks, Preferences, and Local State JSON files directly.
2. Evaluate 7 critical programmatic criteria.
3. Utilize VLM on trajectory frames to ensure the agent didn't "do nothing" (anti-gaming check).
"""

import json
import os
import tempfile
import logging

# We will try to import trajectory sampling utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_json_from_env(copy_from_env, candidate_paths):
    """Attempt to copy and parse JSON from the first valid container path."""
    for path in candidate_paths:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env(path, tmp.name)
            if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 10:
                with open(tmp.name, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                os.unlink(tmp.name)
                return data
        except Exception:
            pass
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    return {}

def check_folders(bookmark_bar, expected_folders):
    """Evaluates bookmark categorization."""
    score = 0
    feedback = []
    
    children = bookmark_bar.get("children", [])
    folders = {child.get("name", "").lower(): child for child in children if child.get("type") == "folder"}
    
    for expected_folder, domains in expected_folders.items():
        folder_node = folders.get(expected_folder.lower())
        if not folder_node:
            feedback.append(f"Folder '{expected_folder}' missing.")
            continue
            
        folder_urls = [bm.get("url", "").lower() for bm in folder_node.get("children", []) if bm.get("type") == "url"]
        matches = sum(1 for domain in domains if any(domain in url for url in folder_urls))
        
        if matches >= len(domains) - 1:  # Allow 1 mistake per folder
            score += 4
            feedback.append(f"Folder '{expected_folder}' populated correctly.")
        else:
            feedback.append(f"Folder '{expected_folder}' missing expected domains (found {matches}/{len(domains)}).")
            
    return score, feedback

def verify_esports_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_folders = metadata.get('expected_folders', {})
    expected_startup = metadata.get('expected_startup_domains', ["discord.com", "battlefy.com"])
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON Configs
    bookmarks_paths = ["/home/ga/.config/google-chrome-cdp/Default/Bookmarks", "/home/ga/.config/google-chrome/Default/Bookmarks"]
    prefs_paths = ["/home/ga/.config/google-chrome-cdp/Default/Preferences", "/home/ga/.config/google-chrome/Default/Preferences"]
    local_state_paths = ["/home/ga/.config/google-chrome-cdp/Local State", "/home/ga/.config/google-chrome/Local State"]

    bookmarks = parse_json_from_env(copy_from_env, bookmarks_paths)
    prefs = parse_json_from_env(copy_from_env, prefs_paths)
    local_state = parse_json_from_env(copy_from_env, local_state_paths)

    # Criterion 1: Bookmarks (20 points)
    b_bar = bookmarks.get("roots", {}).get("bookmark_bar", {})
    bm_score, bm_feedback = check_folders(b_bar, expected_folders)
    score += bm_score
    feedback_parts.extend(bm_feedback)

    # Criterion 2: Performance / Memory Saver (15 points)
    # 2 = explicitly disabled, 0 = default state.
    mem_saver_state = prefs.get("performance_tuning", {}).get("high_efficiency_mode", {}).get("state", -1)
    if mem_saver_state == 2:
        score += 15
        feedback_parts.append("Memory Saver disabled correctly.")
    else:
        feedback_parts.append(f"Memory Saver not explicitly disabled (state={mem_saver_state}).")

    # Criterion 3: Audio Permissions (15 points)
    default_sound = prefs.get("profile", {}).get("default_content_setting_values", {}).get("sound", 1)
    sound_exceptions = prefs.get("profile", {}).get("content_settings", {}).get("exceptions", {}).get("sound", {})
    
    sound_discord_allowed = any("discord.com" in k and v.get("setting") == 1 for k, v in sound_exceptions.items())
    if default_sound == 2 and sound_discord_allowed:
        score += 15
        feedback_parts.append("Global audio muted & Discord allowed.")
    else:
        feedback_parts.append(f"Audio config failed (Default={default_sound}, DiscordAllowed={sound_discord_allowed}).")

    # Criterion 4: Microphone Permissions (15 points)
    default_mic = prefs.get("profile", {}).get("default_content_setting_values", {}).get("media_stream_mic", 0)
    mic_exceptions = prefs.get("profile", {}).get("content_settings", {}).get("exceptions", {}).get("media_stream_mic", {})
    
    mic_discord_allowed = any("discord.com" in k and v.get("setting") == 1 for k, v in mic_exceptions.items())
    if default_mic == 2 and mic_discord_allowed:
        score += 15
        feedback_parts.append("Global mic blocked & Discord allowed.")
    else:
        feedback_parts.append(f"Mic config failed (Default={default_mic}, DiscordAllowed={mic_discord_allowed}).")

    # Criterion 5: QUIC Flag Disabled (10 points)
    flags = local_state.get("browser", {}).get("enabled_labs_experiments", [])
    if "enable-quic@2" in flags:
        score += 10
        feedback_parts.append("QUIC protocol disabled via flags.")
    else:
        feedback_parts.append("QUIC protocol flag not disabled.")

    # Criterion 6: Custom Search Engine (10 points)
    custom_engines = prefs.get("default_search_provider_data", {}).get("template_url_data", {})
    vlr_found = False
    
    # Check overrides
    overrides = prefs.get("search_provider_overrides", [])
    for engine in overrides:
        if engine.get("keyword") == "vlr" and "vlr.gg" in engine.get("search_url", ""):
            vlr_found = True
            
    # Check default search provider tree fallback
    if custom_engines.get("keyword") == "vlr" and "vlr.gg" in custom_engines.get("url", ""):
        vlr_found = True

    if vlr_found:
        score += 10
        feedback_parts.append("VLR custom search engine configured.")
    else:
        feedback_parts.append("VLR custom search engine not found.")

    # Criterion 7: Startup Pages (15 points)
    startup_type = prefs.get("session", {}).get("restore_on_startup", 0)
    startup_urls = prefs.get("session", {}).get("startup_urls", [])
    
    if startup_type == 4:
        found_urls = sum(1 for domain in expected_startup if any(domain in url for url in startup_urls))
        if found_urls >= len(expected_startup):
            score += 15
            feedback_parts.append("Startup pages configured correctly.")
        else:
            feedback_parts.append("Startup configured, but missing required URLs.")
    else:
        feedback_parts.append("Startup pages behavior not set to 'Open a specific page'.")

    # VLM Trajectory Verification (Anti-gaming fallback)
    vlm_passed = False
    if VLM_AVAILABLE and query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        prompt = "Look at these screenshots from a session configuring Google Chrome. Can you confirm the user navigated to the Chrome Settings menu (chrome://settings) OR Chrome Flags (chrome://flags) to manipulate browser internals? Reply in JSON format: {'manipulated_settings': true/false}"
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_res.get("success"):
            vlm_passed = vlm_res.get("parsed", {}).get("manipulated_settings", False)
            if vlm_passed:
                feedback_parts.append("VLM: Confirmed UI interaction with Chrome Settings.")
            else:
                feedback_parts.append("VLM: Could not confirm settings menus were visited. Potential cheating detected.")
                score = min(score, 60) # Cap score below passing if no interaction
                
    else:
        # Fallback if VLM isn't loaded; rely purely on programmatic signals
        vlm_passed = True
        
    passed = score >= 70 and vlm_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }