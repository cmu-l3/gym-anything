#!/usr/bin/env python3
"""
Verifier for SRE Incident Command Setup Task (sre_incident_command_setup@1)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any, List

# Try to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _get_exported_file(copy_from_env, remote_path: str, is_json: bool = True) -> Any:
    """Helper to copy and parse a file from the environment."""
    temp_file = tempfile.NamedTemporaryFile(delete=False)
    temp_file.close()
    try:
        copy_from_env(remote_path, temp_file.name)
        if is_json:
            with open(temp_file.name, 'r', encoding='utf-8') as f:
                return json.load(f)
        else:
            with open(temp_file.name, 'r', encoding='utf-8') as f:
                return f.read()
    except Exception as e:
        logger.warning(f"Failed to copy or parse {remote_path}: {e}")
        return {} if is_json else ""
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

def _find_folder(children: List[Dict], name: str) -> Dict:
    name_lower = name.lower()
    for child in children:
        if child.get('type') == 'folder' and child.get('name', '').lower() == name_lower:
            return child
    return {}

def _count_urls_in_folder(folder: Dict) -> int:
    count = 0
    for child in folder.get('children', []):
        if child.get('type') == 'url':
            count += 1
    return count

def _collect_all_urls(node: Dict, urls: List[str]):
    if node.get('type') == 'url':
        urls.append(node.get('url', '').lower())
    for child in node.get('children', []):
        _collect_all_urls(child, urls)

def verify_sre_incident_command(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_tabs = metadata.get('expected_tabs', [])
    junk_domains = metadata.get('junk_domains', [])
    expected_folders = metadata.get('expected_folders', [])

    # Retrieve all exported files
    cdp_tabs = _get_exported_file(copy_from_env, "/tmp/cdp_tabs_export.json", is_json=True)
    bookmarks = _get_exported_file(copy_from_env, "/tmp/Bookmarks_export.json", is_json=True)
    prefs = _get_exported_file(copy_from_env, "/tmp/Preferences_export.json", is_json=True)
    local_state = _get_exported_file(copy_from_env, "/tmp/LocalState_export.json", is_json=True)
    keywords_txt = _get_exported_file(copy_from_env, "/tmp/keywords_export.txt", is_json=False)

    score = 0
    feedback = []

    # 1. Live Tabs Open (15 pts)
    if isinstance(cdp_tabs, list):
        open_urls = [t.get('url', '') for t in cdp_tabs]
        tabs_found = 0
        for expected in expected_tabs:
            if any(expected in u for u in open_urls):
                tabs_found += 1
        
        tab_score = tabs_found * 5
        score += tab_score
        feedback.append(f"[Tabs] {tabs_found}/3 required tabs open (+{tab_score} pts)")
    else:
        feedback.append("[Tabs] Failed to read CDP tabs.")

    # 2. Bookmark Organization (15 pts) & 3. Junk Purged (5 pts)
    bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
    folders_found = 0
    valid_bookmarks_categorized = 0

    for fname in expected_folders:
        folder = _find_folder(bookmark_bar.get('children', []), fname)
        if folder:
            folders_found += 1
            valid_bookmarks_categorized += _count_urls_in_folder(folder)

    folder_score = int((folders_found / 4) * 5 + min(10, valid_bookmarks_categorized / 1.6))
    score += folder_score
    feedback.append(f"[Bookmarks Folders] {folders_found}/4 folders found, {valid_bookmarks_categorized} items sorted (+{folder_score} pts)")

    # Check junk
    all_urls = []
    _collect_all_urls(bookmarks.get('roots', {}), all_urls)
    junk_count = sum(1 for u in all_urls if any(j in u for j in junk_domains))
    if junk_count == 0:
        score += 5
        feedback.append("[Bookmarks Junk] All junk bookmarks purged (+5 pts)")
    else:
        feedback.append(f"[Bookmarks Junk] {junk_count} junk bookmarks still exist (0 pts)")

    # 4. Custom Search Engines (15 pts)
    se_score = 0
    if "pd|" in keywords_txt or "pd" in keywords_txt:
        se_score += 7.5
    if "tkt|" in keywords_txt or "tkt" in keywords_txt:
        se_score += 7.5
    score += int(se_score)
    feedback.append(f"[Search Engines] Keywords found in Web Data (+{int(se_score)} pts)")

    # 5. Notification Permissions (15 pts)
    notif_score = 0
    try:
        default_notif = prefs.get('profile', {}).get('default_content_setting_values', {}).get('notifications')
        if default_notif == 2:
            notif_score += 5
        
        exceptions = prefs.get('profile', {}).get('content_settings', {}).get('exceptions', {}).get('notifications', {})
        exceptions_str = json.dumps(exceptions).lower()
        if "pagerduty.com" in exceptions_str and "datadoghq.com" in exceptions_str:
            notif_score += 10
    except Exception:
        pass
    score += notif_score
    feedback.append(f"[Notifications] Block global + Explicit allows (+{notif_score} pts)")

    # 6. Wallboard Font Sizes (10 pts)
    font_score = 0
    try:
        webprefs = prefs.get('webkit', {}).get('webprefs', {})
        if webprefs.get('default_font_size') == 22:
            font_score += 5
        if webprefs.get('default_fixed_font_size') == 18:
            font_score += 5
    except Exception:
        pass
    score += font_score
    feedback.append(f"[Fonts] Sizes configured correctly (+{font_score} pts)")

    # 7. Chrome Render Flags (10 pts)
    flag_score = 0
    try:
        experiments = local_state.get('browser', {}).get('enabled_labs_experiments', [])
        exp_str = " ".join(experiments)
        if "enable-gpu-rasterization" in exp_str:
            flag_score += 5
        if "smooth-scrolling" in exp_str:
            flag_score += 5
    except Exception:
        pass
    score += flag_score
    feedback.append(f"[Flags] Performance flags enabled (+{flag_score} pts)")

    # 8. Auto-Startup Config (15 pts)
    startup_score = 0
    try:
        restore = prefs.get('session', {}).get('restore_on_startup')
        urls = prefs.get('session', {}).get('startup_urls', [])
        if restore == 4:
            startup_score += 5
        
        urls_str = " ".join(urls).lower()
        found_startups = sum(1 for e in expected_tabs if e in urls_str)
        if found_startups >= 3:
            startup_score += 10
        elif found_startups > 0:
            startup_score += found_startups * 3
    except Exception:
        pass
    score += startup_score
    feedback.append(f"[Startup] Restore config and URLs set (+{startup_score} pts)")

    # VLM Trajectory Verification (Anti-Gaming)
    vlm_anti_gaming_passed = True
    if VLM_AVAILABLE and env_info.get('query_vlm'):
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = "Look at these trajectory frames from a Chrome browser task. Did the agent navigate through Chrome settings, flag pages, or bookmark manager to actually perform configuration work, rather than doing nothing? Answer 'yes' or 'no'."
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success"):
                response_text = vlm_res.get("response", "").lower()
                if "no" in response_text and "yes" not in response_text:
                    vlm_anti_gaming_passed = False
                    feedback.append("⚠️ VLM Anti-Gaming Flag: Trajectory shows no meaningful interaction with settings/bookmarks.")

    if not vlm_anti_gaming_passed:
        score = min(score, 50)  # Cap score if trajectory proves fake

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }