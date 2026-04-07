#!/usr/bin/env python3
"""
Verifier for seed_bank_conservation_terminal@1

Criteria (100 points total):
1. Bookmark Folders (15 pts) - 4 specific folders exist.
2. Bookmark Cleanup (15 pts) - Zero personal domains remain.
3. Botany Categorization (15 pts) - Botanical bookmarks organized in folders.
4. Custom Search Engines (15 pts) - 'ipni' and 'wfo' keywords exist.
5. PDF Download Preference (15 pts) - always_open_pdf_externally is true.
6. Download Directory (10 pts) - Set to Field_Season_2026.
7. Browser-Initiated Downloads (15 pts) - Downloads appear in Chrome SQLite History.
"""

import os
import sys
import json
import sqlite3
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Personal domains that should be deleted
PERSONAL_DOMAINS = [
    "reddit.com", "youtube.com", "netflix.com", "facebook.com", "spotify.com",
    "steampowered.com", "twitter.com", "instagram.com", "amazon.com", "ebay.com",
    "espn.com", "weather.com", "craigslist.org", "pinterest.com", "tumblr.com"
]

# Required Botanical folders (case insensitive partial match acceptable)
REQUIRED_FOLDERS = ["taxonomy", "seed biology", "permitting", "field operations"]

def _copy_file(copy_from_env, container_path, suffix='.dat'):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    try:
        copy_from_env(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
    except Exception as e:
        logger.debug(f"Failed to copy {container_path}: {e}")
    if os.path.exists(tmp.name):
        os.unlink(tmp.name)
    return None

def extract_all_urls(node, urls_list):
    """Recursively extract all URLs from bookmark node."""
    if node.get('type') == 'url':
        urls_list.append(node.get('url', '').lower())
    for child in node.get('children', []):
        extract_all_urls(child, urls_list)

def verify_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch files
    result_local = _copy_file(copy_from_env, "/tmp/task_result.json", ".json")
    bookmarks_local = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks", ".json")
    prefs_local = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences", ".json")
    history_local = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/History", ".sqlite")
    webdata_local = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Web Data", ".sqlite")

    try:
        # Load JSONs
        if result_local:
            with open(result_local, 'r') as f:
                task_result = json.load(f)
        else:
            task_result = {}

        if bookmarks_local:
            with open(bookmarks_local, 'r') as f:
                bookmarks_data = json.load(f)
        else:
            bookmarks_data = {}

        if prefs_local:
            with open(prefs_local, 'r') as f:
                prefs_data = json.load(f)
        else:
            prefs_data = {}

        # -------------------------------------------------------------------
        # Criterion 1 & 3: Bookmark Folders (15) & Categorization (15)
        # -------------------------------------------------------------------
        found_folders = []
        botanical_in_folders = 0
        bookmark_bar = bookmarks_data.get("roots", {}).get("bookmark_bar", {})
        
        for child in bookmark_bar.get("children", []):
            if child.get("type") == "folder":
                fname = child.get("name", "").lower()
                for req in REQUIRED_FOLDERS:
                    if req in fname and req not in found_folders:
                        found_folders.append(req)
                
                # Check how many items are inside folders
                f_urls = []
                extract_all_urls(child, f_urls)
                botanical_in_folders += len(f_urls)

        # Score folders (15 pts total)
        folder_score = (len(found_folders) / len(REQUIRED_FOLDERS)) * 15
        score += folder_score
        feedback_parts.append(f"Bookmark Folders: Found {len(found_folders)}/{len(REQUIRED_FOLDERS)} ({folder_score:.1f}/15 pts)")

        # Score categorization (15 pts total) - We expect ~20 items to be in these folders
        cat_score = min(15, (botanical_in_folders / 20.0) * 15)
        score += cat_score
        feedback_parts.append(f"Botany Categorization: {botanical_in_folders} items in folders ({cat_score:.1f}/15 pts)")

        # -------------------------------------------------------------------
        # Criterion 2: Bookmark Cleanup (15)
        # -------------------------------------------------------------------
        all_urls = []
        for root_key in ["bookmark_bar", "other", "synced"]:
            extract_all_urls(bookmarks_data.get("roots", {}).get(root_key, {}), all_urls)
        
        personal_found = 0
        for u in all_urls:
            if any(pd in u for pd in PERSONAL_DOMAINS):
                personal_found += 1
                
        if personal_found == 0:
            score += 15
            feedback_parts.append("Bookmark Cleanup: 0 personal domains found (15/15 pts)")
        else:
            cleanup_penalty = min(15, personal_found)
            score += (15 - cleanup_penalty)
            feedback_parts.append(f"Bookmark Cleanup: {personal_found} personal domains remained ({(15 - cleanup_penalty)}/15 pts)")

        # -------------------------------------------------------------------
        # Criterion 4: Custom Search Engines (15)
        # -------------------------------------------------------------------
        ipni_found = False
        wfo_found = False
        
        # Check in Web Data SQLite
        if webdata_local:
            try:
                conn = sqlite3.connect(webdata_local)
                c = conn.cursor()
                c.execute("SELECT keyword, url FROM keywords")
                for row in c.fetchall():
                    kw, url = row[0].lower(), row[1].lower()
                    if 'ipni' in kw and 'ipni.org' in url:
                        ipni_found = True
                    if 'wfo' in kw and 'worldfloraonline' in url:
                        wfo_found = True
                conn.close()
            except sqlite3.Error as e:
                logger.warning(f"Web Data DB query failed: {e}")

        # Check in Preferences JSON fallback
        if not (ipni_found and wfo_found):
            for provider in prefs_data.get('default_search_provider_data', {}).get('template_url_data', {}).values():
                if isinstance(provider, str):
                    if 'ipni' in provider.lower(): ipni_found = True
                    if 'worldfloraonline' in provider.lower(): wfo_found = True

        se_score = 0
        if ipni_found: se_score += 7.5
        if wfo_found: se_score += 7.5
        score += se_score
        feedback_parts.append(f"Custom Search Engines: IPNI={ipni_found}, WFO={wfo_found} ({se_score}/15 pts)")

        # -------------------------------------------------------------------
        # Criterion 5: PDF Download Preference (15)
        # -------------------------------------------------------------------
        pdf_externally = prefs_data.get('plugins', {}).get('always_open_pdf_externally', False)
        if pdf_externally is True:
            score += 15
            feedback_parts.append("PDF Download Preference: Set correctly to True (15/15 pts)")
        else:
            feedback_parts.append("PDF Download Preference: Not set to download PDFs (0/15 pts)")

        # -------------------------------------------------------------------
        # Criterion 6: Download Directory (10)
        # -------------------------------------------------------------------
        dl_dir = prefs_data.get('download', {}).get('default_directory', '')
        if 'Field_Season_2026' in dl_dir:
            score += 10
            feedback_parts.append("Download Directory: Target set correctly (10/10 pts)")
        else:
            feedback_parts.append("Download Directory: Target NOT set correctly (0/10 pts)")

        # -------------------------------------------------------------------
        # Criterion 7: Browser-Initiated Downloads (15)
        # -------------------------------------------------------------------
        dl_score = 0
        pdfs_found_sqlite = 0
        if history_local:
            try:
                conn = sqlite3.connect(history_local)
                c = conn.cursor()
                c.execute("SELECT target_path FROM downloads")
                for row in c.fetchall():
                    path = row[0]
                    if 'Field_Season_2026' in path and path.endswith('.pdf'):
                        if 'USDA_PPQ_587' in path or 'CITES_Export_App' in path or 'Field_Collection_Manifest' in path:
                            pdfs_found_sqlite += 1
                conn.close()
            except sqlite3.Error as e:
                logger.warning(f"History DB query failed: {e}")

        # Need exactly 3 to max it, 5 pts each
        dl_score = min(15, pdfs_found_sqlite * 5)
        score += dl_score
        feedback_parts.append(f"Browser-Initiated Downloads: Found {pdfs_found_sqlite}/3 in Chrome History ({dl_score}/15 pts)")

    finally:
        # Cleanup
        for path in [result_local, bookmarks_local, prefs_local, history_local, webdata_local]:
            if path and os.path.exists(path):
                try:
                    os.unlink(path)
                except:
                    pass

    # Success conditions
    key_criteria_met = (pdf_externally is True) and (pdfs_found_sqlite >= 3)
    passed = score >= 70 and key_criteria_met

    if not key_criteria_met:
        feedback_parts.append("CRITICAL: Failed key criteria (PDF handling forced download AND 3 files downloaded via Chrome)")

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": "\n".join(feedback_parts)
    }