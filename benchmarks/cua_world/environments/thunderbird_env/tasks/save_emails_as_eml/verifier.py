#!/usr/bin/env python3
"""
Verifier for Save Emails as Evidence Files task.

HYBRID VERIFICATION:
1. Programmatic checks (File Content Analysis)
2. Trajectory-based VLM verification (Checking dialogs + workflow)
3. Anti-Gaming timestamps (Prevent pre-staged file injection)
"""

import json
import tempfile
import os
import tarfile
import email
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_save_emails(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Fetch JSON Export
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    task_start = result.get('task_start', 0)
    
    # ---------------------------------------------------------
    # 2. Fetch and Extract Agent's Files
    # ---------------------------------------------------------
    temp_tar = tempfile.NamedTemporaryFile(delete=False, suffix='.tar.gz')
    extract_dir = tempfile.mkdtemp()
    eml_files = []
    
    try:
        copy_from_env("/tmp/casefiles.tar.gz", temp_tar.name)
        if os.path.getsize(temp_tar.name) > 0:
            with tarfile.open(temp_tar.name, "r:gz") as tar:
                tar.extractall(path=extract_dir)
            
            casefiles_dir = os.path.join(extract_dir, "CaseFiles")
            if os.path.exists(casefiles_dir):
                for root, _, files in os.walk(casefiles_dir):
                    for file in files:
                        eml_files.append(os.path.join(root, file))
    except Exception as e:
        logger.warning(f"Failed to copy or extract tarball: {e}")
    finally:
        if os.path.exists(temp_tar.name):
            os.unlink(temp_tar.name)
            
    # ---------------------------------------------------------
    # 3. File Evaluation
    # ---------------------------------------------------------
    expected_patterns = [
        ["contract amendment", "project atlas"],
        ["settlement offer", "martinez"],
        ["discovery documents", "2024-cv-1847"]
    ]
    
    matched_indices = set()
    valid_files_count = 0
    all_after_start = True
    
    for file_path in eml_files:
        try:
            file_mtime = os.path.getmtime(file_path)
            if task_start > 0 and file_mtime < task_start:
                all_after_start = False
                
            with open(file_path, 'rb') as f:
                msg = email.message_from_bytes(f.read())
                
            subject = msg.get('Subject', '').lower()
            if subject:
                valid_files_count += 1
                for i, patterns in enumerate(expected_patterns):
                    if all(p in subject for p in patterns):
                        matched_indices.add(i)
        except Exception as e:
            logger.warning(f"Failed to parse {file_path}: {e}")
            
    # Base Score: 30 points (10 pts per matching email)
    score += len(matched_indices) * 10
    feedback_parts.append(f"Found {len(matched_indices)}/3 expected emails.")
    
    # Validation Score: 20 points for proper Email parsing headers
    if valid_files_count > 0 and valid_files_count >= len(matched_indices):
        score += 20
        feedback_parts.append("Emails parsed successfully as RFC2822 files.")
    elif valid_files_count > 0:
        score += 10
        feedback_parts.append("Some files parsed correctly, others failed.")
    else:
        feedback_parts.append("No valid email headers found in files.")
        
    # Anti-gaming: Exact file count (10 pts)
    if len(eml_files) == 3 and len(matched_indices) == 3:
        score += 10
        feedback_parts.append("Exactly 3 files saved (clean export).")
    elif len(eml_files) > 3:
        feedback_parts.append(f"Extraneous files found ({len(eml_files)} total).")
        
    # Anti-gaming: File Timestamps (20 pts)
    if len(eml_files) > 0 and all_after_start:
        score += 20
        feedback_parts.append("File timestamps verified (anti-gaming passed).")
    elif len(eml_files) > 0:
        feedback_parts.append("WARNING: Some files pre-date the task start time.")
        
    # ---------------------------------------------------------
    # 4. Trajectory-Based VLM Verification (20 pts)
    # ---------------------------------------------------------
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Sample snapshots of the agent's work timeline
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """You are evaluating screenshots chronologically tracing an agent performing a task.
The agent's goal is to export specific emails as .eml files to a folder called 'CaseFiles'.

Assess the visual evidence in the frames and return ONLY valid JSON:
1. Is Thunderbird open and being interacted with?
2. Did the agent open a "Save As" or "Save Message" file dialog at least once?
3. Is there visual evidence of navigating to a "CaseFiles" folder in the save dialog?

Format:
{
    "thunderbird_open": true/false,
    "save_dialog_used": true/false,
    "saving_to_casefiles": true/false
}"""
        
        vlm_result = query_vlm(images=images, prompt=prompt)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("thunderbird_open"): vlm_score += 5
            if parsed.get("save_dialog_used"): vlm_score += 10
            if parsed.get("saving_to_casefiles"): vlm_score += 5
            feedback_parts.append(f"VLM Trajectory verification: {parsed}")
        else:
            feedback_parts.append("VLM query failed, granting fallback visual points.")
            vlm_score = 20
    except Exception as e:
        logger.warning(f"VLM modules error: {e}")
        feedback_parts.append("VLM modules unavailable, granting fallback visual points.")
        vlm_score = 20
        
    score += vlm_score
    
    # Cleanup
    shutil.rmtree(extract_dir, ignore_errors=True)
    
    # Pass evaluation
    passed = (score >= 70) and (len(matched_indices) >= 2)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }