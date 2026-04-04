#!/usr/bin/env python3
"""
Verifier for Piping Material Compatibility Audit task.
Verifies the agent's CSV report against ground truth compatibility rules derived from CAMEO Chemicals.
"""

import json
import csv
import os
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_bool_string(value: str) -> str:
    """Normalize YES/NO/TRUE/FALSE strings to YES/NO."""
    v = value.strip().upper()
    if v in ['YES', 'TRUE', 'Y', 'SAFE', 'COMPATIBLE']:
        return 'YES'
    if v in ['NO', 'FALSE', 'N', 'UNSAFE', 'INCOMPATIBLE']:
        return 'NO'
    return 'UNKNOWN'

def verify_piping_audit(traj, env_info, task_info):
    """
    Verify the piping compatibility audit CSV.
    
    Scoring Criteria:
    - File existence and validity (10 pts)
    - Anti-gaming check (file created during task) (10 pts)
    - CSV Structure (headers) (10 pts)
    - Correct classification of 5 chemicals (12 pts each -> 60 pts total)
    - Hazard notes present for incompatible items (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Ground Truth Data
    # Derived from CAMEO Chemicals Datasheets
    ground_truth = {
        "Sodium Hydroxide": {"al": "NO", "cu": "NO"},  # Corrodes both
        "Ammonia":          {"al": "YES", "cu": "NO"}, # Attacks copper/zinc
        "Methyl Chloride":  {"al": "NO", "cu": "YES"}, # Attacks aluminum (pyrophoric)
        "Sulfuric Acid":    {"al": "NO", "cu": "NO"},  # Strong acid attacks most metals
        "Toluene":          {"al": "YES", "cu": "YES"} # Solvent, generally safe
    }
    
    # Helper to fuzzy match chemical names
    def identify_chemical(name):
        n = name.lower()
        if "sodium" in n and "hydroxide" in n: return "Sodium Hydroxide"
        if "ammonia" in n: return "Ammonia"
        if "methyl" in n and "chloride" in n: return "Methyl Chloride"
        if "sulfuric" in n and "acid" in n: return "Sulfuric Acid"
        if "toluene" in n: return "Toluene"
        return None

    score = 0
    feedback = []
    
    # 1. Load Task Result Metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check File Existence & Timestamp
    if not meta.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    score += 10
    
    if meta.get("file_created_during_task", False):
        score += 10
    else:
        feedback.append("WARNING: Output file timestamp indicates it wasn't created during this task session.")

    # 3. Load and Parse CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(meta["output_path"], temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # Detect header
            sample = f.read(1024)
            f.seek(0)
            has_header = csv.Sniffer().has_header(sample)
            reader = csv.DictReader(f)
            
            # Verify Headers
            required_cols = ["Chemical", "Safe_for_Aluminum", "Safe_for_Copper"]
            if reader.fieldnames:
                headers = [h.strip() for h in reader.fieldnames]
                # Flexible header matching
                if any("Aluminum" in h for h in headers) and any("Copper" in h for h in headers):
                    score += 10
                else:
                    feedback.append(f"Missing required columns. Found: {headers}")
            else:
                feedback.append("CSV appears empty or malformed.")
                return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

            # Process Rows
            rows = list(reader)
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error reading CSV: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Verify Chemical Data
    correct_chemicals = 0
    hazard_notes_ok = True
    
    # Map rows to ground truth chemicals
    found_chemicals = {}
    for row in rows:
        # normalize keys
        norm_row = {k.lower().strip(): v for k,v in row.items()}
        
        # find name column
        name_val = ""
        for k in norm_row:
            if "chemical" in k or "name" in k:
                name_val = norm_row[k]
                break
        
        gt_key = identify_chemical(name_val)
        if gt_key:
            found_chemicals[gt_key] = norm_row

    # Evaluate each required chemical
    for gt_chem, rules in ground_truth.items():
        if gt_chem not in found_chemicals:
            feedback.append(f"Missing chemical: {gt_chem}")
            continue
            
        row = found_chemicals[gt_chem]
        
        # Find al/cu columns flexibly
        al_val = "UNKNOWN"
        cu_val = "UNKNOWN"
        hazard_val = ""
        
        for k, v in row.items():
            if "alum" in k: al_val = normalize_bool_string(v)
            if "cop" in k: cu_val = normalize_bool_string(v)
            if "haz" in k: hazard_val = v.strip()

        # Check correctness
        chem_score = 0
        chem_pass = True
        
        if al_val == rules["al"]:
            chem_score += 6
        else:
            chem_pass = False
            feedback.append(f"{gt_chem}: Aluminum check failed (Expected {rules['al']}, got {al_val})")
            
        if cu_val == rules["cu"]:
            chem_score += 6
        else:
            chem_pass = False
            feedback.append(f"{gt_chem}: Copper check failed (Expected {rules['cu']}, got {cu_val})")
            
        score += chem_score
        if chem_pass: correct_chemicals += 1
        
        # Check hazard notes for incompatible items
        if (rules["al"] == "NO" or rules["cu"] == "NO") and len(hazard_val) < 3:
            hazard_notes_ok = False

    # Bonus points for hazard notes
    if hazard_notes_ok and len(found_chemicals) > 0:
        score += 10
    elif len(found_chemicals) > 0:
        feedback.append("Hazard descriptions were missing or too brief for incompatible items.")

    # Final tally
    feedback.insert(0, f"Correctly classified {correct_chemicals}/5 chemicals.")
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }