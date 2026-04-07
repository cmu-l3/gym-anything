#!/usr/bin/env python3
"""
Verifier for the Reactive Chemical Storage Infrastructure Upgrade task.

Verification Strategy:
1. Programmatic parsing of the exported .t2s (XML) file.
2. Verify the old ambient drum location is deleted.
3. Verify the new AST location is present with exact attributes.
4. Verify the Max Daily Amount was correctly updated.
5. VLM Trajectory fallback if programmatic file is missing or corrupted.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reactive_chemical_storage_upgrade(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_json_path = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\reactive_chemical_storage_result.json")
    target_t2s_path = metadata.get("output_file", "C:\\Users\\Docker\\Desktop\\Tier2Output\\chlorine_storage_updated.t2s")

    # 1. Read JSON result
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_json_path, tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8") as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read result JSON: {e}")
        result = {"file_exists": False}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result.get("file_exists", False):
        # Use VLM as a fallback if file wasn't saved to the exact path but work was done
        return fallback_vlm_verification(traj, "Output .t2s file not found at expected path.")

    # 2. Read the T2S File
    tmp_t2s = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    content = ""
    try:
        copy_from_env(target_t2s_path, tmp_t2s.name)
        
        # Tier2 Submit files are often zip archives containing XML
        import zipfile
        try:
            with zipfile.ZipFile(tmp_t2s.name, 'r') as z:
                for name in z.namelist():
                    if name.endswith('.xml') or name.endswith('.t2s'):
                        content += z.read(name).decode('utf-8', errors='ignore')
        except zipfile.BadZipFile:
            # Not a zip, read as plain text/XML
            with open(tmp_t2s.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported .t2s file: {e}"}
    finally:
        if os.path.exists(tmp_t2s.name):
            os.unlink(tmp_t2s.name)

    # Extract the Chlorine block to ensure we only evaluate the target chemical
    chem_blocks = re.findall(r'(?i)<Chemical[\s>].*?</Chemical>', content, re.DOTALL)
    chlorine_block = ""
    for block in chem_blocks:
        if "7782-50-5" in block or "Chlorine" in block:
            chlorine_block = block
            break
            
    # If explicit blocks aren't matched (different XML schema), fallback to full content
    if not chlorine_block:
        if "7782-50-5" in content:
            chlorine_block = content
        else:
            return fallback_vlm_verification(traj, "Chlorine (CAS 7782-50-5) record not found in the output file.")

    score = 0
    fb = []

    # Criterion 1: Old location deleted (20 pts)
    # Check if "East Wing Drum Storage" or generic "Drum" ambient storage exists in the chlorine block
    if not re.search(r'(?i)East\s*Wing|Drum\s*Storage|Ambient\s*pressure.*Ambient\s*temperature', chlorine_block):
        score += 20
        fb.append("PASS: Old drum location deleted (+20)")
    else:
        fb.append("FAIL: Old drum location still present")

    # Criterion 2: New location added (20 pts)
    if re.search(r'(?i)Tank\s*Farm\s*B|AST[- ]?104', chlorine_block):
        score += 20
        fb.append("PASS: New location (Tank Farm B / AST-104) added (+20)")
    else:
        fb.append("FAIL: New location name missing")

    # Criterion 3: Correct container type (15 pts)
    if re.search(r'(?i)Aboveground tank|Above ground tank', chlorine_block):
        score += 15
        fb.append("PASS: Container type is Aboveground tank (+15)")
    else:
        fb.append("FAIL: Container type not set to Aboveground tank")

    # Criterion 4: Correct pressure and temperature (25 pts)
    has_pressure = bool(re.search(r'(?i)Greater than ambient pressure', chlorine_block))
    has_temp = bool(re.search(r'(?i)Less than ambient temperature', chlorine_block))
    
    if has_pressure and has_temp:
        score += 25
        fb.append("PASS: Pressure and Temperature correctly set to non-ambient (+25)")
    elif has_pressure or has_temp:
        score += 10
        fb.append("PARTIAL: Only Pressure OR Temperature was set correctly (+10)")
    else:
        fb.append("FAIL: Non-ambient pressure and temperature settings missing")

    # Criterion 5: Max Daily Amount updated (20 pts)
    if re.search(r'(?i)90[,]?000', chlorine_block):
        score += 20
        fb.append("PASS: Max Daily Amount updated to 90,000 (+20)")
    else:
        fb.append("FAIL: Max Daily Amount not updated to 90,000")

    passed = score >= 70
    
    # If heavily failed but file exists, cross-check with VLM
    if not passed and score > 0:
        vlm_res = fallback_vlm_verification(traj, "File parsed but missing major criteria. Checking VLM for UI progress.")
        if vlm_res["passed"]:
            return vlm_res

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb)
    }

def fallback_vlm_verification(traj, reason):
    """Fallback VLM verification if the file wasn't exported correctly but the agent did the work in the UI."""
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if not frames:
            return {"passed": False, "score": 0, "feedback": f"{reason} (No frames available for VLM fallback)"}

        prompt = """You are evaluating an AI agent performing a task in EPA Tier2 Submit.
Task: Update the Chlorine chemical record by changing its storage to an Aboveground tank (Tank Farm B, AST-104) with Greater than ambient pressure and Less than ambient temperature, and updating max amount to 90,000.

Look at these trajectory frames. Did the agent successfully navigate to the storage locations and make these specific non-ambient pressure/temperature and tank type updates?

Respond in JSON:
{
    "navigated_to_chlorine": true/false,
    "updated_storage_details": true/false,
    "updated_amount": true/false,
    "confidence": "low/medium/high"
}"""
        
        result = query_vlm(prompt=prompt, images=frames)
        if result and result.get("success"):
            parsed = result.get("parsed", {})
            if parsed.get("navigated_to_chlorine") and parsed.get("updated_storage_details"):
                return {
                    "passed": True,
                    "score": 75,
                    "feedback": f"{reason} | VLM Fallback PASS: Agent visually completed the storage updates in the UI."
                }
                
    except Exception as e:
        logger.warning(f"VLM fallback failed: {e}")
        
    return {"passed": False, "score": 0, "feedback": f"{reason} | VLM Fallback failed or criteria not met."}