#!/usr/bin/env python3
"""
Verifier for Patent Examiner Workspace Task (patent_examiner_workspace@1)

Evaluates based on file parsing (Preferences, Bookmarks, Web Data SQLite, History SQLite)
and dynamic CDP tab states. It also includes a VLM trajectory check for anti-gaming.

Criteria:
1. Bookmark Organization (20 pts)
2. Confidentiality Settings (Search Suggestions) (15 pts) - MUST PASS FOR OVERALL SUCCESS
3. PDF Handling Workflow (15 pts)
4. Pop-up Exceptions (10 pts)
5. Custom Search Engines (15 pts)
6. History Sanitization (10 pts)
7. Active Workspace Tabs (5 pts)
8. VLM Trajectory Verification (10 pts)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Fallback imports if environment utils are missing
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available.")

def _copy_file_to_temp(copy_from_env, container_path: str) -> str:
    """Helper to copy a file from the container to a temporary local file."""
    tmp = tempfile.NamedTemporaryFile(delete=False)
    tmp.close()
    try:
        copy_from_env(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
    except Exception as e:
        logger.debug(f"Failed to copy {container_path}: {e}")
    os.unlink(tmp.name)
    return ""

def verify_task(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    score = 0
    feedback_parts = []
    
    # Flags for critical criteria
    confidentiality_passed = False

    # 1. Load Files
    bookmarks_path = _copy_file_to_temp(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks")
    prefs_path = _copy_file_to_temp(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences")
    keywords_path = _copy_file_to_temp(copy_from_env, "/tmp/keywords_export.txt")
    history_path = _copy_file_to_temp(copy_from_env, "/tmp/history_export.txt")
    tabs_path = _copy_file_to_temp(copy_from_env, "/tmp/tabs_export.json")

    # ----- Criterion 1: Bookmark Organization (20 pts) -----
    if bookmarks_path:
        try:
            with open(bookmarks_path, "r") as f:
                bookmarks = json.load(f)
            
            bar_children = bookmarks.get("roots", {}).get("bookmark_bar", {}).get("children", [])
            
            folders_found = []
            loose_bookmarks = 0
            
            for child in bar_children:
                if child.get("type") == "folder":
                    folders_found.append(child.get("name", ""))
                elif child.get("type") == "url":
                    loose_bookmarks += 1

            req_folders = metadata.get("required_folders", [])
            missing_folders = [f for f in req_folders if f not in folders_found]
            
            if len(missing_folders) == 0 and loose_bookmarks == 0:
                score += 20
                feedback_parts.append("✅ Bookmarks perfectly organized into 4 folders with no loose bookmarks.")
            elif len(missing_folders) == 0:
                score += 10
                feedback_parts.append(f"⚠️ Folders exist, but {loose_bookmarks} loose bookmarks remain.")
            else:
                feedback_parts.append(f"❌ Missing bookmark folders: {missing_folders}")
                
        except Exception as e:
            feedback_parts.append(f"❌ Failed to parse Bookmarks: {e}")
    else:
        feedback_parts.append("❌ Bookmarks file not found.")

    # ----- Parse Preferences for C2, C3, C4 -----
    prefs = {}
    if prefs_path:
        try:
            with open(prefs_path, "r") as f:
                prefs = json.load(f)
        except Exception:
            pass

    # ----- Criterion 2: Confidentiality (Search Suggestions) (15 pts) -----
    suggest_enabled = prefs.get("search", {}).get("suggest_enabled", True)
    if suggest_enabled is False:
        score += 15
        confidentiality_passed = True
        feedback_parts.append("✅ Search suggestions disabled (Confidentiality secured).")
    else:
        feedback_parts.append("❌ Search suggestions STILL ENABLED (Critical IP leak risk).")

    # ----- Criterion 3: PDF Handling (15 pts) -----
    pdf_external = prefs.get("plugins", {}).get("always_open_pdf_externally", False)
    if pdf_external is True:
        score += 15
        feedback_parts.append("✅ PDF external downloading enabled.")
    else:
        feedback_parts.append("❌ PDFs still opening in Chrome viewer.")

    # ----- Criterion 4: Pop-up Exceptions (10 pts) -----
    popups = prefs.get("profile", {}).get("content_settings", {}).get("exceptions", {}).get("popups", {})
    popup_allowed = False
    for k, v in popups.items():
        if "uspto.gov" in k and v.get("setting") == 1:
            popup_allowed = True
            break
            
    if popup_allowed:
        score += 10
        feedback_parts.append("✅ USPTO pop-up exception added.")
    else:
        feedback_parts.append("❌ USPTO pop-up exception missing.")

    # ----- Criterion 5: Custom Search Engines (15 pts) -----
    if keywords_path:
        try:
            with open(keywords_path, "r") as f:
                keywords_data = f.read()
            has_gp = "gp|" in keywords_data and "patents.google.com" in keywords_data
            has_wipo = "wipo|" in keywords_data and "patentscope.wipo.int" in keywords_data
            
            if has_gp and has_wipo:
                score += 15
                feedback_parts.append("✅ Custom search engines (gp, wipo) successfully added.")
            elif has_gp or has_wipo:
                score += 7
                feedback_parts.append("⚠️ Only one custom search engine found.")
            else:
                feedback_parts.append("❌ Custom search engines missing.")
        except Exception:
            feedback_parts.append("❌ Failed to parse Web Data.")

    # ----- Criterion 6: History Sanitization (10 pts) -----
    if history_path:
        try:
            with open(history_path, "r") as f:
                history_data = f.read().lower()
            
            personal_domains = metadata.get("personal_domains_to_purge", [])
            work_domains = metadata.get("work_domains_to_keep", [])
            
            personal_found = sum(1 for d in personal_domains if d in history_data)
            work_found = sum(1 for d in work_domains if d in history_data)
            
            if personal_found == 0 and work_found > 0:
                score += 10
                feedback_parts.append("✅ History sanitized (Personal purged, Professional kept).")
            elif personal_found > 0:
                feedback_parts.append(f"❌ Personal domains still in history (Found {personal_found}).")
            elif work_found == 0:
                feedback_parts.append("❌ Mass deletion detected! Professional history was wiped.")
        except Exception:
            feedback_parts.append("❌ Failed to read History dump.")

    # ----- Criterion 7: Active Tabs (5 pts) -----
    if tabs_path:
        try:
            with open(tabs_path, "r") as f:
                tabs = json.load(f)
            
            urls = [t.get("url", "") for t in tabs]
            req_tabs = metadata.get("required_tabs", [])
            
            tabs_opened = sum(1 for req in req_tabs if any(req in u for u in urls))
            if tabs_opened == len(req_tabs):
                score += 5
                feedback_parts.append("✅ Required workspace tabs are open.")
            else:
                feedback_parts.append(f"❌ Missing workspace tabs. Found {tabs_opened}/{len(req_tabs)}.")
        except Exception:
            pass

    # ----- Criterion 8: VLM Trajectory Verification (10 pts) -----
    if VLM_AVAILABLE and "query_vlm" in env_info:
        query_vlm_fn = env_info["query_vlm"]
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if frames and final_img:
            vlm_prompt = """
            Did the user interact with Chrome Settings (chrome://settings) to configure search, privacy, or PDFs?
            Did they interact with the Bookmark Manager to move folders?
            Reply with a JSON containing a single boolean field "performed_settings_actions".
            """
            vlm_res = query_vlm_fn(images=frames + [final_img], prompt=vlm_prompt)
            if vlm_res and vlm_res.get("parsed", {}).get("performed_settings_actions") is True:
                score += 10
                feedback_parts.append("✅ VLM verified active Settings/Bookmark interactions.")
            else:
                feedback_parts.append("⚠️ VLM could not confirm settings interactions from trajectory.")

    # Cleanup temp files
    for p in [bookmarks_path, prefs_path, keywords_path, history_path, tabs_path]:
        if p and os.path.exists(p):
            os.unlink(p)

    # Calculate Pass/Fail
    # Must achieve overall passing score AND confidentiality setting MUST be correct
    passed = (score >= 70) and confidentiality_passed

    if not confidentiality_passed and score >= 70:
        feedback_parts.append("❌ FAILED: Overall score was passing, but critical Confidentiality setting (search suggestions) was not disabled.")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }