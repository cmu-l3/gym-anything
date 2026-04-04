#!/usr/bin/env python3
"""
Verifier for PSM/RMP Threshold Screening Task.
Checks validity of CSV output and correctness of regulatory logic.
"""

import json
import os
import csv
import io
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_content(content):
    """Parse CSV string into list of dicts."""
    try:
        # Handle potential BOM or encoding issues
        lines = content.strip().splitlines()
        if not lines:
            return []
        
        reader = csv.DictReader(lines)
        # Normalize headers: strip whitespace, lower case
        if reader.fieldnames:
            reader.fieldnames = [h.strip().lower() for h in reader.fieldnames]
        
        return list(reader)
    except Exception as e:
        logger.error(f"CSV parsing error: {e}")
        return []

def normalize_chemical_name(name):
    """Normalize chemical names for fuzzy matching."""
    if not name:
        return ""
    name = name.lower().strip()
    name = name.replace("anhydrous", "").replace(",", "").replace("  ", " ")
    return name.strip()

def normalize_bool(val):
    """Convert Yes/No/True/False to boolean."""
    if not val:
        return False
    s = str(val).lower().strip()
    return s in ['yes', 'y', 'true', '1', 'triggered']

def extract_number(val):
    """Extract numeric value from string (e.g., '1,500 lbs')."""
    if not val:
        return None
    s = str(val).lower().replace(',', '').replace('lbs', '').replace('lb', '').strip()
    try:
        return float(s)
    except ValueError:
        return None

def verify_psm_rmp_threshold_screening(traj, env_info, task_info):
    """
    Verify the regulatory audit task.
    
    Scoring Breakdown (100 pts total):
    1. CSV file exists and created during task (10 pts)
    2. CSV structure is valid (5 headers, 5 rows) (10 pts)
    3. Chlorine logic (PSM=Yes, RMP=No) (20 pts)
    4. Methomyl logic (Not listed/NA) (20 pts)
    5. Ammonia logic (Both Yes) (10 pts)
    6. Sulfur Dioxide logic (PSM=Yes, RMP=No) (10 pts)
    7. Hydrogen Fluoride logic (Both No) (10 pts)
    8. VLM Verification (Trajectory analysis) (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    # 1. Load Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    score = 0
    feedback_parts = []
    
    # Check if file exists and was created
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found"}
        
    if not task_result.get("file_created_during_task", False):
        feedback_parts.append("WARNING: Output file timestamp indicates it wasn't created during this run")
    else:
        score += 10
        feedback_parts.append("File created during task")

    # 2. Load and Parse CSV File
    csv_path = task_result.get("output_path", "/home/ga/Documents/regulatory_threshold_audit.csv")
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    rows = []
    
    try:
        copy_from_env(csv_path, temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            content = f.read()
            rows = parse_csv_content(content)
            
        if len(rows) >= 5:
            score += 10
            feedback_parts.append("CSV structure valid")
        else:
            feedback_parts.append(f"CSV has insufficient rows: {len(rows)}")
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read/parse CSV: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3-7. Verify Logic Row by Row
    chem_map = {normalize_chemical_name(r.get('chemical name', '')): r for r in rows}
    
    logic_score = 0
    
    # Check Chlorine (Critical: Mixed case)
    chlorine = chem_map.get('chlorine')
    if chlorine:
        psm = normalize_bool(chlorine.get('psm triggered', ''))
        rmp = normalize_bool(chlorine.get('rmp triggered', ''))
        if psm and not rmp:
            logic_score += 20
            feedback_parts.append("Chlorine logic correct (PSM=Y, RMP=N)")
        else:
            feedback_parts.append(f"Chlorine logic failed (Got PSM={psm}, RMP={rmp})")
    else:
        feedback_parts.append("Chlorine row missing")

    # Check Methomyl (Critical: Not Listed)
    methomyl = chem_map.get('methomyl')
    if methomyl:
        psm_tq = extract_number(methomyl.get('psm tq (lbs)', ''))
        rmp_tq = extract_number(methomyl.get('rmp tq (lbs)', ''))
        psm_trig = normalize_bool(methomyl.get('psm triggered', ''))
        rmp_trig = normalize_bool(methomyl.get('rmp triggered', ''))
        
        # Should be N/A or empty or 0, definitely NOT triggered
        is_na = (psm_tq is None or psm_tq == 0) and (rmp_tq is None or rmp_tq == 0)
        not_triggered = (not psm_trig) and (not rmp_trig)
        
        if not_triggered:
            logic_score += 20
            feedback_parts.append("Methomyl logic correct (Not triggered)")
        else:
            feedback_parts.append("Methomyl logic failed (Incorrectly marked as triggered)")
    else:
        feedback_parts.append("Methomyl row missing")

    # Check Ammonia (Both Yes)
    ammonia = chem_map.get('ammonia') or chem_map.get('ammonia anhydrous')
    if ammonia:
        psm = normalize_bool(ammonia.get('psm triggered', ''))
        rmp = normalize_bool(ammonia.get('rmp triggered', ''))
        if psm and rmp:
            logic_score += 10
            feedback_parts.append("Ammonia logic correct")
        else:
            feedback_parts.append("Ammonia logic failed")

    # Check Sulfur Dioxide (PSM Only)
    so2 = chem_map.get('sulfur dioxide')
    if so2:
        psm = normalize_bool(so2.get('psm triggered', ''))
        rmp = normalize_bool(so2.get('rmp triggered', ''))
        if psm and not rmp:
            logic_score += 10
            feedback_parts.append("SO2 logic correct")
        else:
            feedback_parts.append("SO2 logic failed")

    # Check Hydrogen Fluoride (Both No)
    hf = chem_map.get('hydrogen fluoride') or chem_map.get('hydrofluoric acid')
    if hf:
        psm = normalize_bool(hf.get('psm triggered', ''))
        rmp = normalize_bool(hf.get('rmp triggered', ''))
        if not psm and not rmp:
            logic_score += 10
            feedback_parts.append("HF logic correct")
        else:
            feedback_parts.append("HF logic failed")

    score += logic_score

    # 8. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the user appear to be searching for chemicals on CAMEO Chemicals "
            "and viewing the 'Regulatory Information' section? "
            "Look for tables mentioning 'Regulatory Information', 'OSHA', 'EPA', or 'Process Safety Management'."
        )
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('yes', True): # Assuming boolean or positive sentiment
             score += 10
             feedback_parts.append("VLM confirmed workflow")
        else:
             # Soft fail for VLM, just no bonus points
             feedback_parts.append("VLM could not confirm regulatory view")
    else:
        # Fallback if no frames
        score += 10
        feedback_parts.append("No VLM frames (skipped)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }