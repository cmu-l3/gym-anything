#!/usr/bin/env python3
"""
Verifier for OpenICE Accessibility Compliance Check.

Scoring Criteria (100 pts total):
1. Environment Setup (20 pts):
   - OpenICE window count increased (indicating device + app windows) OR log confirms device creation.
2. Artifact Creation (Files exist and created during task) (40 pts):
   - Original screenshot exists (10)
   - Python script exists (10)
   - Grayscale image exists (10)
   - Report file exists (10)
3. Processing Validation (Logic check) (40 pts):
   - Grayscale image is actually grayscale (15)
   - Grayscale image dimensions match original (10)
   - Report contains a valid number (0-255) (15)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_accessibility_compliance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Environment Setup (20 pts)
    window_inc = result.get('window_increase', 0)
    device_log = result.get('device_created_log', False)
    
    if window_inc >= 1 or device_log:
        score += 20
        feedback_parts.append("OpenICE environment configured correctly (Device/App active)")
    else:
        feedback_parts.append("Failed to configure OpenICE (No new windows or device log)")

    # 2. Artifact Creation (Files exist & fresh) (40 pts)
    files = {
        'original': result.get('original_image', {}),
        'script': result.get('script_file', {}),
        'gray': result.get('gray_image', {}),
        'report': result.get('report_file', {})
    }
    
    # Original Screenshot
    if files['original'].get('exists') and files['original'].get('created_during_task'):
        score += 10
        feedback_parts.append("Original screenshot captured")
    
    # Script
    if files['script'].get('exists') and files['script'].get('created_during_task'):
        score += 10
        feedback_parts.append("Python script created")
    
    # Gray Image
    if files['gray'].get('exists') and files['gray'].get('created_during_task'):
        score += 10
        feedback_parts.append("Grayscale output created")
    
    # Report
    if files['report'].get('exists') and files['report'].get('created_during_task'):
        score += 10
        feedback_parts.append("Report file created")

    # 3. Processing Validation (40 pts)
    analysis = result.get('image_analysis', {})
    
    # Verify Grayscale Properties
    if analysis.get('gray_valid'):
        is_gray = analysis.get('is_grayscale', False)
        orig_dims = analysis.get('original_dimensions', [0,0])
        gray_dims = analysis.get('gray_dimensions', [0,0])
        
        if is_gray:
            score += 15
            feedback_parts.append("Output image verified as grayscale")
        else:
            feedback_parts.append("Output image is NOT grayscale")
            
        if orig_dims == gray_dims and orig_dims != [0,0]:
            score += 10
            feedback_parts.append("Image dimensions match")
        else:
            feedback_parts.append("Image dimension mismatch")
    
    # Verify Report Content
    report_content = result.get('report_content', "").strip()
    try:
        val = float(report_content)
        if 0 <= val <= 255:
            score += 15
            feedback_parts.append(f"Report contains valid luminance: {val}")
        else:
            feedback_parts.append(f"Report value out of range (0-255): {val}")
    except ValueError:
        feedback_parts.append(f"Report does not contain a number: '{report_content}'")

    # Check for script cheating (if script missing but output exists, zero the logic points)
    if not files['script'].get('exists'):
        if score > 50:
             score -= 25 # Penalize missing script significantly if output magically appeared
             feedback_parts.append("PENALTY: Script missing but output exists")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }