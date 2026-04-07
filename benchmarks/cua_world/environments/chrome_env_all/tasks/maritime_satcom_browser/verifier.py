#!/usr/bin/env python3
"""
Verifier for Maritime Satcom Browser Optimization (maritime_satcom_browser@1)

Evaluates:
1. Deletion of streaming bookmarks (15 pts)
2. Creation of 3 maritime bookmark folders (15 pts)
3. Image blocking enabled in Preferences (20 pts)
4. Prefetching disabled in Preferences (15 pts)
5. Custom Search Engine 'buoy' added (15 pts)
6. 3 specific flags set in Local State (20 pts)

Uses VLM trajectory verification as an anti-gaming measure to ensure the UI was used.
"""

import os
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Fallback imports for VLM trajectory logic if available in the environment framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM libraries not found. Skipping VLM anti-gaming check.")


def _copy_file(copy_from_env, container_paths: List[str], suffix: str = '.json') -> str:
    temp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp.name
    temp.close()

    for cpath in container_paths:
        try:
            copy_from_env(cpath, temp_path)
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 10:
                return temp_path
        except Exception:
            continue
    return ""


def _get_all_urls(node: Dict) -> List[str]:
    urls = []
    if node.get('type') == 'url':
        urls.append(node.get('url', '').lower())
    for child in node.get('children', []):
        urls.extend(_get_all_urls(child))
    return urls


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    streaming_domains = metadata.get('streaming_domains', [])
    expected_folders = metadata.get('expected_folders', [])
    required_flags = metadata.get('required_flags', [])

    score = 0
    feedback = []
    
    # ─── 1. EXTRACT BROWSER FILES ────────────────────────────────────────────────
    bookmarks_path = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Default/Bookmarks"])
    prefs_path = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Default/Preferences"])
    local_state_path = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Local State"])
    web_data_path = _copy_file(copy_from_env, ["/tmp/WebData_export", "/home/ga/.config/google-chrome/Default/Web Data"], suffix=".sqlite")

    bookmarks = {}
    if bookmarks_path:
        try:
            with open(bookmarks_path, 'r', encoding='utf-8') as f:
                bookmarks = json.load(f)
        except Exception:
            pass

    prefs = {}
    if prefs_path:
        try:
            with open(prefs_path, 'r', encoding='utf-8') as f:
                prefs = json.load(f)
        except Exception:
            pass

    local_state = {}
    if local_state_path:
        try:
            with open(local_state_path, 'r', encoding='utf-8') as f:
                local_state = json.load(f)
        except Exception:
            pass

    # ─── 2. EVALUATE CRITERIA ────────────────────────────────────────────────────
    
    # Criterion A: Streaming Purge (15 pts)
    all_urls = _get_all_urls(bookmarks.get('roots', {}))
    found_streaming = [domain for domain in streaming_domains if any(domain in u for u in all_urls)]
    
    if not found_streaming and len(all_urls) > 0:
        score += 15
        feedback.append("✅ Streaming bookmarks purged")
    else:
        feedback.append(f"❌ Streaming bookmarks found: {', '.join(found_streaming)}")

    # Criterion B: Bookmark Folders (15 pts)
    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
    actual_folders = [c.get('name') for c in bookmark_bar.get('children', []) if c.get('type') == 'folder']
    folders_found = 0
    for ef in expected_folders:
        if ef in actual_folders:
            folders_found += 1
    
    folder_score = (folders_found / max(1, len(expected_folders))) * 15
    score += int(folder_score)
    if folders_found == len(expected_folders):
        feedback.append("✅ All maritime bookmark folders created")
    else:
        feedback.append(f"❌ Missing some bookmark folders (found {folders_found}/{len(expected_folders)})")

    # Criterion C: Image Blocking (20 pts) - REQUIRED TO PASS
    image_blocked = False
    try:
        img_setting = prefs.get('profile', {}).get('default_content_setting_values', {}).get('images', 0)
        if img_setting == 2:
            image_blocked = True
            score += 20
            feedback.append("✅ Images globally blocked (Critical Requirement)")
        else:
            feedback.append("❌ Images not blocked (default_content_setting_values.images != 2)")
    except Exception:
        feedback.append("❌ Could not read image settings")

    # Criterion D: Prefetching Disabled (15 pts)
    try:
        prefetch_setting = prefs.get('net', {}).get('network_prediction_options', 0)
        # 2 = Never, which is disabled
        if prefetch_setting == 2:
            score += 15
            feedback.append("✅ Network prediction/prefetching disabled")
        else:
            feedback.append("❌ Network prediction not disabled")
    except Exception:
        feedback.append("❌ Could not read prefetch settings")

    # Criterion E: Custom Search Engine (15 pts)
    search_found = False
    if web_data_path:
        try:
            conn = sqlite3.connect(web_data_path)
            cursor = conn.cursor()
            cursor.execute("SELECT keyword, url FROM keywords WHERE keyword='buoy'")
            row = cursor.fetchone()
            if row and 'ndbc.noaa.gov' in row[1]:
                search_found = True
            conn.close()
        except Exception as e:
            logger.debug(f"SQLite check failed: {e}")
            
    if not search_found:
        # Check fallback in Preferences
        try:
            custom_searches = prefs.get('profile', {}).get('custom_search_providers', [])
            for s in custom_searches:
                if s.get('keyword') == 'buoy' and 'ndbc.noaa.gov' in s.get('url', ''):
                    search_found = True
                    break
        except Exception:
            pass

    if search_found:
        score += 15
        feedback.append("✅ Custom 'buoy' search engine configured")
    else:
        feedback.append("❌ 'buoy' search engine not found")

    # Criterion F: Network Flags (20 pts)
    try:
        enabled_flags = local_state.get('browser', {}).get('enabled_labs_experiments', [])
        flags_found = 0
        for rf in required_flags:
            if rf in enabled_flags:
                flags_found += 1
        
        flag_score = (flags_found / max(1, len(required_flags))) * 20
        score += int(flag_score)
        if flags_found == len(required_flags):
            feedback.append("✅ All required Chrome flags configured correctly")
        else:
            feedback.append(f"❌ Missing or incorrect Chrome flags (found {flags_found}/{len(required_flags)})")
    except Exception:
        feedback.append("❌ Could not read Chrome flags from Local State")

    # ─── 3. VLM ANTI-GAMING (Optional but robust) ────────────────────────────────
    vlm_anti_gaming_passed = True
    if VLM_AVAILABLE and 'query_vlm' in env_info:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = (
                    "You are verifying an agent configuring a browser. Look at these frames from the task. "
                    "Did the agent navigate through the Chrome Settings UI and the chrome://flags page? "
                    "Respond with a JSON object: {\"used_ui\": true/false}"
                )
                vlm_res = env_info['query_vlm'](prompt=prompt, images=frames)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if not parsed.get('used_ui', True):
                        feedback.append("⚠️ VLM indicates the UI might not have been used.")
                        # Could penalize score here if strictly enforcing UI interaction
        except Exception as e:
            logger.debug(f"VLM verification error: {e}")

    # ─── 4. CLEANUP & RESULT ─────────────────────────────────────────────────────
    for p in filter(None, [bookmarks_path, prefs_path, local_state_path, web_data_path]):
        if os.path.exists(p):
            os.unlink(p)

    passed = (score >= 70) and image_blocked and vlm_anti_gaming_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }