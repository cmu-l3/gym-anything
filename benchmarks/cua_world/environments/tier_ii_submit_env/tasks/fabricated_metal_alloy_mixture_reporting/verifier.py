#!/usr/bin/env python3
"""
Verifier for Fabricated Metal Alloy Mixture Reporting task.

Scoring System (100 points total):
- 10 pts: Output .t2s file is saved and updated.
- 10 pts: Chemical name is "316L Stainless Steel", marked as Mixture, and Solid.
- 20 pts: GHS Hazards correctly checked (Carcinogenicity, Sensitization, STOT).
- 10 pts: Component Iron (CAS 7439-89-6) exists with ~68.5%.
- 15 pts: Component Chromium (CAS 7440-47-3) exists with ~17.0%.
- 15 pts: Component Nickel (CAS 7440-02-0) exists with ~12.0%.
- 10 pts: Component Molybdenum (CAS 7439-98-7) exists with ~2.5%.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fabricated_metal_alloy_mixture_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\alloy_mixture_result.json")
    pass_threshold = metadata.get("pass_threshold", 75)
    expected_comps = metadata.get("expected_components", {
        "iron": {"cas": "7439-89-6", "pct": 68.5},
        "chromium": {"cas": "7440-47-3", "pct": 17.0},
        "nickel": {"cas": "7440-02-0", "pct": 12.0},
        "molybdenum": {"cas": "7439-98-7", "pct": 2.5}
    })

    # Retrieve result JSON
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. Check if file was created/saved
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found. Task not completed."}
    
    score += 10
    feedback.append("PASS: Output file exported successfully (+10)")

    if not result.get("file_created_during_task", False):
        feedback.append("WARNING: File appears older than task start time (possible overwrite issue).")

    chemicals = result.get("chemicals", [])
    if not chemicals:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | FAIL: No chemicals found in exported data."}

    # Locate the target chemical
    target_chem = None
    for chem in chemicals:
        name = str(chem.get("name", "")).lower()
        if "316l" in name or "stainless steel" in name:
            target_chem = chem
            break

    if not target_chem:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | FAIL: Chemical '316L Stainless Steel' not found."}

    # 2. Basic Identification and Physical State (10 pts)
    state_ok = target_chem.get("is_solid", False)
    mixture_ok = target_chem.get("is_mixture", False)
    
    if state_ok and mixture_ok:
        score += 10
        feedback.append("PASS: Marked as Solid and Mixture (+10)")
    else:
        feedback.append(f"FAIL: State/Mixture incorrect (Solid: {state_ok}, Mixture: {mixture_ok})")

    # 3. GHS Health Hazards (20 pts)
    hazards = target_chem.get("hazards", {})
    carcinogen = hazards.get("Carcinogenicity", False)
    sensitizer = hazards.get("RespiratorySensitization", False) or hazards.get("RespiratoryOrSkinSensitization", False)
    stot = hazards.get("STOT_RepeatedExposure", False) or hazards.get("SpecificTargetOrganToxicityRepeatedExposure", False)

    if carcinogen and sensitizer and stot:
        score += 20
        feedback.append("PASS: GHS Health Hazards correct (+20)")
    else:
        missing = []
        if not carcinogen: missing.append("Carcinogenicity")
        if not sensitizer: missing.append("Sensitization")
        if not stot: missing.append("STOT")
        feedback.append(f"FAIL: Missing expected health hazards: {', '.join(missing)}")

    # 4. Mixture Components (50 pts total)
    components = target_chem.get("components", [])
    
    def check_component(name, expected_cas, expected_pct, points):
        for comp in components:
            cas = str(comp.get("cas", "")).strip()
            pct_str = str(comp.get("percentage", "")).strip()
            if cas == expected_cas:
                try:
                    pct = float(pct_str)
                    if abs(pct - expected_pct) <= 1.0:
                        return True, f"PASS: {name} component correct ({cas}, {pct}%) (+{points})"
                    else:
                        return False, f"FAIL: {name} percentage wrong (expected {expected_pct}%, got {pct}%)"
                except ValueError:
                    return False, f"FAIL: {name} percentage not a valid number ('{pct_str}')"
        return False, f"FAIL: {name} component missing (CAS {expected_cas})"

    # Iron (10 pts)
    ok, msg = check_component("Iron", expected_comps["iron"]["cas"], expected_comps["iron"]["pct"], 10)
    if ok: score += 10
    feedback.append(msg)

    # Chromium (15 pts)
    ok, msg = check_component("Chromium", expected_comps["chromium"]["cas"], expected_comps["chromium"]["pct"], 15)
    if ok: score += 15
    feedback.append(msg)

    # Nickel (15 pts)
    ok, msg = check_component("Nickel", expected_comps["nickel"]["cas"], expected_comps["nickel"]["pct"], 15)
    if ok: score += 15
    feedback.append(msg)

    # Molybdenum (10 pts)
    ok, msg = check_component("Molybdenum", expected_comps["molybdenum"]["cas"], expected_comps["molybdenum"]["pct"], 10)
    if ok: score += 10
    feedback.append(msg)

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }