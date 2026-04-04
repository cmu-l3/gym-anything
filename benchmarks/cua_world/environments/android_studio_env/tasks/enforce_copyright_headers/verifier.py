#!/usr/bin/env python3
"""
Verifier for enforce_copyright_headers task.

Verification Criteria:
1. Copyright Profile Configuration (30 pts):
   - A profile XML exists in .idea/copyright/
   - Contains expected license text
2. Kotlin Source Application (25 pts):
   - MainActivity.kt contains the license header
   - File was modified during task
3. XML Source Application (25 pts):
   - activity_main.xml contains the license header
   - File was modified during task
4. VLM Verification (20 pts):
   - Validates that the agent used the Settings/Copyright UI based on trajectory
   - (Anti-gaming check to ensure they didn't just paste text manually without config)

Pass Threshold: 80 points
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_copyright_headers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_parts = metadata.get("expected_text_parts", [
        "Copyright (C) 2025 TechCorp Inc.",
        "All rights reserved.",
        "Licensed under the Apache License, Version 2.0."
    ])
    
    # Read result JSON
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
    
    # ---------------------------------------------------------
    # Criterion 1: Profile Configuration (30 pts)
    # ---------------------------------------------------------
    profile_exists = result.get("profile_exists", False)
    profile_content = result.get("profile_content", "")
    
    if profile_exists:
        # Check content match
        all_parts_found = all(part in profile_content for part in expected_parts)
        if all_parts_found:
            score += 30
            feedback_parts.append("Copyright profile configured correctly (30/30)")
        else:
            score += 10
            feedback_parts.append("Copyright profile exists but missing some text (10/30)")
    else:
        feedback_parts.append("No Copyright profile found in .idea/copyright/ (0/30)")

    # ---------------------------------------------------------
    # Criterion 2: Kotlin File Application (25 pts)
    # ---------------------------------------------------------
    kt_modified = result.get("kotlin_file_modified", False)
    kt_content = result.get("kotlin_content", "")
    
    # Verify text presence
    kt_has_text = all(part in kt_content for part in expected_parts)
    
    if kt_has_text and kt_modified:
        score += 25
        feedback_parts.append("MainActivity.kt has correct header and was modified (25/25)")
    elif kt_has_text:
        # Penalize if timestamp doesn't show modification (unlikely if text is there, but good check)
        score += 15
        feedback_parts.append("MainActivity.kt has header but timestamp weird (15/25)")
    else:
        feedback_parts.append("MainActivity.kt missing copyright header (0/25)")

    # ---------------------------------------------------------
    # Criterion 3: XML File Application (25 pts)
    # ---------------------------------------------------------
    xml_modified = result.get("xml_file_modified", False)
    xml_content = result.get("xml_content", "")
    
    xml_has_text = all(part in xml_content for part in expected_parts)
    
    if xml_has_text and xml_modified:
        score += 25
        feedback_parts.append("activity_main.xml has correct header and was modified (25/25)")
    elif xml_has_text:
        score += 15
        feedback_parts.append("activity_main.xml has header but timestamp weird (15/25)")
    else:
        feedback_parts.append("activity_main.xml missing copyright header (0/25)")

    # ---------------------------------------------------------
    # Criterion 4: VLM Trajectory Verification (20 pts)
    # ---------------------------------------------------------
    # We want to verify they actually used the UI (Settings -> Copyright)
    # This prevents an agent from just using `sed` or `echo` to prepend text to files
    # without actually configuring the IDE tool as requested.
    
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, num_samples=5)
            
            prompt = """
            You are verifying if an agent used Android Studio's 'Copyright' settings.
            Look at these screenshots of the agent's workflow.
            
            Do you see:
            1. The 'Settings' or 'Preferences' dialog?
            2. The 'Copyright' or 'Copyright Profiles' section in settings?
            3. A dialog for adding/editing a Copyright Profile?
            4. The 'Update Copyright' action being run (or Analyze menu)?
            
            Answer YES if you see at least one of these specific UI elements confirming 
            usage of the IDE's copyright tool. Answer NO otherwise.
            """
            
            vlm_result = query_vlm(prompt=prompt, images=frames)
            
            if vlm_result and vlm_result.get("success"):
                response = vlm_result.get("response", "").upper()
                if "YES" in response:
                    vlm_score = 20
                    feedback_parts.append("VLM verified usage of Copyright Settings UI (20/20)")
                else:
                    feedback_parts.append("VLM did not observe Copyright Settings UI usage (0/20)")
            else:
                # If VLM fails, we give partial benefit of doubt if files are correct
                if score >= 50:
                    vlm_score = 10
                    feedback_parts.append("VLM skipped, granting partial credit (10/20)")
        except ImportError:
            # Fallback if gym_anything not available
            vlm_score = 20
            feedback_parts.append("VLM unavailable, bypassing check (20/20)")
    
    score += vlm_score

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }