#!/usr/bin/env python3
"""
Verifier for Municipal Urban Planner Workspace (urban_planner_workspace@1)

Verifies multi-faceted configuration of Google Chrome:
1. Bookmark Folder structure and organization (20 pts)
2. Personal Bookmarks fully removed (10 pts)
3. History & Cookie Sanitization (anti-gaming: removed personal, kept pro) (20 pts)
4. Presentation Font Size to 18 (10 pts)
5. Spatial Download Configuration (15 pts)
6. Custom Search Engines (10 pts)
7. Startup Pages (15 pts)

Total points: 100. Pass threshold: 70 points AND Criterion 2 (Removal of Personal BMs) must be passed.
"""

import json
import logging
import os
import sqlite3
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PERSONAL_DOMAINS = [
    "netflix.com", "reddit.com", "x.com", "hulu.com", "steampowered.com",
    "twitch.tv", "facebook.com", "instagram.com", "tiktok.com", "espn.com",
    "draftkings.com", "pinterest.com", "etsy.com", "spotify.com", "tinder.com"
]

PRO_DOMAINS = [
    "egis.hud.gov", "msc.fema.gov", "openstreetmap.org", "earth.google.com",
    "ejscreen.epa.gov", "data.census.gov", "bls.gov", "bea.gov",
    "library.municode.com", "planning.org", "iccsafe.org", "nacto.org",
    "transit.dot.gov", "fhwa.dot.gov", "mutcd.fhwa.dot.gov", "strongtowns.org",
    "nextdoor.com", "polco.us", "publicinput.com", "planetizen.com"
]

EXPECTED_FOLDERS = ["GIS & Maps", "Demographics", "Zoning & Code", "Transportation", "Public Engagement"]


def _copy_file(copy_from_env, container_path: str, suffix: str = '') -> str:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    copy_from_env(container_path, tmp.name)
    return tmp.name


def _get_all_bookmark_urls(node):
    urls = []
    if isinstance(node, dict):
        if node.get('type') == 'url':
            urls.append(node.get('url', '').lower())
        for child in node.get('children', []):
            urls.extend(_get_all_bookmark_urls(child))
    return urls


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable."}

    score = 0
    feedback_parts = []
    
    try:
        # Copy required Chrome profile files
        bm_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks", ".json")
        pref_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences", ".json")
        hist_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/History", ".sqlite")
        cookie_path = _copy_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Cookies", ".sqlite")

        # 1. & 2. Bookmarks Analysis
        try:
            with open(bm_path, 'r') as f:
                bookmarks_data = json.load(f)
        except json.JSONDecodeError:
            bookmarks_data = {}

        bbar = bookmarks_data.get('roots', {}).get('bookmark_bar', {}).get('children', [])
        
        # Criterion 1: Folders
        folders_found = [c.get('name') for c in bbar if c.get('type') == 'folder']
        c1_score = 0
        for ef in EXPECTED_FOLDERS:
            if any(ef.lower() in f.lower() for f in folders_found):
                c1_score += 4
        
        score += c1_score
        feedback_parts.append(f"C1 Folders: {c1_score}/20 pts (Found: {folders_found})")

        # Criterion 2: Personal Domains removed from bookmarks
        all_bm_urls = _get_all_bookmark_urls(bookmarks_data.get('roots', {}))
        personal_bm_found = sum(1 for url in all_bm_urls if any(p in url for p in PERSONAL_DOMAINS))
        c2_score = 10 if personal_bm_found == 0 else 0
        score += c2_score
        feedback_parts.append(f"C2 Personal Bookmarks: {c2_score}/10 pts ({personal_bm_found} found)")

        # 3. History & Cookie Sanitization Analysis
        c3_score = 0
        try:
            conn_h = sqlite3.connect(hist_path)
            c_h = conn_h.cursor()
            c_h.execute("SELECT url FROM urls")
            h_urls = [row[0].lower() for row in c_h.fetchall()]
            conn_h.close()

            personal_hist = sum(1 for u in h_urls if any(p in u for p in PERSONAL_DOMAINS))
            pro_hist = sum(1 for u in h_urls if any(p in u for p in PRO_DOMAINS))

            conn_c = sqlite3.connect(cookie_path)
            c_c = conn_c.cursor()
            c_c.execute("SELECT host_key FROM cookies")
            c_hosts = [row[0].lower() for row in c_c.fetchall()]
            conn_c.close()

            personal_cook = sum(1 for h in c_hosts if any(p in h for p in PERSONAL_DOMAINS))
            pro_cook = sum(1 for h in c_hosts if any(p in h for p in PRO_DOMAINS))

            if personal_hist == 0 and pro_hist > 5:
                c3_score += 10
            if personal_cook == 0 and pro_cook > 5:
                c3_score += 10
            
            feedback_parts.append(f"C3 DB Sanitization: {c3_score}/20 pts (Pers Hist: {personal_hist}, Pers Cook: {personal_cook})")
        except sqlite3.Error as e:
            feedback_parts.append(f"C3 DB Error: {e}")

        # 4, 5, 6, 7. Preferences Analysis
        try:
            with open(pref_path, 'r') as f:
                prefs = json.load(f)
        except json.JSONDecodeError:
            prefs = {}

        # C4: Font Size
        font_size = prefs.get('webkit', {}).get('webprefs', {}).get('default_font_size', 16)
        c4_score = 10 if font_size == 18 else 0
        score += c4_score
        feedback_parts.append(f"C4 Font Size: {c4_score}/10 pts (Size: {font_size})")

        # C5: Download Config
        dl_dir = prefs.get('download', {}).get('default_directory', '').lower()
        dl_prompt = prefs.get('download', {}).get('prompt_for_download', False)
        c5_score = 0
        if "spatial_data" in dl_dir:
            c5_score += 8
        if dl_prompt is True:
            c5_score += 7
        score += c5_score
        feedback_parts.append(f"C5 Download Config: {c5_score}/15 pts")

        # C6: Custom Search
        search_str = json.dumps(prefs).lower()
        c6_score = 0
        if "municode" in search_str:
            c6_score += 5
        if "parcel" in search_str:
            c6_score += 5
        score += c6_score
        feedback_parts.append(f"C6 Search Engines: {c6_score}/10 pts")

        # C7: Startup Pages
        startup_type = prefs.get('session', {}).get('restore_on_startup', 0)
        startup_urls = [u.lower() for u in prefs.get('session', {}).get('startup_urls', [])]
        c7_score = 0
        if startup_type == 4:
            c7_score += 5
            if any("census.gov" in u for u in startup_urls):
                c7_score += 5
            if any("ejscreen.epa.gov" in u for u in startup_urls):
                c7_score += 5
        score += c7_score
        feedback_parts.append(f"C7 Startup Pages: {c7_score}/15 pts")

    finally:
        # Cleanup temp files
        for p in [bm_path, pref_path, hist_path, cookie_path]:
            if os.path.exists(p):
                os.unlink(p)

    key_criteria_met = (c2_score == 10)  # Personal Bookmarks MUST be removed
    passed = score >= 70 and key_criteria_met

    if not key_criteria_met:
        feedback_parts.append("CRITICAL FAILURE: Personal bookmarks were not fully removed.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }