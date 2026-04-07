#!/usr/bin/env python3
"""
Verifier for configure_project_release_defaults task.

Task: Configure 'Orion Satellite Interface' project:
1. Create version 'v2.1-Beta'
2. Set Default Version = 'v2.1-Beta'
3. Set Default Assignee = 'Sarah Connor'

Verification:
- Primary: Check Redmine database state via exported JSON
- Secondary: Anti-gaming checks (version created during task)
- Tertiary: VLM trajectory check for workflow verification
"""

import json
import os
import sys
import tempfile
import logging
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed
sys.path.insert(0, str(Path(__file__).parent.parent))
try:
    from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("vlm_utils not found, VLM verification will be skipped")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_project_release_defaults(traj, env_info, task_info):
    """
    Verify project configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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

    # Extract data
    db_state = result.get('db_state', {})
    task_start = result.get('task_start', 0)
    
    if db_state.get('error'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Database query error: {db_state['error']}"
        }

    score = 0
    feedback_parts = []
    
    # ==========================================================
    # Criterion 1: Version Created (30 pts)
    # ==========================================================
    version_created = db_state.get('version_created', False)
    version_created_on = db_state.get('version_created_on', 0)
    
    if version_created:
        # Anti-gaming: Check if version was created AFTER task start
        # Allow 5 second clock skew tolerance
        if version_created_on >= (task_start - 5):
            score += 30
            feedback_parts.append("Version 'v2.1-Beta' created successfully")
        else:
            score += 5 # Partial credit if it exists but looks old (shouldn't happen in clean env)
            feedback_parts.append("Version exists but timestamp predates task")
    else:
        feedback_parts.append("Version 'v2.1-Beta' NOT created")

    # ==========================================================
    # Criterion 2: Default Assignee Set (30 pts)
    # ==========================================================
    if db_state.get('is_correct_assignee_set', False):
        score += 30
        feedback_parts.append("Default assignee set to Sarah Connor")
    else:
        actual_id = db_state.get('default_assignee_id')
        feedback_parts.append(f"Default assignee incorrect (ID: {actual_id})")

    # ==========================================================
    # Criterion 3: Default Version Set (30 pts)
    # ==========================================================
    if db_state.get('is_correct_version_set', False):
        score += 30
        feedback_parts.append("Default version set to v2.1-Beta")
    else:
        actual_ver = db_state.get('default_version_id')
        feedback_parts.append(f"Default version incorrect (ID: {actual_ver})")

    # ==========================================================
    # Criterion 4: VLM Workflow Verification (10 pts)
    # ==========================================================
    # We check if the agent actually visited the settings tabs
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=5)
        final_shot = get_final_screenshot(traj)
        
        prompt = """
        Analyze these screenshots of a user interacting with Redmine.
        The user goal is to:
        1. Go to Project Settings > Versions tab to create a version
        2. Go to Project Settings > Information tab to set defaults
        
        Do you see evidence of:
        - The "Versions" tab being active or clicked?
        - The "Information" (or main Settings) tab being active?
        - A "New version" form?
        
        Respond with JSON: {"versions_tab_seen": bool, "settings_tab_seen": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_shot], prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('versions_tab_seen'):
                    vlm_score += 5
                if parsed.get('settings_tab_seen'):
                    vlm_score += 5
        except Exception:
            # Fallback if VLM fails: give points if DB state is perfect
            if score == 90:
                vlm_score = 10
                
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append("Workflow validated via visual analysis")

    # Final tally
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }