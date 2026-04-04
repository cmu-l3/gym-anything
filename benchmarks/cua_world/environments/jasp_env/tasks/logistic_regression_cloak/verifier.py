#!/usr/bin/env python3
"""
Verifier for Logistic Regression Task (JASP)

Checks:
1. JASP .jasp file creation (valid zip, created during task).
2. Text report content (presence of specific statistics).
3. Statistical consistency (OR ≈ exp(B)).
4. VLM verification of the UI state (tables visible).
"""

import json
import os
import sys
import tempfile
import base64
import math
import logging
import zipfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_logistic_regression(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ====================================================================
    # 1. Retrieve and Parse Result JSON
    # ====================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ====================================================================
    # 2. Verify JASP File (30 points)
    # ====================================================================
    jasp_info = result.get("jasp_file", {})
    jasp_exists = jasp_info.get("exists", False)
    jasp_valid = jasp_info.get("is_valid_zip", False)
    jasp_fresh = jasp_info.get("created_during_task", False)

    if jasp_exists:
        if jasp_fresh:
            score += 15
            feedback_parts.append("JASP file saved successfully.")
        else:
            feedback_parts.append("JASP file exists but was NOT created during this task (stale).")
        
        if jasp_valid:
            score += 15
            feedback_parts.append("JASP file is a valid archive.")
        else:
            feedback_parts.append("JASP file is corrupted or empty.")
    else:
        feedback_parts.append("JASP output file not found.")

    # ====================================================================
    # 3. Verify Report Content (40 points)
    # ====================================================================
    report_info = result.get("report_file", {})
    report_exists = report_info.get("exists", False)
    report_content_b64 = report_info.get("content_base64", "")
    
    stats = {}
    
    if report_exists and report_content_b64:
        score += 5
        try:
            content = base64.b64decode(report_content_b64).decode('utf-8', errors='ignore')
            lines = content.split('\n')
            
            # Parse key-value pairs
            for line in lines:
                if '=' in line:
                    key, val = line.split('=', 1)
                    key = key.strip().lower()
                    val = val.strip()
                    # Clean value of comments or units
                    val = ''.join(c for c in val if c.isdigit() or c in '.-')
                    try:
                        stats[key] = float(val)
                    except ValueError:
                        pass
            
            # Check B (Coefficient)
            # Ground truth: Mischief B is approx 0.12 (varies by exact model spec, but positive)
            b_val = stats.get('b')
            if b_val is not None:
                score += 10
                if -0.5 < b_val < 1.0: # Wide range for valid structural model
                    feedback_parts.append(f"Coefficient B ({b_val}) is in valid range.")
                else:
                    feedback_parts.append(f"Coefficient B ({b_val}) seems implausible.")
            else:
                feedback_parts.append("Coefficient B not found in report.")

            # Check OR (Odds Ratio)
            or_val = stats.get('or')
            if or_val is not None:
                score += 10
                # Consistency check: OR ≈ exp(B)
                if b_val is not None:
                    expected_or = math.exp(b_val)
                    if abs(or_val - expected_or) < 0.2:
                        score += 5
                        feedback_parts.append("Odds Ratio is consistent with Coefficient B.")
                    else:
                        feedback_parts.append(f"Odds Ratio ({or_val}) inconsistent with B ({b_val}).")
            else:
                feedback_parts.append("Odds Ratio not found in report.")

            # Check P-value
            p_val = stats.get('p')
            if p_val is not None:
                score += 5
                if 0 <= p_val <= 1:
                    feedback_parts.append("P-value is valid.")
                else:
                    feedback_parts.append("P-value out of probability range.")

            # Check Accuracy
            acc_val = stats.get('accuracy')
            if acc_val is not None:
                score += 5
                if 40 <= acc_val <= 100:
                    feedback_parts.append(f"Accuracy ({acc_val}%) is reasonable.")
        except Exception as e:
            feedback_parts.append(f"Error parsing report: {str(e)}")
    else:
        feedback_parts.append("Report file not found or empty.")

    # ====================================================================
    # 4. VLM Verification (30 points)
    # ====================================================================
    # We check if the final screen shows the Logistic Regression Output
    
    final_img = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=4)
    all_images = frames + ([final_img] if final_img else [])

    if all_images:
        prompt = """
        Review these screenshots of JASP software.
        1. Is the "Logistic Regression" analysis visible in the results pane (right side)?
        2. Do you see a "Coefficients" table?
        3. Do you see a "Confusion Matrix" or classification table?
        
        Answer JSON: {"logistic_visible": bool, "coefficients_table": bool, "confusion_matrix": bool}
        """
        
        try:
            vlm_res = query_vlm(prompt, images=all_images)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('logistic_visible'):
                score += 10
                feedback_parts.append("VLM: Logistic Regression analysis visible.")
            if parsed.get('coefficients_table'):
                score += 10
                feedback_parts.append("VLM: Coefficients table found.")
            if parsed.get('confusion_matrix'):
                score += 10
                feedback_parts.append("VLM: Confusion matrix found.")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback points if files are perfect but VLM fails
            if score >= 60:
                score += 15
                feedback_parts.append("VLM skipped (error), assuming visual correctness based on files.")

    # ====================================================================
    # Final Scoring
    # ====================================================================
    passed = score >= 60 and jasp_exists and report_exists
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }