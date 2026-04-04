#!/usr/bin/env python3
"""
Verifier for Chemical Cloud Behavior Prediction task.

Verification Logic:
1. File Existence & Anti-Gaming: Checks if report exists and was created during task.
2. Content Analysis: Parses the text file to find:
   - Presence of all 5 required chemicals.
   - Correct Vapor Density values (within tolerance).
   - Correct Boiling Points (within tolerance).
   - Correct Cloud Behavior classification (derived from Vapor Density).
   - Correct Rain Scrubbing classification (derived from Solubility).
3. VLM Verification: Checks trajectory frames to confirm CAMEO Chemicals website usage.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utilities
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth data
CHEMICALS_DB = {
    "chlorine": {
        "aliases": ["chlorine", "cl2", "7782-50-5"],
        "vd_target": 2.5,
        "vd_tol": 0.5,
        "bp_c": -34,
        "bp_tol": 8,
        "behavior_type": "ground",
        "scrubbable": True
    },
    "ammonia": {
        "aliases": ["ammonia", "nh3", "7664-41-7", "anhydrous ammonia"],
        "vd_target": 0.6,
        "vd_tol": 0.2,
        "bp_c": -33,
        "bp_tol": 8,
        "behavior_type": "elevated",
        "scrubbable": True
    },
    "phosgene": {
        "aliases": ["phosgene", "cocl2", "75-44-5", "carbonyl chloride"],
        "vd_target": 3.4,
        "vd_tol": 0.5,
        "bp_c": 8,
        "bp_tol": 8,
        "behavior_type": "ground",
        "scrubbable": None  # Ambiguous (reacts but technically scrubbable/soluble initially) - accept either
    },
    "methyl isocyanate": {
        "aliases": ["methyl isocyanate", "mic", "624-83-9"],
        "vd_target": 2.0,
        "vd_tol": 0.4,
        "bp_c": 39,
        "bp_tol": 8,
        "behavior_type": "ground",
        "scrubbable": False  # Reacts violently
    },
    "sulfur dioxide": {
        "aliases": ["sulfur dioxide", "so2", "7446-09-5"],
        "vd_target": 2.3,
        "vd_tol": 0.5,
        "bp_c": -10,
        "bp_tol": 8,
        "behavior_type": "ground",
        "scrubbable": True
    }
}

def extract_numbers_near_keyword(text: str, keywords: List[str], window: int = 200) -> List[float]:
    """Find numbers near specific keywords in text."""
    text_lower = text.lower()
    found_numbers = []
    
    for kw in keywords:
        start_idx = 0
        while True:
            idx = text_lower.find(kw, start_idx)
            if idx == -1:
                break
                
            # Define window around keyword
            start = max(0, idx - window)
            end = min(len(text), idx + window)
            snippet = text[start:end]
            
            # Extract numbers (handles negatives and decimals)
            matches = re.findall(r'-?\d+\.?\d*', snippet)
            for m in matches:
                try:
                    val = float(m)
                    # Filter out likely CAS numbers or years (rough heuristic)
                    if -100 < val < 500: 
                        found_numbers.append(val)
                except ValueError:
                    pass
            
            start_idx = idx + 1
            
    return found_numbers

def check_classification_text(text: str, expected_type: str) -> bool:
    """Check if text contains correct classification keywords."""
    text = text.lower()
    if expected_type == "ground":
        keywords = ["ground", "heavier", "heavy", "low", "sink", "settle", "accumulate"]
        return any(k in text for k in keywords) and "elevated" not in text and "rise" not in text
    elif expected_type == "elevated":
        keywords = ["elevated", "lighter", "rise", "float", "dispers", "upward"]
        return any(k in text for k in keywords)
    return False

def verify_cloud_behavior(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (Anti-Gaming)
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found at ~/Desktop/cloud_behavior_assessment.txt"}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during the task session."}

    # 3. Load Output File Content
    output_path = task_result.get("output_path", "")
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_path, temp_txt.name)
        with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read output file: {str(e)}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    if len(content.strip()) < 100:
        return {"passed": False, "score": 5, "feedback": "File content is too short to be a valid report."}

    # 4. Content Verification Logic
    score = 10  # Base score for creating file
    feedback = ["File created (+10)"]
    
    chemicals_passed = 0
    content_lower = content.lower()

    for chem, data in CHEMICALS_DB.items():
        chem_score = 0
        # Check if chemical section exists (heuristic: assume chemical name is present)
        aliases = data["aliases"]
        if not any(a in content_lower for a in aliases):
            feedback.append(f"Missing chemical: {chem}")
            continue

        # Isolate approximate section (simple split or window, here we search whole text if specific enough, 
        # but to avoid cross-contamination, we ideally find the name and look nearby. 
        # For simplicity in this robust verifier, we search near the name instance.)
        
        # Find index of chemical name
        idx = -1
        for a in aliases:
            idx = content_lower.find(a)
            if idx != -1: 
                break
        
        # Look at ~500 chars after mention
        section = content_lower[idx:idx+800] if idx != -1 else ""
        
        # Check Vapor Density
        vd_nums = extract_numbers_near_keyword(section, ["vapor density", "vd", "relative density"])
        vd_correct = any(abs(n - data["vd_target"]) <= data["vd_tol"] for n in vd_nums)
        if vd_correct:
            chem_score += 4
        
        # Check Boiling Point
        bp_nums = extract_numbers_near_keyword(section, ["boiling", "bp", "temperature"])
        # Convert C to F for check: F = C*1.8 + 32
        expected_f = (data["bp_c"] * 1.8) + 32
        bp_correct = False
        for n in bp_nums:
            if abs(n - data["bp_c"]) <= data["bp_tol"] or abs(n - expected_f) <= (data["bp_tol"] * 2):
                bp_correct = True
                break
        if bp_correct:
            chem_score += 4
            
        # Check Behavior Classification
        if check_classification_text(section, data["behavior_type"]):
            chem_score += 5
        
        # Check Rain Scrubbing
        scrub_keywords = ["rain", "scrub", "soluble", "dissolve"]
        not_scrub_keywords = ["not rain", "not scrub", "insoluble", "react", "violent"]
        
        is_scrubbable_text = any(k in section for k in scrub_keywords)
        is_not_scrubbable_text = any(k in section for k in not_scrub_keywords)
        
        if data["scrubbable"] is True:
            if is_scrubbable_text and not ("not" in section and "soluble" in section): 
                chem_score += 3
        elif data["scrubbable"] is False:
            if is_not_scrubbable_text:
                chem_score += 3
        else: # None/Ambiguous
            chem_score += 3 # Free points if mentioned
            
        if chem_score >= 8:
            chemicals_passed += 1
            
        score += chem_score
        
    feedback.append(f"Correctly assessed {chemicals_passed}/5 chemicals")

    # 5. VLM Verification (Trajectory Analysis)
    # Check if agent actually used CAMEO Chemicals
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the user appear to be using the CAMEO Chemicals website? "
            "Look for: Blue NOAA header, 'CAMEO Chemicals' text, search bars, or chemical datasheets (e.g., Chlorine, Ammonia). "
            "Answer 'yes' or 'no' and explain."
        )
        try:
            vlm_res = query_vlm(vlm_prompt, images=frames)
            if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
                score += 10
                feedback.append("VLM confirmed CAMEO usage (+10)")
            else:
                feedback.append("VLM could not confirm CAMEO usage")
        except Exception:
            pass # VLM failure shouldn't fail task if file output is perfect

    # Final scoring
    # Max possible ~10 (base) + 5*16 (80) + 10 (VLM) = 100
    passed = (score >= 60) and (chemicals_passed >= 3)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }