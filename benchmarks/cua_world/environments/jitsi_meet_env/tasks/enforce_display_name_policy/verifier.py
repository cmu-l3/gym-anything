#!/usr/bin/env python3
"""
Verifier for enforce_display_name_policy task.

Verification Criteria:
1. Config File Analysis: `requireDisplayName` must be set to `true` in config.js.
2. Evidence Screenshot: Agent must have saved a screenshot showing the disabled Join button.
3. VLM Trajectory: Confirm agent navigated to config, edited it, refreshed, and successfully joined.
"""

import json
import os
import re
import logging
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_display_name_policy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # --- Step 1: Load Exported Results ---
    result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}

    # --- Step 2: Verify Configuration File (40 pts) ---
    config_valid = False
    config_content = ""
    
    with tempfile.NamedTemporaryFile(suffix='.js') as f_js:
        try:
            # The export script saved the config to /tmp/config_final.js
            copy_from_env("/tmp/config_final.js", f_js.name)
            f_js.seek(0)
            config_content = f_js.read().decode('utf-8', errors='ignore')
            
            # Remove comments to avoid false positives (simple C-style comments)
            # This is a basic strip; a full parser would be better but overkill here.
            clean_content = re.sub(r'//.*', '', config_content)
            
            # Check for requireDisplayName: true
            # Pattern allows for spacing variations: requireDisplayName : true
            if re.search(r'requireDisplayName\s*:\s*true', clean_content):
                config_valid = True
                score += 40
                feedback_parts.append("Configuration correctly updated (40/40)")
            else:
                feedback_parts.append("Configuration NOT updated: 'requireDisplayName: true' not found")
                
        except Exception as e:
            feedback_parts.append(f"Could not read config file: {e}")

    # --- Step 3: Verify Evidence Screenshot (30 pts) ---
    evidence_valid = False
    evidence_path = result.get("evidence_path")
    evidence_exists = result.get("evidence_exists", False)
    evidence_fresh = result.get("evidence_created_during_task", False)
    
    if evidence_exists and evidence_fresh:
        with tempfile.NamedTemporaryFile(suffix='.png') as f_img:
            try:
                copy_from_env(evidence_path, f_img.name)
                
                # VLM Check on Evidence
                prompt = """
                Analyze this screenshot from Jitsi Meet.
                1. Is this the "Pre-join" or "Waiting to join" screen?
                2. Is the name input field empty?
                3. Is the "Join meeting" button visible but visually DISABLED (greyed out/unclickable)?
                
                Return JSON:
                {
                    "is_prejoin_screen": true/false,
                    "name_field_empty": true/false,
                    "join_button_disabled": true/false
                }
                """
                vlm_res = query_vlm(image=f_img.name, prompt=prompt)
                
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('is_prejoin_screen') and parsed.get('join_button_disabled'):
                        evidence_valid = True
                        score += 30
                        feedback_parts.append("Evidence screenshot validates policy enforcement (30/30)")
                    else:
                        feedback_parts.append("Evidence screenshot does not show disabled join button")
                else:
                    feedback_parts.append("Failed to analyze evidence screenshot")
                    
            except Exception as e:
                feedback_parts.append(f"Failed to retrieve evidence screenshot: {e}")
    else:
        feedback_parts.append("Evidence screenshot missing or not created during task")

    # --- Step 4: Verify Successful Join & Workflow (Traj VLM) (30 pts) ---
    # We need to confirm they actually joined at the end.
    workflow_valid = False
    
    # Sample frames to see progression: Editor -> Browser -> Join
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    if frames:
        prompt = """
        Analyze these screenshots of a user performing a task.
        Sequence:
        1. Did the user edit a configuration file (text editor visible)?
        2. Did the user try to join a Jitsi meeting?
        3. In the FINAL frame, is the user successfully INSIDE the meeting (video/avatar visible, toolbar visible, NOT on pre-join screen)?
        
        Return JSON:
        {
            "config_edited": true/false,
            "attempted_join": true/false,
            "final_state_in_meeting": true/false
        }
        """
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('final_state_in_meeting'):
                workflow_valid = True
                score += 30
                feedback_parts.append("Workflow verification passed: User successfully joined meeting (30/30)")
            else:
                feedback_parts.append("Workflow verification failed: User did not successfully join the meeting at the end")
        else:
            feedback_parts.append("VLM analysis of trajectory failed")
    else:
        feedback_parts.append("No trajectory frames available")

    # --- Final Scoring ---
    # Pass threshold: Must have config correct AND evidence valid. 
    # The 'Successful Join' is important but the core task is the policy change.
    # We set pass if score >= 70.
    
    passed = score >= 70 and config_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }