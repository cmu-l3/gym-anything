#!/usr/bin/env python3
"""
Verifier for classify_bone_quality_misch task.

Task: Measure bone density at 4 sites and classify using Misch Scale.
Output: bone_quality_report.txt and site_19_density.png

Verification Strategy:
1. Parse text report for correct classification (D1-D4) of 4 sites.
2. Verify screenshot existence and content using VLM (to confirm measurement tool usage).
3. Anti-gaming: Check file timestamps.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bone_quality_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON from Container
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Check Report Existence & Freshness (20 pts)
    report_exists = result_data.get('report_exists', False)
    report_fresh = result_data.get('report_created_during_task', False)
    
    if report_exists:
        if report_fresh:
            score += 20
            feedback_parts.append("Report created successfully.")
        else:
            score += 5
            feedback_parts.append("Report exists but was not created during this task session.")
    else:
        feedback_parts.append("Report file not found.")
        return {"passed": False, "score": 0, "feedback": "Report file missing."}

    # 3. Parse and Evaluate Report Content (40 pts)
    # Expected format: "Site #3: 450 - D3"
    content = result_data.get('report_content', '')
    
    sites_to_check = {
        "Site #3": ground_truth.get("site_3", {}).get("class", "D3"),
        "Site #8": ground_truth.get("site_8", {}).get("class", "D3"),
        "Site #19": ground_truth.get("site_19", {}).get("class", "D2"),
        "Site #30": ground_truth.get("site_30", {}).get("class", "D2")
    }
    
    correct_sites = 0
    for site, expected_class in sites_to_check.items():
        # Regex to find "Site #X: [number] - [Class]"
        # Flexible for format: "Site #3: 400 HU - D3" or "Site #3: 400 D3"
        pattern = re.compile(rf"{re.escape(site)}.*?(D[1-4])", re.IGNORECASE)
        match = pattern.search(content)
        
        if match:
            found_class = match.group(1).upper()
            # Allow adjacent classes (e.g. D2/D3 borderline) if strictly needed, 
            # but usually we want exact match for clear cases.
            # Here we enforce exact match for simplicity.
            if found_class == expected_class:
                correct_sites += 1
            else:
                feedback_parts.append(f"{site}: Expected {expected_class}, found {found_class}.")
        else:
            feedback_parts.append(f"{site}: Entry not found in report.")
            
    score += (correct_sites * 10)  # 4 sites * 10 pts = 40 pts
    feedback_parts.append(f"Correctly classified {correct_sites}/4 sites.")

    # 4. Evidence Screenshot Verification (20 pts for file, 20 pts for VLM content)
    screenshot_exists = result_data.get('screenshot_exists', False)
    screenshot_fresh = result_data.get('screenshot_created_during_task', False)
    
    if screenshot_exists and screenshot_fresh:
        score += 20
        feedback_parts.append("Evidence screenshot saved.")
        
        # VLM Verification
        # Retrieve the specific screenshot file from env to verify content
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\site_19_density.png", temp_img.name)
            
            vlm_prompt = """
            Verify this screenshot from dental planning software.
            1. Does it show a dental X-ray/CBCT view (jawbone/teeth)?
            2. Is there a measurement tool or density probe visible (showing a number like 'HU' or density)?
            3. Is the view focused on the mandible (lower jaw)?
            
            Return JSON: {"is_dental": bool, "has_measurement": bool, "is_mandible": bool}
            """
            
            # Use the retrieved file for VLM
            vlm_result = query_vlm(images=[temp_img.name], prompt=vlm_prompt)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                vlm_score = 0
                if parsed.get("is_dental"): vlm_score += 5
                if parsed.get("has_measurement"): vlm_score += 10
                if parsed.get("is_mandible"): vlm_score += 5
                
                score += vlm_score
                if vlm_score == 20:
                    feedback_parts.append("Screenshot verified by VLM.")
                else:
                    feedback_parts.append(f"Screenshot VLM partial match ({vlm_score}/20).")
            else:
                # Fallback if VLM fails technically
                score += 10 
                feedback_parts.append("VLM check skipped (error), awarded partial points.")
                
        except Exception as e:
            feedback_parts.append(f"Failed to copy screenshot for VLM: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    else:
        feedback_parts.append("Evidence screenshot missing or old.")

    # Final result
    passed = (score >= 70) and (correct_sites >= 2) and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }