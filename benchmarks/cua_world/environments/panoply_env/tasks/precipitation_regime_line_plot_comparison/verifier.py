#!/usr/bin/env python3
"""
Verifier for precipitation_regime_line_plot_comparison task.

Scoring criteria (100 pts total, pass threshold = 75):
  1. Amazon Line Plot (20 pts): amazon_annual_precip.png exists, created during task, >= 8KB.
  2. Med Line Plot (20 pts): mediterranean_annual_precip.png exists, created during task, >= 8KB.
  3. Report Structure (20 pts): All requested fields are present in the text file.
  4. Scientific Correctness (20 pts): Amazon classified as tropical/equatorial/wet; 
     Med classified as mediterranean/winter-wet; Med dry season identified as summer.
  5. VLM Trajectory Verification (20 pts): Verifies that Panoply line plots (X-Y graphs)
     were actually utilized during the workflow, differentiating from standard map plots.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent's workflow in the NASA Panoply scientific data viewer.
The task required the agent to create a "line plot along one axis" (an X-Y line graph) instead of the default geographical map.

Look at these trajectory frames and the final screenshot. 
1. Is there evidence that the agent successfully created and viewed a 1D LINE PLOT (an X-Y graph with time on the X axis and precipitation on the Y axis)?
2. The plot should NOT just be a map of the world or region. It must be a line graph.

Reply in JSON format:
{
    "line_plot_created": true/false,
    "reasoning": "Brief explanation of what you see in the frames regarding line plots"
}
"""

def verify_precipitation_regime_line_plot_comparison(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        copy_from_env('/tmp/precipitation_regime_line_plot_comparison_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1: Amazon Line Plot (20 pts)
    # ----------------------------------------------------------------
    amazon_exists = result.get('amazon_plot_exists', False)
    amazon_mtime = int(result.get('amazon_plot_mtime', 0))
    amazon_size = int(result.get('amazon_plot_size', 0))
    amazon_format = result.get('amazon_plot_format', '')

    if amazon_exists and amazon_mtime >= task_start and amazon_size >= 8000 and amazon_format == 'PNG':
        score += 20
        feedback.append(f"Amazon plot exported successfully ({amazon_size} bytes)")
    elif amazon_exists and amazon_mtime >= task_start:
        score += 10
        feedback.append(f"Amazon plot exported but small or invalid format (Size: {amazon_size}, Format: {amazon_format})")
    else:
        feedback.append("Amazon plot missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 2: Mediterranean Line Plot (20 pts)
    # ----------------------------------------------------------------
    med_exists = result.get('med_plot_exists', False)
    med_mtime = int(result.get('med_plot_mtime', 0))
    med_size = int(result.get('med_plot_size', 0))
    med_format = result.get('med_plot_format', '')

    if med_exists and med_mtime >= task_start and med_size >= 8000 and med_format == 'PNG':
        score += 20
        feedback.append(f"Mediterranean plot exported successfully ({med_size} bytes)")
    elif med_exists and med_mtime >= task_start:
        score += 10
        feedback.append(f"Mediterranean plot exported but small or invalid format (Size: {med_size}, Format: {med_format})")
    else:
        feedback.append("Mediterranean plot missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 3: Report Structure (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    amz_regime = result.get('amazon_regime', '').strip().lower()
    med_regime = result.get('med_regime', '').strip().lower()
    med_dry = result.get('med_dry_season', '').strip().lower()
    contrast = result.get('regime_contrast', '').strip()

    has_core_fields = bool(amz_regime) and bool(med_regime) and bool(med_dry) and bool(contrast)

    if report_exists and report_mtime >= task_start and has_core_fields:
        score += 20
        feedback.append("Report successfully created with required fields")
    elif report_exists and report_mtime >= task_start:
        score += 10
        feedback.append("Report created but missing some required fields")
    else:
        feedback.append("Report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 4: Scientific Correctness (20 pts)
    # ----------------------------------------------------------------
    correct_amz = any(kw in amz_regime for kw in ['tropical', 'equatorial', 'wet', 'rainforest', 'monsoon'])
    correct_med = any(kw in med_regime for kw in ['mediterranean', 'winter', 'dry summer', 'csb', 'csa'])
    correct_dry = any(kw in med_dry for kw in ['summer', 'jja', 'jun', 'jul', 'aug'])

    science_score = 0
    if correct_amz: science_score += 6
    if correct_med: science_score += 7
    if correct_dry: science_score += 7
    
    if science_score > 0:
        score += science_score
        feedback.append(f"Scientific correctness check: {science_score}/20 pts (Amz:{correct_amz}, Med:{correct_med}, Dry:{correct_dry})")
    else:
        feedback.append("Scientific correctness check failed (incorrect regime classifications)")

    # ----------------------------------------------------------------
    # Criterion 5: VLM Trajectory Verification (20 pts)
    # ----------------------------------------------------------------
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("line_plot_created", False):
                    score += 20
                    feedback.append("VLM confirmed line plots were utilized")
                else:
                    feedback.append(f"VLM did not detect line plots. Reason: {parsed.get('reasoning', 'none')}")
            else:
                feedback.append("No images available for VLM verification")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback.append("VLM verification skipped due to error")
    else:
        feedback.append("VLM verification skipped (not available)")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "amazon_plot_exists": amazon_exists,
            "med_plot_exists": med_exists,
            "report_fields_found": has_core_fields,
            "scientific_score": science_score
        }
    }