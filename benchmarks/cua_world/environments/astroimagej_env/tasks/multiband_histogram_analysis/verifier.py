#!/usr/bin/env python3
"""
Verifier for the Multiband Histogram Analysis task.

Scoring System (100 points total):
- 10 points: Output file exists and is correctly formatted.
- 15 points: VLM verification that the AstroImageJ Histogram window was utilized.
- 25 points: [OIII] filter (Mean within 1%: 12.5 pts, Mode within 5%: 12.5 pts).
- 25 points: H-alpha filter (Mean within 1%: 12.5 pts, Mode within 5%: 12.5 pts).
- 25 points: [SII] filter (Mean within 1%: 12.5 pts, Mode within 5%: 12.5 pts).

Pass threshold: 70 points (requires programmatic accuracy on the extraction).
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_HISTOGRAM_PROMPT = """You are verifying an astronomical image processing task performed in AstroImageJ (ImageJ).
Review these chronologically sampled screenshots from the user's session.

Look carefully for the 'Histogram' window.
The Histogram window in AstroImageJ displays a bar graph of pixel intensities and a table of statistics at the bottom including: 'Count', 'Mean', 'StdDev', 'Min', 'Max', 'Mode'.

Did the user successfully open and view the 'Histogram' window at any point during this session?

Respond in JSON format:
{
    "histogram_window_used": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Briefly state where you saw (or did not see) the Histogram window."
}
"""

def verify_histogram_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    mean_tol_pct = metadata.get('mean_tolerance_pct', 1.0) / 100.0
    mode_tol_pct = metadata.get('mode_tolerance_pct', 5.0) / 100.0

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Retrieve the exported task result
    # ---------------------------------------------------------
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ---------------------------------------------------------
    # 2. Retrieve the dynamically generated ground truth
    # ---------------------------------------------------------
    gt = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/histogram_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
            
    if 'stats' not in gt:
        return {"passed": False, "score": 0, "feedback": "Ground truth missing stats"}

    # ---------------------------------------------------------
    # 3. Assess File Structure and Content (10 pts)
    # ---------------------------------------------------------
    output_exists = task_result.get('output_exists', False)
    file_created = task_result.get('file_created_during_task', False)
    content = task_result.get('output_content', '')

    if not output_exists:
        feedback_parts.append("❌ Output file ionization_stats.txt not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    elif not file_created:
        feedback_parts.append("❌ Output file exists but was not created during this task session.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    else:
        score += 10
        feedback_parts.append("✅ Output file exists and was created correctly.")

    # ---------------------------------------------------------
    # 4. Parse content using Regex and evaluate (75 pts max)
    # ---------------------------------------------------------
    # Expected format: [OIII] 502nm - Mean: <value>, Mode: <value>
    # We use a forgiving regex to extract values
    def extract_stats(filter_name, text):
        # Match e.g., "[OIII]" or "OIII" or "502nm", then grab Mean and Mode
        pattern = re.compile(rf'{filter_name}.*?Mean:\s*([0-9.-]+).*?Mode:\s*([0-9.-]+)', re.IGNORECASE)
        match = pattern.search(text)
        if match:
            try:
                return float(match.group(1)), float(match.group(2))
            except ValueError:
                return None, None
        return None, None

    # OIII Check (25 pts)
    oiii_mean, oiii_mode = extract_stats('OIII', content)
    gt_oiii = gt['stats']['OIII']
    if oiii_mean is not None:
        if abs(oiii_mean - gt_oiii['mean']) <= (abs(gt_oiii['mean']) * mean_tol_pct):
            score += 12.5
            feedback_parts.append("✅ [OIII] Mean is accurate.")
        else:
            feedback_parts.append(f"❌ [OIII] Mean incorrect (Got: {oiii_mean}, Expected: {gt_oiii['mean']:.4f}).")
        
        if abs(oiii_mode - gt_oiii['mode']) <= (abs(gt_oiii['mode']) * mode_tol_pct):
            score += 12.5
            feedback_parts.append("✅ [OIII] Mode is accurate.")
        else:
            feedback_parts.append(f"❌ [OIII] Mode incorrect (Got: {oiii_mode}, Expected: {gt_oiii['mode']:.4f}).")
    else:
        feedback_parts.append("❌ [OIII] stats could not be parsed.")

    # Ha Check (25 pts)
    ha_mean, ha_mode = extract_stats('H-alpha|656nm', content)
    gt_ha = gt['stats']['Ha']
    if ha_mean is not None:
        if abs(ha_mean - gt_ha['mean']) <= (abs(gt_ha['mean']) * mean_tol_pct):
            score += 12.5
            feedback_parts.append("✅ H-alpha Mean is accurate.")
        else:
            feedback_parts.append(f"❌ H-alpha Mean incorrect.")
        
        if abs(ha_mode - gt_ha['mode']) <= (abs(gt_ha['mode']) * mode_tol_pct):
            score += 12.5
            feedback_parts.append("✅ H-alpha Mode is accurate.")
        else:
            feedback_parts.append(f"❌ H-alpha Mode incorrect.")
    else:
        feedback_parts.append("❌ H-alpha stats could not be parsed.")

    # SII Check (25 pts)
    sii_mean, sii_mode = extract_stats('SII|673nm', content)
    gt_sii = gt['stats']['SII']
    if sii_mean is not None:
        if abs(sii_mean - gt_sii['mean']) <= (abs(gt_sii['mean']) * mean_tol_pct):
            score += 12.5
            feedback_parts.append("✅ [SII] Mean is accurate.")
        else:
            feedback_parts.append(f"❌ [SII] Mean incorrect.")
        
        if abs(sii_mode - gt_sii['mode']) <= (abs(gt_sii['mode']) * mode_tol_pct):
            score += 12.5
            feedback_parts.append("✅ [SII] Mode is accurate.")
        else:
            feedback_parts.append(f"❌ [SII] Mode incorrect.")
    else:
        feedback_parts.append("❌ [SII] stats could not be parsed.")

    # ---------------------------------------------------------
    # 5. VLM Trajectory Verification (15 pts)
    # ---------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=6)
        try:
            vlm_result = query_vlm(prompt=VLM_HISTOGRAM_PROMPT, images=frames)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                used_histogram = parsed.get("histogram_window_used", False)
                if used_histogram:
                    score += 15
                    feedback_parts.append("✅ VLM verified Histogram window usage.")
                else:
                    feedback_parts.append("❌ VLM did NOT detect Histogram window usage in trajectory.")
            else:
                feedback_parts.append("⚠️ VLM verification failed (skipped).")
        except Exception as e:
            logger.warning(f"VLM exception: {e}")
            feedback_parts.append("⚠️ VLM check exception.")
    else:
        feedback_parts.append("⚠️ VLM capability unavailable (skipped).")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }