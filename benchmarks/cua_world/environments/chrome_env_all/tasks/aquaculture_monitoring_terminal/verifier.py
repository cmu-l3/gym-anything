#!/usr/bin/env python3
"""
Verifier for Aquaculture Monitoring Terminal task (aquaculture_monitoring_terminal@1)

Verifies:
1. Bookmark Organization: 4 expected folders exist and contain work URLs.
2. Bookmark Purging: Unauthorized domains are removed entirely.
3. Startup Pages: NOAA and 10.0.0.50 set to open on startup.
4. Performance Exceptions: Local IPs and NOAA domain added to Memory Saver exceptions.
5. Insecure Content: Local IPs allowed to load insecure content.
6. Search Engines: 'fb' and 'hach' shortcuts configured correctly.
7. VLM Trajectory: Agent used the UI to configure settings (anti-gaming).
"""

import json
import logging
import os
import sqlite3
import sys
import tempfile
from typing import Dict, Any, List

# Add utils to path for VLM
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'utils'))
try:
    from vlm_utils import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _copy_file_from_env(copy_from_env, container_path: str, suffix: str = '') -> str:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    try:
        copy_from_env(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
    except Exception as e:
        logger.warning(f"Failed to copy {container_path}: {e}")
    if os.path.exists(tmp.name):
        os.unlink(tmp.name)
    return None

def _get_all_bookmark_urls(node: Dict, urls: List[str]):
    if node.get('type') == 'url':
        urls.append(node.get('url', '').lower())
    for child in node.get('children', []):
        _get_all_bookmark_urls(child, urls)

def verify_task(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    metadata = task_info.get('metadata', {})
    expected_folders = [f.lower() for f in metadata.get('folders', [])]
    unauthorized_domains = metadata.get('unauthorized_domains', [])
    startup_urls_expect = metadata.get('startup_urls', [])
    perf_exceptions_expect = metadata.get('performance_exceptions', [])
    insecure_ips_expect = metadata.get('insecure_content_ips', [])
    expected_search = metadata.get('search_engines', {})

    score = 0
    feedback_parts = []
    
    # --- Data Extraction ---
    bookmarks_path = _copy_file_from_env(copy_from_env, "/tmp/chrome_export/Bookmarks", ".json")
    prefs_path = _copy_file_from_env(copy_from_env, "/tmp/chrome_export/Preferences", ".json")
    web_data_path = _copy_file_from_env(copy_from_env, "/tmp/chrome_export/Web Data", ".sqlite")
    
    bookmarks = {}
    if bookmarks_path:
        with open(bookmarks_path, 'r', encoding='utf-8') as f:
            bookmarks = json.load(f)
            
    prefs = {}
    if prefs_path:
        with open(prefs_path, 'r', encoding='utf-8') as f:
            prefs = json.load(f)

    # --- Criteria 1: Bookmark Organization (15 pts) ---
    found_folders = []
    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
    for child in bookmark_bar.get('children', []):
        if child.get('type') == 'folder':
            found_folders.append(child.get('name', '').lower())
    
    folders_found_count = sum(1 for ef in expected_folders if ef in found_folders)
    if folders_found_count == len(expected_folders):
        score += 15
        feedback_parts.append("✅ Bookmark Organization: All 4 folders created correctly.")
    elif folders_found_count > 0:
        pts = int((folders_found_count / len(expected_folders)) * 15)
        score += pts
        feedback_parts.append(f"⚠️ Bookmark Organization: {folders_found_count}/4 folders created ({pts} pts).")
    else:
        feedback_parts.append("❌ Bookmark Organization: Required folders not found.")

    # --- Criteria 2: Bookmark Purging (15 pts) ---
    all_urls = []
    for root in bookmarks.get('roots', {}).values():
        if isinstance(root, dict):
            _get_all_bookmark_urls(root, all_urls)
            
    unauthorized_found = 0
    for url in all_urls:
        if any(bad_domain in url for bad_domain in unauthorized_domains):
            unauthorized_found += 1
            
    if unauthorized_found == 0 and len(all_urls) > 0:
        score += 15
        feedback_parts.append("✅ Bookmark Purging: All unauthorized bookmarks deleted.")
    else:
        feedback_parts.append(f"❌ Bookmark Purging: {unauthorized_found} unauthorized domains still exist in bookmarks.")

    # --- Criteria 3: Startup Pages (10 pts) ---
    session_restore = prefs.get('session', {}).get('restore_on_startup', 0)
    startup_urls = prefs.get('session', {}).get('startup_urls', [])
    
    startup_matches = 0
    for expect in startup_urls_expect:
        if any(expect in su for su in startup_urls):
            startup_matches += 1
            
    if session_restore == 4 and startup_matches == len(startup_urls_expect):
        score += 10
        feedback_parts.append("✅ Startup Pages: Configured correctly.")
    elif startup_matches > 0:
        score += 5
        feedback_parts.append(f"⚠️ Startup Pages: Partially configured ({startup_matches}/{len(startup_urls_expect)} URLs found).")
    else:
        feedback_parts.append("❌ Startup Pages: Not configured correctly.")

    # --- Criteria 4: Performance Exceptions (25 pts) ---
    exceptions = prefs.get('profile', {}).get('performance_tuning', {}).get('tab_discarding', {}).get('exceptions_with_time', {})
    exc_keys = [k.lower() for k in exceptions.keys()]
    
    perf_matches = 0
    for expect in perf_exceptions_expect:
        if any(expect in k for k in exc_keys):
            perf_matches += 1
            
    if perf_matches == len(perf_exceptions_expect):
        score += 25
        feedback_parts.append("✅ Performance Exceptions: All IPs/domains added to Memory Saver whitelist.")
    elif perf_matches > 0:
        pts = int((perf_matches / len(perf_exceptions_expect)) * 25)
        score += pts
        feedback_parts.append(f"⚠️ Performance Exceptions: {perf_matches}/{len(perf_exceptions_expect)} added ({pts} pts).")
    else:
        feedback_parts.append("❌ Performance Exceptions: None found in tab discarding exceptions.")

    # --- Criteria 5: Insecure Content Allowed (20 pts) ---
    insecure = prefs.get('profile', {}).get('content_settings', {}).get('exceptions', {}).get('insecure_content', {})
    ins_keys = [k.lower() for k, v in insecure.items() if v.get('setting') == 1]
    
    ins_matches = 0
    for expect in insecure_ips_expect:
        if any(expect in k for k in ins_keys):
            ins_matches += 1
            
    if ins_matches == len(insecure_ips_expect):
        score += 20
        feedback_parts.append("✅ Insecure Content: All local IoT IPs allowed.")
    elif ins_matches > 0:
        pts = int((ins_matches / len(insecure_ips_expect)) * 20)
        score += pts
        feedback_parts.append(f"⚠️ Insecure Content: {ins_matches}/{len(insecure_ips_expect)} IPs allowed ({pts} pts).")
    else:
        feedback_parts.append("❌ Insecure Content: Settings not modified for local IPs.")

    # --- Criteria 6: Search Engines (15 pts) ---
    search_score = 0
    if web_data_path:
        try:
            conn = sqlite3.connect(web_data_path)
            cursor = conn.cursor()
            cursor.execute("SELECT keyword, url FROM keywords")
            engines = cursor.fetchall()
            conn.close()
            
            fb_found, hach_found = False, False
            for kw, url in engines:
                if 'fb' in kw.lower() and expected_search['fb'] in url:
                    fb_found = True
                if 'hach' in kw.lower() and expected_search['hach'] in url:
                    hach_found = True
            
            if fb_found: search_score += 7.5
            if hach_found: search_score += 7.5
            
            score += search_score
            if search_score == 15:
                feedback_parts.append("✅ Search Shortcuts: 'fb' and 'hach' correctly configured.")
            elif search_score > 0:
                feedback_parts.append("⚠️ Search Shortcuts: Partially configured.")
            else:
                feedback_parts.append("❌ Search Shortcuts: Not configured in Web Data.")
        except Exception as e:
            feedback_parts.append(f"❌ Search Shortcuts: Error querying SQLite DB - {e}")
    else:
        feedback_parts.append("❌ Search Shortcuts: Could not extract Web Data DB.")

    # --- VLM Anti-Gaming Verification ---
    vlm_passed = False
    if VLM_AVAILABLE:
        query_vlm_fn = env_info.get('query_vlm')
        if query_vlm_fn:
            try:
                frames = sample_trajectory_frames(traj, n=4)
                if frames:
                    vlm_prompt = """Look at these screenshots from a user's browser session. 
Did the user interact with the Chrome Settings pages? Specifically, look for 'chrome://settings', the 'Performance' page, or the 'Site settings' page. 
We want to verify the user actually clicked through the UI to configure the browser.
Reply in JSON: {"used_settings_ui": true/false}"""
                    vlm_res = query_vlm_fn(prompt=vlm_prompt, images=frames)
                    vlm_passed = vlm_res.get('parsed', {}).get('used_settings_ui', False)
                    if vlm_passed:
                        feedback_parts.append("✅ VLM Check: UI interaction verified.")
                    else:
                        feedback_parts.append("⚠️ VLM Check: Could not clearly verify settings UI usage in trajectory.")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
    
    # Cleanup
    for path in [bookmarks_path, prefs_path, web_data_path]:
        if path and os.path.exists(path):
            try: os.unlink(path)
            except: pass

    # Critical failure: Must have done SOME performance/security configuration
    key_criteria_met = (perf_matches > 0) or (ins_matches > 0)
    passed = (score >= 75) and key_criteria_met

    if not key_criteria_met:
        feedback_parts.append("❌ CRITICAL: Core technical goals (Performance / Insecure Content) not met.")

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": "\n".join(feedback_parts)
    }