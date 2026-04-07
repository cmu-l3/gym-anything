#!/usr/bin/env python3
"""
Verifier for Audit VA Drug Classifications Task.

Verification Logic:
1. Checks if the output file was created and contains lines.
2. Decodes the file and parses for "Code" and "Description".
3. Validates that at least one code starts with "CN" or "CV".
4. Cross-references found codes against the Ground Truth extracted from VistA.
5. Uses VLM to verify that the agent actually navigated the Global Viewer.
"""

import json
import base64
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_va_drug_classifications(traj, env_info, task_info):
    """
    Verify the agent correctly audited the VA Drug Class file.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Copy result JSON
    local_result_path = "task_result_temp.json"
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    score = 0
    feedback = []
    
    # 2. Check System State (10 pts)
    if result.get("vista_running", False):
        score += 10
        feedback.append("VistA container is active.")
    else:
        feedback.append("VistA container was not running.")

    # 3. Check File Existence and Creation (10 pts)
    output_exists = result.get("output_exists", False)
    created_during = result.get("file_created_during_task", False)
    
    if output_exists and created_during:
        score += 10
        feedback.append("Report file created during task.")
    elif output_exists:
        score += 5
        feedback.append("Report file exists but timestamp check failed.")
    else:
        feedback.append("Report file not found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 4. Parse File Content (20 pts for count)
    content_b64 = result.get("output_content_b64", "")
    try:
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except:
        content = ""

    lines = [l.strip() for l in content.split('\n') if l.strip()]
    entry_count = len(lines)
    
    if entry_count >= 5:
        score += 20
        feedback.append(f"Found {entry_count} entries (met minimum of 5).")
    elif entry_count > 0:
        score += 10
        feedback.append(f"Found {entry_count} entries (minimum 5 required).")
    else:
        feedback.append("File is empty.")

    # 5. Content Validation (Target Category & Validity) (30 pts)
    # Parse codes from lines. Expecting "Code: X - Description: Y" or similar
    # Regex to find code-like patterns (2 uppercase letters + 3 digits, e.g., CN101)
    # Or just generic code at start of line
    
    found_codes = []
    target_found = False
    
    # Simple regex for VA Drug Codes (e.g., AA000, CN101)
    code_pattern = re.compile(r'\b([A-Z]{2}\d{3})\b')
    
    for line in lines:
        match = code_pattern.search(line)
        if match:
            code = match.group(1)
            found_codes.append(code)
            if code.startswith("CN") or code.startswith("CV"):
                target_found = True

    if target_found:
        score += 20
        feedback.append("Target category (CN/CV) found in report.")
    else:
        feedback.append("No CN (Central Nervous) or CV (Cardio) codes found in report.")

    # Cross-reference with Ground Truth
    gt_raw = result.get("ground_truth_data", "")
    # GT format is "CODE^DESC|CODE^DESC|..."
    valid_codes_in_gt = 0
    if gt_raw:
        for code in found_codes:
            if code in gt_raw:
                valid_codes_in_gt += 1
    
    if valid_codes_in_gt >= min(3, len(found_codes)) and len(found_codes) > 0:
        score += 10
        feedback.append("Reported codes validated against database.")
    elif len(found_codes) > 0:
        feedback.append(f"Warning: Only {valid_codes_in_gt} codes matched validation data.")

    # 6. VLM Visual Verification (30 pts)
    # Check if they actually used the Global Viewer
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    vlm_passed = False
    
    if query_vlm and final_screenshot:
        prompt = """
        Analyze this screenshot of the VistA/YottaDB web interface.
        1. Is the Global Viewer visible (showing global browsing)?
        2. Is the global '^PS(50.605)' or 'VA DRUG CLASS' visible?
        3. Are there drug classification codes (like CN101, CV000) listed?
        
        Respond with JSON: {"global_viewer_visible": bool, "drug_class_global_visible": bool, "codes_visible": bool}
        """
        try:
            vlm_res = query_vlm(prompt, final_screenshot)
            # Simple keyword check if parsing fails, or use dictionary if structured
            if isinstance(vlm_res, dict):
                parsed = vlm_res
            else:
                # Basic string fallback
                lower_res = str(vlm_res).lower()
                parsed = {
                    "global_viewer_visible": "global" in lower_res,
                    "drug_class_global_visible": "ps" in lower_res or "drug" in lower_res,
                    "codes_visible": "code" in lower_res
                }

            if parsed.get("drug_class_global_visible") or parsed.get("codes_visible"):
                score += 30
                vlm_passed = True
                feedback.append("Visual verification passed: Global data visible.")
            elif parsed.get("global_viewer_visible"):
                score += 15
                feedback.append("Visual verification partial: Global viewer open but specific data unclear.")
            else:
                feedback.append("Visual verification failed: Relevant UI not detected.")
                
        except Exception as e:
            feedback.append(f"VLM check error: {e}")

    # Final Score Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }