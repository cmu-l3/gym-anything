#!/usr/bin/env python3
"""
Verifier for Audit Mail Groups Task.

Verification Strategy:
1. Infrastructure: VistA running, YDBGui accessible.
2. File Evidence: Report file exists and was created during the task.
3. Content Accuracy: The names listed in the report match actual Mail Groups in VistA (^XMB(3.8)).
4. Visual Evidence: VLM trajectory analysis confirms navigation to ^XMB(3.8).
"""

import json
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_mail_groups(traj, env_info, task_info):
    """
    Verify the agent audited Mail Groups correctly.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Retrieve Result JSON
    # We use a unique temp file to avoid collisions
    import tempfile
    fd, temp_path = tempfile.mkstemp(suffix='.json')
    os.close(fd)
    
    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    
    # 3. Infrastructure Check (10 pts)
    if result.get('vista_running') and result.get('ydbgui_accessible'):
        score += 10
        feedback_parts.append("Infrastructure OK.")
    else:
        feedback_parts.append("Infrastructure check failed (VistA or YDBGui down).")

    # 4. File Existence & Anti-Gaming (10 pts)
    file_content = result.get('file_content', '')
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("Report file created successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("Report file exists but timestamp check failed (pre-existing?).")
    else:
        feedback_parts.append("Report file not found.")

    # 5. Content Verification (45 pts)
    # Parse agent report
    # We split by newlines and common separators, ignoring empty lines
    agent_lines = [line.strip() for line in re.split(r'[\r\n]+', file_content) if line.strip()]
    
    # Parse ground truth (raw string from M output)
    ground_truth_raw = result.get('ground_truth_names', '')
    ground_truth_set = set(name.strip().upper() for name in ground_truth_raw.split('\n') if name.strip())
    
    valid_matches = 0
    matched_names = []
    
    # Logic: Look for mail group names in the agent's lines.
    # Since agent might write "1. PHARMACY", we check if the line *contains* a valid group name.
    # To be strict but fair: we check if any known group name is a substring of the agent's line.
    for line in agent_lines:
        line_upper = line.upper()
        # Find if this line matches a known group
        # Optimization: Exact match preferred, then substring
        if line_upper in ground_truth_set:
            valid_matches += 1
            matched_names.append(line_upper)
            continue
        
        # Check substring (risky if group names are very short, but MailMan names usually unique enough)
        # We'll skip very short names (<3 chars) for substring check to avoid false positives
        found = False
        for gt_name in ground_truth_set:
            if len(gt_name) > 3 and gt_name in line_upper:
                valid_matches += 1
                matched_names.append(gt_name)
                found = True
                break
        if not found and line_upper in ground_truth_set: # Catch short exact matches
             valid_matches += 1
             matched_names.append(line_upper)

    # Cap matches at unique count to prevent duplicate padding
    unique_matches = len(set(matched_names))
    
    # Scoring for content:
    # Target is 10 valid groups.
    # 4.5 points per valid group up to 10 groups = 45 points.
    content_score = min(45, unique_matches * 4.5)
    score += content_score
    
    if unique_matches >= 10:
        feedback_parts.append(f"Content valid: Found {unique_matches} valid mail groups.")
    else:
        feedback_parts.append(f"Content partial: Found {unique_matches}/10 valid mail groups.")

    # 6. VLM Visual Verification (35 pts)
    # We check frames for evidence of ^XMB(3.8) navigation
    vlm_score = 0
    if query_vlm:
        # Sample frames from trajectory
        frames = traj.get('images', []) # Assuming standard gym interface
        # Or use whatever helper is available to get frames. 
        # Since 'traj' structure varies, we assume standard usage or helper.
        # Fallback to final screenshot if trajectory not available easily
        
        # We will use the final screenshot path from result JSON as primary check if traj is complex
        final_ss_path = result.get('screenshot_path')
        
        prompt = """
        Analyze this screenshot of the VistA YDBGui interface.
        I am looking for evidence that the user is browsing the MailMan Mail Group file.
        
        Indicators:
        1. Text "^XMB(3.8)" or "Mail Group" in the Global Viewer input or breadcrumbs.
        2. A list of entries (IENs) or names that look like system groups (e.g., "POSTMASTER", "PHARMACY", "LAB").
        3. A detailed view of a mail group record (Zero node visible).
        
        Does this screenshot show the Mail Group global?
        Answer "YES" or "NO" with a brief reason.
        """
        
        # If we have the file locally via copy (we don't, it's in env), we need to read it.
        # Actually VLM usually runs on host with access to images if they are in the traj object.
        # If traj images are PIL objects:
        
        images_to_check = []
        if 'trajectory' in traj: # Common pattern
             # Grab last few frames
             images_to_check = [step['observation'] for step in traj['trajectory'][-3:]]
        elif 'images' in traj:
             images_to_check = traj['images'][-3:]
        
        # If we have images, check them
        vlm_success = False
        for img in images_to_check:
            try:
                resp = query_vlm(image=img, prompt=prompt)
                if "YES" in resp.upper():
                    vlm_success = True
                    break
            except:
                continue
        
        if vlm_success:
            vlm_score = 35
            feedback_parts.append("Visual verification passed (Mail Group global visited).")
        else:
            feedback_parts.append("Visual verification failed (Could not confirm navigation to ^XMB(3.8)).")
    
    score += vlm_score

    # Final Pass/Fail
    passed = (score >= 55) and (unique_matches >= 5) # Threshold: 55 pts AND at least 5 real groups found

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }