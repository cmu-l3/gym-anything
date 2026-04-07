#!/usr/bin/env python3
"""
Verifier for Wind Farm SCADA Console Task (wind_farm_scada_console@1)

Verifies 7 criteria (100 pts total):
1. Junk bookmarks deleted (15 pts)
2. Operational bookmarks organized into 4 required folders (20 pts)
3. Chrome Flags (offline-auto-reload, no-quic, no-smooth-scrolling) configured (15 pts)
4. Diagnostic Search Engines (fault, part) added (15 pts)
5. Font sizes enlarged (15 pts)
6. Startup configured to restore session (10 pts)
7. LOTO manual PDF downloaded successfully (10 pts)

Pass threshold: 75 points
"""

import os
import sys
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target Domains
JUNK_DOMAINS = [
    "ign.com", "draftkings.com", "netflix.com", "steampowered.com",
    "espn.com", "reddit.com", "twitch.tv", "hulu.com"
]

REQUIRED_FOLDERS = [
    "Weather & Forecasting",
    "SCADA Control",
    "OEM Manuals",
    "Safety & LOTO"
]

def _copy_and_parse_json(copy_from_env, container_path: str) -> Optional[Dict]:
    """Helper to copy a file from the container and parse it as JSON."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = tmp.name
    tmp.close()
    
    try:
        copy_from_env(container_path, tmp_path)
        if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 0:
            with open(tmp_path, 'r', encoding='utf-8') as f:
                return json.load(f)
    except Exception as e:
        logger.warning(f"Failed to copy/parse {container_path}: {e}")
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
    return None

def _copy_file_to_temp(copy_from_env, container_path: str) -> Optional[str]:
    """Helper to copy a file from the container and return its local path."""
    tmp = tempfile.NamedTemporaryFile(delete=False)
    tmp_path = tmp.name
    tmp.close()
    
    try:
        copy_from_env(container_path, tmp_path)
        if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 0:
            return tmp_path
    except Exception as e:
        logger.warning(f"Failed to copy {container_path}: {e}")
    
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    return None

def _collect_bookmarks(node: Dict, collected: List[Dict]):
    """Recursively collect all URL bookmarks."""
    if node.get('type') == 'url':
        collected.append(node)
    for child in node.get('children', []):
        _collect_bookmarks(child, collected)

def check_junk_bookmarks(bookmarks_data: Dict) -> Tuple[int, str]:
    if not bookmarks_data:
        return 0, "❌ Failed to read Bookmarks file."
    
    all_bms = []
    _collect_bookmarks(bookmarks_data.get('roots', {}), all_bms)
    
    found_junk = []
    for bm in all_bms:
        url = bm.get('url', '').lower()
        for junk in JUNK_DOMAINS:
            if junk in url:
                found_junk.append(junk)
                break
                
    if not found_junk:
        return 15, "✅ All junk bookmarks successfully deleted."
    
    deduplicated = list(set(found_junk))
    penalty = len(deduplicated) * 2
    score = max(0, 15 - penalty)
    return score, f"❌ Found {len(deduplicated)} remaining junk domains (e.g., {deduplicated[0]})."

def check_operational_folders(bookmarks_data: Dict) -> Tuple[int, str]:
    if not bookmarks_data:
        return 0, "❌ Failed to read Bookmarks file."
    
    bar_children = bookmarks_data.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    
    folders_found = []
    score = 0
    feedback = []
    
    for req_f in REQUIRED_FOLDERS:
        # Find folder case-insensitive/approximate
        req_clean = req_f.lower().replace('&', 'and')
        folder_node = None
        for child in bar_children:
            if child.get('type') == 'folder':
                child_clean = child.get('name', '').lower().replace('&', 'and')
                if req_clean in child_clean or child_clean in req_clean:
                    folder_node = child
                    break
        
        if folder_node:
            urls = []
            _collect_bookmarks(folder_node, urls)
            if len(urls) >= 2:
                score += 5
                folders_found.append(req_f)
            else:
                feedback.append(f"❌ Folder '{req_f}' found, but contains < 2 bookmarks.")
        else:
            feedback.append(f"❌ Folder '{req_f}' not found on the bookmark bar.")
            
    if score == 20:
        return 20, "✅ All 4 operational folders correctly created and populated."
    
    return score, " ".join(feedback)

def check_chrome_flags(local_state_data: Dict) -> Tuple[int, str]:
    if not local_state_data:
        return 0, "❌ Failed to read Local State file for flags."
    
    experiments = local_state_data.get('browser', {}).get('enabled_labs_experiments', [])
    
    score = 0
    feedback = []
    
    if "enable-offline-auto-reload@1" in experiments:
        score += 5
        feedback.append("✅ Offline Auto-Reload enabled.")
    else:
        feedback.append("❌ Offline Auto-Reload NOT enabled.")
        
    if "enable-quic@2" in experiments:
        score += 5
        feedback.append("✅ QUIC protocol disabled.")
    else:
        feedback.append("❌ QUIC protocol NOT disabled.")
        
    if "smooth-scrolling@2" in experiments:
        score += 5
        feedback.append("✅ Smooth Scrolling disabled.")
    else:
        feedback.append("❌ Smooth Scrolling NOT disabled.")
        
    return score, " ".join(feedback)

def check_search_engines(web_data_path: str) -> Tuple[int, str]:
    if not web_data_path:
        return 0, "❌ Failed to retrieve Web Data database."
        
    score = 0
    feedback = []
    
    try:
        conn = sqlite3.connect(web_data_path)
        cursor = conn.cursor()
        cursor.execute("SELECT keyword, url FROM keywords")
        rows = cursor.fetchall()
        conn.close()
        
        fault_found = False
        part_found = False
        
        for keyword, url in rows:
            kw = str(keyword).lower()
            u = str(url).lower()
            if 'fault' in kw and 'kb.blueridge-wind.local/search?fault_code=' in u:
                fault_found = True
            if 'part' in kw and 'parts.windoem.com/catalog?sku=' in u:
                part_found = True
                
        if fault_found:
            score += 7
            feedback.append("✅ Fault DB search engine configured.")
        else:
            feedback.append("❌ Fault DB search engine missing/incorrect.")
            
        if part_found:
            score += 8
            feedback.append("✅ Part Catalog search engine configured.")
        else:
            feedback.append("❌ Part Catalog search engine missing/incorrect.")
            
    except Exception as e:
        logger.error(f"SQLite error reading keywords: {e}")
        return 0, "❌ Error analyzing Search Engines database."
        
    return score, " ".join(feedback)

def check_preferences(prefs_data: Dict) -> Tuple[int, int, str]:
    if not prefs_data:
        return 0, 0, "❌ Failed to read Preferences file."
    
    # Fonts
    font_score = 0
    font_feedback = []
    
    webprefs = prefs_data.get('webkit', {}).get('webprefs', {})
    def_font = webprefs.get('default_font_size', 16)
    min_font = webprefs.get('minimum_font_size', 0)
    
    if def_font == 22:
        font_score += 7
        font_feedback.append("✅ Default font size is 22.")
    else:
        font_feedback.append(f"❌ Default font size is {def_font} (expected 22).")
        
    if min_font == 16:
        font_score += 8
        font_feedback.append("✅ Minimum font size is 16.")
    else:
        font_feedback.append(f"❌ Minimum font size is {min_font} (expected 16).")
        
    # Startup
    startup_score = 0
    startup_feedback = ""
    restore_behavior = prefs_data.get('session', {}).get('restore_on_startup', 0)
    
    if restore_behavior == 1:
        startup_score = 10
        startup_feedback = "✅ Startup set to restore previous session."
    else:
        startup_feedback = "❌ Startup NOT set to restore previous session."
        
    return font_score, startup_score, " ".join(font_feedback) + " | " + startup_feedback

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback_parts = []
    
    # ── Retrieve Files ──────────────────────────────────────────
    bookmarks_data = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks")
    local_state_data = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome/Local State")
    prefs_data = _copy_and_parse_json(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences")
    task_result = _copy_and_parse_json(copy_from_env, "/tmp/task_result.json")
    
    web_data_path = _copy_file_to_temp(copy_from_env, "/tmp/chrome_export/Web Data")
    if not web_data_path:
        web_data_path = _copy_file_to_temp(copy_from_env, "/home/ga/.config/google-chrome/Default/Web Data")

    # ── Criterion 1: Junk Bookmarks (15 pts) ──────────────────────
    s1, f1 = check_junk_bookmarks(bookmarks_data)
    score += s1
    feedback_parts.append(f"[1] Junk Bookmarks ({s1}/15): {f1}")

    # ── Criterion 2: Operational Folders (20 pts) ─────────────────
    s2, f2 = check_operational_folders(bookmarks_data)
    score += s2
    feedback_parts.append(f"[2] Operational Folders ({s2}/20): {f2}")

    # ── Criterion 3: Chrome Flags (15 pts) ────────────────────────
    s3, f3 = check_chrome_flags(local_state_data)
    score += s3
    feedback_parts.append(f"[3] Chrome Flags ({s3}/15): {f3}")

    # ── Criterion 4: Search Engines (15 pts) ──────────────────────
    s4, f4 = check_search_engines(web_data_path)
    score += s4
    feedback_parts.append(f"[4] Search Engines ({s4}/15): {f4}")
    
    if web_data_path and os.path.exists(web_data_path):
        os.unlink(web_data_path)

    # ── Criteria 5 & 6: Fonts (15 pts) & Startup (10 pts) ─────────
    s5, s6, f56 = check_preferences(prefs_data)
    score += s5 + s6
    feedback_parts.append(f"[5&6] Fonts & Startup ({(s5+s6)}/25): {f56}")

    # ── Criterion 7: PDF Download (10 pts) ────────────────────────
    s7 = 0
    f7 = "❌ PDF download status unknown."
    if task_result:
        pdf_exists = task_result.get("pdf_exists", False)
        during_task = task_result.get("pdf_downloaded_during_task", False)
        size = task_result.get("pdf_size_bytes", 0)
        
        if pdf_exists and during_task and size > 0:
            s7 = 10
            f7 = "✅ LOTO procedure PDF downloaded successfully."
        elif pdf_exists:
            f7 = "❌ PDF exists but timestamps suggest it was not downloaded by agent."
        else:
            f7 = "❌ LOTO procedure PDF not found in target directory."
            
    score += s7
    feedback_parts.append(f"[7] Safety PDF ({s7}/10): {f7}")

    # ── Final Assessment ──────────────────────────────────────────
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }