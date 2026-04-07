#!/usr/bin/env python3
"""
Verifier for vet_clinic_front_desk_setup@1

Verification Strategy:
1. Bookmarks Check (30 pts)
   - 5 Specific folders exist (10 pts)
   - Vet URLs categorized properly (20 pts)
2. Personal Bookmarks Removed (10 pts)
3. Site Settings (35 pts)
   - PDFs download instead of open (15 pts)
   - Notifications blocked (10 pts)
   - Sound muted (10 pts)
4. Custom Search Engines via 'Web Data' DB (15 pts)
5. Startup Pages configured (10 pts)
"""

import os
import json
import sqlite3
import tempfile
import logging
import shutil
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_file_from_env(copy_from_env, container_path: str, suffix: str = '') -> str:
    """Helper to copy a file and return local temp path. Returns None on failure."""
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

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0
    
    # Metadata targets
    target_folders = ["practice & labs", "suppliers & diets", "client finance", "medical reference", "industry org"]
    personal_domains = ["netflix.com", "facebook.com", "pinterest.com", "spotify.com", "amazon.com", "zillow.com"]
    startup_domains = ["ezyvet.com", "vetconnectplus.com"]
    target_search = ["plumbs", "merck"]

    # --- Fetch Files ---
    bookmarks_path = get_file_from_env(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks", ".json")
    prefs_path = get_file_from_env(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences", ".json")
    webdata_path = get_file_from_env(copy_from_env, "/home/ga/.config/google-chrome/Default/Web Data", ".sqlite")

    # 1 & 2. Verify Bookmarks
    if bookmarks_path:
        try:
            with open(bookmarks_path, 'r') as f:
                b_data = json.load(f)
            
            bar_children = b_data.get('roots', {}).get('bookmark_bar', {}).get('children', [])
            
            # Check Folder Existence
            found_folders = [c.get('name', '').lower().strip() for c in bar_children if c.get('type') == 'folder']
            folders_matched = sum(1 for tf in target_folders if tf in found_folders)
            f_score = min(10, folders_matched * 2)
            score += f_score
            feedback.append(f"Bookmark folders matched: {folders_matched}/{len(target_folders)} (+{f_score} pts)")

            # Check Personal Clutter
            def check_personal(node):
                if node.get('type') == 'url':
                    url = node.get('url', '').lower()
                    if any(pd in url for pd in personal_domains):
                        return True
                for child in node.get('children', []):
                    if check_personal(child):
                        return True
                return False
            
            has_personal = check_personal(b_data.get('roots', {}).get('bookmark_bar', {}))
            if not has_personal:
                score += 10
                feedback.append("All personal bookmarks successfully removed (+10 pts)")
            else:
                feedback.append("Personal bookmarks (e.g. Netflix, Facebook) still exist in the browser (+0 pts)")

            # Check Categorization (Simple count of URLs successfully moved inside folders vs loose)
            loose_urls = sum(1 for c in bar_children if c.get('type') == 'url')
            folder_urls = 0
            for folder in [c for c in bar_children if c.get('type') == 'folder']:
                folder_urls += sum(1 for c in folder.get('children', []) if c.get('type') == 'url')
            
            if folder_urls >= 15 and loose_urls == 0:
                score += 20
                feedback.append("Veterinary bookmarks successfully categorized into folders (+20 pts)")
            elif folder_urls > 0:
                score += 10
                feedback.append(f"Partial bookmark categorization ({folder_urls} in folders, {loose_urls} loose) (+10 pts)")
            else:
                feedback.append("Bookmarks were not moved into folders (+0 pts)")

        except Exception as e:
            feedback.append(f"Error parsing Bookmarks JSON: {e}")
        finally:
            os.unlink(bookmarks_path)
    else:
        feedback.append("Could not fetch Bookmarks file")

    # 3 & 5. Verify Preferences (Site Settings and Startup)
    pdf_correct = False
    sound_correct = False
    
    if prefs_path:
        try:
            with open(prefs_path, 'r') as f:
                p_data = json.load(f)

            # PDF Settings
            pdf_ext = p_data.get('plugins', {}).get('always_open_pdf_externally', False)
            if pdf_ext is True:
                score += 15
                pdf_correct = True
                feedback.append("PDFs correctly configured to download (+15 pts)")
            else:
                feedback.append("PDFs not configured to download automatically (+0 pts)")

            # Notifications & Sound Block
            c_settings = p_data.get('profile', {}).get('default_content_setting_values', {})
            notif = c_settings.get('notifications')
            sound = c_settings.get('sound')
            
            if notif == 2:
                score += 10
                feedback.append("Notifications correctly blocked (+10 pts)")
            else:
                feedback.append(f"Notifications not blocked globally (current: {notif}) (+0 pts)")

            if sound == 2:
                score += 10
                sound_correct = True
                feedback.append("Sound correctly muted by default (+10 pts)")
            else:
                feedback.append(f"Sound not muted globally (current: {sound}) (+0 pts)")

            # Startup Pages
            restore_mode = p_data.get('session', {}).get('restore_on_startup')
            startup_urls = p_data.get('session', {}).get('startup_urls', [])
            
            s_matched = sum(1 for expected in startup_domains if any(expected in u.lower() for u in startup_urls))
            if restore_mode == 4 and s_matched == 2:
                score += 10
                feedback.append("Startup pages configured correctly (+10 pts)")
            elif s_matched > 0:
                score += 5
                feedback.append("Startup pages partially configured (+5 pts)")
            else:
                feedback.append("Startup pages not configured (+0 pts)")

        except Exception as e:
            feedback.append(f"Error parsing Preferences JSON: {e}")
        finally:
            os.unlink(prefs_path)
    else:
        feedback.append("Could not fetch Preferences file")

    # 4. Verify Search Engines (via Web Data SQLite)
    if webdata_path:
        try:
            # Copy to temp to avoid DB locks
            db_copy = webdata_path + "_copy.sqlite"
            shutil.copy2(webdata_path, db_copy)
            conn = sqlite3.connect(db_copy)
            cursor = conn.cursor()
            
            # Chrome stores search engines in 'keywords' table
            cursor.execute("SELECT keyword FROM keywords")
            rows = cursor.fetchall()
            found_kws = [row[0].lower() for row in rows if row[0]]
            
            kw_matched = sum(1 for t_kw in target_search if t_kw in found_kws)
            if kw_matched == 2:
                score += 15
                feedback.append("Both custom search engines configured (+15 pts)")
            elif kw_matched == 1:
                score += 7
                feedback.append("One custom search engine configured (+7 pts)")
            else:
                feedback.append("Custom search engines not configured (+0 pts)")
                
            conn.close()
            os.unlink(db_copy)
        except Exception as e:
            feedback.append(f"Error querying Web Data database: {e}")
        finally:
            os.unlink(webdata_path)
    else:
        feedback.append("Could not fetch Web Data SQLite file")

    # Passing thresholds
    passed = score >= 75 and pdf_correct and sound_correct
    
    if passed:
        feedback.insert(0, f"✅ Task passed with {score}/100 points.")
    else:
        feedback.insert(0, f"❌ Task failed. Score: {score}/100. (Requires 75 points, plus PDF and Sound settings enforced).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }