#!/usr/bin/env python3
"""
Verifier for audit_mislocated_capitals task.

Verifies that the agent correctly identified and marked 3 mislocated capitals
while leaving correctly located capitals untouched.

Scoring:
- 15 pts for each correctly marked mislocated capital (Tokyo, Ottawa, Cairo)
- 10 pts for each correctly UNMARKED capital (Canberra, Buenos Aires, London)
- 10 pts for App running
- 15 pts for VLM process verification (trajectory checks)
"""

import logging
import tempfile
import os
import json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_capitals(traj, env_info, task_info):
    """
    Verify the audit results extracted from the GeoPackage.
    """
    # 1. Setup and file retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result text file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/sdcard/task_result.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            lines = f.readlines()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse results
    results = {}
    metadata = {}
    
    # Expected cities
    targets = {
        "Tokyo": "MISLOCATED",
        "Ottawa": "MISLOCATED",
        "Cairo": "MISLOCATED",
        "Canberra": "",
        "Buenos Aires": "",
        "London": ""
    }
    
    parsing_metadata = False
    for line in lines:
        line = line.strip()
        if not line: continue
        
        if line == "--- METADATA ---":
            parsing_metadata = True
            continue
            
        if parsing_metadata:
            if '=' in line:
                key, val = line.split('=', 1)
                metadata[key] = val
        else:
            # Parse CSV-like: Name|Notes|Lat|Lon
            parts = line.split('|')
            if len(parts) >= 2:
                name = parts[0]
                notes = parts[1] if len(parts) > 1 else ""
                if name in targets:
                    results[name] = notes

    # 3. Scoring
    score = 0
    feedback = []
    
    # Check each city
    correct_marks = 0
    false_positives = 0
    
    for city, expected_note in targets.items():
        actual_note = results.get(city, "").strip()
        
        if expected_note == "MISLOCATED":
            # Must match exactly
            if actual_note == "MISLOCATED":
                score += 15
                correct_marks += 1
                feedback.append(f"✓ {city}: Correctly marked as MISLOCATED")
            else:
                feedback.append(f"✗ {city}: Missed (Found: '{actual_note}')")
        else:
            # Should be empty or at least NOT "MISLOCATED"
            if "MISLOCATED" not in actual_note:
                score += 10
                feedback.append(f"✓ {city}: Correctly left unmarked")
            else:
                score -= 5 # Penalty for false positive
                false_positives += 1
                feedback.append(f"✗ {city}: Incorrectly marked as MISLOCATED")

    # App running check
    if metadata.get('app_running') == 'true':
        score += 10
        feedback.append("✓ QField was running")
    else:
        feedback.append("⚠ QField was closed")

    # 4. VLM Verification (Trajectory Analysis)
    # We want to see if the agent actually inspected the features (opened forms)
    # rather than just running a script or guessing.
    # We look for "Attributes" panel or similar in trajectory frames.
    
    vlm_score = 0
    if traj:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """
        Review these screenshots of a user using QField (GIS app).
        The user is supposed to be inspecting feature attributes.
        
        Look for:
        1. An open side panel or popup showing "Feature Attributes" or "Identified Results".
        2. Text fields labeled "name", "latitude", "longitude", or "notes".
        3. An on-screen keyboard being used (implies editing).
        
        Do you see evidence of the user inspecting or editing attributes?
        Reply with JSON: {"evidence_found": true/false, "confidence": "high/medium/low"}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('evidence_found'):
                vlm_score = 15
                feedback.append("✓ VLM: Evidence of feature inspection found")
            else:
                feedback.append("⚠ VLM: No evidence of feature inspection in sampled frames")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: give partial credit if programmatic pass is high
            if score >= 60:
                vlm_score = 10
    
    score += vlm_score

    # Final tally
    passed = (score >= 70) and (correct_marks >= 2) and (false_positives == 0)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "\n".join(feedback),
        "details": results
    }