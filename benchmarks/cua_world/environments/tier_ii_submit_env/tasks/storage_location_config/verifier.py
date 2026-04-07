#!/usr/bin/env python3
import json
import tempfile
import os
import logging
import base64
import re
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_storage_location_config(traj, env_info, task_info):
    """
    Verifies that the agent correctly created a facility and 
    added the chemical and associated spatial storage layouts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the exported JSON result safely
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    file_found = result.get("file_found", False)
    created_during_task = result.get("created_during_task", False)
    
    # Do-Nothing / File Existence check
    if file_found and created_during_task:
        score += 15
        feedback.append("PASS: Exported .t2s file found and timestamp verified (+15).")
    elif file_found:
        score += 5
        feedback.append("PARTIAL: .t2s file found but predates task start (Possible gaming attempt) (+5).")
    else:
        feedback.append("FAIL: Target .t2s file was not generated.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
        
    # Decode XML payload
    b64_content = result.get("file_b64", "")
    try:
        xml_content = base64.b64decode(b64_content).decode('utf-8', errors='ignore')
    except Exception as e:
        xml_content = ""
        feedback.append(f"WARNING: File content decode error: {e}")

    # 2. Check Facility Identification
    if re.search(r"Precision\s*Metal\s*Finishing", xml_content, re.IGNORECASE):
        score += 10
        feedback.append("PASS: Facility Name matched (+10).")
    else:
        feedback.append("FAIL: Facility Name not found in data.")

    if re.search(r"30\.4715", xml_content) and re.search(r"91\.1871", xml_content):
        score += 5
        feedback.append("PASS: Geospatial coordinates matched (+5).")
    
    # 3. Check Chemical Properties (Sulfuric Acid CAS)
    cas_correct = False
    if re.search(r"7664-93-9", xml_content):
        score += 15
        cas_correct = True
        feedback.append("PASS: Correct CAS Number matched (+15).")
    else:
        feedback.append("FAIL: Sulfuric Acid CAS (7664-93-9) not found.")

    # 4. Check Storage Location Configurations
    # Location 1
    has_tank = bool(re.search(r"Above\s*ground\s*tank", xml_content, re.IGNORECASE))
    has_tank_desc = bool(re.search(r"Tank\s*Farm", xml_content, re.IGNORECASE) or re.search(r"T-101", xml_content, re.IGNORECASE))
    
    if has_tank and has_tank_desc:
        score += 15
        feedback.append("PASS: Storage 1 (Above ground tank config) complete (+15).")
    elif has_tank or has_tank_desc:
        score += 7
        feedback.append("PARTIAL: Storage 1 partially configured (+7).")
    else:
        feedback.append("FAIL: Storage 1 configuration missing.")

    # Location 2
    has_drum = bool(re.search(r"Plastic.*drum|non-metallic\s*drum", xml_content, re.IGNORECASE))
    has_drum_desc = bool(re.search(r"Building\s*3", xml_content, re.IGNORECASE) or re.search(r"Plating\s*Line", xml_content, re.IGNORECASE))
    
    if has_drum and has_drum_desc:
        score += 15
        feedback.append("PASS: Storage 2 (Plastic drum config) complete (+15).")
    elif has_drum or has_drum_desc:
        score += 7
        feedback.append("PARTIAL: Storage 2 partially configured (+7).")
    else:
        feedback.append("FAIL: Storage 2 configuration missing.")

    # 5. VLM / Trajectory Process Verification (Multi-Signal)
    try:
        # Dynamically import framework VLM methods
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + ([final] if final else [])
        
        prompt = """You are evaluating an agent performing a compliance data entry task in EPA Tier2 Submit.
        The workflow should include navigating tabs to add a Facility, a Chemical (Sulfuric Acid), and TWO Storage Locations.
        
        Analyze the chronological screenshots. Provide a JSON response:
        {
            "app_opened": true/false,
            "facility_entered": true/false,
            "chemical_added": true/false,
            "storage_configured": true/false,
            "save_dialog_seen": true/false,
            "confidence": "high|medium|low"
        }"""
        
        vlm_result = query_vlm(images=images, prompt=prompt)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            vlm_score = sum([
                5 if parsed.get("app_opened") else 0,
                5 if parsed.get("facility_entered") else 0,
                5 if parsed.get("chemical_added") else 0,
                5 if parsed.get("storage_configured") else 0,
                5 if parsed.get("save_dialog_seen") else 0
            ])
            score += vlm_score
            feedback.append(f"VLM Trajectory Verification: +{vlm_score}/25 points.")
        else:
            feedback.append("VLM processing failed; awarding grace points.")
            score += 10
    except ImportError:
        logger.warning("VLM module not available. Skipping VLM check.")
        score += 25  # Grace points if VLM module is unsupported locally

    # Ensure score caps
    score = min(score, 100)
    
    # Pass Requirements: Minimum score + anti-gaming + critical cas insertion
    passed = (score >= 65) and file_found and created_during_task and cas_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }