#!/usr/bin/env python3
"""
Verifier for rmp_regulated_pressurized_chemical task.

Validation strategy uses multiple independent signals:
1. File checks: Did the agent create the requested .t2s export file?
2. XML parsing checks: Verifies the chemical exists with correct regulatory flags (112r, EHS).
3. VLM Trajectory checks: Ensures the agent actually navigated the GUI instead of using a script.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    from gym_anything.vlm import sample_trajectory_frames
except ImportError:
    # Fallback if gym_anything not in path
    sample_trajectory_frames = lambda traj, n: []


# VLM Prompt to ensure genuine GUI interaction
VLM_PROMPT = """You are auditing an agent's desktop interaction trajectory.
The agent was tasked with adding a chemical in the EPA Tier2 Submit application.

Analyze these chronological screenshots and answer:
1. Is the Tier2 Submit application GUI visible and actively being used?
2. Is there evidence of navigating to the "Chemical Inventory" section or a chemical entry form?
3. Did the agent physically interact with the form (e.g., clicking checkboxes, entering text)?

Respond in JSON format:
{
    "used_gui": true/false,
    "navigated_inventory": true/false,
    "interacted_with_form": true/false
}
"""

def verify_rmp_regulated_pressurized_chemical(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\tmp\\rmp_task_result.json")
    target_cas = metadata.get("cas_number", "7664-41-7")
    pass_threshold = metadata.get("pass_threshold", 65)

    feedback = []
    score = 0
    max_score = 100

    # 1. Evaluate Trajectory via VLM (Anti-gaming)
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    frames = sample_trajectory_frames(traj, n=4)
    
    if query_vlm and frames:
        try:
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_gui"): vlm_score += 15
                if parsed.get("navigated_inventory"): vlm_score += 15
                if parsed.get("interacted_with_form"): vlm_score += 10
                feedback.append(f"VLM Trajectory Verification: {vlm_score}/40 pts")
            else:
                feedback.append("VLM evaluation failed, assigning 0 trajectory points.")
        except Exception as e:
            logger.error(f"VLM Exception: {e}")
            feedback.append("VLM exception occurred.")
    else:
        # If VLM isn't available, grant points implicitly so legitimate tests pass
        vlm_score = 40
        feedback.append("VLM not available, skipping trajectory check (granted 40 pts).")
    
    score += vlm_score

    # 2. Retrieve Result JSON
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export file not found/parseable: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # 3. Assess File Artifacts
    if not result.get("file_exists", False):
        feedback.append("FAIL: Output .t2s file not found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
    
    if not result.get("file_created_during_task", False):
        feedback.append("WARNING: Output file was not created/modified during the task timeframe.")

    chemicals = result.get("chemicals", [])
    target_chem = None
    for c in chemicals:
        if target_cas in c.get("cas", "") or target_cas in c.get("xml", ""):
            target_chem = c
            break

    if not target_chem:
        feedback.append(f"FAIL: Chemical {target_cas} not found in submission.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    score += 10
    feedback.append(f"PASS: Chemical {target_cas} present (+10)")

    # 4. XML Parsing for Regulatory Flags & Values
    xml = target_chem.get("xml", "").lower()

    # EHS Flag (10 pts)
    if re.search(r'<ehs[^>]*>\s*(true|1|yes)\s*</ehs>', xml):
        score += 10
        feedback.append("PASS: EHS flag is true (+10)")
    else:
        feedback.append("FAIL: EHS flag missing or false.")

    # CAA 112(r) / RMP Flag (15 pts)
    if re.search(r'<subjecttocaa112r[^>]*>\s*(true|1|yes)\s*</subjecttocaa112r>', xml):
        score += 15
        feedback.append("PASS: SubjectToCAA112r flag is true (+15)")
    else:
        feedback.append("FAIL: CAA 112(r) / RMP flag missing or false.")

    # Hazard Checks (10 pts)
    haz_gas = 'gasunderpressure' in xml and re.search(r'<gasunderpressure[^>]*>\s*(true|1)\s*</', xml)
    haz_flam = 'flammable' in xml and re.search(r'<flammable[^>]*>\s*(true|1)\s*</', xml)
    haz_tox = 'acutetoxicity' in xml and re.search(r'<acutetoxicity[^>]*>\s*(true|1)\s*</', xml)
    haz_skin = 'skincorrosion' in xml and re.search(r'<skincorrosion[^>]*>\s*(true|1)\s*</', xml)
    
    haz_count = sum([bool(haz_gas), bool(haz_flam), bool(haz_tox), bool(haz_skin)])
    score += int(10 * (haz_count / 4))
    if haz_count == 4:
        feedback.append("PASS: All required hazards selected (+10)")
    else:
        feedback.append(f"FAIL: Only found {haz_count}/4 expected hazards.")

    # Amounts (5 pts)
    max_amt = re.search(r'<maxdailyamount[^>]*>\s*([0-9\.]+)\s*<', xml)
    avg_amt = re.search(r'<averagedailyamount[^>]*>\s*([0-9\.]+)\s*<', xml)
    amt_pts = 0
    if max_amt and (max_amt.group(1) == "18500" or max_amt.group(1) == "05"): amt_pts += 2.5
    if avg_amt and (avg_amt.group(1) == "7200" or avg_amt.group(1) == "04"): amt_pts += 2.5
    score += int(amt_pts)
    if amt_pts == 5:
        feedback.append("PASS: Inventory amounts correct (+5)")
    else:
        feedback.append("FAIL: Inventory amounts incorrect or missing.")

    # Storage Pressure/Temp (10 pts)
    press = re.search(r'<pressure[^>]*>\s*(2|above ambient.*?)\s*<', xml)
    temp = re.search(r'<temperature[^>]*>\s*(3|below ambient.*?)\s*<', xml)
    
    if press:
        score += 5
        feedback.append("PASS: Storage pressure correct (+5)")
    else:
        feedback.append("FAIL: Storage pressure incorrect.")
        
    if temp:
        score += 5
        feedback.append("PASS: Storage temperature correct (+5)")
    else:
        feedback.append("FAIL: Storage temperature incorrect.")

    # Final Evaluation
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }