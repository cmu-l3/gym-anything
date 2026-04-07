#!/usr/bin/env python3
"""
Verifier for financial_forensics_workspace@1

Task: Configure browser per OpSec guidelines:
- Bookmark organization into 4 specific folders
- Delete personal bookmarks
- Custom search engine shortcuts (oc, icij, ofac)
- Privacy hardening (3rd party cookies, DNT, Safe Browsing)
- Download path and prompt
- Startup pages

Scoring (100 points total):
1. Investigative Folders Created (20 pts)
2. Bookmarks Categorized (15 pts)
3. Personal Bookmarks Deleted (15 pts)
4. Custom Search Engines (15 pts)
5. Privacy & Security Hardening (15 pts)
6. Download Configuration (10 pts)
7. Startup Pages (10 pts)
"""

import os
import json
import logging
import sqlite3
import tempfile
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _copy_file(copy_from_env, paths, suffix=''):
    """Copy a file from the container, trying multiple possible paths."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    
    for p in paths:
        try:
            copy_from_env(p, tmp.name)
            if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
                return tmp.name
        except Exception:
            pass
            
    if os.path.exists(tmp.name):
        os.unlink(tmp.name)
    return None


def check_folders_and_bookmarks(bookmarks_data: Dict) -> Tuple[int, str, int, str]:
    score_folders = 0
    score_categorized = 0
    feedback_folders = []
    feedback_cat = []
    
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    expected_folders = {
        'Sanctions & Watchlists': ['ofac.treas.gov', 'un.org', 'sanctionsmap.eu', 'fatf-gafi.org'],
        'Corporate Registries': ['opencorporates.com', 'gov.uk', 'sec.gov', 'delaware.gov', 'zefix.ch'],
        'Intelligence Databases': ['offshoreleaks.icij.org', 'aleph.occrp.org', 'investigativedashboard.org'],
        'Asset Tracking': ['zillow.com', 'a836-acris.nyc.gov', 'marinetraffic.com', 'flightradar24.com']
    }
    
    correctly_categorized = 0
    
    for folder_name, expected_domains in expected_folders.items():
        folder = None
        for child in children:
            if child.get('type') == 'folder' and child.get('name', '').lower() == folder_name.lower():
                folder = child
                break
                
        if folder:
            score_folders += 5
            feedback_folders.append(f"    - Folder '{folder_name}' found: Yes (+5)")
            for bm in folder.get('children', []):
                if bm.get('type') == 'url':
                    url = bm.get('url', '').lower()
                    if any(d in url for d in expected_domains):
                        correctly_categorized += 1
        else:
            feedback_folders.append(f"    - Folder '{folder_name}' found: No")
            
    if correctly_categorized >= 12:
        score_categorized = 15
    elif correctly_categorized >= 8:
        score_categorized = 10
    elif correctly_categorized >= 4:
        score_categorized = 5
        
    feedback_cat.append(f"    - Professional bookmarks categorized: {correctly_categorized}/16 (+{score_categorized})")
    
    return score_folders, "\n".join(feedback_folders), score_categorized, "\n".join(feedback_cat)


def check_personal_deleted(bookmarks_data: Dict) -> Tuple[int, str]:
    score = 0
    personal_domains = ['facebook.com', 'pinterest.com', 'amazon.com', 'netflix.com', 'spotify.com', 'expedia.com', 'tripadvisor.com']
    
    all_urls = []
    def extract_urls(node):
        if node.get('type') == 'url':
            all_urls.append(node.get('url', '').lower())
        for child in node.get('children', []):
            extract_urls(child)
            
    roots = bookmarks_data.get('roots', {})
    for _, root_node in roots.items():
        if isinstance(root_node, dict):
            extract_urls(root_node)
            
    found_personal = sum(1 for url in all_urls if any(d in url for d in personal_domains))
            
    if found_personal == 0:
        score = 15
        return score, "    - Personal bookmarks deleted: Yes (+15)"
    else:
        return score, f"    - Personal bookmarks deleted: No ({found_personal} personal bookmarks still found)"


def check_search_engines(copy_from_env, prefs_data: Dict) -> Tuple[int, str]:
    score = 0
    found_oc, found_icij, found_ofac = False, False, False
    
    # Check Web Data SQLite database
    web_data_local = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Web Data",
        "/home/ga/.config/google-chrome-cdp/Default/Web Data"
    ], '.sqlite')
    
    if web_data_local:
        try:
            conn = sqlite3.connect(web_data_local)
            cursor = conn.cursor()
            cursor.execute("SELECT keyword, url FROM keywords")
            keywords = {row[0]: row[1] for row in cursor.fetchall()}
            conn.close()
            
            if 'oc' in keywords and 'opencorporates.com' in keywords['oc']: found_oc = True
            if 'icij' in keywords and 'offshoreleaks.icij.org' in keywords['icij']: found_icij = True
            if 'ofac' in keywords and 'sanctionssearch.ofac.treas.gov' in keywords['ofac']: found_ofac = True
        except Exception as e:
            logger.error(f"Error querying Web Data: {e}")
        finally:
            os.unlink(web_data_local)
            
    # Fallback to Preferences JSON string scanning
    if prefs_data and not (found_oc and found_icij and found_ofac):
        prefs_str = json.dumps(prefs_data).lower()
        if not found_oc and '"keyword": "oc"' in prefs_str and 'opencorporates' in prefs_str: found_oc = True
        if not found_icij and '"keyword": "icij"' in prefs_str and 'offshoreleaks' in prefs_str: found_icij = True
        if not found_ofac and '"keyword": "ofac"' in prefs_str and 'sanctionssearch' in prefs_str: found_ofac = True
        
    if found_oc: score += 5
    if found_icij: score += 5
    if found_ofac: score += 5
    
    feedback = [
        f"    - oc (OpenCorporates): {'Found' if found_oc else 'Missing'}",
        f"    - icij (Offshore Leaks): {'Found' if found_icij else 'Missing'}",
        f"    - ofac (OFAC): {'Found' if found_ofac else 'Missing'}"
    ]
    return score, "\n".join(feedback)


def check_privacy(prefs_data: Dict) -> Tuple[int, str]:
    score = 0
    feedback = []
    
    profile = prefs_data.get('profile', {})
    if profile.get('cookie_controls_mode') == 1 or profile.get('block_third_party_cookies') == True:
        score += 5
        feedback.append("    - Third-party cookies blocked: Yes (+5)")
    else:
        feedback.append("    - Third-party cookies blocked: No")
        
    if prefs_data.get('enable_do_not_track') == True:
        score += 5
        feedback.append("    - Do Not Track enabled: Yes (+5)")
    else:
        feedback.append("    - Do Not Track enabled: No")
        
    if prefs_data.get('safebrowsing', {}).get('enhanced') == True:
        score += 5
        feedback.append("    - Enhanced Safe Browsing: Yes (+5)")
    else:
        feedback.append("    - Enhanced Safe Browsing: No")
        
    return score, "\n".join(feedback)


def check_download(prefs_data: Dict) -> Tuple[int, str]:
    score = 0
    feedback = []
    
    download = prefs_data.get('download', {})
    directory = download.get('default_directory', '')
    
    if 'Case_GoldenFleece/Evidence' in directory or 'Case_GoldenFleece\\Evidence' in directory:
        score += 5
        feedback.append("    - Download directory correct: Yes (+5)")
    else:
        feedback.append(f"    - Download directory correct: No (found: {directory})")
        
    if download.get('prompt_for_download') == True:
        score += 5
        feedback.append("    - Prompt for download: Yes (+5)")
    else:
        feedback.append("    - Prompt for download: No")
        
    return score, "\n".join(feedback)


def check_startup(prefs_data: Dict) -> Tuple[int, str]:
    score = 0
    feedback = []
    
    session = prefs_data.get('session', {})
    if session.get('restore_on_startup') == 4:
        score += 5
        feedback.append("    - Open specific pages on startup: Yes (+5)")
    else:
        feedback.append("    - Open specific pages on startup: No")
        
    startup_urls = session.get('startup_urls', [])
    found_icij = any('offshoreleaks.icij.org' in url for url in startup_urls)
    found_oc = any('opencorporates.com' in url for url in startup_urls)
    
    if found_icij and found_oc:
        score += 5
        feedback.append("    - Required startup URLs present: Yes (+5)")
    else:
        feedback.append("    - Required startup URLs present: No")
        
    return score, "\n".join(feedback)


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    bookmarks_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Bookmarks",
        "/home/ga/.config/google-chrome-cdp/Default/Bookmarks"
    ], '.json')
    
    prefs_path = _copy_file(copy_from_env, [
        "/home/ga/.config/google-chrome/Default/Preferences",
        "/home/ga/.config/google-chrome-cdp/Default/Preferences"
    ], '.json')

    bookmarks_data = {}
    if bookmarks_path:
        try:
            with open(bookmarks_path, 'r', encoding='utf-8') as f:
                bookmarks_data = json.load(f)
        except Exception:
            pass
        finally:
            os.unlink(bookmarks_path)

    prefs_data = {}
    if prefs_path:
        try:
            with open(prefs_path, 'r', encoding='utf-8') as f:
                prefs_data = json.load(f)
        except Exception:
            pass
        finally:
            os.unlink(prefs_path)

    total_score = 0
    feedback_parts = ["=== FINANCIAL FORENSICS WORKSPACE VERIFICATION ==="]

    c1_score, c1_fb, c2_score, c2_fb = check_folders_and_bookmarks(bookmarks_data)
    total_score += c1_score + c2_score
    feedback_parts.append(f"\n[1] Investigative Folders ({c1_score}/20 pts):\n{c1_fb}")
    feedback_parts.append(f"\n[2] Bookmark Categorization ({c2_score}/15 pts):\n{c2_fb}")

    c3_score, c3_fb = check_personal_deleted(bookmarks_data)
    total_score += c3_score
    feedback_parts.append(f"\n[3] Personal Bookmarks Deleted ({c3_score}/15 pts):\n{c3_fb}")

    c4_score, c4_fb = check_search_engines(copy_from_env, prefs_data)
    total_score += c4_score
    feedback_parts.append(f"\n[4] Custom Search Engines ({c4_score}/15 pts):\n{c4_fb}")

    c5_score, c5_fb = check_privacy(prefs_data)
    total_score += c5_score
    feedback_parts.append(f"\n[5] Privacy & Security Hardening ({c5_score}/15 pts):\n{c5_fb}")

    c6_score, c6_fb = check_download(prefs_data)
    total_score += c6_score
    feedback_parts.append(f"\n[6] Download Configuration ({c6_score}/10 pts):\n{c6_fb}")

    c7_score, c7_fb = check_startup(prefs_data)
    total_score += c7_score
    feedback_parts.append(f"\n[7] Startup Pages ({c7_score}/10 pts):\n{c7_fb}")

    passed = total_score >= 70 and c3_score == 15 and c1_score >= 15

    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_parts)
    }