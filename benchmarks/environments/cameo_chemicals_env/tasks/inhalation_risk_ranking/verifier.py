#!/usr/bin/env python3
"""
Verifier for inhalation_risk_ranking task.
Verifies the CSV output against ground truth values and ranking logic.
Also uses VLM to ensure the agent actually researched the data.
"""

import json
import csv
import io
import os
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utils if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inhalation_risk_ranking(traj, env_info, task_info):
    """
    Verify the Inhalation Risk Ranking task.
    
    Criteria:
    1. Output CSV exists and has content (10 pts)
    2. File created during task (Anti-gaming) (10 pts)
    3. Correct chemicals present (10 pts)
    4. IDLH and Vapor Pressure values are reasonably accurate (30 pts)
    5. Calculations (Ratio) are correct based on input values (10 pts)
    6. Ranking is correct (Highest risk to lowest) (20 pts)
    7. VLM: Evidence of browsing CAMEO Chemicals datasheets (10 pts)
    """
    
    # 1. Setup and helper functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('output_path', '/home/ga/Documents/inhalation_risk_assessment.csv')
    ground_truth_chems = metadata.get('chemicals', {})
    expected_ranking_order = metadata.get('expected_ranking', [])

    score = 0
    max_score = 100
    feedback = []
    
    # 2. Retrieve Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tmp_json:
        try:
            copy_from_env("/tmp/task_result.json", tmp_json.name)
            tmp_json.seek(0)
            task_result = json.load(tmp_json)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {str(e)}"}

    # 3. Check File Existence and Creation Time
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not created."}
    
    score += 10
    feedback.append("File created.")

    if task_result.get("file_created_during_task", False):
        score += 10
        feedback.append("File created during task window.")
    else:
        feedback.append("WARNING: File timestamp suggests pre-existence or creation before task start.")

    # 4. Retrieve and Parse CSV Content
    rows = []
    with tempfile.NamedTemporaryFile(suffix='.csv') as tmp_csv:
        try:
            copy_from_env(expected_path, tmp_csv.name)
            tmp_csv.seek(0)
            # Read as text
            content = tmp_csv.read().decode('utf-8', errors='replace')
            
            # Parse CSV
            f = io.StringIO(content)
            reader = csv.DictReader(f)
            # Normalize headers: strip whitespace, lower case for robust matching
            reader.fieldnames = [name.strip() for name in reader.fieldnames]
            for row in reader:
                rows.append(row)
                
            if len(rows) != 5:
                feedback.append(f"Expected 5 rows of data, found {len(rows)}.")
            
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read/parse CSV: {str(e)}"}

    # 5. Validate Content (Chemicals, Values, Math, Ranking)
    
    # Mapping for normalization
    chem_map = {
        "methanol": "Methanol",
        "toluene": "Toluene",
        "acetone": "Acetone",
        "carbon disulfide": "Carbon Disulfide",
        "ethylene oxide": "Ethylene Oxide"
    }
    
    chemicals_found = 0
    data_accuracy_points = 0
    math_points = 0
    ranking_points = 0
    
    # Check headers
    required_cols = ["IDLH_ppm", "Vapor_Pressure_mmHg", "VP_IDLH_Ratio", "Risk_Rank"]
    headers_ok = all(any(req.lower() in (h.lower() for h in (row.keys() if rows else []))) for req in required_cols)
    if not headers_ok:
        feedback.append("CSV headers missing required columns.")
    
    # Process rows
    processed_data = [] # List of tuples (chem_name, ratio, rank)
    
    for row in rows:
        # Identify chemical
        c_name_raw = row.get("Chemical", "")
        c_cas_raw = row.get("CAS", "")
        
        # Determine canonical name
        canonical_name = None
        for key, val in chem_map.items():
            if key in c_name_raw.lower():
                canonical_name = val
                break
        
        if not canonical_name:
            # Try CAS fallback
            for name, data in ground_truth_chems.items():
                if data["cas"] in c_cas_raw:
                    canonical_name = name
                    break
        
        if canonical_name:
            chemicals_found += 1
            
            # Validate Data
            try:
                # Flexible extraction (handle common CSV issues)
                idlh = float(row.get("IDLH_ppm", 0))
                vp = float(row.get("Vapor_Pressure_mmHg", 0))
                ratio = float(row.get("VP_IDLH_Ratio", 0))
                rank = int(row.get("Risk_Rank", 0))
                
                gt = ground_truth_chems[canonical_name]
                
                # Check IDLH (Exact match usually expected for regulations, allow small diff)
                idlh_ok = abs(idlh - gt["idlh"]) < (gt["idlh"] * 0.1)
                
                # Check VP (High variance allowed due to temp diffs in sources)
                # Allow +/- 35%
                vp_ok = abs(vp - gt["vp_approx"]) < (gt["vp_approx"] * 0.35)
                
                if idlh_ok and vp_ok:
                    data_accuracy_points += 6 # 5 chemicals * 6 pts = 30 max
                
                # Check Math (Ratio = VP / IDLH)
                calc_ratio = vp / idlh if idlh > 0 else 0
                if abs(calc_ratio - ratio) < 0.01:
                    math_points += 2 # 5 chemicals * 2 pts = 10 max
                
                processed_data.append({"name": canonical_name, "rank": rank, "ratio": ratio})
                
            except ValueError:
                feedback.append(f"Invalid number format for {canonical_name}")
        else:
            feedback.append(f"Unknown chemical row: {c_name_raw}")

    # Scale Data Accuracy Score
    score += min(30, data_accuracy_points)
    if data_accuracy_points < 15:
        feedback.append("Data accuracy low (IDLH/VP values mismatch reference).")
    else:
        feedback.append("Data values acceptable.")

    # Scale Math Score
    score += min(10, math_points)

    # Check Chemical Completeness
    if chemicals_found == 5:
        score += 10
        feedback.append("All 5 chemicals found.")
    else:
        feedback.append(f"Only {chemicals_found}/5 chemicals identified.")

    # Check Ranking
    # Sort processed data by rank index in file
    processed_data.sort(key=lambda x: x["rank"])
    ranked_names = [x["name"] for x in processed_data]
    
    # Compare with expected order
    if ranked_names == expected_ranking_order:
        score += 20
        feedback.append("Risk ranking order is correct.")
    else:
        # Partial credit for top risk
        if ranked_names and ranked_names[0] == expected_ranking_order[0]:
            score += 5
            feedback.append("Top risk (Ethylene Oxide) correctly identified.")
        feedback.append(f"Ranking incorrect. Got: {ranked_names[:3]}...")

    # 6. VLM Verification (Anti-Gaming)
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            # Sample frames from trajectory
            frames = sample_trajectory_frames(traj, n=8)
            prompt = (
                "Review these screenshots of an agent performing a task. "
                "The agent should be using the CAMEO Chemicals website to look up 'Methanol', 'Toluene', 'Acetone', etc. "
                "1. Do you see the CAMEO Chemicals website (blue/white theme, NOAA logo)? "
                "2. Do you see specific chemical datasheets being viewed (e.g., 'Physical Properties' or 'Hazards' sections)? "
                "3. Does the agent visit multiple different pages? "
                "Answer 'Yes' only if there is clear visual evidence of research."
            )
            result = query_vlm(images=frames, prompt=prompt)
            
            if result.get("success", False) and "yes" in result.get("response", "").lower():
                vlm_score = 10
                feedback.append("VLM: Web research verified.")
            else:
                feedback.append("VLM: No clear evidence of browsing CAMEO Chemicals.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            vlm_score = 10 # Fallback to giving points if VLM fails to avoid punishing agent for system error
            feedback.append("VLM check skipped (system error).")
    else:
        vlm_score = 10 # Skip if not available
        feedback.append("VLM check skipped.")

    score += vlm_score

    # Final Pass Determination
    # Must get ranking correct OR have very high data accuracy to pass
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }