#!/usr/bin/env python3
"""
Verifier for Digital Archival Workspace Task (digital_archival_workspace@1)
Evaluates Chrome configuration based on copied JSON and SQLite files.
"""

import os
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _copy_file(copy_from_env, container_paths: List[str], suffix: str = '.json') -> Optional[str]:
    """Helper to copy a file from the container, trying multiple candidate paths."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp_path = tmp.name
    tmp.close()

    for cpath in container_paths:
        try:
            copy_from_env(cpath, tmp_path)
            if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 10:
                return tmp_path
        except Exception:
            pass

    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    return None

def _collect_bookmarks(node: Dict, collected: List[Dict]) -> None:
    if isinstance(node, dict):
        if node.get('type') == 'url':
            collected.append(node)
        for child in node.get('children', []):
            _collect_bookmarks(child, collected)

def _find_folder_fuzzy(children: List[Dict], keywords: List[str]) -> Optional[Dict]:
    for child in children:
        if child.get('type') == 'folder':
            name_lower = child.get('name', '').lower()
            if all(kw.lower() in name_lower for kw in keywords):
                return child
    return None

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available."}

    # Extract Files
    bookmarks_local = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Default/Bookmarks"])
    prefs_local = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Default/Preferences"])
    local_state_local = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Local State"])
    web_data_local = _copy_file(copy_from_env, ["/home/ga/.config/google-chrome/Default/Web Data"], suffix='.sqlite')

    score = 0
    feedback = []
    
    # Flags tracking for strict pass conditions
    mhtml_enabled = False
    prefetch_disabled = False

    try:
        # ==========================================
        # 1 & 2. Bookmarks Organization & Cleanup
        # ==========================================
        if bookmarks_local:
            with open(bookmarks_local, 'r') as f:
                bm_data = json.load(f)
            
            bbar_children = bm_data.get('roots', {}).get('bookmark_bar', {}).get('children', [])
            all_bms = []
            _collect_bookmarks(bm_data.get('roots', {}), all_bms)
            all_urls = [b.get('url', '').lower() for b in all_bms]

            # A. Clutter Deletion (10 points)
            clutter_domains = ['netflix.com', 'reddit.com', 'buzzfeed.com', 'twitter.com', 'x.com']
            clutter_found = [d for d in clutter_domains if any(d in u for u in all_urls)]
            if not clutter_found:
                score += 10
                feedback.append("✅ Clutter/personal bookmarks successfully deleted (+10)")
            else:
                feedback.append(f"❌ Clutter bookmarks still present: {', '.join(clutter_found)} (+0)")

            # B. Organization (20 points, 5 per folder)
            folders_to_check = [
                (["web", "archives"], ["archive.org", "perma.cc", "conifer", "archive-it"]),
                (["metadata", "standards"], ["dublincore", "premis", "mets"]),
                (["repositories"], ["dspace", "fedora", "eprints"]),
                (["crawl", "tools"], ["heritrix", "webrecorder"])
            ]
            
            folder_score = 0
            for keywords, expected_domains in folders_to_check:
                folder = _find_folder_fuzzy(bbar_children, keywords)
                if folder:
                    f_bms = []
                    _collect_bookmarks(folder, f_bms)
                    f_urls = [b.get('url', '').lower() for b in f_bms]
                    matches = sum(1 for d in expected_domains if any(d in u for u in f_urls))
                    
                    if matches >= 2:
                        folder_score += 5
                        feedback.append(f"✅ Folder '{keywords[0]}' created and populated correctly (+5)")
                    else:
                        feedback.append(f"❌ Folder '{keywords[0]}' exists but is missing expected URLs (+0)")
                else:
                    feedback.append(f"❌ Folder matching '{keywords[0]}' not found (+0)")
            score += folder_score
        else:
            feedback.append("❌ Could not read Bookmarks file (+0)")

        # ==========================================
        # 3. Chrome Flags (MHTML & Reader Mode)
        # ==========================================
        if local_state_local:
            with open(local_state_local, 'r') as f:
                ls_data = json.load(f)
            
            labs = ls_data.get('browser', {}).get('enabled_labs_experiments', [])
            labs_str = " ".join(labs).lower()

            if 'save-page-as-mhtml' in labs_str:
                score += 15
                mhtml_enabled = True
                feedback.append("✅ MHTML flag enabled (+15)")
            else:
                feedback.append("❌ MHTML flag NOT enabled (+0)")

            if 'enable-reader-mode' in labs_str:
                score += 10
                feedback.append("✅ Reader Mode flag enabled (+10)")
            else:
                feedback.append("❌ Reader Mode flag NOT enabled (+0)")
        else:
            feedback.append("❌ Could not read Local State file (+0)")

        # ==========================================
        # 4. Download & 5. Privacy Settings
        # ==========================================
        if prefs_local:
            with open(prefs_local, 'r') as f:
                prefs_data = json.load(f)
            
            # Downloads (15 points)
            dl_dir = prefs_data.get('download', {}).get('default_directory', '')
            dl_prompt = prefs_data.get('download', {}).get('prompt_for_download', False)
            
            dl_score = 0
            if "Web_Archives" in dl_dir:
                dl_score += 10
            if dl_prompt is True:
                dl_score += 5
                
            score += dl_score
            if dl_score == 15:
                feedback.append("✅ Download directory and prompt correctly configured (+15)")
            else:
                feedback.append(f"⚠️ Download config partially/not correct (score: {dl_score}/15)")

            # Network Prefetching (15 points)
            # Chrome uses net.network_prediction_options (2 = never) OR dns_prefetching.enabled
            pred_options = prefs_data.get('net', {}).get('network_prediction_options')
            dns_prefetch = prefs_data.get('dns_prefetching', {}).get('enabled')
            
            if pred_options == 2 or dns_prefetch is False:
                score += 15
                prefetch_disabled = True
                feedback.append("✅ Network prefetching correctly disabled (+15)")
            else:
                feedback.append("❌ Network prefetching NOT disabled (+0)")
        else:
            feedback.append("❌ Could not read Preferences file (+0)")

        # ==========================================
        # 6. Custom Search Engine (Web Data)
        # ==========================================
        se_found = False
        if web_data_local:
            try:
                conn = sqlite3.connect(web_data_local)
                cursor = conn.cursor()
                cursor.execute("SELECT keyword, url FROM keywords")
                for kw, url in cursor.fetchall():
                    if kw and url and 'ia' in kw.lower() and 'archive.org/web' in url.lower():
                        se_found = True
                        break
                conn.close()
            except sqlite3.Error as e:
                logger.error(f"SQLite error reading Web Data: {e}")

        if se_found:
            score += 15
            feedback.append("✅ Custom Search Engine 'Wayback (ia)' configured (+15)")
        else:
            feedback.append("❌ Custom Search Engine 'Wayback (ia)' NOT found (+0)")

    finally:
        # Cleanup temp files
        for p in [bookmarks_local, prefs_local, local_state_local, web_data_local]:
            if p and os.path.exists(p):
                os.unlink(p)

    # Final Pass Condition Evaluation
    # Archival MUST have MHTML and disabled prefetch to be considered successful.
    key_criteria_met = mhtml_enabled and prefetch_disabled
    passed = (score >= 75) and key_criteria_met

    feedback_str = "\n".join(feedback)
    if passed:
        feedback_str = f"🎉 PASS: Task completed successfully (Score: {score}/100)\n\n" + feedback_str
    else:
        feedback_str = f"⚠️ FAIL: Task not completed (Score: {score}/100)\n"
        if score >= 75 and not key_criteria_met:
            feedback_str += "Note: Score threshold met, but critical archival capabilities (MHTML or Prefetch toggle) were missed.\n"
        feedback_str += "\n" + feedback_str

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }