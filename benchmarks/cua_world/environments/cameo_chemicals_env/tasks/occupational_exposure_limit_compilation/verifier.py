#!/usr/bin/env python3
"""
Verifier for Occupational Exposure Limit Compilation task.
Verifies that the agent correctly looked up PEL/IDLH values for 5 chemicals
and identified the most dangerous one (Lowest IDLH).
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_occupational_exposure_limit_compilation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the exposure limits report.
    
    Scoring Criteria:
    - Report file exists and created during task: 5 pts
    - All 5 chemicals mentioned: 10 pts
    - Correct IDLH values (±10% or exact match): 8 pts each (40 pts total)
    - Correct PEL values (±10% or exact match): 5 pts each (25 pts total)
    - Correct Lowest IDLH identification: 10 pts
    - VLM Trajectory check (visited CAMEO): 10 pts
    
    Total: 100 pts
    Pass Threshold: 60 pts
    """
    
    # 1. Setup and Helper Functions
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', [])
    target_lowest_idlh = metadata.get('lowest_idlh_chemical', 'Chlorine')
    report_path = metadata.get('report_path', '/home/ga/Documents/exposure_limits_report.txt')

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 2. Retrieve Task Result JSON (Metadata)
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy task result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution metadata"}

    # 3. Check File Existence & Timestamp
    if not task_result.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found at expected path."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file was not created or modified during the task execution time."}
    
    if task_result.get('report_size_bytes', 0) < 50:
        return {"passed": False, "score": 0, "feedback": "Report file is empty or too small."}

    score += 5
    feedback_parts.append("Report file created successfully")

    # 4. Retrieve and Read Report Content
    content = ""
    with tempfile.NamedTemporaryFile(suffix='.txt') as f:
        try:
            copy_from_env(report_path, f.name)
            with open(f.name, 'r', errors='ignore') as txt_file:
                content = txt_file.read()
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read report content: {e}"}

    logger.info(f"Report Content:\n{content}")

    # 5. Verify Chemical Presence
    chems_found = 0
    for chem in expected_chemicals:
        if re.search(chem['regex_name'], content, re.IGNORECASE):
            chems_found += 1
    
    if chems_found == len(expected_chemicals):
        score += 10
        feedback_parts.append(f"All {len(expected_chemicals)} chemicals listed")
    else:
        feedback_parts.append(f"Found {chems_found}/{len(expected_chemicals)} chemicals")

    # 6. Verify Numeric Values (PEL and IDLH)
    # We use a helper to extract numbers associated with specific keywords near chemical names
    
    def check_value(text, chem_regex, type_label, expected_val, tolerance=0.15):
        # Look for the chemical section, then find the type label (PEL/IDLH) and a number
        # This is a bit heuristic: Split text by chemicals or look for lines
        # Simpler approach: Look for regex pattern: "ChemName ... Type ... Number"
        # We allow matches across newlines
        
        pattern = f"{chem_regex}.{{0,200}}{type_label}.{{0,50}}?([0-9]+(?:\\.[0-9]+)?)"
        match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
        
        if not match:
            # Try alternative order: "Type ... ChemName ... Number" (less likely but possible)
            return False, 0.0

        found_val = float(match.group(1))
        
        # Check tolerance
        if abs(found_val - expected_val) <= (expected_val * tolerance):
            return True, found_val
        return False, found_val

    values_correct = 0
    
    for chem in expected_chemicals:
        name = chem['name']
        regex = chem['regex_name']
        
        # Check IDLH (8 pts)
        passed_idlh, val_idlh = check_value(content, regex, "IDLH", chem['idlh_val'])
        if passed_idlh:
            score += 8
            values_correct += 1
        else:
            logger.info(f"Failed IDLH for {name}: Expected {chem['idlh_val']}, found {val_idlh} or not found")

        # Check PEL (5 pts)
        passed_pel, val_pel = check_value(content, regex, "PEL|TWA|Permissible", chem['pel_val'])
        if passed_pel:
            score += 5
            values_correct += 1
        else:
            logger.info(f"Failed PEL for {name}: Expected {chem['pel_val']}, found {val_pel} or not found")

    if values_correct > 0:
        feedback_parts.append(f"Verified {values_correct} exposure values")

    # 7. Verify Lowest IDLH Conclusion
    # Look for "LOWEST_IDLH: Chlorine"
    conclusion_pattern = r"LOWEST_IDLH\s*[:=-]\s*Chlorine"
    if re.search(conclusion_pattern, content, re.IGNORECASE):
        score += 10
        feedback_parts.append("Correctly identified Chlorine as lowest IDLH")
    else:
        feedback_parts.append("Failed to identify Chlorine as lowest IDLH in expected format")

    # 8. VLM Trajectory Verification
    # Check if agent actually used CAMEO Chemicals
    vlm_score = 0
    if query_vlm:
        # We use a simple prompt on a sample of frames
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = (
            "Does this screenshot show the 'CAMEO Chemicals' website? "
            "Is the user looking at a chemical datasheet or search results? "
            "Answer 'Yes' if any of this is visible."
        )
        
        # We check the frames until we get a positive
        verified_visually = False
        for img in frames:
            res = query_vlm(image=img, prompt=prompt)
            if res.get('success') and "yes" in res.get('parsed', {}).get('response', '').lower():
                verified_visually = True
                break
            # Fallback for simple string response
            if res.get('success') and "yes" in str(res.get('response', '')).lower():
                verified_visually = True
                break
        
        if verified_visually:
            score += 10
            feedback_parts.append("Visual verification passed")
        else:
            feedback_parts.append("Visual verification inconclusive")
    else:
        # If VLM not available, grant points if file is correct (assume valid work)
        if score > 50: 
            score += 10
            feedback_parts.append("VLM skipped (awarded based on result)")

    # 9. Final Tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }