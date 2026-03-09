#!/usr/bin/env python3
"""
Verifier for polymerization_hazard_assessment task.
"""

import json
import os
import csv
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    return name.strip().lower()

def normalize_cas(cas):
    return cas.strip().replace(" ", "")

def check_triggers(conditions_text, expected_triggers):
    """Check if at least one expected trigger keyword is found."""
    text = conditions_text.lower()
    found_triggers = [t for t in expected_triggers if t in text]
    return len(found_triggers) > 0, found_triggers

def verify_polymerization_hazard_assessment(traj, env_info, task_info):
    """
    Verify the polymerization assessment CSV against ground truth.
    
    Scoring:
    - 10 pts: File exists and is valid CSV
    - 18 pts: CAS Numbers correct (3 pts * 6)
    - 42 pts: Polymerization YES/NO correct (7 pts * 6)
    - 20 pts: Triggering conditions for YES chemicals (5 pts * 4)
    - 6 pts: N/A for NO chemicals (3 pts * 2)
    - 4 pts: Anti-gaming (timestamp + diversity)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    output_path = metadata.get('output_path', "/home/ga/Documents/polymerization_assessment.csv")

    score = 0
    feedback_parts = []
    
    # 1. Load Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf_result:
        try:
            copy_from_env("/tmp/task_result.json", tf_result.name)
            with open(tf_result.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # 2. Check File Existence and Timestamp (Anti-gaming)
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    if not task_result.get("file_created_during_task", False):
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this task session.")
    else:
        score += 2 # Timestamp valid
        
    # 3. Load and Parse CSV
    csv_rows = []
    with tempfile.NamedTemporaryFile(suffix='.csv') as tf_csv:
        try:
            copy_from_env(output_path, tf_csv.name)
            with open(tf_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                # Read entire content to check for empty file
                content = f.read().strip()
                if not content:
                    return {"passed": False, "score": score, "feedback": "CSV file is empty."}
                
                # Reset pointer and parse
                f.seek(0)
                reader = csv.reader(f)
                header = next(reader, None)
                if header:
                    csv_rows = list(reader)
                    score += 8 # Valid CSV structure with header
                    feedback_parts.append("Valid CSV format")
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse CSV: {e}"}

    # 4. Verify Content
    matched_chemicals = {}
    
    # Map CSV rows to ground truth chemicals
    for row in csv_rows:
        if len(row) < 3:
            continue
        
        name = normalize_name(row[0])
        # Try to match with ground truth keys
        for gt_name, gt_data in ground_truth.items():
            if gt_name in name or name in gt_name:
                matched_chemicals[gt_name] = {
                    "cas": row[1] if len(row) > 1 else "",
                    "hazard": row[2] if len(row) > 2 else "",
                    "triggers": row[3] if len(row) > 3 else ""
                }

    # Evaluate per chemical
    correct_classifications = 0
    conditions_texts = []
    
    for gt_name, gt_data in ground_truth.items():
        if gt_name not in matched_chemicals:
            feedback_parts.append(f"Missing chemical: {gt_name}")
            continue

        chem_data = matched_chemicals[gt_name]
        
        # CAS Check (3 pts)
        if normalize_cas(chem_data["cas"]) == gt_data["cas"]:
            score += 3
        
        # Hazard YES/NO Check (7 pts)
        agent_hazard = chem_data["hazard"].strip().upper()
        expected_hazard = "YES" if gt_data["polymerizes"] else "NO"
        
        if agent_hazard == expected_hazard:
            score += 7
            correct_classifications += 1
        else:
            feedback_parts.append(f"{gt_name}: Expected {expected_hazard}, got {agent_hazard}")

        # Triggers Check
        if gt_data["polymerizes"]:
            # YES Chemical (5 pts)
            valid_triggers, found = check_triggers(chem_data["triggers"], gt_data["triggers"])
            if valid_triggers:
                score += 5
                conditions_texts.append(chem_data["triggers"])
            else:
                feedback_parts.append(f"{gt_name}: Missing valid triggers (e.g., heat, peroxides)")
        else:
            # NO Chemical (3 pts)
            triggers_text = chem_data["triggers"].strip().lower()
            if triggers_text in ["n/a", "na", "none", "-", "no", "not applicable", ""]:
                score += 3

    # Anti-gaming: Diversity of conditions (2 pts)
    # Check if agent just copy-pasted the exact same text for all YES chemicals
    if len(conditions_texts) >= 3:
        unique_conditions = set(t.strip().lower() for t in conditions_texts)
        if len(unique_conditions) >= 2:
            score += 2
        else:
            feedback_parts.append("Suspicious: Identical trigger text for all chemicals")

    # 5. VLM Verification (Trajectory Check)
    # Ensure agent actually visited datasheets and didn't just write from training memory
    try:
        frames = sample_trajectory_frames(traj, n=8)
        vlm_prompt = (
            "Does the user appear to be browsing chemical datasheets on the CAMEO Chemicals website? "
            "Look for headers like 'Reactivity Profile', 'Chemical Datasheet', or chemical names like Styrene or Acrylic Acid. "
            "Answer YES or NO with brief reasoning."
        )
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        # We don't deduct points heavily for this unless it's obviously unrelated, 
        # but we use it to validate the process.
        if "YES" in vlm_result.get("response", "").upper():
            feedback_parts.append("Visual verification passed: Browsing activity detected.")
        else:
            feedback_parts.append("Visual verification warning: Could not confirm CAMEO browsing.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Final result construction
    passed = (score >= 70) and (correct_classifications >= 5)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts) if feedback_parts else "All criteria met.",
        "details": {
            "correct_classifications": correct_classifications,
            "chemicals_found": list(matched_chemicals.keys())
        }
    }