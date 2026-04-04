#!/usr/bin/env python3
"""
Verifier for configure_lookup_lists task.

Scoring:
- 30 pts: Visit Type "Orthopedic Consultation" added (must be a NEW document)
- 30 pts: Location "Orthopedics Wing B" added (must be a NEW document)
- 30 pts: Physician "Dr. Sarah Mitchell" added (must be a NEW document)
- 10 pts: VLM verification of Admin UI navigation
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_lookup_lists(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
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

    score = 0
    feedback_parts = []
    
    results = result.get("results", {})
    
    # 2. Verify Lookup Entries (30 pts each)
    # Check Visit Type
    r_vt = results.get("visit_type", {})
    if r_vt.get("found") and r_vt.get("is_new"):
        score += 30
        feedback_parts.append("✅ Visit Type added")
    elif r_vt.get("found"):
        # Found but not new? (Should rely on setup clearing them, but if agent reused one?)
        feedback_parts.append("⚠️ Visit Type found but timestamp ambiguous (partial credit)")
        score += 15
    else:
        feedback_parts.append("❌ Visit Type missing")

    # Check Location
    r_loc = results.get("location", {})
    if r_loc.get("found") and r_loc.get("is_new"):
        score += 30
        feedback_parts.append("✅ Location added")
    elif r_loc.get("found"):
        score += 15
        feedback_parts.append("⚠️ Location found (ambiguous)")
    else:
        feedback_parts.append("❌ Location missing")

    # Check Physician
    r_phys = results.get("physician", {})
    if r_phys.get("found") and r_phys.get("is_new"):
        score += 30
        feedback_parts.append("✅ Physician added")
    elif r_phys.get("found"):
        score += 15
        feedback_parts.append("⚠️ Physician found (ambiguous)")
    else:
        feedback_parts.append("❌ Physician missing")

    # 3. VLM Verification (10 pts)
    # Did the agent actually visit the Administration section?
    frames = sample_trajectory_frames(traj, n=4)
    vlm_score = 0
    vlm_feedback = ""
    
    if frames:
        prompt = """
        Review these screenshots of a user interacting with HospitalRun.
        The user task is to add items to Lookup Lists in the Administration section.
        
        Look for:
        1. The 'Administration' menu or header.
        2. A list of items or a dropdown for 'Lookup Lists'.
        3. A modal or form input field where text is being typed.
        
        Does the user appear to be navigating the Administration / Lookup Lists interface?
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            # Simple heuristic check on response
            if vlm_resp and vlm_resp.get("success"):
                text = vlm_resp.get("parsed", {}).get("answer", "").lower() + str(vlm_resp.get("raw", "")).lower()
                if "yes" in text or "administration" in text or "lookup" in text:
                    vlm_score = 10
                    vlm_feedback = "✅ UI navigation verified"
                else:
                    vlm_feedback = "❌ UI navigation unclear"
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            
    score += vlm_score
    if vlm_feedback:
        feedback_parts.append(vlm_feedback)

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }