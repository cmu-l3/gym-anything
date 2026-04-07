#!/usr/bin/env python3
"""
Verifier for assistive_browser_setup task.
Checks font sizes, zoom, bookmarks, preferences, and desktop shortcut.
Uses multiple independent criteria and copy_from_env for robust evaluation.
"""

import json
import os
import hashlib
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Domain lists for bookmark verification ---
AT_DOMAINS = ["nvaccess.org", "freedomscientific.com", "aph.org", "afb.org",
              "bookshare.org", "learningally.org", "bemyeyes.com", "ablenetinc.com"]
HEALTH_DOMAINS = ["webmd.com", "mayoclinic.org", "cdc.gov", "nih.gov",
                  "medlineplus.gov", "medicare.gov/care-compare"]
DAILY_DOMAINS = ["amazon.com", "instacart.com", "doordash.com", "usps.com",
                 "ups.com", "chase.com"]
ENTERTAINMENT_DOMAINS = ["youtube.com", "spotify.com", "npr.org", "facebook.com", "zoom.us"]
GOV_DOMAINS = ["ssa.gov", "medicare.gov", "va.gov", "usa.gov", "benefits.gov"]

FOLDER_THRESHOLDS = {
    "assistive technology": (6, 5.0),
    "health & wellness": (4, 2.5),
    "health and wellness": (4, 2.5),
    "daily living": (4, 0),
    "entertainment": (4, 0),
    "government services": (4, 2.5),
}

EXPECTED_SEARCH_KEYWORDS = ["yt", "amz"]

def _urls_in_folder(folder_node):
    urls = []
    for child in folder_node.get("children", []):
        if child.get("type") == "url":
            urls.append(child.get("url", ""))
        elif child.get("type") == "folder":
            urls.extend(_urls_in_folder(child))
    return urls

def _domain_match(url, domain):
    return domain.lower() in url.lower()

def _count_domain_matches(urls, domains):
    matched = 0
    for d in domains:
        if any(_domain_match(u, d) for u in urls):
            matched += 1
    return matched


def check_assistive_browser_setup(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env function available"}

    score = 0.0
    feedback = []
    temp_dir = tempfile.mkdtemp()
    
    try:
        # Copy necessary files from the container
        bm_path = os.path.join(temp_dir, "Bookmarks")
        prefs_path = os.path.join(temp_dir, "Preferences")
        init_bm_path = os.path.join(temp_dir, "initial_bookmarks.json")
        shortcut_path = os.path.join(temp_dir, "Accessible_Chrome.desktop")
        
        # Chrome CDP profile
        copy_from_env("/home/ga/.config/google-chrome-cdp/Default/Bookmarks", bm_path)
        copy_from_env("/home/ga/.config/google-chrome-cdp/Default/Preferences", prefs_path)
        copy_from_env("/tmp/initial_bookmarks.json", init_bm_path)
        
        # Copy shortcut (might not exist)
        try:
            copy_from_env("/home/ga/Desktop/Accessible_Chrome.desktop", shortcut_path)
        except Exception:
            pass

        if not os.path.exists(bm_path) or not os.path.exists(prefs_path):
            return {"passed": False, "score": 0, "feedback": "Failed to copy Chrome profile files"}

        with open(bm_path, 'r', encoding='utf-8') as f:
            bookmarks = json.load(f)
        with open(prefs_path, 'r', encoding='utf-8') as f:
            prefs = json.load(f)

        desktop_shortcut_content = ""
        if os.path.exists(shortcut_path) and os.path.getsize(shortcut_path) > 0:
            with open(shortcut_path, 'r', encoding='utf-8') as f:
                desktop_shortcut_content = f.read()

        # Anti-gaming: Check if bookmarks changed
        if os.path.exists(init_bm_path):
            with open(bm_path, 'rb') as f1, open(init_bm_path, 'rb') as f2:
                if hashlib.md5(f1.read()).hexdigest() == hashlib.md5(f2.read()).hexdigest():
                    feedback.append("WARNING: Bookmarks file is untouched from initial state.")

        # ================================================================
        # CRITERION 1: Font sizes (20 pts)
        # ================================================================
        webkit = prefs.get("webkit", {}).get("webprefs", {})
        default_fs = webkit.get("default_font_size", 16)
        fixed_fs = webkit.get("default_fixed_font_size", 13)
        min_fs = webkit.get("minimum_font_size", 0)

        c1_score = 0
        if abs(default_fs - 24) <= 2:
            c1_score += 8
            feedback.append(f"C1: default_font_size={default_fs} ✓")
        else:
            feedback.append(f"C1: default_font_size={default_fs}, expected ~24 ✗")

        if abs(fixed_fs - 20) <= 2:
            c1_score += 6
            feedback.append(f"C1: default_fixed_font_size={fixed_fs} ✓")
        else:
            feedback.append(f"C1: default_fixed_font_size={fixed_fs}, expected ~20 ✗")

        if abs(min_fs - 16) <= 2:
            c1_score += 6
            feedback.append(f"C1: minimum_font_size={min_fs} ✓")
        else:
            feedback.append(f"C1: minimum_font_size={min_fs}, expected ~16 ✗")

        font_criterion_met = c1_score >= 6
        score += c1_score

        # ================================================================
        # CRITERION 2: Default page zoom (10 pts)
        # ================================================================
        zoom_level = prefs.get("partition", {}).get("default_zoom_level",
                     prefs.get("profile", {}).get("default_zoom_level", 0.0))
        
        c2_score = 0
        if zoom_level > 0.5: # Blink zoom > 0.5 is > ~110%
            c2_score = 10
            feedback.append(f"C2: zoom_level={zoom_level:.2f} (non-default, >100%) ✓")
        elif zoom_level != 0.0:
            c2_score = 5
            feedback.append(f"C2: zoom_level={zoom_level:.2f} (changed but low) ~")
        else:
            feedback.append(f"C2: zoom_level=0.0 (unchanged) ✗")
        score += c2_score

        # ================================================================
        # CRITERION 3: Bookmark folders created (15 pts)
        # ================================================================
        bookmark_bar = bookmarks.get("roots", {}).get("bookmark_bar", {})
        bar_children = bookmark_bar.get("children", [])
        
        found_folders = {}
        folders_on_bar = []
        for child in bar_children:
            if child.get("type") == "folder":
                fname = child.get("name", "").lower().strip()
                folders_on_bar.append(fname)
                found_folders[fname] = child

        expected_folders = ["assistive technology", "health & wellness", "daily living", "entertainment", "government services"]
        
        c3_score = 0
        c3_matched = 0
        for ef in expected_folders:
            matched = False
            ef_alt = ef.replace("&", "and")
            for ff in folders_on_bar:
                if ef in ff or ff in ef or ef_alt in ff or ff in ef_alt:
                    matched = True
                    break
            if matched:
                c3_matched += 1
                c3_score += 3
        
        feedback.append(f"C3: {c3_matched}/5 expected folders found ({c3_score} pts)")
        score += c3_score

        # ================================================================
        # CRITERION 4: Bookmarks correctly categorized (10 pts)
        # ================================================================
        c4_score = 0
        for folder_key, domains in [("assistive technology", AT_DOMAINS), ("health & wellness", HEALTH_DOMAINS), ("government services", GOV_DOMAINS)]:
            threshold, pts = FOLDER_THRESHOLDS.get(folder_key, (0, 0))
            folder_node = None
            for ff_name, ff_node in found_folders.items():
                fk_alt = folder_key.replace("&", "and")
                if folder_key in ff_name or fk_alt in ff_name:
                    folder_node = ff_node
                    break
            
            if folder_node:
                urls = _urls_in_folder(folder_node)
                matched = _count_domain_matches(urls, domains)
                if matched >= threshold:
                    c4_score += pts
                    feedback.append(f"C4: '{folder_key}' has {matched}/{len(domains)} domains ✓")
                else:
                    feedback.append(f"C4: '{folder_key}' has {matched}/{len(domains)} domains (need {threshold}) ✗")
            else:
                feedback.append(f"C4: '{folder_key}' folder not found ✗")
        score += c4_score

        # ================================================================
        # CRITERION 5: No loose bookmarks (5 pts)
        # ================================================================
        loose_urls = [c for c in bar_children if c.get("type") == "url"]
        c5_score = 5 if len(loose_urls) == 0 else (2 if len(loose_urls) <= 3 else 0)
        feedback.append(f"C5: {len(loose_urls)} loose bookmarks on bar ({c5_score} pts)")
        score += c5_score

        # ================================================================
        # CRITERION 6: Search engine shortcuts (10 pts)
        # ================================================================
        c6_score = 0
        prefs_str = json.dumps(prefs).lower()
        
        for kw in EXPECTED_SEARCH_KEYWORDS:
            if f'"keyword": "{kw}"' in prefs_str or f'"keyword":"{kw}"' in prefs_str:
                c6_score += 5
                feedback.append(f"C6: search shortcut '{kw}' found ✓")
            else:
                feedback.append(f"C6: search shortcut '{kw}' not found ✗")
        score += c6_score

        # ================================================================
        # CRITERION 7: Homepage and startup pages (10 pts)
        # ================================================================
        c7_score = 0
        homepage = prefs.get("homepage", "")
        if "afb.org" in homepage.lower():
            c7_score += 4
            feedback.append(f"C7: homepage contains afb.org ✓")
        else:
            feedback.append(f"C7: homepage incorrect ✗")

        startup_urls = prefs.get("session", {}).get("startup_urls", [])
        restore_on_startup = prefs.get("session", {}).get("restore_on_startup", 5)
        
        if restore_on_startup == 4:
            if any("afb.org" in u.lower() for u in startup_urls):
                c7_score += 3
            if any("google.com" in u.lower() for u in startup_urls):
                c7_score += 3
            feedback.append(f"C7: Startup pages configured correctly (+{c7_score-4})")
        else:
            feedback.append(f"C7: restore_on_startup={restore_on_startup}, expected 4 ✗")
        score += c7_score

        # ================================================================
        # CRITERION 8: Privacy & autofill settings (10 pts)
        # ================================================================
        c8_score = 0
        if not prefs.get("credentials_enable_service", True) or not prefs.get("profile", {}).get("password_manager_enabled", True):
            c8_score += 2.5
        if not prefs.get("autofill", {}).get("profile_enabled", True):
            c8_score += 2.5
        if not prefs.get("autofill", {}).get("credit_card_enabled", True):
            c8_score += 2.5
        
        cookie_setting = prefs.get("profile", {}).get("default_content_setting_values", {}).get("cookies", 1)
        if prefs.get("profile", {}).get("block_third_party_cookies", False) or cookie_setting == 2:
            c8_score += 2.5

        feedback.append(f"C8: Privacy settings configured ({c8_score}/10 pts)")
        score += c8_score

        # ================================================================
        # CRITERION 9: Download directory (5 pts)
        # ================================================================
        c9_score = 0
        dl_dir = prefs.get("download", {}).get("default_directory", "")
        if "Client_Downloads" in dl_dir:
            c9_score += 3
        if prefs.get("download", {}).get("prompt_for_download", False):
            c9_score += 2
            
        feedback.append(f"C9: Download configured ({c9_score}/5 pts)")
        score += c9_score

        # ================================================================
        # CRITERION 10: Desktop shortcut (15 pts)
        # ================================================================
        c10_score = 0
        if desktop_shortcut_content:
            c10_score += 3
            if "[Desktop Entry]" in desktop_shortcut_content:
                c10_score += 2
            if "Name=Accessible Chrome" in desktop_shortcut_content or "Name = Accessible Chrome" in desktop_shortcut_content:
                c10_score += 2
            if "--force-renderer-accessibility" in desktop_shortcut_content:
                c10_score += 4
            if "--enable-caret-browsing" in desktop_shortcut_content:
                c10_score += 4
            feedback.append(f"C10: Desktop shortcut found and parsed ({c10_score}/15 pts) ✓")
        else:
            feedback.append("C10: Accessible_Chrome.desktop not found ✗")
        score += c10_score

        # ================================================================
        # FINAL SCORING
        # ================================================================
        max_score = 110.0
        normalized_score = min(100, (score / max_score) * 100)
        
        passed = normalized_score >= 64 and font_criterion_met and c3_matched >= 3

        return {
            "passed": passed,
            "score": int(normalized_score),
            "feedback": "\n".join(feedback)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}
    finally:
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)