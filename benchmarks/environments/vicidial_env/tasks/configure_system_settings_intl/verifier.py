#!/usr/bin/env python3
"""
Verifier for configure_system_settings_intl task.

Checks:
1. Validates that the 6 specific system settings were updated in the database.
2. Compares against initial state (handled implicitly by requiring specific non-default values).
3. Uses VLM to verify the agent navigated to the System Settings page.
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, 
# though we usually use the helper provided by the framework or gym_anything.
# Mocking the VLM query import for the standalone file structure pattern
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback/Mock for local testing
    def sample_trajectory_frames(traj, n): return []
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_system_settings(traj, env_info, task_info):
    """
    Verify system settings configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {
        "use_non_latin": "1",
        "custom_fields_enabled": "1",
        "allow_chats": "1",
        "callback_limit": "1",
        "enable_queuemetrics_logging": "1",
        "allow_emails": "1"
    })

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    final_values = result.get("final_values", {})
    
    # --- Scoring ---
    score = 0
    feedback_parts = []
    
    # 1. Database Verification (15 points per field = 90 points total)
    field_scores = {
        "use_non_latin": 15,
        "custom_fields_enabled": 15,
        "allow_chats": 15,
        "callback_limit": 15,
        "enable_queuemetrics_logging": 15,
        "allow_emails": 15
    }
    
    fields_correct = 0
    
    for field, expected in expected_values.items():
        actual = str(final_values.get(field, "0"))
        if actual == expected:
            score += field_scores[field]
            fields_correct += 1
        else:
            feedback_parts.append(f"{field}: expected {expected}, got {actual}")

    if fields_correct == 6:
        feedback_parts.append("All database settings correct.")
    else:
        feedback_parts.append(f"{fields_correct}/6 settings correct.")

    # 2. VLM Verification (10 points)
    # Check if the agent visited the System Settings page
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_prompt = """
            You are verifying a Vicidial administration task.
            Look at these screenshots of the agent's workflow.
            
            Did the agent visit the 'System Settings' or 'Admin' configuration page? 
            This page typically contains a very long form with many configuration options (text fields, dropdowns)
            labeled 'System Settings'.
            
            Respond JSON: {"visited_settings_page": true/false}
            """
            vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("visited_settings_page", False):
                    vlm_score = 10
                    feedback_parts.append("VLM: System Settings page visit confirmed.")
                else:
                    feedback_parts.append("VLM: Could not visually confirm System Settings page visit.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Be lenient if VLM fails technically, but strictly typically we want evidence
        pass

    score += vlm_score

    # Final Pass Determination
    # Must get at least 4/6 settings correct (60pts) + VLM (10pts) or 5/6 settings (75pts)
    # Threshold: 60
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }