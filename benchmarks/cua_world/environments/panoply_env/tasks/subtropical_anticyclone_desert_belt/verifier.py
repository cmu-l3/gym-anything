#!/usr/bin/env python3
"""
Verifier for subtropical_anticyclone_desert_belt task.

Occupation: Desertification Researcher / Climate Policy Scientist (UNEP)
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. SLP Global Plot (20 pts): slp_global_july.png exists, >15KB, newer than task_start.
  2. Precipitation Global Plot (20 pts): precip_global_july.png exists, >15KB, newer than task_start.
  3. Report Completeness (20 pts): desert_belt_report.txt contains all 5 required fields.
  4. Mechanism Correctness (15 pts): Mechanism field mentions key physics (subsidence, Hadley cell, sinking, etc.).
  5. SLP-Precipitation Relationship (25 pts): SLP_PRECIP_RELATIONSHIP is exactly "NEGATIVE".
"""

import json
import os
import tempfile

def verify_subtropical_anticyclone_desert_belt(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/subtropical_anticyclone_desert_belt_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # 1. SLP Global Plot (20 pts)
    slp_exists = result.get('slp_png_exists', False)
    slp_mtime = int(result.get('slp_png_mtime', 0))
    slp_size = int(result.get('slp_png_size', 0))

    if slp_exists and slp_mtime >= task_start and slp_size >= 15000:
        score += 20
        feedback.append(f"SLP global plot exported correctly ({slp_size} bytes).")
    elif slp_exists and slp_mtime >= task_start and slp_size >= 5000:
        score += 10
        feedback.append(f"SLP plot present but suspiciously small ({slp_size} bytes).")
    else:
        feedback.append("SLP global plot missing or not created during task.")

    # 2. Precipitation Global Plot (20 pts)
    precip_exists = result.get('precip_png_exists', False)
    precip_mtime = int(result.get('precip_png_mtime', 0))
    precip_size = int(result.get('precip_png_size', 0))

    if precip_exists and precip_mtime >= task_start and precip_size >= 15000:
        score += 20
        feedback.append(f"Precipitation global plot exported correctly ({precip_size} bytes).")
    elif precip_exists and precip_mtime >= task_start and precip_size >= 5000:
        score += 10
        feedback.append(f"Precipitation plot present but suspiciously small ({precip_size} bytes).")
    else:
        feedback.append("Precipitation global plot missing or not created during task.")

    # Prevent identical plots from scoring full points
    if slp_size > 0 and slp_size == precip_size:
        score -= 20
        feedback.append("WARNING: SLP and Precipitation plots are identical in size. Likely the same plot exported twice.")

    # 3. Report Completeness (20 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    month = result.get('analysis_month', '').strip().lower()
    high = result.get('nh_subtropical_high', '').strip()
    desert = result.get('associated_desert', '').strip()
    mechanism = result.get('mechanism', '').strip().lower()
    relationship = result.get('slp_precip_relationship', '').strip().upper()

    has_all = bool(month) and bool(high) and bool(desert) and bool(mechanism) and bool(relationship)
    
    if report_exists and report_mtime >= task_start:
        if has_all:
            score += 20
            feedback.append("Report contains all required fields.")
        else:
            score += 10
            feedback.append("Report is missing one or more required fields.")
            
        # 4. Mechanism Correctness (15 pts)
        mech_keywords = ["subsidence", "subside", "descend", "hadley", "sink", "high pressure"]
        if any(kw in mechanism for kw in mech_keywords):
            score += 15
            feedback.append("Mechanism correctly identifies atmospheric subsidence/Hadley cell dynamics.")
        else:
            feedback.append("Mechanism lacks key physical terminology (subsidence, descending air, Hadley cell, etc.).")
            
        # 5. SLP-Precipitation Relationship (25 pts)
        if relationship == "NEGATIVE":
            score += 25
            feedback.append("SLP-Precipitation relationship correctly identified as NEGATIVE.")
        else:
            feedback.append(f"Incorrect SLP-Precipitation relationship (got '{relationship}', expected 'NEGATIVE').")
            
        # Optional check on month
        if "july" not in month:
            feedback.append(f"Warning: Analysis month was '{month}', expected July.")
    else:
        feedback.append("Desert belt report missing or not created during task.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }