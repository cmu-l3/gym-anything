#!/usr/bin/env python3
"""
Verifier for audit_pain_management_cisplatin task.

Verifies:
1. Report file creation and freshness (Anti-gaming).
2. Correct identification of Ibuprofen risk (Renal/Nephrotoxicity).
3. Correct identification of Safe options (Paracetamol/Codeine).
4. VLM verification of app navigation (Trajectory).
"""

import json
import os
import tempfile
import logging
import re
from typing import Dict, Any

# Adjust import based on environment; gym_anything usually provides these utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Mock for local testing if gym_anything not installed
    def sample_trajectory_frames(traj, n): return []
    def query_vlm(prompt, images): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pain_audit(traj, env_info, task_info):
    """
    Verify the Cisplatin Pain Management Audit task.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Temporary file to hold the result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not read task result file. Did the agent create the report?"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Anti-gaming (20 pts)
    if result_data.get("file_exists") and result_data.get("created_during_task"):
        score += 20
        feedback.append("Report file created successfully.")
    elif result_data.get("file_exists"):
        score += 5
        feedback.append("Report file exists but timestamp suggests it wasn't created during this session.")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file '/sdcard/cisplatin_pain_audit.txt' was not found."}

    content = result_data.get("file_content", "").lower()
    
    # Criterion 2: Ibuprofen Risk Identification (25 pts)
    # Must mention Ibuprofen and a relevant kidney keyword
    has_ibuprofen = "ibuprofen" in content
    risk_keywords = metadata.get("risk_keywords", ["renal", "kidney", "nephrotox"])
    has_risk_warning = any(k in content for k in risk_keywords)
    
    if has_ibuprofen and has_risk_warning:
        score += 25
        feedback.append("Correctly identified Ibuprofen renal/kidney risk.")
    elif has_ibuprofen:
        score += 10
        feedback.append("Mentioned Ibuprofen but missed the specific 'renal/kidney' risk warning.")
    else:
        feedback.append("Report did not mention Ibuprofen.")

    # Criterion 3: Safe Options (Paracetamol/Codeine) (15 pts)
    has_paracetamol = "paracetamol" in content
    has_codeine = "codeine" in content
    
    if has_paracetamol and has_codeine:
        score += 15
        feedback.append("Included both Paracetamol and Codeine.")
    elif has_paracetamol or has_codeine:
        score += 7
        feedback.append("Included one of the safe alternatives.")
    
    # Criterion 4: Recommendation (15 pts)
    # Should recommend the safe ones or say avoid ibuprofen
    rec_safe = "paracetamol" in content or "codeine" in content
    rec_avoid = "avoid" in content or "caution" in content
    
    if "recommendation" in content and (rec_safe or rec_avoid):
        score += 15
        feedback.append("Provided a clear recommendation.")
    
    # Criterion 5: VLM Trajectory Verification (25 pts)
    # Check if the agent actually used the app
    frames = sample_trajectory_frames(traj, n=6)
    vlm_prompt = """
    You are verifying an agent's usage of a medical app 'Liverpool Cancer iChart'.
    The task was to check interactions for Cisplatin with Ibuprofen, Paracetamol, and Codeine.
    
    Look at the sequence of images and determine:
    1. Did the agent select 'Cisplatin'?
    2. Did the agent navigate to find 'Ibuprofen', 'Paracetamol', or 'Codeine'?
    3. Did the agent view an interaction result screen (traffic light colors visible)?
    
    Return JSON:
    {
        "app_used": true,
        "drugs_searched": true,
        "interaction_viewed": true,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    vlm_data = vlm_result.get("parsed", {})
    
    if vlm_data.get("app_used") and vlm_data.get("interaction_viewed"):
        score += 25
        feedback.append("VLM verification confirmed app usage and interaction checks.")
    else:
        feedback.append("VLM could not verify meaningful app usage.")

    # Final tally
    passed = score >= 60 and result_data.get("file_exists") and has_risk_warning
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }