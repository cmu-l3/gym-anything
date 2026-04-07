#!/usr/bin/env python3
"""
Verifier for water_treatment_chemical_transition task.

Scoring Breakdown (100 pts total, passing threshold 70):
- Output file exists: 10 pts
- Chlorine (CAS 7782-50-5) Days On-Site updated to 60: 20 pts
- Sodium Hypochlorite (CAS 7681-52-9) added: 10 pts
- Sodium Hypochlorite PhysicalState is Liquid: 5 pts
- Sodium Hypochlorite Days On-Site is 305: 5 pts
- Sodium Hypochlorite Hazards set correctly: 15 pts (5 pts each for 3 hazards)
- Sodium Hypochlorite Inventory & Storage correct: 15 pts (5 pts each for max, avg, storage location)
- Facility RMP Status (CAA 112r) unchecked/cleared: 20 pts

Anti-gaming: The output folder is wiped in setup, so the .t2s file MUST have been created during the task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_water_treatment_chemical_transition(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\water_treatment_chemical_transition_result.json")
    pass_threshold = metadata.get("pass_threshold", 70)

    # 1. Retrieve the exported JSON from the container
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read or parse result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            try:
                os.unlink(tmp.name)
            except:
                pass

    # 2. Check if the agent successfully saved the .t2s file
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "FAIL: Output .t2s file not found. Task was not saved/exported."}

    score = 10
    fb = ["PASS: Output file exists (+10)"]

    fac = result.get("facility_flat", {})
    chemicals = result.get("chemicals", [])

    cl_chem = None
    sh_chem = None
    for chem in chemicals:
        cas = chem.get("cas", "")
        if "7782-50-5" in cas:
            cl_chem = chem
        elif "7681-52-9" in cas:
            sh_chem = chem

    # 3. Verify Chlorine modification
    if cl_chem:
        flat = cl_chem.get("flat_data", {})
        days = str(flat.get("DaysOnSite", "")).strip()
        if days == "60":
            score += 20
            fb.append("PASS: Chlorine DaysOnSite updated to 60 (+20)")
        else:
            fb.append(f"FAIL: Chlorine DaysOnSite is {days} (expected 60)")
    else:
        fb.append("FAIL: Chlorine (CAS 7782-50-5) missing from export")

    # 4. Verify Sodium Hypochlorite addition
    if sh_chem:
        score += 10
        fb.append("PASS: Sodium Hypochlorite (CAS 7681-52-9) added (+10)")
        flat = sh_chem.get("flat_data", {})

        # State & Days
        state_str = str(flat.get("PhysicalState", "")).lower()
        if "liquid" in state_str:
            score += 5
            fb.append("PASS: Sodium Hypo PhysicalState is Liquid (+5)")
        elif any("liquid" in str(v).lower() for v in flat.values()):
            score += 5
            fb.append("PASS: Sodium Hypo PhysicalState contains Liquid (Fallback) (+5)")
        else:
            fb.append("FAIL: Sodium Hypo PhysicalState not set to Liquid")

        days = str(flat.get("DaysOnSite", "")).strip()
        if days == "305":
            score += 5
            fb.append("PASS: Sodium Hypo DaysOnSite is 305 (+5)")
        else:
            fb.append(f"FAIL: Sodium Hypo DaysOnSite is {days} (expected 305)")

        # Helper for Hazards
        def has_hazard(hazard_key, hazard_text):
            for k, v in flat.items():
                if hazard_key.lower() in k.lower() and str(v).lower() in ['true', '1', 'yes']:
                    return True
                if hazard_text.lower() in str(v).lower() and str(v).lower() not in ['false', '0', 'no']:
                    return True
            return False

        if has_hazard("CorrosiveToMetal", "corrosive to metal"):
            score += 5
            fb.append("PASS: Corrosive to metal hazard set (+5)")
        else:
            fb.append("FAIL: Corrosive to metal hazard missing")

        if has_hazard("SkinCorrosion", "skin corrosion"):
            score += 5
            fb.append("PASS: Skin corrosion hazard set (+5)")
        else:
            fb.append("FAIL: Skin corrosion hazard missing")

        if has_hazard("SeriousEyeDamage", "eye damage"):
            score += 5
            fb.append("PASS: Eye damage hazard set (+5)")
        else:
            fb.append("FAIL: Eye damage hazard missing")

        # Inventory & Storage Values
        inv_str = " ".join(str(v).lower() for v in flat.values())
        if "15000" in inv_str or "05" in inv_str:
            score += 5
            fb.append("PASS: Max amount 15,000 found (+5)")
        else:
            fb.append("FAIL: Max amount 15,000 not found")
            
        if "10000" in inv_str or "04" in inv_str:
            score += 5
            fb.append("PASS: Avg amount 10,000 found (+5)")
        else:
            fb.append("FAIL: Avg amount 10,000 not found")

        if "above ground" in inv_str and "ambient" in inv_str:
            score += 5
            fb.append("PASS: Storage location (Above ground tank, Ambient) found (+5)")
        else:
            fb.append("FAIL: Storage location missing or incorrect")
    else:
        fb.append("FAIL: Sodium Hypochlorite (CAS 7681-52-9) not found in export")

    # 5. Verify Facility RMP Status Change
    rmp_status = "false"
    for k, v in fac.items():
        if "accidentprevention" in k.lower() or "caa112" in k.lower() or "rmp" in k.lower():
            if str(v).lower() in ["true", "1", "yes"]:
                rmp_status = "true"
                break
    
    if rmp_status == "false":
        score += 20
        fb.append("PASS: Facility CAA 112(r) / RMP status is correctly unchecked (+20)")
    else:
        fb.append("FAIL: Facility CAA 112(r) / RMP status is still True")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb)
    }