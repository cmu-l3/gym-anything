#!/usr/bin/env python3
"""
Verifier for identify_software_version task.

Criteria:
1. File Creation (Anti-gaming): File must exist and be created *during* the task.
2. Content Structure: File must contain Software, Version, and Edition lines.
3. Accuracy: Version and Edition must match Ground Truth (allowing for minor formatting differences).
4. Process (VLM): The agent must have actually opened the About dialog (checked via trajectory).
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_software_version(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Anti-Gaming (20 pts) ---
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("✅ File created successfully")
    elif result.get('file_exists'):
        score += 10
        feedback_parts.append("⚠️ File exists but timestamp indicates pre-existence (or clock skew)")
    else:
        feedback_parts.append("❌ Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Content Structure (20 pts) ---
    content = result.get('file_content_raw', '')
    lines = content.splitlines()
    
    has_software = any('software:' in line.lower() and 'lobby track' in line.lower() for line in lines)
    has_version = any('version:' in line.lower() for line in lines)
    has_edition = any('edition:' in line.lower() for line in lines)
    
    if has_software and has_version and has_edition:
        score += 20
        feedback_parts.append("✅ File format correct")
    else:
        score += (10 if has_software else 0) + (5 if has_version else 0) + (5 if has_edition else 0)
        feedback_parts.append("⚠️ File format incomplete (missing Software, Version, or Edition headers)")

    # --- Criterion 3: Data Accuracy (30 pts) ---
    agent_version = result.get('parsed_agent_version', '').strip()
    agent_edition = result.get('parsed_agent_edition', '').strip()
    gt_version = result.get('ground_truth_version', 'unknown')
    gt_edition = result.get('ground_truth_edition', 'Free')

    # Version check (Fuzzy match: starts with same major.minor)
    version_correct = False
    if agent_version and gt_version != 'unknown':
        # Extract X.Y from both
        agent_xy = re.search(r'(\d+\.\d+)', agent_version)
        gt_xy = re.search(r'(\d+\.\d+)', gt_version)
        
        if agent_xy and gt_xy and agent_xy.group(1) == gt_xy.group(1):
            version_correct = True
        elif agent_version == gt_version:
            version_correct = True
            
    if version_correct:
        score += 15
        feedback_parts.append(f"✅ Version accurate ({agent_version})")
    else:
        feedback_parts.append(f"❌ Version mismatch (Expected ~{gt_version}, Got '{agent_version}')")

    # Edition check (Case insensitive substring)
    if gt_edition.lower() in agent_edition.lower():
        score += 15
        feedback_parts.append(f"✅ Edition accurate ({agent_edition})")
    else:
        feedback_parts.append(f"❌ Edition mismatch (Expected '{gt_edition}', Got '{agent_edition}')")

    # --- Criterion 4: Process Verification via VLM (30 pts) ---
    # We need to confirm they actually opened the About dialog
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = (
        "Analyze these screenshots of a user interacting with Jolly Lobby Track software. "
        "Did the user open an 'About' dialog or 'Help' window that displays version information? "
        "Look for a popup window containing 'About Lobby Track', version numbers (like 6.7...), or copyright info. "
        "Return JSON: {\"about_dialog_seen\": boolean, \"confidence\": \"high|medium|low\"}"
    )
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    about_seen = False
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        about_seen = parsed.get('about_dialog_seen', False)
        
        if about_seen:
            score += 30
            feedback_parts.append("✅ VLM confirmed About dialog opened")
        else:
            feedback_parts.append("⚠️ VLM did not observe About dialog (required for full score)")
    else:
        # Fallback if VLM fails: if text version was correct, give benefit of doubt but reduced
        if version_correct:
            score += 15
            feedback_parts.append("⚠️ VLM check failed, granting partial credit based on correct version")
        else:
            feedback_parts.append("❌ VLM check failed")

    # --- Final Result ---
    # Pass if score >= 60 AND file exists AND version is correct
    passed = (score >= 60) and version_correct and result.get('file_exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }