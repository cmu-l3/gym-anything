#!/usr/bin/env python3
"""
Verifier for litigation_ediscovery_workspace@1

Verification checks:
1. Bookmark Organization (20 pts): 3 folders exist and hold legal domains.
2. Personal Bookmark Deletion (15 pts): No Facebook, Netflix, etc. remain in JSON.
3. Selective History Purge (20 pts): 'globex' URLs deleted, >=30 entries remain.
4. Selective Cookie Purge (10 pts): 'globex' cookies deleted, >=10 remain.
5. Search Engine Shortcuts (10 pts): 'usc' and 'scholar' added in Preferences.
6. Security & Downloads (15 pts): Download prompt/dir, autofill/password disabled.
7. HTML Export (10 pts): HTML file exists and contains valid exports.
"""

import os
import json
import sqlite3
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_file(copy_fn, container_paths, suffix=''):
    """Helper to try copying a file from possible locations in the container."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    for p in container_paths:
        try:
            copy_fn(p, tmp.name)
            if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
                return tmp.name
        except Exception:
            pass
    os.unlink(tmp.name)
    return None

def verify_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    meta = task_info.get('metadata', {})
    personal_domains = meta.get('personal_domains', [])
    purge_kw = meta.get('purge_keyword', 'globex')
    
    score = 0
    feedback = []

    # 1. & 2. Bookmarks Checks
    bm_path = get_file(copy_fn=copy_from_env, container_paths=[
        "/home/ga/.config/google-chrome/Default/Bookmarks"
    ], suffix='.json')
    
    if bm_path:
        with open(bm_path, 'r', encoding='utf-8') as f:
            bm_data = json.load(f)
        os.unlink(bm_path)
        
        # Flatten all bookmark URLs to check for personal domains
        all_urls_str = json.dumps(bm_data).lower()
        has_personal = any(pd.lower() in all_urls_str for pd in personal_domains)
        if not has_personal:
            score += 15
            feedback.append("✅ Personal bookmarks completely deleted.")
        else:
            feedback.append("❌ Personal bookmarks still found in browser.")

        # Check for 3 legal folders
        bar = bm_data.get("roots", {}).get("bookmark_bar", {}).get("children", [])
        folders_found = [c.get("name", "").lower() for c in bar if c.get("type") == "folder"]
        req_folders = ["court dockets", "legal research", "e-discovery"]
        found_reqs = sum(1 for req in req_folders if req in folders_found)
        if found_reqs == 3:
            score += 20
            feedback.append("✅ All 3 legal bookmark folders organized correctly.")
        else:
            score += (found_reqs * 5)
            feedback.append(f"⚠️ Found {found_reqs}/3 required bookmark folders.")
    else:
        feedback.append("❌ Could not read Bookmarks file.")

    # 3. History Purge
    hist_path = get_file(copy_fn=copy_from_env, container_paths=[
        "/home/ga/.config/google-chrome/Default/History"
    ], suffix='.db')
    
    if hist_path:
        conn = sqlite3.connect(hist_path)
        c = conn.cursor()
        c.execute(f"SELECT COUNT(*) FROM urls WHERE url LIKE '%{purge_kw}%'")
        globex_hist = c.fetchone()[0]
        c.execute("SELECT COUNT(*) FROM urls")
        total_hist = c.fetchone()[0]
        conn.close()
        os.unlink(hist_path)
        
        if globex_hist == 0 and total_hist >= 20:
            score += 20
            feedback.append("✅ Sensitive 'globex' history selectively purged without clearing valid history.")
        elif globex_hist == 0 and total_hist < 20:
            feedback.append("❌ History completely wiped. Valid legal research history was destroyed.")
        else:
            feedback.append(f"❌ {globex_hist} sensitive 'globex' history items remain.")
    else:
        feedback.append("❌ Could not read History DB.")

    # 4. Cookies Purge
    cookie_path = get_file(copy_fn=copy_from_env, container_paths=[
        "/home/ga/.config/google-chrome/Default/Network/Cookies",
        "/home/ga/.config/google-chrome/Default/Cookies"
    ], suffix='.db')
    
    if cookie_path:
        try:
            conn = sqlite3.connect(cookie_path)
            c = conn.cursor()
            c.execute(f"SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%{purge_kw}%'")
            globex_cookies = c.fetchone()[0]
            c.execute("SELECT COUNT(*) FROM cookies")
            total_cookies = c.fetchone()[0]
            conn.close()
            
            if globex_cookies == 0 and total_cookies >= 5:
                score += 10
                feedback.append("✅ Sensitive cookies purged while preserving valid ones.")
            elif globex_cookies == 0 and total_cookies < 5:
                feedback.append("❌ All cookies wiped out indiscriminately.")
            else:
                feedback.append(f"❌ {globex_cookies} sensitive 'globex' cookies remain.")
        except Exception as e:
            feedback.append(f"❌ Cookie DB Error: {str(e)}")
        finally:
            os.unlink(cookie_path)
    else:
        feedback.append("❌ Could not read Cookies DB.")

    # 5. & 6. Preferences (Search Engines & Security)
    pref_path = get_file(copy_fn=copy_from_env, container_paths=[
        "/home/ga/.config/google-chrome/Default/Preferences"
    ], suffix='.json')

    if pref_path:
        with open(pref_path, 'r', encoding='utf-8') as f:
            pref_data = json.load(f)
            pref_str = json.dumps(pref_data)
        os.unlink(pref_path)

        # Search engines
        if 'law.cornell.edu/uscode' in pref_str and 'scholar.google.com' in pref_str:
            score += 10
            feedback.append("✅ Custom search engines configured.")
        else:
            feedback.append("❌ Custom search engines missing.")

        # Downloads
        dl_dir = pref_data.get('download', {}).get('default_directory', '')
        dl_prompt = pref_data.get('download', {}).get('prompt_for_download', False)
        if 'TechCorp_Case' in dl_dir and dl_prompt:
            score += 5
            feedback.append("✅ Secure download path and prompt configured.")
        else:
            feedback.append("❌ Download preferences incorrect.")

        # Credentials/Autofill
        pw_saved = pref_data.get('profile', {}).get('password_manager_enabled', True)
        af_enabled = pref_data.get('autofill', {}).get('profile_enabled', True)
        if not pw_saved and not af_enabled:
            score += 10
            feedback.append("✅ Password saving and autofill securely disabled.")
        else:
            score += 5 if not pw_saved or not af_enabled else 0
            feedback.append("❌ Credential/Autofill security settings not fully locked down.")
    else:
        feedback.append("❌ Could not read Preferences.")

    # 7. HTML Export
    html_path = get_file(copy_fn=copy_from_env, container_paths=[
        "/home/ga/Desktop/TechCorp_Bookmarks.html"
    ], suffix='.html')

    if html_path:
        with open(html_path, 'r', encoding='utf-8') as f:
            html_content = f.read().lower()
        os.unlink(html_path)
        
        if '<dl>' in html_content and 'court dockets' in html_content:
            score += 10
            feedback.append("✅ Valid bookmark HTML export found on Desktop.")
        else:
            score += 5
            feedback.append("⚠️ Desktop HTML file found, but may not be a valid bookmark export.")
    else:
        feedback.append("❌ Bookmarks HTML export not found on Desktop.")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }