#!/usr/bin/env python3
"""
Verifier for gemology_lab_workspace@1

Checks:
1. Bookmark Folders exist and correctly contain professional domains (20 + 15 pts)
2. Personal domains removed from Bookmarks AND History (15 pts)
3. Default font size >= 20 (20 pts)
4. Download directory points to Appraisal_Reports & prompt is true (15 pts)
5. Third-party cookies blocked (15 pts)
"""

import os
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any, List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def copy_file_from_container(copy_from_env, container_path: str, suffix: str = '') -> str:
    """Helper to copy a file and return local temp path."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    try:
        copy_from_env(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
    except Exception as e:
        logger.error(f"Failed to copy {container_path}: {e}")
    
    if os.path.exists(tmp.name):
        os.unlink(tmp.name)
    return None

def verify_gemology_workspace(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_folders = [f.lower() for f in metadata.get('folders', [])]
    personal_domains = metadata.get('personal_domains', [])
    prof_domains = metadata.get('professional_domains', [])
    expected_dl_dir = metadata.get('expected_download_dir', 'Appraisal_Reports')
    min_font_size = metadata.get('expected_min_font_size', 20)

    score = 0
    feedback = []
    
    # 1. Copy Files
    bookmarks_path = copy_file_from_container(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks", ".json")
    prefs_path = copy_file_from_container(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences", ".json")
    history_path = copy_file_from_container(copy_from_env, "/home/ga/.config/google-chrome/Default/History", ".sqlite")

    bookmarks_data = {}
    prefs_data = {}

    if bookmarks_path:
        try:
            with open(bookmarks_path, 'r') as f:
                bookmarks_data = json.load(f)
        except Exception:
            pass

    if prefs_path:
        try:
            with open(prefs_path, 'r') as f:
                prefs_data = json.load(f)
        except Exception:
            pass

    # --- CRITERION 1 & 2: Bookmarks (Folders & Categorization) ---
    c1_score = 0
    c2_score = 0
    found_folders = []
    
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    
    for child in bookmark_bar:
        if child.get('type') == 'folder':
            fname = child.get('name', '').lower()
            if any(expected.replace(" & ", "") in fname.replace(" & ", "") for expected in expected_folders):
                found_folders.append(fname)
                c1_score += 5  # 5 pts per folder (max 20)
                
                # Check contents of the folder for professional domains
                for item in child.get('children', []):
                    url = item.get('url', '').lower()
                    if any(pd in url for pd in prof_domains):
                        c2_score += 1 # Rough proportional credit

    c2_score = min(15, c2_score) # Max 15 pts for categorization
    
    score += c1_score
    score += c2_score
    feedback.append(f"Bookmark Folders: {c1_score}/20 pts. Categorization: {c2_score}/15 pts.")

    # --- CRITERION 3: Artifact Cleanup (Bookmarks & History) ---
    c3_score = 15
    cleanup_issues = []
    
    # Check Bookmarks for personal domains
    def check_personal_bm(nodes):
        for node in nodes:
            if node.get('type') == 'url':
                url = node.get('url', '').lower()
                if any(pd in url for pd in personal_domains):
                    return True
            if 'children' in node:
                if check_personal_bm(node['children']):
                    return True
        return False

    if check_personal_bm(bookmark_bar):
        c3_score -= 7
        cleanup_issues.append("Personal domains found in Bookmarks.")

    # Check History for personal domains
    history_ok = True
    if history_path:
        try:
            conn = sqlite3.connect(history_path)
            c = conn.cursor()
            
            # Check if personal domains exist
            query_conds = " OR ".join([f"url LIKE '%{d}%'" for d in personal_domains])
            c.execute(f"SELECT count(*) FROM urls WHERE {query_conds}")
            personal_count = c.fetchone()[0]
            
            if personal_count > 0:
                c3_score -= 8
                cleanup_issues.append(f"Found {personal_count} personal domain entries in History.")
                history_ok = False
                
            # Anti-gaming: Ensure professional domains were NOT deleted
            prof_conds = " OR ".join([f"url LIKE '%{d}%'" for d in prof_domains])
            c.execute(f"SELECT count(*) FROM urls WHERE {prof_conds}")
            prof_count = c.fetchone()[0]
            if prof_count == 0:
                c3_score = 0
                cleanup_issues.append("All professional history was deleted! Mass-deletion detected.")
                
            conn.close()
        except Exception as e:
            logger.error(f"History check failed: {e}")
            cleanup_issues.append("Failed to verify history database.")
            c3_score = 0
    else:
        cleanup_issues.append("History database not found.")
        c3_score = 0

    c3_score = max(0, c3_score)
    score += c3_score
    if cleanup_issues:
        feedback.append(f"Cleanup: {c3_score}/15 pts. Issues: {'; '.join(cleanup_issues)}")
    else:
        feedback.append(f"Cleanup: {c3_score}/15 pts. Successfully sanitized personal data.")

    # --- CRITERION 4: Font Size ---
    c4_score = 0
    font_size = prefs_data.get('webkit', {}).get('webprefs', {}).get('default_font_size', 16)
    if font_size >= min_font_size:
        c4_score = 20
        feedback.append(f"Font Size: 20/20 pts (Set to {font_size}).")
    else:
        feedback.append(f"Font Size: 0/20 pts (Currently {font_size}, expected >={min_font_size}).")
    score += c4_score

    # --- CRITERION 5: Downloads ---
    c5_score = 0
    dl_dir = prefs_data.get('download', {}).get('default_directory', '')
    dl_prompt = prefs_data.get('download', {}).get('prompt_for_download', False)
    
    if expected_dl_dir in dl_dir:
        c5_score += 8
    if dl_prompt:
        c5_score += 7
        
    score += c5_score
    feedback.append(f"Downloads: {c5_score}/15 pts (Dir: {expected_dl_dir in dl_dir}, Prompt: {dl_prompt}).")

    # --- CRITERION 6: Privacy (Cookies) ---
    c6_score = 0
    # Cookie controls mode: 1 = block third party, 2 = block all third party
    cookie_mode = prefs_data.get('profile', {}).get('cookie_controls_mode', 0)
    if cookie_mode in [1, 2]:
        c6_score = 15
        feedback.append(f"Privacy: 15/15 pts (Third-party cookies blocked).")
    else:
        feedback.append(f"Privacy: 0/15 pts (Third-party cookies not blocked, mode={cookie_mode}).")
    score += c6_score

    # Cleanup temp files
    for p in [bookmarks_path, prefs_path, history_path]:
        if p and os.path.exists(p):
            try:
                os.unlink(p)
            except:
                pass

    # Critical Requirements: Font size adjustment and Cleanup are required.
    critical_met = (c4_score == 20) and (c3_score >= 8)
    passed = (score >= 70) and critical_met

    if not critical_met and score >= 70:
        feedback.append("FAILED: Met points threshold but missed critical criteria (Font Size or Data Cleanup).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }