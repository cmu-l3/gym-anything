#!/usr/bin/env python3
"""
Verifier for aggregated_ehs_component_reporting task.

Verification Strategy:
1. File Creation Anti-Gaming: Output .t2s exists and was saved *after* task start.
2. Facility Metadata: NAICS code correctly updated to 336412.
3. Component Calculation: Max/Avg Daily Amounts must equal exactly 3500 lbs (bypassing range codes).
4. Chemical Identity: Nitric Acid (CAS 7697-37-2), Pure flag = True, EHS flag = True.
5. Storage Configuration: At least 2 storage locations attached to the chemical (Tank A & B).
6. Hazards: Oxidizer, Corrosive to metal, Acute Toxicity, Skin Corrosion marked true.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\aggregated_ehs_result.json"
START_TIME_PATH = "C:\\Users\\Docker\\Desktop\\task_start_time.txt"


def get_ci(d, keys, default=None):
    """Case-insensitive dictionary key lookup."""
    if not isinstance(d, dict):
        return default
    d_lower = {k.lower(): v for k, v in d.items()}
    for k in keys:
        if k.lower() in d_lower:
            return d_lower[k.lower()]
    return default


def verify_aggregated_ehs_component_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)

    # Extract JSON results
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    tmp_start = tempfile.NamedTemporaryFile(suffix=".txt", delete=False)
    
    try:
        copy_from_env(result_file, tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
            
        try:
            copy_from_env(START_TIME_PATH, tmp_start.name)
            with open(tmp_start.name, "r") as f:
                task_start_time = float(f.read().strip())
        except Exception:
            task_start_time = 0.0
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export file not found: {e}"}
    finally:
        for tmp_file in [tmp_json.name, tmp_start.name]:
            try:
                os.unlink(tmp_file)
            except Exception:
                pass

    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output precision_aerospace_final.t2s not found."}

    # Anti-gaming: Ensure file was generated during the task
    file_mtime = result.get("file_mtime", 0)
    if task_start_time > 0 and file_mtime < task_start_time:
        return {"passed": False, "score": 0, "feedback": "File timestamp predates task start (Do-Nothing detected)."}

    score = 10
    fb = ["File successfully generated (+10)"]
    
    fac = result.get("facility", {})
    chems = result.get("chemicals", [])
    
    # 1. Facility Metadata (15 pts)
    naics = str(get_ci(fac, ["NAICS", "NAICSCode", "naics_code"], ""))
    if "336412" in naics:
        score += 15
        fb.append("NAICS code updated to 336412 (+15)")
    else:
        fb.append(f"FAIL: NAICS code is {naics} (expected 336412)")

    # Find target chemical
    nitric_acid = None
    for chem in chems:
        cas = str(get_ci(chem, ["CAS", "CASNumber"], "")).strip()
        name = str(get_ci(chem, ["ChemicalName", "Name"], "")).lower()
        if "7697-37-2" in cas or "nitric acid" in name:
            nitric_acid = chem
            break

    if not nitric_acid:
        fb.append("FAIL: Nitric Acid (CAS 7697-37-2) not found in inventory.")
        return {"passed": False, "score": score, "feedback": " | ".join(fb)}

    # 2. Chemical Identity (15 pts)
    cas = str(get_ci(nitric_acid, ["CAS", "CASNumber"], "")).strip()
    is_pure = str(get_ci(nitric_acid, ["IsPure", "Pure"], "false")).lower() == "true"
    is_ehs = str(get_ci(nitric_acid, ["IsEHS", "EHS"], "false")).lower() == "true"
    
    if "7697-37-2" in cas and is_pure and is_ehs:
        score += 15
        fb.append("Chemical identity accurate (Pure EHS Nitric Acid) (+15)")
    else:
        fb.append(f"FAIL: Chem ID params incorrect. CAS={cas}, Pure={is_pure}, EHS={is_ehs}")

    # 3. Calculation & Exact Quantities (30 pts)
    # They should bypass range codes and enter the EXACT calculated pure component weight
    try:
        max_amt = float(get_ci(nitric_acid, ["MaxDailyAmount", "MaximumAmount", "MaxAmount"], 0))
        avg_amt = float(get_ci(nitric_acid, ["AverageDailyAmount", "AvgAmount", "AveAmount"], 0))
        
        # 10,000 lbs total solution * 35% concentration = 3,500 lbs pure component
        if 3495 <= max_amt <= 3505 and 3495 <= avg_amt <= 3505:
            score += 30
            fb.append(f"Exact calculated EHS quantities reported: {max_amt} lbs (+30)")
        else:
            fb.append(f"FAIL: Quantities reported as Max={max_amt}, Avg={avg_amt} (expected exactly 3500)")
    except (ValueError, TypeError):
        fb.append("FAIL: Quantities could not be parsed as floats.")

    # 4. Storage Configuration (20 pts)
    storage_locs = nitric_acid.get("storage_locations", [])
    if len(storage_locs) >= 2:
        descriptions = [str(get_ci(s, ["Location", "Description", "StorageLocation"], "")).lower() for s in storage_locs]
        has_tank_a = any("tank a" in d for d in descriptions)
        has_tank_b = any("tank b" in d for d in descriptions)
        
        if has_tank_a and has_tank_b:
            score += 20
            fb.append(f"2 Storage locations attached with correct descriptions (+20)")
        else:
            score += 10
            fb.append(f"2 Storage locations found, but missing 'Tank A' / 'Tank B' naming (+10)")
    else:
        fb.append(f"FAIL: Found {len(storage_locs)} storage locations (expected 2)")

    # 5. Hazard Accuracy (10 pts)
    hazards = nitric_acid.get("hazards", {})
    haz_str = str(hazards).lower()
    required_hazards = ["oxidizer", "corrosive to metal", "acute toxicity", "skin corrosion"]
    
    missing = [h for h in required_hazards if h not in haz_str]
    if not missing:
        score += 10
        fb.append("All required physical and health hazards configured (+10)")
    else:
        fb.append(f"FAIL: Missing hazard configuration for: {missing}")

    passed = score >= 85
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb)
    }