#!/usr/bin/env python3
"""
Verifier for Factory Inspection Terminal Configuration Task (factory_inspection_terminal@1)

Verification Criteria (100 points total):
1. Bookmark folders created (20 pts)
2. Bookmarks correctly categorized (10 pts)
3. Chrome flags configured (15 pts)
4. Font size settings (10 pts)
5. Homepage and startup pages (15 pts)
6. Search engine shortcuts (15 pts)
7. Download directory and privacy settings (15 pts)

Pass threshold: score >= 70
"""

import logging
import os
import json
import tempfile
from typing import Dict, List, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Domain mapping for verification against categories
DOMAIN_MAPPING = {
    'quality': ['asq.org', 'iso.org', 'nist.gov', 'astm.org', 'asme.org', 'ipc.org'],
    'components': ['digikey.com', 'mouser.com', 'arrow.com', 'thomasnet.com', 'octopart.com', 'lcsc.com'],
    'safety': ['osha.gov', 'nfpa.org', 'ul.com', 'ansi.org', 'cpsc.gov'],
    'manufacturing': ['sme.org', 'themanufacturinginstitute.org', 'industryweek.com', 'automationworld.com', 'qualitymag.com', 'pqndt.com', 'sixsigmaonline.org', 'lean.org'],
    'blocked': ['youtube.com', 'reddit.com', 'facebook.com', 'twitter.com', 'x.com', 'instagram.com', 'espn.com', 'netflix.com']
}

# Flexible folder keyword detection
FOLDER_KEYWORDS = {
    'quality': ['quality', 'standard'],
    'components': ['component', 'supplier'],
    'safety': ['safety', 'compliance'],
    'manufacturing': ['manufacturing', 'resource'],
    'blocked': ['blocked', 'personal']
}


def _copy_and_parse_json(copy_from_env, filename: str) -> Dict:
    """Copy a JSON file from Chrome profile paths in the container and parse it."""
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp.name
    temp.close()
    
    # Check both potential Chrome config locations
    paths = [
        f"/home/ga/.config/google-chrome-cdp/Default/{filename}",
        f"/home/ga/.config/google-chrome/Default/{filename}",
        f"/home/ga/.config/google-chrome-cdp/{filename}",  # For Local State
        f"/home/ga/.config/google-chrome/{filename}"
    ]
    
    data = {}
    for path in paths:
        try:
            copy_from_env(path, temp_path)
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 10:
                with open(temp_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                break
        except Exception as e:
            continue
            
    if os.path.exists(temp_path):
        os.unlink(temp_path)
        
    return data


def check_folders(bookmarks_data: Dict) -> Tuple[int, str]:
    """Criterion 1: Check for existence of the 5 required folders."""
    if not bookmarks_data:
        return 0, "No bookmark data found."
        
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    found_categories = set()
    
    for child in children:
        if child.get('type') == 'folder':
            name = child.get('name', '').lower()
            
            for cat, keywords in FOLDER_KEYWORDS.items():
                if all(kw in name for kw in keywords):
                    found_categories.add(cat)
                    
    score = 20 if len(found_categories) >= 4 else (len(found_categories) * 4)
    feedback = f"Found folders for categories: {', '.join(found_categories) if found_categories else 'None'}."
    
    return score, feedback


def check_categorization(bookmarks_data: Dict) -> Tuple[int, str]:
    """Criterion 2: Check if domains are correctly categorized in their folders."""
    if not bookmarks_data:
        return 0, "No bookmark data found."
        
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    
    cat_scores = {'quality': 0, 'components': 0}
    
    for child in children:
        if child.get('type') == 'folder':
            name = child.get('name', '').lower()
            
            # Identify which folder this is
            current_cat = None
            for cat in ['quality', 'components']:
                if all(kw in name for kw in FOLDER_KEYWORDS[cat]):
                    current_cat = cat
                    break
                    
            if current_cat:
                folder_children = child.get('children', [])
                matched_domains = 0
                for item in folder_children:
                    if item.get('type') == 'url':
                        url = item.get('url', '').lower()
                        if any(domain in url for domain in DOMAIN_MAPPING[current_cat]):
                            matched_domains += 1
                
                # Check for >= 5 matches out of 6
                if matched_domains >= 5:
                    cat_scores[current_cat] = 5
                    
    total_score = sum(cat_scores.values())
    return total_score, f"Quality categorization score: {cat_scores['quality']}/5, Components categorization score: {cat_scores['components']}/5."


def check_flags(local_state: Dict) -> Tuple[int, str]:
    """Criterion 3: Check if required Chrome flags are enabled."""
    if not local_state:
        return 0, "No Local State data found."
        
    experiments = local_state.get('browser', {}).get('enabled_labs_experiments', [])
    flags_found = {
        'smooth-scrolling': False,
        'scrollable-tabstrip': False,
        'back-forward-cache': False
    }
    
    for exp in experiments:
        exp_str = str(exp).lower()
        if 'smooth-scrolling@1' in exp_str or 'smooth-scrolling@true' in exp_str:
            flags_found['smooth-scrolling'] = True
        if 'scrollable-tabstrip@1' in exp_str or 'scrollable-tabstrip@true' in exp_str:
            flags_found['scrollable-tabstrip'] = True
        if 'back-forward-cache@1' in exp_str or 'back-forward-cache@true' in exp_str:
            flags_found['back-forward-cache'] = True
            
    score = sum(5 for v in flags_found.values() if v)
    enabled_flags = [k for k, v in flags_found.items() if v]
    return score, f"Found enabled flags: {', '.join(enabled_flags) if enabled_flags else 'None'}."


def check_font_sizes(prefs: Dict) -> Tuple[int, str]:
    """Criterion 4: Check font size configurations."""
    if not prefs:
        return 0, "No Preferences data found."
        
    webkit = prefs.get('webkit', {}).get('webprefs', {})
    
    try:
        default_font = int(webkit.get('default_font_size', 16))
    except (ValueError, TypeError):
        default_font = 16
        
    try:
        min_font = int(webkit.get('minimum_font_size', 0))
    except (ValueError, TypeError):
        min_font = 0
        
    score = 0
    feedback = []
    
    if default_font == 20:
        score += 5
        feedback.append("Default font size is 20.")
    else:
        feedback.append(f"Default font size is {default_font} (Expected: 20).")
        
    if 12 <= min_font <= 16:
        score += 5
        feedback.append(f"Minimum font size is {min_font} (Expected: 14).")
    else:
        feedback.append(f"Minimum font size is {min_font} (Expected: 14).")
        
    return score, " ".join(feedback)


def check_homepage_startup(prefs: Dict) -> Tuple[int, str]:
    """Criterion 5: Check homepage and startup configuration."""
    if not prefs:
        return 0, "No Preferences data found."
        
    score = 0
    feedback = []
    
    # Evaluate Homepage
    homepage = prefs.get('homepage', '').lower()
    if 'asq.org' in homepage:
        score += 5
        feedback.append("Homepage properly set to ASQ.")
    else:
        feedback.append(f"Homepage incorrect: {homepage}")
        
    # Evaluate Startup URLs
    session = prefs.get('session', {})
    startup_urls = session.get('startup_urls', [])
    if not startup_urls and 'startup_urls' in prefs.get('session_startup', {}):
        startup_urls = prefs.get('session_startup', {}).get('urls', [])
        
    urls_str = " ".join([url.lower() for url in startup_urls])
    startup_score = 0
    
    if 'asq.org' in urls_str: startup_score += 4
    if 'osha.gov' in urls_str: startup_score += 3
    if 'digikey.com' in urls_str: startup_score += 3
        
    score += startup_score
    feedback.append(f"Startup pages score: {startup_score}/10.")
    
    return score, " ".join(feedback)


def check_search_engines(prefs: Dict) -> Tuple[int, str]:
    """Criterion 6: Check custom search engines setup."""
    if not prefs:
        return 0, "No Preferences data found."
        
    keywords_found = set()
    
    # 1. Search overrides
    search_overrides = prefs.get('search_provider_overrides', [])
    for sp in search_overrides:
        if isinstance(sp, dict):
            kw = sp.get('keyword', '').lower()
            if kw: keywords_found.add(kw)
            
    # 2. default_search_provider_data
    dsp_data = prefs.get('default_search_provider_data', {}).get('template_url_data', {})
    kw = dsp_data.get('keyword', '').lower()
    if kw: keywords_found.add(kw)
    
    # 3. Raw JSON dump string search (safest fallback for OSWorld style checks)
    prefs_str = json.dumps(prefs).lower()
    if '"keyword": "parts"' in prefs_str or '"keyword":"parts"' in prefs_str:
        keywords_found.add('parts')
    if '"keyword": "spec"' in prefs_str or '"keyword":"spec"' in prefs_str:
        keywords_found.add('spec')
    if '"keyword": "msds"' in prefs_str or '"keyword":"msds"' in prefs_str:
        keywords_found.add('msds')
        
    score = 0
    found = []
    for kw in ['parts', 'spec', 'msds']:
        if kw in keywords_found:
            score += 5
            found.append(kw)
            
    return score, f"Found custom search keywords: {', '.join(found) if found else 'None'}."


def check_privacy_downloads(prefs: Dict) -> Tuple[int, str]:
    """Criterion 7: Check download location, prompt, and privacy settings."""
    if not prefs:
        return 0, "No Preferences data found."
        
    score = 0
    feedback = []
    
    dl_dir = prefs.get('download', {}).get('default_directory', '').lower()
    if 'inspection_reports' in dl_dir:
        score += 3
        feedback.append("Download directory correct.")
    else:
        feedback.append("Download directory incorrect.")
        
    prompt = prefs.get('download', {}).get('prompt_for_download', False)
    if prompt:
        score += 2
        feedback.append("Download prompt enabled.")
        
    cookie_controls = prefs.get('profile', {}).get('cookie_controls_mode', 0)
    if cookie_controls == 1 or prefs.get('profile', {}).get('block_third_party_cookies', False):
        score += 2
        feedback.append("Third-party cookies blocked.")
        
    pwd_mgr = prefs.get('profile', {}).get('password_manager_enabled', True)
    cred_svc = prefs.get('credentials_enable_service', True)
    if not pwd_mgr or not cred_svc:
        score += 3
        feedback.append("Password saving disabled.")
        
    autofill_profile = prefs.get('autofill', {}).get('profile_enabled', True)
    if not autofill_profile:
        score += 2
        feedback.append("Address autofill disabled.")
        
    autofill_cc = prefs.get('autofill', {}).get('credit_card_enabled', True)
    if not autofill_cc:
        score += 3
        feedback.append("Payment autofill disabled.")
        
    return score, " ".join(feedback)


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available"}

    try:
        # Check files from container
        bookmarks_data = _copy_and_parse_json(copy_from_env, "Bookmarks")
        prefs_data = _copy_and_parse_json(copy_from_env, "Preferences")
        local_state_data = _copy_and_parse_json(copy_from_env, "Local State")
        
        # Verify basic structural integrity to catch naive agent mass-deletions
        if not bookmarks_data or not prefs_data:
            return {"passed": False, "score": 0, "feedback": "Could not extract Chrome configuration files."}
            
        bookmark_count = str(bookmarks_data).count("'type': 'url'")
        if bookmark_count < 25:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Anti-gaming fail: Mass deletion detected. Only {bookmark_count}/32 bookmarks remain."
            }

        score = 0
        feedback_parts = ["=== FACTORY INSPECTION TERMINAL VERIFICATION ==="]
        
        c1_score, c1_fb = check_folders(bookmarks_data)
        score += c1_score
        feedback_parts.append(f"1. Bookmark Folders ({c1_score}/20): {c1_fb}")
        
        c2_score, c2_fb = check_categorization(bookmarks_data)
        score += c2_score
        feedback_parts.append(f"2. Categorization ({c2_score}/10): {c2_fb}")
        
        c3_score, c3_fb = check_flags(local_state_data)
        score += c3_score
        feedback_parts.append(f"3. Chrome Flags ({c3_score}/15): {c3_fb}")
        
        c4_score, c4_fb = check_font_sizes(prefs_data)
        score += c4_score
        feedback_parts.append(f"4. Font Size ({c4_score}/10): {c4_fb}")
        
        c5_score, c5_fb = check_homepage_startup(prefs_data)
        score += c5_score
        feedback_parts.append(f"5. Homepage/Startup ({c5_score}/15): {c5_fb}")
        
        c6_score, c6_fb = check_search_engines(prefs_data)
        score += c6_score
        feedback_parts.append(f"6. Search Engines ({c6_score}/15): {c6_fb}")
        
        c7_score, c7_fb = check_privacy_downloads(prefs_data)
        score += c7_score
        feedback_parts.append(f"7. Privacy & Downloads ({c7_score}/15): {c7_fb}")
        
        feedback_parts.append(f"\nFinal Score: {score}/100")
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification encountered an error: {e}"}