#!/usr/bin/env python3
"""
Verifier for Investigative OPSEC Workspace (investigative_opsec_workspace@1)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_bookmark_nodes(node: Dict, type_filter: Optional[str] = None) -> List[Dict]:
    """Recursively fetch all bookmark nodes matching a type."""
    nodes = []
    if isinstance(node, dict):
        if type_filter is None or node.get('type') == type_filter:
            nodes.append(node)
        for child in node.get('children', []):
            nodes.extend(get_bookmark_nodes(child, type_filter))
    return nodes

def verify_opsec_workspace(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Temporary files
    tmp_bookmarks = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    tmp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    tmp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    try:
        # Copy from environment
        copy_from_env('/home/ga/.config/google-chrome/Default/Bookmarks', tmp_bookmarks)
        copy_from_env('/home/ga/.config/google-chrome/Default/Preferences', tmp_prefs)
        copy_from_env('/tmp/export_metadata.json', tmp_meta)

        with open(tmp_bookmarks, 'r', encoding='utf-8') as f:
            bookmarks = json.load(f)
        with open(tmp_prefs, 'r', encoding='utf-8') as f:
            prefs = json.load(f)
        with open(tmp_meta, 'r', encoding='utf-8') as f:
            meta = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to read Chrome files: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read Chrome profile data. Did the agent open Chrome?"}
    finally:
        for p in [tmp_bookmarks, tmp_prefs, tmp_meta]:
            if os.path.exists(p):
                os.unlink(p)

    score = 0
    feedback = []
    metadata = task_info.get('metadata', {})
    
    # ---------------------------------------------------------
    # Anti-gaming: Ensure files were actually modified
    # ---------------------------------------------------------
    if meta.get("preferences_mtime", 0) == 0:
        return {"passed": False, "score": 0, "feedback": "Chrome Preferences file not found/modified. Task not attempted."}

    # ---------------------------------------------------------
    # Criterion 1 & 2: Folder Existence & Categorization (30 pts)
    # ---------------------------------------------------------
    expected_folders = metadata.get("expected_folders", ["Secure Comms", "Public Records", "Target Intel", "News Outlets"])
    bbar = bookmarks.get("roots", {}).get("bookmark_bar", {})
    bbar_children = bbar.get("children", [])
    
    found_folders = {}
    for child in bbar_children:
        if child.get("type") == "folder":
            name_lower = child.get("name", "").lower()
            for ef in expected_folders:
                if ef.lower() in name_lower:
                    found_folders[ef] = child

    folder_pts = 0
    cat_pts = 0
    for ef in expected_folders:
        if ef in found_folders:
            folder_pts += 3.75
            # Check if it has bookmarks inside
            urls = get_bookmark_nodes(found_folders[ef], "url")
            if len(urls) >= 3: # Expecting around 5 per category
                cat_pts += 3.75

    score += folder_pts
    score += cat_pts
    feedback.append(f"Folders found: {len(found_folders)}/{len(expected_folders)} ({folder_pts:.1f}/15 pts)")
    feedback.append(f"Categorization: {cat_pts:.1f}/15 pts")

    # ---------------------------------------------------------
    # Criterion 3: Personal Sites Purged (15 pts)
    # ---------------------------------------------------------
    personal_domains = metadata.get("personal_domains_to_purge", ["netflix.com", "hulu.com", "facebook.com", "instagram.com", "twitter.com"])
    all_urls = [u.get("url", "").lower() for u in get_bookmark_nodes(bookmarks, "url")]
    
    purged_count = 0
    for pd in personal_domains:
        if not any(pd in url for url in all_urls):
            purged_count += 1
            
    purge_pts = purged_count * 3
    score += purge_pts
    feedback.append(f"Personal sites purged: {purged_count}/{len(personal_domains)} ({purge_pts}/15 pts)")

    # ---------------------------------------------------------
    # Criterion 4: Hardware & Permissions Locked (20 pts)
    # ---------------------------------------------------------
    content_settings = prefs.get("profile", {}).get("default_content_setting_values", {})
    
    perms = [
        ("Location", content_settings.get("geolocation")),
        ("Camera", content_settings.get("media_stream_camera")),
        ("Microphone", content_settings.get("media_stream_mic")),
        ("Background Sync", content_settings.get("background_sync"))
    ]
    
    perm_pts = 0
    for name, val in perms:
        if val == 2: # 2 means BLOCK in Chrome
            perm_pts += 5
            
    score += perm_pts
    feedback.append(f"Hardware/Site permissions blocked: {perm_pts}/20 pts")

    # ---------------------------------------------------------
    # Criterion 5: Anti-Telemetry Configured (15 pts)
    # ---------------------------------------------------------
    telemetry_pts = 0
    
    # Block 3rd party cookies (cookie_controls_mode == 1 means block third-party)
    if prefs.get("profile", {}).get("cookie_controls_mode") == 1:
        telemetry_pts += 5
        
    # Do Not Track
    if prefs.get("enable_do_not_track") is True:
        telemetry_pts += 5
        
    # Safe Browsing Disabled
    safebrowsing = prefs.get("safebrowsing", {})
    if safebrowsing.get("enabled") is False or prefs.get("profile", {}).get("safebrowsing", {}).get("enabled") is False:
        telemetry_pts += 5
        
    score += telemetry_pts
    feedback.append(f"Privacy & Anti-Telemetry configured: {telemetry_pts}/15 pts")

    # ---------------------------------------------------------
    # Criterion 6: Search Engines (10 pts)
    # ---------------------------------------------------------
    prefs_str = json.dumps(prefs).lower()
    search_engines = metadata.get("search_engines", ["pacer", "offshore"])
    
    se_pts = 0
    for se in search_engines:
        if f'"keyword": "{se}"' in prefs_str or f'{se}' in prefs_str:
            # Check for the distinct URLs to be robust
            if se == "pacer" and ("hconnect.pacer" in prefs_str):
                se_pts += 5
            elif se == "offshore" and ("offshoreleaks.icij" in prefs_str):
                se_pts += 5
                
    score += se_pts
    feedback.append(f"OSINT Search Engines configured: {se_pts}/10 pts")

    # ---------------------------------------------------------
    # Criterion 7: Secure Download Path (10 pts)
    # ---------------------------------------------------------
    dl_pts = 0
    dl_dir = metadata.get("download_dir", "Secure_Vault")
    
    download_settings = prefs.get("download", {})
    default_dir = download_settings.get("default_directory", "")
    prompt_dl = download_settings.get("prompt_for_download", False)
    
    if dl_dir in default_dir:
        dl_pts += 5
    if prompt_dl is True:
        dl_pts += 5
        
    score += dl_pts
    feedback.append(f"Download security configured: {dl_pts}/10 pts")

    # ---------------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------------
    passed = score >= 75 and (purged_count == len(personal_domains))
    
    if score >= 75 and purged_count < len(personal_domains):
        feedback.append("CRITICAL: Pass threshold met, but personal sites were not fully purged. FAILED.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }