#!/usr/bin/env python3
"""
Verifier for Beverage Director Cellar Workspace Setup (beverage_director_workspace@1)

Verifies:
1. Bookmark Import & Organization (4 folders, no loose bookmarks on bar)
2. Junk Bookmark Deletion (ESPN, Netflix, Facebook, X/Twitter completely gone)
3. Accessibility Font Settings (default=18, min=14)
4. Translation Enabled
5. Download Configuration (Tech_Sheets path created and set, prompt enabled)
6. Chrome Flags Configured (smooth-scrolling, parallel-downloading)
7. Search & Startup Pages (ws, gs search engines; startup URLs set)
"""

import os
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _copy_file(copy_fn, container_path: str, suffix: str = '.tmp') -> Optional[str]:
    """Helper to copy a file from the container to a local temp path."""
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        tmp.close()
        copy_fn(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
        os.unlink(tmp.name)
    except Exception as e:
        logger.debug(f"Failed to copy {container_path}: {e}")
        try:
            os.unlink(tmp.name)
        except:
            pass
    return None

def _get_all_bookmarks(node: dict, collected: list = None) -> list:
    if collected is None:
        collected = []
    if isinstance(node, dict):
        if node.get('type') == 'url':
            collected.append(node)
        for child in node.get('children', []):
            _get_all_bookmarks(child, collected)
    return collected

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available."}

    # Files to copy
    bookmarks_path = "/home/ga/.config/google-chrome/Default/Bookmarks"
    prefs_path = "/home/ga/.config/google-chrome/Default/Preferences"
    local_state_path = "/home/ga/.config/google-chrome/Local State"
    web_data_path = "/home/ga/.config/google-chrome/Default/Web Data"
    result_path = "/tmp/task_result.json"

    tmp_bookmarks = _copy_file(copy_from_env, bookmarks_path, '.json')
    tmp_prefs = _copy_file(copy_from_env, prefs_path, '.json')
    tmp_local = _copy_file(copy_from_env, local_state_path, '.json')
    tmp_webdata = _copy_file(copy_from_env, web_data_path, '.sqlite')
    tmp_result = _copy_file(copy_from_env, result_path, '.json')

    try:
        # Load JSONs
        bookmarks = {}
        if tmp_bookmarks:
            try:
                with open(tmp_bookmarks, 'r') as f:
                    bookmarks = json.load(f)
            except: pass

        prefs = {}
        if tmp_prefs:
            try:
                with open(tmp_prefs, 'r') as f:
                    prefs = json.load(f)
            except: pass
            
        local_state = {}
        if tmp_local:
            try:
                with open(tmp_local, 'r') as f:
                    local_state = json.load(f)
            except: pass
            
        result_state = {}
        if tmp_result:
            try:
                with open(tmp_result, 'r') as f:
                    result_state = json.load(f)
            except: pass

        score = 0
        max_score = 100
        feedback_parts = []
        
        # 1. Bookmark Import & Organization (25 points)
        # 4 folders * 5 points + 5 points for no loose bookmarks
        bm_score = 0
        expected_folders = ["Old World Appellations", "New World Regions", "Distributors & Allocations", "Education & Reference"]
        
        bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
        
        folders_found = []
        loose_bookmarks = 0
        for child in children:
            if child.get('type') == 'folder':
                folders_found.append(child.get('name', ''))
            elif child.get('type') == 'url':
                loose_bookmarks += 1

        for ef in expected_folders:
            # Check case-insensitive
            if any(ef.lower() in f.lower() for f in folders_found):
                bm_score += 5
                
        if loose_bookmarks == 0 and len(folders_found) > 0:
            bm_score += 5
            
        score += bm_score
        feedback_parts.append(f"Bookmark Organization: {bm_score}/25 (Found folders: {folders_found}, Loose links: {loose_bookmarks})")

        # 2. Junk Bookmark Deletion (10 points)
        junk_domains = ["espn.com", "netflix.com", "facebook.com", "x.com", "twitter.com"]
        all_bms = _get_all_bookmarks(bookmarks)
        junk_found = 0
        for bm in all_bms:
            url = bm.get('url', '').lower()
            if any(jd in url for jd in junk_domains):
                junk_found += 1
                
        junk_score = max(0, 10 - (junk_found * 3))
        if junk_score == 10:
            score += 10
            feedback_parts.append("Junk Bookmarks: 10/10 (All junk removed)")
        else:
            score += junk_score
            feedback_parts.append(f"Junk Bookmarks: {junk_score}/10 ({junk_found} junk domains still present)")

        # 3. Accessibility Font Settings (15 points)
        webprefs = prefs.get('webkit', {}).get('webprefs', {})
        def_font = webprefs.get('default_font_size', 16)
        min_font = webprefs.get('minimum_font_size', 0)
        
        font_score = 0
        if def_font == 18:
            font_score += 7.5
        if min_font == 14:
            font_score += 7.5
            
        score += font_score
        feedback_parts.append(f"Fonts: {font_score}/15 (Default: {def_font}, Min: {min_font})")

        # 4. Translation Enabled (10 points)
        trans_enabled = prefs.get('translate', {}).get('enabled', False)
        if trans_enabled:
            score += 10
            feedback_parts.append("Translation: 10/10 (Enabled)")
        else:
            feedback_parts.append("Translation: 0/10 (Not enabled)")

        # 5. Download Configuration (10 points)
        dl_dir = prefs.get('download', {}).get('default_directory', '')
        dl_prompt = prefs.get('download', {}).get('prompt_for_download', False)
        dir_created = result_state.get('tech_sheets_dir_exists', False)
        
        dl_score = 0
        if "Tech_Sheets" in dl_dir and dir_created:
            dl_score += 5
        if dl_prompt:
            dl_score += 5
            
        score += dl_score
        feedback_parts.append(f"Downloads: {dl_score}/10 (Path correct: {'Tech_Sheets' in dl_dir}, Prompt: {dl_prompt})")

        # 6. Chrome Flags Configured (15 points)
        flags = local_state.get('browser', {}).get('enabled_labs_experiments', [])
        flag_score = 0
        if any("smooth-scrolling" in f for f in flags):
            flag_score += 7.5
        if any("enable-parallel-downloading" in f for f in flags):
            flag_score += 7.5
            
        score += flag_score
        feedback_parts.append(f"Flags: {flag_score}/15 (Found {len(flags)} custom flags)")

        # 7. Search & Startup Pages (15 points)
        startup_score = 0
        startup_urls = prefs.get('session', {}).get('startup_urls', [])
        restore_type = prefs.get('session', {}).get('restore_on_startup', 0)
        
        if restore_type == 4: # Open specific pages
            if any("sevenfifty.com" in u for u in startup_urls):
                startup_score += 5
            if any("binwise.com" in u for u in startup_urls):
                startup_score += 5
                
        search_score = 0
        if tmp_webdata:
            try:
                conn = sqlite3.connect(tmp_webdata)
                cursor = conn.cursor()
                cursor.execute("SELECT keyword, url FROM keywords")
                rows = cursor.fetchall()
                found_ws = any('ws' == r[0] for r in rows)
                found_gs = any('gs' == r[0] for r in rows)
                if found_ws and found_gs:
                    search_score = 5
                elif found_ws or found_gs:
                    search_score = 2.5
                conn.close()
            except Exception as e:
                logger.debug(f"SQLite error: {e}")
                
        total_s7 = startup_score + search_score
        score += total_s7
        feedback_parts.append(f"Search & Startup: {total_s7}/15")

        score = int(score)
        passed = score >= 75 and bm_score >= 15 and junk_score >= 8
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    finally:
        # Cleanup
        for p in [tmp_bookmarks, tmp_prefs, tmp_local, tmp_webdata, tmp_result]:
            if p and os.path.exists(p):
                os.unlink(p)