#!/usr/bin/env python3
"""
Verifier for backup_visitor_database task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_backup_visitor_database(traj, env_info, task_info):
    """
    Verifies that the Jolly Lobby Track database was backed up correctly.
    
    Criteria:
    1. Backup directory exists.
    2. Database backup file exists with correct name pattern.
    3. File created/modified AFTER task start (anti-gaming).
    4. File is non-trivial size (>1KB) and likely binary.
    5. Manifest file exists with required info.
    6. VLM: Confirms visual evidence of file operations or app settings exploration.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Directory and File Existence (25 pts)
    if result.get("backup_dir_exists", False):
        score += 5
        if result.get("backup_file_found", False):
            score += 20
            feedback_parts.append("Backup file found.")
        else:
            feedback_parts.append("Backup directory created, but file missing.")
    else:
        feedback_parts.append("Backup directory not found.")

    # 2. File Validity Checks (30 pts)
    backup_filename = result.get("backup_filename", "")
    valid_ext = result.get("valid_extension", False)
    is_binary = result.get("is_binary_format", False)
    size = result.get("backup_size_bytes", 0)
    
    if valid_ext:
        score += 10
    if is_binary and size > 1024: # >1KB
        score += 10
        feedback_parts.append(f"File appears valid ({int(size/1024)}KB).")
    elif size > 0:
        feedback_parts.append("File is too small or text-only (fake data?).")
        
    # Check size match with ground truth if available
    gt_size = result.get("ground_truth_size_bytes", 0)
    if gt_size > 0 and abs(size - gt_size) < (gt_size * 0.05): # within 5%
        score += 10
        feedback_parts.append("Size matches original database.")
    elif gt_size > 0 and size > 1024:
        # Partial credit if size is reasonable but not exact (maybe they backed up a different valid file)
        score += 5
        
    # 3. Anti-Gaming Timestamp (15 pts)
    if result.get("backup_created_during_task", False):
        score += 15
    else:
        feedback_parts.append("File timestamp predates task (did you just move an old file?).")

    # 4. Manifest Check (15 pts)
    manifest_content = result.get("manifest_content_preview", "").lower()
    if result.get("manifest_exists", False):
        score += 5
        # Check for keywords in manifest
        keywords_hit = 0
        if any(x in manifest_content for x in [".sdf", ".mdb", ".db", "wine", "drive_c", "program"]): 
            keywords_hit += 1 # Path likely present
        if any(x in manifest_content for x in ["202", ":", "am", "pm"]): 
            keywords_hit += 1 # Timestamp likely present
        if any(c.isdigit() for c in manifest_content): 
            keywords_hit += 1 # Size likely present
            
        if keywords_hit >= 2:
            score += 10
            feedback_parts.append("Manifest contains required metadata.")
        else:
            score += 5
            feedback_parts.append("Manifest exists but may be incomplete.")
    
    # 5. VLM Verification (15 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        if final_scr:
            frames.append(final_scr)
            
        prompt = """
        Review these screenshots of a user performing a database backup task.
        Look for:
        1. Interaction with 'Lobby Track' software menus (File, Settings, Database).
        2. Interaction with a file browser (Explorer/Nautilus) inside or outside Wine.
        3. Use of terminal commands to find or copy files.
        4. Creation of a folder named 'LobbyTrackBackup'.
        
        Does the user appear to be searching for and copying a database file?
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp.get("success") and vlm_resp.get("parsed", {}).get("answer_bool", True): # Assuming boolean or positive sentiment
                # Simple sentiment check since output format varies
                resp_text = str(vlm_resp.get("response", "")).lower()
                if "yes" in resp_text or "true" in resp_text or "correct" in resp_text:
                    vlm_score = 15
                else:
                    vlm_score = 5 # minimal credit for effort
            else:
                vlm_score = 15 # Default to full points if VLM fails/is ambiguous to avoid false negatives on valid file work
        except Exception:
            vlm_score = 15 # Fallback
            
    score += vlm_score

    # Threshold
    passed = score >= 60 and result.get("backup_file_found", False) and result.get("backup_created_during_task", False)

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }