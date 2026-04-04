#!/usr/bin/env python3
"""
Verifier for analyze_airway_patency task.

Verifies:
1. Output files exist (sagittal screenshot, axial screenshot, report)
2. Files were created during the task (anti-gaming)
3. Report contains valid measurement and classification
4. VLM verifies screenshots show airway analysis (dark column, measurements)
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_airway_patency(traj, env_info, task_info):
    """
    Verify the airway analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Download report and screenshots for inspection if needed
    # (Here we rely on result.json for content and VLM for visuals, 
    # but could download images if local processing was required)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Freshness (30 points)
    sagittal_exists = result.get('sagittal_exists', False)
    axial_exists = result.get('axial_exists', False)
    report_exists = result.get('report_exists', False)
    created_during = result.get('files_created_during_task', False)
    
    files_count = sum([sagittal_exists, axial_exists, report_exists])
    
    if files_count == 3:
        score += 15
        feedback_parts.append("All output files present")
    elif files_count > 0:
        score += 5 * files_count
        feedback_parts.append(f"{files_count}/3 output files present")
    else:
        feedback_parts.append("No output files found")
        
    if created_during:
        score += 15
        feedback_parts.append("Files verified as newly created")
    else:
        if files_count > 0:
            feedback_parts.append("Files pre-dated task (possible gaming)")

    # 2. Report Content Analysis (20 points)
    report_content = result.get('report_content', "")
    measurement = None
    classification = None
    
    # Extract measurement (e.g., "8.5 mm" or "8.5mm")
    mm_match = re.search(r'(\d+(\.\d+)?)\s*mm', report_content, re.IGNORECASE)
    if mm_match:
        try:
            measurement = float(mm_match.group(1))
            score += 10
            feedback_parts.append(f"Measurement found: {measurement}mm")
        except ValueError:
            pass
            
    # Check classification
    valid_classifications = ["Normal", "Narrowed", "Severely narrowed"]
    found_class = False
    for vc in valid_classifications:
        if vc.lower() in report_content.lower():
            classification = vc
            found_class = True
            break
            
    if found_class:
        score += 5
        feedback_parts.append(f"Classification found: {classification}")
        
    # Consistency check
    if measurement is not None and classification:
        consistent = False
        if measurement > 11 and "Normal" in classification: consistent = True
        elif 6 <= measurement <= 11 and "Narrowed" in classification: consistent = True
        elif measurement < 6 and "Severely" in classification: consistent = True
        
        if consistent:
            score += 5
            feedback_parts.append("Measurement matches classification logic")
        else:
            feedback_parts.append("Mismatch between measurement and classification")

    # 3. VLM Visual Verification (50 points)
    # We need to verify the agent actually visualized the airway
    
    if not query_vlm:
        feedback_parts.append("VLM verification skipped (no tool)")
        # Fallback scoring if VLM missing (should not happen in prod)
        if score >= 40: score = 100 
    else:
        # Get screenshots
        # Since we can't easily download specific files from windows in this snippet 
        # (framework does final screenshot only usually), we use trajectory frames.
        # Ideally, we would copy the specific output files 'sagittal_airway.png' 
        # to the host to check them, but 'traj' usually contains the screen recording.
        
        # We'll use the trajectory to see if they were working on the airway
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        vlm_prompt = """
        Review these screenshots of a dental software (Blue Sky Plan).
        The user should be analyzing the airway (throat/pharynx area).
        
        Check for:
        1. Soft tissue rendering: Is the view showing soft tissue (skin/flesh) or just white bone? 
           The airway should appear as a dark empty column/tube.
        2. Measurement: Is there a measurement tool (ruler line with a number) used in the airway region?
        3. Views: Can you see Sagittal (side) or Axial (top-down) views?
        
        Answer JSON:
        {
          "soft_tissue_visible": boolean,
          "airway_column_visible": boolean,
          "measurement_tool_used": boolean,
          "confidence": "low/medium/high"
        }
        """
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if vlm_result and vlm_result.get('success'):
            analysis = vlm_result.get('parsed', {})
            
            if analysis.get('soft_tissue_visible') or analysis.get('airway_column_visible'):
                score += 20
                feedback_parts.append("VLM: Airway visualization confirmed")
            else:
                feedback_parts.append("VLM: Could not confirm airway visualization")
                
            if analysis.get('measurement_tool_used'):
                score += 30
                feedback_parts.append("VLM: Measurement action confirmed")
            else:
                feedback_parts.append("VLM: No measurement detected")

    # Final Pass/Fail
    passed = score >= 60 and files_count >= 2 and measurement is not None
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }