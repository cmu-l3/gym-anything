#!/usr/bin/env python3
"""
Verifier for arrangement_conference_workspace@1

Verification Strategy (Multi-Criteria):
1. SQLite validation of Chrome's History DB (Selective deletion check).
2. SQLite validation of Chrome's Web Data DB (Custom Search Engine check).
3. JSON validation of Chrome's Bookmarks (Folder organization & Purging).
4. JSON validation of Chrome's Preferences (Privacy/Download settings).
5. VLM validation of Agent Trajectory (Ensures agent used UI to do the work).
"""

import os
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    metadata = task_info.get('metadata', {})
    sensitive_names = metadata.get('sensitive_names', ['patterson', 'smith', 'hernandez', 'oconnor', "o'connor"])
    personal_domains = metadata.get('personal_domains', ['netflix', 'amazon', 'facebook', 'draftkings', 'reddit'])
    req_folders = metadata.get('professional_folders', ['Merchandise', 'Cemeteries', 'Florists', 'Vital Statistics'])
    
    score = 0
    feedback = []
    
    # =========================================================================
    # 1. Retrieve Files via copy_from_env
    # =========================================================================
    def get_json_file(cpath):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env(cpath, tmp.name)
            with open(tmp.name, 'r') as f:
                return json.load(f)
        except Exception:
            return {}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
                
    def get_db_file(cpath):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        tmp.close()
        try:
            copy_from_env(cpath, tmp.name)
            if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
                return tmp.name
            return None
        except Exception:
            return None

    bookmarks_data = get_json_file("/home/ga/.config/google-chrome/Default/Bookmarks")
    prefs_data = get_json_file("/home/ga/.config/google-chrome/Default/Preferences")
    history_db = get_db_file("/tmp/History_export.db")
    webdata_db = get_db_file("/tmp/WebData_export.db")

    # =========================================================================
    # CRITERION 1 & 2: Bookmarks (Folders & Purging) - 20 pts + 10 pts
    # =========================================================================
    def traverse_bookmarks(node, folders, urls):
        if node.get('type') == 'url':
            urls.append(node.get('url', ''))
        elif node.get('type') == 'folder':
            folders.append(node.get('name', ''))
            for child in node.get('children', []):
                traverse_bookmarks(child, folders, urls)

    all_folders = []
    all_urls = []
    bb_children = bookmarks_data.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    for child in bb_children:
        traverse_bookmarks(child, all_folders, all_urls)

    # Folders Check (20 pts)
    folders_found = [f for f in req_folders if f in all_folders]
    folder_pts = len(folders_found) * 5
    score += folder_pts
    feedback.append(f"Bookmark Folders: Found {len(folders_found)}/4 required folders (+{folder_pts} pts).")

    # Purged Personal Bookmarks Check (10 pts)
    personal_found = sum(1 for url in all_urls if any(p in url.lower() for p in personal_domains))
    if personal_found == 0 and len(all_urls) > 0:
        score += 10
        feedback.append("Personal Bookmarks: Successfully purged (+10 pts).")
    else:
        feedback.append(f"Personal Bookmarks: Found {personal_found} personal links remaining (0 pts).")

    # =========================================================================
    # CRITERION 3: Selective History Sanitization - 20 pts
    # =========================================================================
    if history_db:
        try:
            conn = sqlite3.connect(history_db)
            c = conn.cursor()
            
            # Check sensitive
            sensitive_conditions = " OR ".join([f"url LIKE '%{n}%' OR title LIKE '%{n}%'" for n in sensitive_names])
            c.execute(f"SELECT COUNT(*) FROM urls WHERE {sensitive_conditions}")
            sensitive_count = c.fetchone()[0]
            
            # Check general
            c.execute("SELECT COUNT(*) FROM urls")
            total_count = c.fetchone()[0]
            
            if sensitive_count == 0 and total_count >= 15:
                score += 20
                feedback.append(f"History: Selectively sanitized. 0 sensitive, {total_count} total remaining (+20 pts).")
            elif sensitive_count == 0 and total_count < 15:
                # Agent gamed it by deleting ALL history
                feedback.append(f"History: Sensitive items removed, but general history was also wiped! ({total_count} total) (0 pts).")
            else:
                feedback.append(f"History: Found {sensitive_count} sensitive entries remaining (0 pts).")
            conn.close()
        except Exception as e:
            feedback.append(f"History DB Error: {e}")
            if history_db and os.path.exists(history_db): os.unlink(history_db)
    else:
        feedback.append("History DB missing or inaccessible.")

    # =========================================================================
    # CRITERION 4 & 5: Privacy Settings & Downloads (Preferences) - 20 + 15 pts
    # =========================================================================
    # Privacy
    suggest_enabled = prefs_data.get('search', {}).get('suggest_enabled', True)
    address_enabled = prefs_data.get('autofill', {}).get('profile_enabled', True)
    cc_enabled = prefs_data.get('autofill', {}).get('credit_card_enabled', True)
    
    priv_score = 0
    if not suggest_enabled: priv_score += 10
    if not address_enabled: priv_score += 5
    if not cc_enabled: priv_score += 5
    
    score += priv_score
    feedback.append(f"Privacy Settings: Score {priv_score}/20 pts (Autocomplete: {not suggest_enabled}, Address: {not address_enabled}, CC: {not cc_enabled}).")

    # Downloads
    dl_dir = prefs_data.get('download', {}).get('default_directory', '')
    dl_prompt = prefs_data.get('download', {}).get('prompt_for_download', False)
    
    dl_score = 0
    if metadata['download_dir'] in dl_dir: dl_score += 10
    if dl_prompt: dl_score += 5
    
    score += dl_score
    feedback.append(f"Download Settings: Score {dl_score}/15 pts (Dir: {metadata['download_dir'] in dl_dir}, Prompt: {dl_prompt}).")

    # =========================================================================
    # CRITERION 6: Custom Search Engine - 15 pts
    # =========================================================================
    search_found = False
    
    # Check Preferences first (sometimes stored here based on version/flags)
    overrides = prefs_data.get('search_provider_overrides', [])
    if any(o.get('keyword') == 'obit' for o in overrides):
        search_found = True
        
    # Check WebData DB
    if not search_found and webdata_db:
        try:
            conn = sqlite3.connect(webdata_db)
            c = conn.cursor()
            c.execute("SELECT COUNT(*) FROM keywords WHERE keyword = 'obit'")
            count = c.fetchone()[0]
            if count > 0: search_found = True
            conn.close()
        except Exception:
            pass

    if search_found:
        score += 15
        feedback.append("Search Engine: 'obit' shortcut found (+15 pts).")
    else:
        feedback.append("Search Engine: 'obit' shortcut not found (0 pts).")

    # Cleanup temp DBs
    if history_db and os.path.exists(history_db): os.unlink(history_db)
    if webdata_db and os.path.exists(webdata_db): os.unlink(webdata_db)

    # =========================================================================
    # VLM TRAJECTORY CHECK (Anti-Gaming)
    # =========================================================================
    vlm_feedback = ""
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        # Import dynamically to prevent import errors in different runner environments
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            Look at these frames from a web browser task trajectory.
            The agent was supposed to:
            1. Open Chrome Settings (chrome://settings) to adjust Privacy/Downloads/Search Engines.
            2. Open Chrome History (chrome://history) to delete specific entries.
            3. Use the Bookmark Manager to organize bookmarks.
            
            Did the agent actually display/interact with any of these configuration interfaces (Settings, History, Bookmark Manager)?
            Respond ONLY with a JSON object: {"used_config_interfaces": true/false}
            """
            
            vlm_res = query_vlm(prompt=prompt, images=images)
            vlm_parsed = vlm_res.get("parsed", {})
            if vlm_parsed.get("used_config_interfaces", False):
                vlm_feedback = "VLM confirms interaction with Chrome configuration interfaces."
            else:
                # Deduct if they miraculously passed DB checks without using UI (Gaming)
                if score > 50:
                    score = int(score * 0.5)
                    vlm_feedback = "PENALTY: VLM found no visual evidence of using Settings/History UI. Score halved for potential script gaming."
        except Exception as e:
            vlm_feedback = f"VLM Check skipped/failed: {e}"
    else:
        vlm_feedback = "VLM function not available."

    feedback.append(vlm_feedback)
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }