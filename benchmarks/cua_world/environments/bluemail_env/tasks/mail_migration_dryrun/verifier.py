#!/usr/bin/env python3
"""
Verifier for mail_migration_dryrun task.

Scoring Breakdown (100 pts):
1. Manifest File (50 pts):
   - Exists & created during task: 15 pts
   - Has header row: 5 pts
   - Row count >= 15: 20 pts (partial: 12 pts for >= 8)
   - Content looks real (cols match email metadata): 10 pts

2. Folder Organization (30 pts):
   - 2+ custom folders created: 15 pts (partial: 8 pts for 1)
   - 10+ emails moved to custom folders: 15 pts (partial: 10 pts for 5+)

3. Report Email (20 pts):
   - Draft to correct recipient: 10 pts
   - Subject/Body relevance: 10 pts

Anti-gaming:
- Manifest must have mtime > task_start_time.
- "Do nothing" (no file, no folders, no draft) = 0 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mail_migration_dryrun(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('report_recipient', 'it-migration@company.com').lower()
    min_rows = metadata.get('min_manifest_rows', 15)
    
    # 1. Retrieve Result
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
    feedback = []
    
    analysis = result.get('analysis', {})
    manifest_info = analysis.get('manifest', {})
    
    # --- CRITERION 1: MANIFEST FILE (50 pts) ---
    manifest_exists = result.get('manifest_exists', False)
    manifest_mtime = int(result.get('manifest_mtime', 0))
    task_start = int(result.get('task_start_time', 0))
    
    # Check 1: Existence & Timing
    if manifest_exists and manifest_mtime > task_start:
        score += 15
        feedback.append("Manifest file created.")
        
        # Check 2: Header
        if manifest_info.get('has_header', False):
            score += 5
            feedback.append("Manifest has header.")
        
        # Check 3: Row Count
        row_count = manifest_info.get('row_count', 0)
        if row_count >= min_rows:
            score += 20
            feedback.append(f"Manifest has sufficient rows ({row_count}).")
        elif row_count >= (min_rows // 2):
            score += 12
            feedback.append(f"Manifest has partial rows ({row_count}).")
        elif row_count > 0:
            score += 5
            feedback.append(f"Manifest has few rows ({row_count}).")
            
        # Check 4: Content Validation
        cols = manifest_info.get('cols', [])
        # Look for keywords like 'subject', 'sender', 'from', 'date' in header
        relevant_cols = [c for c in cols if any(k in c for k in ['subject', 'sender', 'from', 'date', 'title'])]
        if len(relevant_cols) >= 2:
            score += 10
            feedback.append("Manifest columns look valid.")
        else:
            feedback.append(f"Manifest columns unclear: {cols}")
    else:
        feedback.append("Manifest file not created or not modified during task.")

    # --- CRITERION 2: FOLDER ORGANIZATION (30 pts) ---
    custom_folders = analysis.get('custom_folders', {})
    folder_count = analysis.get('custom_folder_count', 0)
    moved_count = analysis.get('emails_in_custom_folders', 0)
    
    # Check 1: Folders Created
    if folder_count >= 2:
        score += 15
        feedback.append(f"Created {folder_count} custom folders.")
    elif folder_count == 1:
        score += 8
        feedback.append("Created 1 custom folder.")
        
    # Check 2: Emails Moved
    if moved_count >= 10:
        score += 15
        feedback.append(f"Moved {moved_count} emails to folders.")
    elif moved_count >= 5:
        score += 10
        feedback.append(f"Moved {moved_count} emails (partial).")
    elif moved_count > 0:
        score += 5
        feedback.append("Moved a few emails.")
        
    # --- CRITERION 3: REPORT EMAIL (20 pts) ---
    drafts = analysis.get('drafts', [])
    report_found = False
    
    for draft in drafts:
        to_field = draft.get('to', '').lower()
        if expected_recipient in to_field:
            score += 10
            feedback.append("Report draft found to correct recipient.")
            
            # Content check
            subj = draft.get('subject', '').lower()
            body = draft.get('body', '').lower()
            if any(w in subj for w in ['migration', 'dry', 'run', 'report']) or \
               any(w in body for w in ['count', 'total', 'folder', 'inventoried']):
                score += 10
                feedback.append("Report content relevant.")
            report_found = True
            break
            
    if not report_found:
        feedback.append("No report draft found to correct recipient.")

    # --- FINAL RESULT ---
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }