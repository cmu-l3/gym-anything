#!/usr/bin/env python3
"""
Verifier for Antiquities Provenance Workspace (antiquities_provenance_workspace@1)

Verifies modifications made to Chrome profile settings based on specification:
1. Bookmark Folder Creation
2. Bookmark Categorization
3. Data Purging (Personal Bookmarks)
4. Startup Behavior URLs
5. Site Permissions (Notifications blocked globally, select Popups allowed)
6. Font Accessibility
7. Download Management
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _copy_file(copy_from_env, container_paths, suffix='.json'):
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

    if os.path.exists(temp_path):
        os.unlink(temp_path)
    return None


def _collect_all_urls(node, urls=None):
    if urls is None:
        urls = []
    if isinstance(node, dict):
        if node.get('type') == 'url':
            urls.append(node.get('url', ''))
        for child in node.get('children', []):
            _collect_all_urls(child, urls)
    return urls


def _find_folder(children, folder_name):
    fname = folder_name.lower().replace(' ', '')
    for child in children:
        if child.get('type') == 'folder':
            cname = child.get('name', '').lower().replace(' ', '')
            if fname in cname:
                return child
    return None


def verify_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy Bookmarks from Container
    bookmarks_local = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Bookmarks",
        "/home/ga/.config/google-chrome-cdp/Default/Bookmarks"
    ])
    bookmarks_data = {}
    if bookmarks_local:
        try:
            with open(bookmarks_local, 'r') as f:
                bookmarks_data = json.load(f)
        except Exception:
            pass
        os.unlink(bookmarks_local)

    # Copy Preferences from Container
    prefs_local = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Preferences",
        "/home/ga/.config/google-chrome-cdp/Default/Preferences"
    ])
    prefs_data = {}
    if prefs_local:
        try:
            with open(prefs_local, 'r') as f:
                prefs_data = json.load(f)
        except Exception:
            pass
        os.unlink(prefs_local)

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []

    # 1. Folder Creation & 2. Bookmark Categorization
    expected_folders = metadata.get('expected_folders', [
        "Provenance & Stolen Art", "Museum Archives", "Auction Records", "Internal Admin"
    ])
    
    expected_mapping = {
        "Provenance & Stolen Art": ["fbi.gov", "interpol.int", "artloss.com", "lootedart.com"],
        "Museum Archives": ["metmuseum.org", "getty.edu", "britishmuseum.org", "louvre.fr"],
        "Auction Records": ["artnet.com", "sothebys.com", "christies.com", "artsy.net", "mutualart.com"],
        "Internal Admin": ["mail.google.com", "workday.com", "docusign.com"]
    }

    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    bb_children = bookmark_bar.get('children', [])

    folders_found = 0
    cat_score = 0
    for folder_name in expected_folders:
        folder_node = _find_folder(bb_children, folder_name)
        if folder_node:
            folders_found += 1
            urls_in_folder = [u.lower() for u in _collect_all_urls(folder_node)]
            expected_domains = expected_mapping.get(folder_name, [])
            matches = sum(1 for d in expected_domains if any(d in u for u in urls_in_folder))
            cat_score += (matches / len(expected_domains)) * (15.0 / len(expected_folders))

    folder_score = (folders_found / len(expected_folders)) * 15
    score += folder_score
    score += cat_score
    feedback_parts.append(f"Folders found: {folders_found}/{len(expected_folders)} ({folder_score:.1f} pts)")
    feedback_parts.append(f"Bookmark categorization ({cat_score:.1f} pts)")

    # 3. Data Purging
    all_urls = [u.lower() for u in _collect_all_urls(bookmarks_data.get('roots', {}))]
    personal_domains = metadata.get('personal_domains', ["netflix.com", "espn.com", "facebook.com", "hulu.com"])
    
    purged_count = 0
    for pd in personal_domains:
        if not any(pd in u for u in all_urls):
            purged_count += 1
    
    purge_score = (purged_count / len(personal_domains)) * 10
    score += purge_score
    feedback_parts.append(f"Data purging: {purged_count}/{len(personal_domains)} personal domains removed ({purge_score:.1f} pts)")

    # 4. Startup Behavior
    startup_score = 0
    session_prefs = prefs_data.get('session', {})
    restore_on_startup = session_prefs.get('restore_on_startup', 0)
    startup_urls = session_prefs.get('startup_urls', [])
    startup_urls_lower = [u.lower() for u in startup_urls]

    expected_startup = metadata.get('startup_urls', ["artloss.com", "artnet.com"])
    if restore_on_startup == 4:
        startup_score += 5
        matches = sum(1 for d in expected_startup if any(d in u for u in startup_urls_lower))
        startup_score += (matches / len(expected_startup)) * 10
    
    score += startup_score
    feedback_parts.append(f"Startup pages configured ({startup_score:.1f} pts)")

    # 5. Site Permissions
    perm_score = 0
    profile_prefs = prefs_data.get('profile', {})
    
    def_notifs = profile_prefs.get('default_content_setting_values', {}).get('notifications', 0)
    if def_notifs == 2:
        perm_score += 10
    
    popup_exceptions = profile_prefs.get('content_settings', {}).get('exceptions', {}).get('popups', {})
    expected_popups = metadata.get('popup_allow_domains', ["artnet.com", "metmuseum.org"])
    popup_matches = 0
    for exp_dom in expected_popups:
        for key, val in popup_exceptions.items():
            if exp_dom in key.lower() and val.get('setting') == 1:
                popup_matches += 1
                break
    
    perm_score += (popup_matches / len(expected_popups)) * 5
    score += perm_score
    feedback_parts.append(f"Site permissions configured ({perm_score:.1f} pts)")

    # 6. Typography
    typo_score = 0
    webprefs = prefs_data.get('webkit', {}).get('webprefs', {})
    exp_default_font = metadata.get('default_font_size', 18)
    exp_min_font = metadata.get('min_font_size', 14)
    
    if webprefs.get('default_font_size') == exp_default_font:
        typo_score += 8
    if webprefs.get('minimum_font_size') == exp_min_font:
        typo_score += 7
    
    score += typo_score
    feedback_parts.append(f"Font accessibility configured ({typo_score:.1f} pts)")

    # 7. Download Management
    dl_score = 0
    download_prefs = prefs_data.get('download', {})
    dl_dir = download_prefs.get('default_directory', '')
    exp_dir = metadata.get('download_dir', '/home/ga/Documents/Auction_Catalog_Assets')
    
    if dl_dir.rstrip('/') == exp_dir.rstrip('/'):
        dl_score += 8
    elif 'Auction_Catalog_Assets' in dl_dir:
        dl_score += 4
        
    if download_prefs.get('prompt_for_download') is True:
        dl_score += 7
        
    score += dl_score
    feedback_parts.append(f"Download management configured ({dl_score:.1f} pts)")

    # Passing Threshold Criteria
    passed = score >= 75 and purge_score == 10

    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " | ".join(feedback_parts)
    }