#!/usr/bin/env python3
"""
Verifier for offline_reference_archive_creation task.

SCORING CRITERIA:
1. Target folder creation (10 pts)
2. File Quantity (30 pts) - At least 3 files saved
3. File Validity/Content (25 pts) - Files are PDFs/EMLs and contain keywords
4. Draft Confirmation (20 pts) - Email drafted to dispatch@company.com
5. VLM Workflow Verification (15 pts) - Evidence of search and save dialogs

Pass threshold: 70 points
"""

import json
import tempfile
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_offline_archive(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_files = metadata.get('min_files', 3)
    target_dir = metadata.get('target_dir', '/home/ga/Documents/OfflineDocs')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Folder Creation (10 pts)
    if result.get('dir_exists'):
        score += 10
        feedback_parts.append(f"Folder '{os.path.basename(target_dir)}' created")
    else:
        feedback_parts.append("Target folder NOT created")

    # 2. File Quantity (30 pts)
    file_count = result.get('file_count', 0)
    if file_count >= min_files:
        score += 30
        feedback_parts.append(f"Saved {file_count} files (Target: {min_files}+)")
    elif file_count > 0:
        # Partial credit: 10 pts per file up to 20
        partial = file_count * 10
        score += partial
        feedback_parts.append(f"Saved {file_count} files (Partial credit)")
    else:
        feedback_parts.append("No files saved")

    # 3. File Validity & Content (25 pts)
    # Check extensions and content flag
    files_meta = result.get('files_metadata', [])
    valid_extensions = ['.pdf', '.eml', '.txt', '.html']
    valid_files = 0
    for f in files_meta:
        if any(f['extension'] == ext for ext in valid_extensions) and f['size'] > 100:
            valid_files += 1
    
    if valid_files >= min_files and result.get('relevant_content_found'):
        score += 25
        feedback_parts.append("Files contain relevant keywords (RAID/Kernel)")
    elif result.get('relevant_content_found'):
        score += 15
        feedback_parts.append("Files contain keywords but some formats/sizes questionable")
    elif valid_files > 0:
        score += 10
        feedback_parts.append("Files saved but keywords not detected in content")

    # 4. Draft Confirmation (20 pts)
    if result.get('draft_found'):
        score += 20
        feedback_parts.append("Confirmation email drafted")
        # Bonus for correct subject?
        subj = result.get('draft_subject', '').lower()
        if 'offline' in subj or 'docs' in subj:
            feedback_parts.append("(Subject correct)")
    else:
        feedback_parts.append("No confirmation draft found")

    # 5. VLM Workflow Verification (15 pts)
    # Check if they actually searched and used print/save dialogs
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')
    
    vlm_score = 0
    if query_vlm and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt="""Analyze these screenshots of an email client workflow.
                    
                    Look for:
                    1. A search performed (search bar usage, keywords like 'RAID' or 'Kernel').
                    2. A 'Print' dialog, 'Save As' dialog, or file picker window appearing.
                    3. A 'Compose' window for the final email.
                    
                    Return JSON:
                    {
                        "search_performed": true/false,
                        "save_dialog_visible": true/false,
                        "compose_visible": true/false
                    }"""
                )
                
                parsed = vlm_result.get('parsed', {}) if isinstance(vlm_result, dict) else {}
                
                if parsed.get('search_performed'): vlm_score += 5
                if parsed.get('save_dialog_visible'): vlm_score += 5
                if parsed.get('compose_visible'): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM verified workflow actions (+{vlm_score}pts)")
        except Exception as e:
            # Fallback if VLM fails - give partial credit if files exist (benefit of doubt)
            if file_count >= min_files:
                score += 10
                feedback_parts.append("VLM skipped, implicit workflow credit")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }