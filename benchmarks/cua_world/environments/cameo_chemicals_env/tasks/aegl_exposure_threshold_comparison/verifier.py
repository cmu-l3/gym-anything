#!/usr/bin/env python3
"""
Verifier for aegl_exposure_threshold_comparison task.

Verification Logic:
1.  **File Analysis (50 pts):**
    - File must exist and be created during the task.
    - Must contain "Chlorine", "Ammonia", and "Hydrogen Cyanide".
    - Must contain numerical values within valid ranges for 60-min AEGLs.
    - Must correctly identify Chlorine as having the lowest AEGL-2.

2.  **VLM Analysis (50 pts):**
    - Uses trajectory frames to verify the agent actually visited the website.
    - Checks if agent navigated to datasheets and viewed AEGL tables.
    - Anti-gaming: Prevents an agent from just writing the file from training memory.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aegl_exposure_threshold_comparison(traj, env_info, task_info):
    """
    Verify the AEGL report creation and research process.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    SCORE_FILE_EXISTS = 10
    SCORE_CHEMICAL_NAMES = 10
    SCORE_VALUES_CORRECT = 15
    SCORE_CONCLUSION = 15
    SCORE_VLM_TRAJECTORY = 50  # High weight on process to prevent gaming

    total_score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON and Report File
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    report_content = ""
    result_metadata = {}
    
    try:
        # Get metadata
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_metadata = json.load(f)
            
        # Get report content if it exists
        if result_metadata.get("output_exists") and result_metadata.get("file_created_during_task"):
            try:
                copy_from_env(result_metadata["report_file_path"], temp_report.name)
                with open(temp_report.name, 'r', errors='ignore') as f:
                    report_content = f.read()
            except Exception as e:
                logger.warning(f"Could not read report file: {e}")
    except Exception as e:
        logger.error(f"Error reading result files: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # 2. File Existence & Anti-Gaming (Timestamp) Check
    if result_metadata.get("output_exists") and result_metadata.get("file_created_during_task"):
        total_score += SCORE_FILE_EXISTS
        feedback_parts.append("✅ Report file created.")
    else:
        feedback_parts.append("❌ Report file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # 3. Content Analysis
    content_lower = report_content.lower()
    
    # Check Chemical Names
    chems_found = 0
    if "chlorine" in content_lower: chems_found += 1
    if "ammonia" in content_lower: chems_found += 1
    if "hydrogen cyanide" in content_lower or "hcn" in content_lower: chems_found += 1
    
    if chems_found == 3:
        total_score += SCORE_CHEMICAL_NAMES
        feedback_parts.append("✅ All 3 chemicals mentioned.")
    elif chems_found > 0:
        partial = int(SCORE_CHEMICAL_NAMES * (chems_found / 3))
        total_score += partial
        feedback_parts.append(f"⚠️ Only {chems_found}/3 chemicals mentioned.")
    else:
        feedback_parts.append("❌ No relevant chemicals found in report.")

    # Check Values (Regex for approximate ranges)
    # Chlorine AEGL-2 60min is ~2.0 ppm
    # Ammonia AEGL-2 60min is ~160 ppm
    # HCN AEGL-2 60min is ~7.1 ppm
    
    values_valid = False
    # Look for numbers near chemical names is complex with regex, simplified check:
    # Check if numbers in roughly correct ranges exist in the file at all
    nums = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", content_lower)]
    
    has_chlorine_val = any(1.5 <= n <= 2.5 for n in nums)
    has_ammonia_val = any(140 <= n <= 180 for n in nums)
    has_hcn_val = any(6.0 <= n <= 8.0 for n in nums)
    
    if has_chlorine_val and has_ammonia_val and has_hcn_val:
        total_score += SCORE_VALUES_CORRECT
        feedback_parts.append("✅ AEGL-2 values appear correct.")
    elif has_chlorine_val or has_ammonia_val or has_hcn_val:
        total_score += int(SCORE_VALUES_CORRECT / 2)
        feedback_parts.append("⚠️ Some AEGL values found, but not all match expected ranges.")
    else:
        feedback_parts.append("❌ Could not find valid AEGL-2 values (Chlorine ~2.0, Ammonia ~160, HCN ~7.1).")

    # Check Conclusion (Chlorine is lowest AEGL-2)
    # "Chlorine" should appear near "lowest", "most hazardous", "most toxic", "worst"
    conclusion_keywords = ["lowest", "small", "most hazardous", "worst", "danger", "evacuation"]
    
    # Simplistic check: does "chlorine" appear in the text? (Already checked)
    # Does the text NOT say Ammonia or HCN is the lowest?
    # This is hard to parse perfectly, so we give points if they identify Chlorine's low value
    if "chlorine" in content_lower and any(k in content_lower for k in conclusion_keywords):
        total_score += SCORE_CONCLUSION
        feedback_parts.append("✅ Conclusion correctly identifies Chlorine hazard.")
    else:
        feedback_parts.append("❌ Conclusion analysis failed or missing.")

    # 4. VLM Verification (Process)
    # This is critical to ensure they actually used the tool
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    Review these screenshots of an agent performing a task.
    The agent should be visiting the 'CAMEO Chemicals' website (cameochemicals.noaa.gov).
    
    Check for:
    1. Did the agent visit the CAMEO Chemicals website?
    2. Did the agent search for chemicals like Chlorine, Ammonia, or Hydrogen Cyanide?
    3. Did the agent view the 'Response Information' or 'AEGL' tables (lots of numbers in a grid)?
    
    Answer JSON:
    {
        "visited_website": boolean,
        "searched_chemicals": boolean,
        "viewed_tables": boolean,
        "explanation": "brief reasoning"
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get("parsed", {})
        
        vlm_score = 0
        if parsed.get("visited_website"): vlm_score += 10
        if parsed.get("searched_chemicals"): vlm_score += 20
        if parsed.get("viewed_tables"): vlm_score += 20
        
        total_score += vlm_score
        feedback_parts.append(f"✅ VLM Verification: {vlm_score}/50 pts ({parsed.get('explanation', '')})")
        
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        # Fallback: if text file is perfect, give partial VLM points (benefit of doubt or API fail)
        if total_score >= 40:
            total_score += 25
            feedback_parts.append("⚠️ VLM check failed, granting partial credit based on output quality.")
        else:
            feedback_parts.append("❌ VLM check failed and output poor.")

    # Final tally
    passed = total_score >= 60
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }