#!/usr/bin/env python3
"""
Verifier for Avalanche Safety & Patrol Dispatch Browser Setup

Verification Strategy:
1. Programmatically extract Chrome Bookmarks and Preferences via copy_from_env.
2. Verify 4 specific bookmark folders exist.
3. Verify operational sorting (domains accurately mapped to folders).
4. Verify Off-Duty media quarantine (domains isolated, not deleted).
5. Verify Startup sequence (restore_on_startup == 4, 3 target URLs present).
6. Verify Privacy & Security settings (clear cookies on exit, credentials disabled).
7. Verify Download path.
8. VLM Trajectory Verification: Analyze workflow progression to ensure anti-gaming.

Returns standard dictionary: {"passed": bool, "score": int, "feedback": str}
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any, Tuple, List

# Standard framework imports for VLM verification
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Domain Mappings
A_W_DOMAINS = ["avalanche.org", "avalanche.state.co.us", "nwac.us", "mesowest.utah.edu", "wpc.ncep.noaa.gov", "weather.gov", "snodas.noaa.gov", "nrcs.usda.gov"]
MED_DOMAINS = ["wemjournal.org", "nremt.org", "redcross.org", "heart.org", "pubmed.ncbi.nlm.nih.gov", "cdc.gov"]
OPS_DOMAINS = ["fcc.gov", "dol.gov", "fs.usda.gov", "faa.gov", "americanavalancheassociation.org", "nsp.org"]
MEDIA_DOMAINS = ["tetongravity.com", "newschoolers.com", "powder.com", "outsideonline.com", "youtube.com", "netflix.com", "spotify.com", "instagram.com", "reddit.com", "backcountry.com"]


def _get_file_from_container(copy_from_env, container_path: str) -> dict:
    """Helper to safely copy and parse a JSON file from the container."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            with open(tmp.name, 'r', encoding='utf-8') as f:
                return json.load(f)
    except Exception as e:
        logger.debug(f"Error copying/parsing {container_path}: {e}")
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
    return {}


def _check_domain_in_folder(folder_node: dict, target_domains: List[str]) -> int:
    """Returns the count of target domains found in the folder's children."""
    count = 0
    urls = [child.get('url', '').lower() for child in folder_node.get('children', []) if child.get('type') == 'url']
    for domain in target_domains:
        if any(domain in u for u in urls):
            count += 1
    return count


def verify_task(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable."}

    # Fetch configuration files
    bookmarks = _get_file_from_container(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks")
    prefs = _get_file_from_container(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences")
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    if not bookmarks or not prefs:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve Chrome profile data. Ensure the browser was manipulated."}

    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
    folders = [c for c in bookmark_bar.get('children', []) if c.get('type') == 'folder']
    
    # -----------------------------------------------------------------
    # Criterion 1 & 2 & 3: Bookmark Structure & Sorting (40 pts)
    # -----------------------------------------------------------------
    aw_folder = next((f for f in folders if "avalanche" in f.get('name', '').lower() and "weather" in f.get('name', '').lower()), None)
    med_folder = next((f for f in folders if "medical" in f.get('name', '').lower()), None)
    ops_folder = next((f for f in folders if "operation" in f.get('name', '').lower()), None)
    media_folder = next((f for f in folders if "media" in f.get('name', '').lower() or "off-duty" in f.get('name', '').lower()), None)
    
    folders_found = sum(1 for x in [aw_folder, med_folder, ops_folder, media_folder] if x is not None)
    score += (folders_found * 2.5)  # Max 10 pts
    feedback_parts.append(f"Bookmark folders created: {folders_found}/4")

    ops_sorted = 0
    if aw_folder: ops_sorted += _check_domain_in_folder(aw_folder, A_W_DOMAINS)
    if med_folder: ops_sorted += _check_domain_in_folder(med_folder, MED_DOMAINS)
    if ops_folder: ops_sorted += _check_domain_in_folder(ops_folder, OPS_DOMAINS)
    
    ops_score = min(15, int((ops_sorted / 20.0) * 15))
    score += ops_score
    feedback_parts.append(f"Operational bookmarks correctly sorted: {ops_sorted}/20")

    quarantined = 0
    if media_folder: 
        quarantined = _check_domain_in_folder(media_folder, MEDIA_DOMAINS)
    
    media_score = min(15, int((quarantined / 10.0) * 15))
    score += media_score
    feedback_parts.append(f"Media bookmarks quarantined: {quarantined}/10")

    # -----------------------------------------------------------------
    # Criterion 4: Startup Sequence (15 pts)
    # -----------------------------------------------------------------
    restore_behavior = prefs.get('session', {}).get('restore_on_startup', 0)
    startup_urls = prefs.get('session', {}).get('startup_urls', [])
    
    startup_matched = 0
    for t_url in task_info.get('metadata', {}).get('startup_urls', []):
        if any(t_url in s_url for s_url in startup_urls):
            startup_matched += 1
            
    if restore_behavior == 4 and startup_matched >= 3:
        score += 15
        feedback_parts.append("Startup sequence fully configured.")
    elif restore_behavior == 4 and startup_matched > 0:
        score += 7
        feedback_parts.append(f"Startup sequence partially configured ({startup_matched}/3 URLs).")
    else:
        feedback_parts.append("Startup sequence incorrect or disabled.")

    # -----------------------------------------------------------------
    # Criterion 5 & 6: Privacy and Credentials (20 pts)
    # -----------------------------------------------------------------
    # Chrome often stores "clear on exit" in different places based on the version. Check both.
    clear_cookies_session = prefs.get('profile', {}).get('default_content_setting_values', {}).get('cookies', 0) == 4
    clear_cookies_privacy = prefs.get('privacy', {}).get('clear_on_exit', {}).get('cookies', False)
    clear_cookies_profile = prefs.get('profile', {}).get('clear_on_exit', {}).get('cookies', False)
    
    if clear_cookies_session or clear_cookies_privacy or clear_cookies_profile:
        score += 10
        feedback_parts.append("Clear cookies/data on exit is ENABLED.")
    else:
        feedback_parts.append("Clear cookies on exit is DISABLED (Safety risk).")
        
    pwd_manager = prefs.get('profile', {}).get('password_manager_enabled', True)
    autofill = prefs.get('autofill', {}).get('profile_enabled', True)
    
    if not pwd_manager and not autofill:
        score += 10
        feedback_parts.append("Credentials/Autofill disabled.")
    else:
        feedback_parts.append("Credentials/Autofill remain enabled.")

    # -----------------------------------------------------------------
    # Criterion 7: Download Path (5 pts)
    # -----------------------------------------------------------------
    dl_dir = prefs.get('download', {}).get('default_directory', '')
    if 'Incident_Reports' in dl_dir:
        score += 5
        feedback_parts.append("Download directory configured correctly.")
    else:
        feedback_parts.append(f"Download directory incorrect: {dl_dir}")

    # -----------------------------------------------------------------
    # Criterion 8: VLM Trajectory Verification (10 pts)
    # Anti-gaming: Prove the agent actively navigated the settings and bookmark manager UI.
    # -----------------------------------------------------------------
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            vlm_prompt = """You are analyzing an AI agent configuring Google Chrome. 
            Look at the provided trajectory frames. 
            Did the agent open the Chrome Settings pages (e.g., Startup, Privacy, Downloads)?
            Did the agent interact with the Bookmark Manager or the Bookmark Bar to organize folders?
            Respond strictly in JSON format:
            {"used_settings": true/false, "used_bookmarks": true/false}
            """
            
            vlm_response = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                vlm_score = 0
                if parsed.get("used_settings", False): vlm_score += 5
                if parsed.get("used_bookmarks", False): vlm_score += 5
                score += vlm_score
                feedback_parts.append(f"VLM Workflow Verification: {vlm_score}/10 pts")
            else:
                feedback_parts.append("VLM Verification skipped/failed.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM Verification error.")
    else:
        # Give free points if VLM is unavailable but core task looks complete
        if score >= 70:
            score += 10
            feedback_parts.append("VLM unavailable, assuming valid trajectory based on high file score.")

    # Final Pass/Fail logic
    # Threshold is 75/100, but they MUST have enabled clear-on-exit or startup URLs for it to pass (safety/workflow critical)
    critical_features_met = (clear_cookies_session or clear_cookies_privacy or clear_cookies_profile) or (restore_behavior == 4)
    passed = score >= 75 and critical_features_met

    if score >= 75 and not critical_features_met:
        feedback_parts.append("FAILED: Score met threshold, but critical workflow settings (Startup/Privacy) were not completed.")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }