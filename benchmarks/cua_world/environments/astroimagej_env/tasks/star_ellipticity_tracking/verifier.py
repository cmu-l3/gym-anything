#!/usr/bin/env python3
"""
Verifier for the Star Ellipticity Tracking task.

Verification checks:
1. Report file exists and was created during the task.
2. Report contains valid star measurements (>= 5 stars).
3. Reported positions are within image bounds.
4. FWHM values are physically reasonable.
5. Computed average ellipticity is within tolerance of ground truth.
6. Tracking quality label matches ground truth.
7. VLM verification of the process (trajectory).
8. VLM verification of final content.
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Prompts ---
PROCESS_PROMPT = """You are verifying an agent performing star shape analysis in AstroImageJ.
These images show chronological samples of the workflow.

Look for:
1. An astronomical FITS image (star field) being opened/viewed.
2. The agent taking measurements (using point/click tools, drawing circles/ellipses/lines on stars, or opening the "Results" table).
3. The agent creating/editing a text report file.

Respond in JSON format:
{
    "image_loaded": true/false,
    "measurements_taken": true/false,
    "report_created": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

FINAL_CONTENT_PROMPT = """You are verifying the final state of an AstroImageJ tracking assessment task.
Look at this screenshot and determine:

1. Is there evidence of astronomical analysis (AstroImageJ open, image visible, or results tables)?
2. Is there a text editor open showing the "Tracking Quality Assessment" report?

Respond in JSON format:
{
    "astronomy_app_visible": true/false,
    "report_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

def verify_star_ellipticity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_stars = metadata.get('minimum_stars', 5)
    ellipticity_tol = metadata.get('ellipticity_tolerance', 0.08)

    score = 0
    feedback_parts = []
    
    # 1. Fetch Result and Ground Truth JSONs
    result = {}
    gt = {}
    
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
            
        copy_from_env("/tmp/tracking_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.error(f"Error reading JSON files: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_res.name): os.unlink(temp_res.name)
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    # Extract GT info
    gt_avg_e = gt.get('avg_ellipticity', 0.05)
    gt_quality = gt.get('tracking_quality', 'GOOD')
    img_width = gt.get('image_width', 4000)
    img_height = gt.get('image_height', 4000)

    # 2. Programmatic Checks
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not found"}
        
    if not report_created:
        feedback_parts.append("Warning: Report file existed before task start (might be gaming)")
    else:
        score += 10
        feedback_parts.append("Report file created successfully")

    raw_content = result.get('report_content_raw', '').replace('|', '\n')
    
    # Parse stars
    star_lines = []
    # Match lines that look like data: ID X Y Maj Min E PA
    # E.g., "1 450 600 3.2 3.0 0.06 45.1"
    for line in raw_content.split('\n'):
        # Matches a row starting with an integer, followed by at least 6 floats/ints
        if re.match(r'^\s*\d+\s+[\d\.]+\s+[\d\.]+\s+[\d\.]+\s+[\d\.]+\s+[\d\.]+\s+[\d\.]+', line):
            star_lines.append(line)
            
    num_stars = len(star_lines)
    
    if num_stars >= min_stars:
        score += 15
        feedback_parts.append(f"Measured {num_stars} stars (>= {min_stars})")
    elif num_stars > 0:
        score += int(15 * (num_stars / min_stars))
        feedback_parts.append(f"Measured only {num_stars} stars")
    else:
        feedback_parts.append("No valid star measurements found in report")

    # Validate physical properties
    valid_positions = 0
    valid_fwhm = 0
    for line in star_lines:
        parts = line.split()
        if len(parts) >= 7:
            try:
                x, y = float(parts[1]), float(parts[2])
                maj, minor = float(parts[3]), float(parts[4])
                # Bounds check (approximate, allow slight leeway)
                if 0 <= x <= img_width + 100 and 0 <= y <= img_height + 100:
                    valid_positions += 1
                if 0.5 <= maj <= 100 and 0.5 <= minor <= 100:
                    valid_fwhm += 1
            except:
                pass

    if num_stars > 0:
        if valid_positions == num_stars:
            score += 10
            feedback_parts.append("Star coordinates are within image bounds")
        if valid_fwhm == num_stars:
            score += 10
            feedback_parts.append("FWHM values are physically reasonable")

    # Parse Summary
    reported_e = None
    reported_quality = None
    
    e_match = re.search(r'Average_Ellipticity:\s*([\d\.]+)', raw_content, re.IGNORECASE)
    if e_match:
        try:
            reported_e = float(e_match.group(1))
        except: pass
        
    q_match = re.search(r'Tracking_Quality:\s*(GOOD|FAIR|POOR)', raw_content, re.IGNORECASE)
    if q_match:
        reported_quality = q_match.group(1).upper()

    # Score Ellipticity vs GT
    if reported_e is not None:
        if abs(reported_e - gt_avg_e) <= ellipticity_tol:
            score += 20
            feedback_parts.append(f"Ellipticity accurate ({reported_e:.3f} vs GT {gt_avg_e:.3f})")
        elif abs(reported_e - gt_avg_e) <= ellipticity_tol * 2:
            score += 10
            feedback_parts.append(f"Ellipticity approximate ({reported_e:.3f} vs GT {gt_avg_e:.3f})")
        else:
            feedback_parts.append(f"Ellipticity inaccurate ({reported_e:.3f} vs GT {gt_avg_e:.3f})")
    else:
        feedback_parts.append("Average_Ellipticity not found in report")

    # Score Quality
    if reported_quality == gt_quality:
        score += 15
        feedback_parts.append(f"Tracking Quality correct ({gt_quality})")
    elif reported_quality is not None:
        feedback_parts.append(f"Tracking Quality incorrect (Expected {gt_quality}, Got {reported_quality})")
    else:
        feedback_parts.append("Tracking_Quality not found in report")

    # 3. VLM Verification
    if query_vlm:
        # Trajectory check
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            process_res = query_vlm(prompt=PROCESS_PROMPT, images=frames)
            if process_res and process_res.get('success'):
                parsed = process_res.get('parsed', {})
                if parsed.get('image_loaded') and parsed.get('measurements_taken'):
                    score += 10
                    feedback_parts.append("VLM confirmed measurement workflow")

        # Final state check
        final_img = get_final_screenshot(traj)
        if final_img:
            final_res = query_vlm(prompt=FINAL_CONTENT_PROMPT, image=final_img)
            if final_res and final_res.get('success'):
                parsed = final_res.get('parsed', {})
                if parsed.get('astronomy_app_visible') or parsed.get('report_visible'):
                    score += 10
                    feedback_parts.append("VLM confirmed final visual state")

    # Evaluate pass/fail
    # Requires finding stars, getting ellipticity right or quality right, and VLM evidence or high overall score
    key_criteria_met = (num_stars >= 3) and (reported_e is not None)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }