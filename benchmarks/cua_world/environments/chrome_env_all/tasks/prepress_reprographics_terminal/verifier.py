#!/usr/bin/env python3
"""
Verifier for prepress_reprographics_terminal@1

Criteria (100 points total):
  1. PDF Handling Modification (20 pts): plugins.always_open_pdf_externally == True
  2. Download Spool Config (15 pts): custom path + prompt enabled
  3. Hardware Accel Flags (20 pts): gpu rasterization + ignore blocklist in Local State
  4. Bookmark Hierarchy (20 pts): 4 specified folders with appropriate contents
  5. Sanitization (15 pts): No personal domains remain in the bookmark tree
  6. Color Search Engine (10 pts): Web Data SQLite contains keyword 'color' -> pantone
"""

import os
import sys
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Fallback VLM Utility import
sys.path.insert(0, str(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'utils')))
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False


def _copy_file(copy_from_env, container_path: str, suffix: str = '') -> Optional[str]:
    """Copy a file from container to a local temp file."""
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        tmp.close()
        copy_from_env(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
        os.unlink(tmp.name)
    except Exception as e:
        logger.debug(f"Failed to copy {container_path}: {e}")
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
    return None

def _read_json(path: str) -> dict:
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}

def _collect_bookmark_urls(node: dict, collected: Optional[List[dict]] = None) -> List[dict]:
    if collected is None:
        collected = []
    if node.get('type') == 'url':
        collected.append(node)
    for child in node.get('children', []):
        _collect_bookmark_urls(child, collected)
    return collected

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable."}

    metadata = task_info.get('metadata', {})
    expected_spool = metadata.get('expected_spool_dir', 'Prepress_Spool')
    expected_flags = metadata.get('expected_flags', ['enable-gpu-rasterization', 'ignore-gpu-blocklist'])
    expected_folders = metadata.get('expected_folders', ['Web-to-Print MIS', 'Color Management', 'Asset Libraries', 'Equipment Support'])
    banned_domains = metadata.get('banned_domains', ['netflix.com', 'facebook.com', 'espn.com', 'x.com', 'twitter.com', 'hulu.com'])
    search_keyword = metadata.get('search_keyword', 'color')
    
    score = 0
    feedback_parts = []
    
    # 1. Copy Files
    res_path = _copy_file(copy_from_env, "/tmp/task_result.json")
    pref_path = _copy_file(copy_from_env, "/tmp/Preferences.json")
    loc_path = _copy_file(copy_from_env, "/tmp/Local_State.json")
    bk_path = _copy_file(copy_from_env, "/tmp/Bookmarks.json")
    web_data_path = _copy_file(copy_from_env, "/tmp/Web_Data.sqlite")
    
    results = _read_json(res_path) if res_path else {}
    prefs = _read_json(pref_path) if pref_path else {}
    local_state = _read_json(loc_path) if loc_path else {}
    bookmarks = _read_json(bk_path) if bk_path else {}
    
    task_start = results.get('task_start', 0)

    # VLM Trajectory Check - Anti-gaming
    vlm_points = 0
    if VLM_AVAILABLE and 'query_vlm' in env_info:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            vlm_prompt = "Did the user actively navigate Chrome Settings, chrome://flags, or the Bookmark Manager during this sequence? Answer 'yes' or 'no' in JSON format like {\"active_navigation\": true/false}."
            vlm_res = env_info['query_vlm'](prompt=vlm_prompt, images=frames)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('active_navigation'):
                vlm_points = 10
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Criterion 1: PDF Handling (20 pts)
    always_open_pdf = prefs.get('plugins', {}).get('always_open_pdf_externally', False)
    if always_open_pdf:
        score += 20
        feedback_parts.append("[+] PDF handling correctly set to download.")
    else:
        feedback_parts.append("[-] PDF handling not set to download externally.")

    # Criterion 2: Download Spool Config (15 pts)
    download_dir = prefs.get('download', {}).get('default_directory', '')
    prompt_for_dl = prefs.get('download', {}).get('prompt_for_download', False)
    dl_score = 0
    if download_dir.endswith("Prepress_Spool"): dl_score += 7.5
    if prompt_for_dl: dl_score += 7.5
    score += dl_score
    if dl_score == 15:
        feedback_parts.append("[+] Download spool properly configured.")
    else:
        feedback_parts.append(f"[-] Download settings incomplete (Dir: {download_dir}, Prompt: {prompt_for_dl}).")

    # Criterion 3: Hardware Accel Flags (20 pts)
    experiments = local_state.get('browser', {}).get('enabled_labs_experiments', [])
    flags_found = 0
    for ef in expected_flags:
        if any(ef in exp for exp in experiments):
            flags_found += 1
    
    flag_score = flags_found * 10
    score += flag_score
    if flags_found == len(expected_flags):
        feedback_parts.append("[+] GPU Rasterization flags enabled.")
    else:
        feedback_parts.append(f"[-] Missing required Chrome flags. Found {flags_found}/{len(expected_flags)}.")

    # Criterion 4: Bookmark Hierarchy (20 pts)
    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    folders_found = 0
    for child in bookmark_bar:
        if child.get('type') == 'folder' and child.get('name') in expected_folders:
            urls = _collect_bookmark_urls(child)
            if len(urls) >= 3: # Must have actually sorted items into it
                folders_found += 1
    
    bk_score = folders_found * 5
    score += bk_score
    feedback_parts.append(f"[*] Found {folders_found}/{len(expected_folders)} prepress bookmark folders.")

    # Criterion 5: Sanitization (15 pts)
    all_bks = _collect_bookmark_urls(bookmarks.get('roots', {}))
    banned_found = 0
    for bk in all_bks:
        url = bk.get('url', '').lower()
        if any(banned in url for banned in banned_domains):
            banned_found += 1
            
    if banned_found == 0 and len(all_bks) > 10:
        score += 15
        feedback_parts.append("[+] Personal bookmarks successfully purged.")
    else:
        feedback_parts.append(f"[-] Found {banned_found} personal bookmarks remaining.")

    # Criterion 6: Color Search Engine (10 pts)
    search_score = 0
    if web_data_path and os.path.exists(web_data_path):
        try:
            conn = sqlite3.connect(web_data_path)
            cursor = conn.cursor()
            cursor.execute("SELECT url FROM keywords WHERE keyword=?", (search_keyword,))
            row = cursor.fetchone()
            if row and "pantone.com/color-finder" in row[0]:
                search_score = 10
            conn.close()
        except Exception as e:
            logger.error(f"SQLite check failed: {e}")
            
    score += search_score
    if search_score == 10:
        feedback_parts.append("[+] Custom color search engine verified in Web Data.")
    else:
        feedback_parts.append("[-] Custom color search engine not found or incorrect.")

    # Cleanup temp files
    for p in [res_path, pref_path, loc_path, bk_path, web_data_path]:
        if p and os.path.exists(p):
            os.unlink(p)

    # Final logic
    key_criteria_met = always_open_pdf and (banned_found == 0) and (flags_found == len(expected_flags))
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": int(score),
        "feedback": "\n".join(feedback_parts)
    }