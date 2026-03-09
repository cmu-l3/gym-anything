#!/usr/bin/env python3
import json
import csv
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_concentration_variant_shipping_audit(traj, env_info, task_info):
    """
    Verifies the shipping audit CSV contains correct UN numbers and labels
    for the specific concentrations requested.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Load result metadata
    result_meta = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            result_meta = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}

    if not result_meta.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file shipping_audit.csv not found on Desktop."}

    if not result_meta.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp predates task start (anti-gaming check failed)."}

    # 2. Load and parse the CSV content
    rows = []
    with tempfile.NamedTemporaryFile(suffix='.csv') as tf:
        try:
            copy_from_env("/home/ga/Desktop/shipping_audit.csv", tf.name)
            tf.seek(0)
            # encoding='utf-8-sig' handles BOM if created by Excel/TextEditor
            with open(tf.name, 'r', encoding='utf-8-sig', errors='replace') as f:
                reader = csv.reader(f)
                rows = list(reader)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read CSV file: {e}"}

    # Basic CSV Structure Check
    if not rows:
        return {"passed": False, "score": 0, "feedback": "CSV file is empty."}
    
    # Normalize headers
    headers = [h.lower().strip() for h in rows[0]]
    if "un_number" not in headers or "hazard_labels" not in headers:
         return {"passed": False, "score": 10, "feedback": "CSV headers missing or incorrect. Expected: Product, UN_Number, Hazard_Labels"}

    un_idx = headers.index("un_number")
    lbl_idx = headers.index("hazard_labels")
    prod_idx = headers.index("product") if "product" in headers else 0

    data_rows = rows[1:]
    if len(data_rows) < 5:
        return {"passed": False, "score": 20, "feedback": f"Incomplete data. Expected 5 entries, found {len(data_rows)}."}

    # 3. Validation Logic
    # We define criteria functions for flexibility
    def check_entry(target_name, expected_un, required_labels, excluded_labels=None):
        """
        Searches for a row matching expected_un (most reliable key).
        Returns points (0-20) and feedback.
        """
        match = None
        
        # Try finding by UN first (strong signal)
        for r in data_rows:
            if len(r) <= max(un_idx, lbl_idx): continue
            row_un = ''.join(filter(str.isdigit, r[un_idx])) # Clean UN number "UN 1005" -> "1005"
            if row_un == expected_un:
                match = r
                break
        
        if not match:
            return 0, f"Missing or incorrect entry for {target_name} (Expected UN {expected_un})"

        row_labels = match[lbl_idx].lower()
        score = 10 # Half points for getting the UN right
        
        # Check required labels
        missing = [l for l in required_labels if l.lower() not in row_labels]
        if missing:
            return score, f"{target_name}: Correct UN {expected_un}, but missing labels: {', '.join(missing)}"
        
        # Check excluded labels (crucial for H2O2 15% vs 50%)
        if excluded_labels:
            found_excluded = [l for l in excluded_labels if l.lower() in row_labels]
            if found_excluded:
                return score, f"{target_name}: Correct UN {expected_un}, but included wrong labels for this concentration: {', '.join(found_excluded)}"

        return 20, f"{target_name}: Correct"

    # Scoring
    total_score = 10 # Base for valid CSV
    feedback_lines = []
    
    # 1. Ammonia, Anhydrous (UN 1005)
    s, f = check_entry("Ammonia Anhydrous", "1005", ["2.2", "Non-Flammable"]) # Accepts either code or text
    total_score += s
    feedback_lines.append(f)

    # 2. Ammonia, 25% Solution (UN 2672)
    s, f = check_entry("Ammonia Solution", "2672", ["8", "Corrosive"])
    total_score += s
    feedback_lines.append(f)

    # 3. Hydrogen Peroxide 50% (UN 2014) - Oxidizer AND Corrosive
    s, f = check_entry("H2O2 50%", "2014", ["5.1", "8"]) # "Oxidizer" and "Corrosive" implied by codes usually, but user might write names
    total_score += s
    feedback_lines.append(f)

    # 4. Hydrogen Peroxide 15% (UN 2984) - Oxidizer ONLY (No Corrosive label for UN 2984 usually, though strictly it's Class 5.1)
    # Key distinction: UN 2014 has secondary hazard 8. UN 2984 does not.
    s, f = check_entry("H2O2 15%", "2984", ["5.1"], excluded_labels=["8", "Corrosive"])
    total_score += s
    feedback_lines.append(f)

    # 5. Nitric Acid Red Fuming (UN 2032)
    s, f = check_entry("Red Fuming Nitric", "2032", ["8", "5.1", "6.1"]) # Corrosive, Oxidizer, Poison
    total_score += s
    feedback_lines.append(f)

    # 4. VLM Verification (Bonus/Confirmation)
    # Check if they actually visited multiple pages
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_res = query_vlm(
            frames, 
            "Does the user appear to be navigating between different chemical datasheets on the CAMEO Chemicals website? Look for headers like 'Ammonia', 'Hydrogen Peroxide', 'Nitric Acid'."
        )
        if vlm_res.get("success") and vlm_res.get("answer_bool"):
            # If they did the work visually but maybe made a typo in CSV, we might be lenient? 
            # For now, just logging or using as tiebreaker.
            pass
        elif total_score > 60:
             # If score is high but VLM says no navigation, suspicious (pasted answer?)
             # We won't fail them purely on VLM but add warning
             feedback_lines.append("(Warning: Limited navigation detected in screen recording)")

    # Cap score
    total_score = min(100, total_score)
    passed = total_score >= 70

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_lines)
    }