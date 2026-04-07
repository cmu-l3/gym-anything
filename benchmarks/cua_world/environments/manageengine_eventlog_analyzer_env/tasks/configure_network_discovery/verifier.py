#!/usr/bin/env python3
"""
Verifier for configure_network_discovery task.

Verification Strategy:
1. File Verification: Check if the agent created the summary file with the correct IP details.
2. Anti-Gaming: Verify the file was created during the task.
3. VLM Verification: Analyze trajectory frames to verify the agent navigated to the discovery settings
   and input the correct IP range (10.0.1.1 - 10.0.1.254).
"""

import json
import os
import base64
import tempfile
import logging
import sys
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_network_discovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. File Verification (40 points)
    summary_exists = result.get("summary_exists", False)
    summary_created = result.get("summary_created_during_task", False)
    summary_content_b64 = result.get("summary_content_base64", "")
    
    summary_text = ""
    if summary_content_b64:
        try:
            summary_text = base64.b64decode(summary_content_b64).decode('utf-8', errors='ignore')
        except:
            pass

    if summary_exists and summary_created:
        score += 10
        feedback_parts.append("Summary file created")
        
        # Check content
        lower_text = summary_text.lower()
        if "10.0.1.1" in lower_text and "10.0.1.254" in lower_text:
            score += 20
            feedback_parts.append("Correct IP range in summary")
        else:
            feedback_parts.append("Missing IP range (10.0.1.1-254) in summary")
            
        if "127.0.0.1" in lower_text or "localhost" in lower_text:
            score += 10
            feedback_parts.append("Localhost mentioned in summary")
    else:
        feedback_parts.append("Summary file missing or created before task")

    # 2. VLM Verification (60 points)
    # We need to verify the actual UI interaction because the file could be hallucinated.
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying if an agent configured a Network Discovery Scan in ManageEngine EventLog Analyzer.
    
    Look for these specific actions in the screenshots:
    1. Navigation to a 'Settings', 'Admin', or 'Discovery' section.
    2. A form or input field where IP ranges are entered.
    3. The specific IP addresses "10.0.1.1" and "10.0.1.254" being typed or visible in a list.
    4. "127.0.0.1" or "localhost" being added.
    5. A 'Save', 'Add', or 'Discover' button being clicked.
    
    Return JSON:
    {
        "navigated_to_discovery": true/false,
        "ip_range_visible": true/false,
        "localhost_visible": true/false,
        "save_action_visible": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("navigated_to_discovery"):
            score += 10
            feedback_parts.append("VLM: Navigated to discovery settings")
            
        if parsed.get("ip_range_visible"):
            score += 25
            feedback_parts.append("VLM: Verified IP range entry (10.0.1.x)")
        else:
            feedback_parts.append("VLM: Could not clearly see IP range entry")
            
        if parsed.get("localhost_visible"):
            score += 10
            feedback_parts.append("VLM: Verified localhost entry")
            
        if parsed.get("save_action_visible"):
            score += 15
            feedback_parts.append("VLM: Verified save action")
    else:
        feedback_parts.append("VLM verification failed to process images")

    # Final Evaluation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }