#!/usr/bin/env python3
"""
Verifier for the Multi-Location EHS Chemical Storage task.

Employs robust multi-signal verification:
1. Programmatic File Checks: File exists, created during task, size > 0.
2. XML/Text Parsing: Parses the exported .t2s (which is typically a ZIP containing XML, 
   or raw XML depending on version) using loose regexes to find CAS, name, and location keywords.
3. VLM Trajectory Verification: Samples the interaction frames to confirm actual UI 
   checkboxes (EHS, Hazards) and workflow progression were completed.
"""

import json
import os
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM prompts
TRAJECTORY_PROMPT = """You are an expert EHS auditor verifying a Tier II chemical inventory entry from a sequence of screenshots.
The agent is adding 'Sulfuric Acid' (CAS 7664-93-9).

Analyze the screenshots and determine if the following actions were performed.
Return a valid JSON object with boolean values for each key:
{
  "ehs_checked": true/false,
  "reactive_checked": true/false,
  "health_acute_chronic_checked": true/false,
  "quantities_entered": true/false,
  "days_on_site_365": true/false,
  "storage_tank_farm": true/false,
  "storage_production": true/false,
  "storage_maintenance": true/false,
  "workflow_progression": true/false
}
"""

FINAL_PROMPT = """You are analyzing the final state of the EPA Tier2 Submit application.
Return a valid JSON object with boolean values:
{
  "chemical_in_list": true/false
}
"""

def get_trajectory_frames(traj, num_frames=8):
    """Extract PIL Image frames evenly sampled from trajectory."""
    frames = []
    for step in traj:
        obs = step.get("observation", {})
        if isinstance(obs, dict):
            for k, v in obs.items():
                if hasattr(v, "mode") and hasattr(v, "size"):  # Looks like PIL Image
                    frames.append(v)
                    break
    if not frames:
        return []
    if len(frames) <= num_frames:
        return frames
    indices = [int(i * (len(frames) - 1) / (num_frames - 1)) for i in range(num_frames)]
    return [frames[i] for i in indices]


def verify_multi_location_chemical_storage(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\multi_location_chemical_storage_result.json")
    output_file = metadata.get("output_file", "C:\\Users\\Docker\\Desktop\\Tier2Output\\multi_location_storage.t2s")
    pass_threshold = metadata.get("pass_threshold", 65)

    score = 0
    feedback_parts = []

    # 1. Check metadata JSON
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp_json.name)
        with open(tmp_json.name, "r") as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve metadata: {e}"}
    finally:
        os.unlink(tmp_json.name)

    if not result_meta.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Submission .t2s file not found. Task not completed."
        }
        
    if not result_meta.get("created_during_task", False):
        feedback_parts.append("WARNING: Output file timestamp indicates it may not have been created during this task.")

    # 2. Extract and parse the .t2s XML file
    tmp_t2s = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    xml_content = ""
    try:
        copy_from_env(output_file, tmp_t2s.name)
        # .t2s files are typically ZIP archives containing XML, try to unzip first
        try:
            with zipfile.ZipFile(tmp_t2s.name, 'r') as z:
                for filename in z.namelist():
                    if filename.endswith('.xml') or 'tier2' in filename.lower() or 'submission' in filename.lower():
                        xml_content += z.read(filename).decode('utf-8', errors='ignore') + "\n"
        except zipfile.BadZipFile:
            # Fallback: Read directly if it's plaintext XML
            with open(tmp_t2s.name, 'r', encoding='utf-8', errors='ignore') as f:
                xml_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Could not read .t2s file: {e}")
    finally:
        os.unlink(tmp_t2s.name)

    xml_lower = xml_content.lower()
    
    # XML heuristics
    xml_cas_found = '7664-93-9' in xml_lower
    xml_name_found = 'sulfuric' in xml_lower
    xml_tank_found = 'tank farm' in xml_lower or 'north yard' in xml_lower
    xml_prod_found = 'production' in xml_lower or 'building 3' in xml_lower
    xml_maint_found = 'maintenance' in xml_lower or 'building 7' in xml_lower

    if xml_cas_found:
        score += 10
        feedback_parts.append("CAS 7664-93-9 found in export (+10)")
    else:
        feedback_parts.append("CAS 7664-93-9 NOT found in export")

    if xml_name_found:
        score += 5
        feedback_parts.append("Sulfuric Acid name found in export (+5)")

    # 3. VLM Verification
    vlm_traj_res = {}
    vlm_final_res = {}
    
    if query_vlm:
        frames = get_trajectory_frames(traj, num_frames=8)
        if frames:
            try:
                traj_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
                if traj_res.get("success"):
                    vlm_traj_res = traj_res.get("parsed", {})
            except Exception as e:
                logger.warning(f"VLM trajectory query failed: {e}")
                
            final_frame = frames[-1] if frames else None
            if final_frame:
                try:
                    final_res = query_vlm(prompt=FINAL_PROMPT, image=final_frame)
                    if final_res.get("success"):
                        vlm_final_res = final_res.get("parsed", {})
                except Exception as e:
                    logger.warning(f"VLM final query failed: {e}")

    # Process VLM trajectory checks
    if vlm_traj_res.get("ehs_checked", False):
        score += 10
        feedback_parts.append("EHS checked (+10)")
        
    if vlm_traj_res.get("reactive_checked", False):
        score += 10
        feedback_parts.append("Reactive hazard checked (+10)")
        
    if vlm_traj_res.get("health_acute_chronic_checked", False):
        score += 10
        feedback_parts.append("Health hazards checked (+10)")
        
    if vlm_traj_res.get("quantities_entered", False):
        score += 10
        feedback_parts.append("Quantities entered (+10)")
        
    if vlm_traj_res.get("days_on_site_365", False):
        score += 5
        feedback_parts.append("Days on site 365 entered (+5)")

    # Storage Locations (Hybrid checking: allow XML OR VLM verification to count)
    loc_count = 0
    if vlm_traj_res.get("storage_tank_farm", False) or xml_tank_found:
        score += 8
        loc_count += 1
        feedback_parts.append("Tank Farm location present (+8)")
        
    if vlm_traj_res.get("storage_production", False) or xml_prod_found:
        score += 8
        loc_count += 1
        feedback_parts.append("Production Floor location present (+8)")
        
    if vlm_traj_res.get("storage_maintenance", False) or xml_maint_found:
        score += 8
        loc_count += 1
        feedback_parts.append("Maintenance Shop location present (+8)")

    if loc_count == 3:
        score += 6
        feedback_parts.append("All 3 distinct locations present (+6)")

    # Workflow Checks
    if vlm_traj_res.get("workflow_progression", False):
        score += 5
        feedback_parts.append("Workflow progression verified (+5)")
        
    if vlm_final_res.get("chemical_in_list", False):
        score += 5
        feedback_parts.append("Final state chemical list verified (+5)")

    # Gate: Chemical must exist in file to pass
    passed = (score >= pass_threshold) and xml_cas_found

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }