#!/usr/bin/env python3
"""
Verifier for SEM FFT Restoration Task.

Scoring Criteria:
1. File Creation (10 pts): Output file exists and was created during task.
2. Noise Reduction (40 pts): SSIM(Restored, GT) > SSIM(Noisy, GT) + margin.
3. Detail Preservation (30 pts): SSIM(Restored, GT) > SSIM(Blur, GT) + margin.
   (Ensures agent didn't just blur the image).
4. Workflow Verification (20 pts): VLM check on trajectory for FFT window.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sem_fft_restoration(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    passed = False

    # 2. Check File Existence (10 pts)
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("Output file created successfully.")
    else:
        feedback.append("Output file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 3. Metric Evaluation
    metrics = result.get("metrics", {})
    if not metrics.get("calculation_success"):
        feedback.append("Failed to calculate image metrics.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    ssim_restored = metrics.get("ssim_restored", 0.0)
    ssim_noisy = metrics.get("ssim_noisy", 0.0)
    ssim_blur = metrics.get("ssim_blur", 0.0)

    feedback.append(f"SSIM Scores - Restored: {ssim_restored:.4f}, Noisy: {ssim_noisy:.4f}, Blur Baseline: {ssim_blur:.4f}")

    # Criterion: Noise Reduction (40 pts)
    # Require 5% improvement over noisy image
    if ssim_restored > (ssim_noisy + 0.05):
        score += 40
        feedback.append("Significant noise reduction achieved (+40 pts).")
    elif ssim_restored > ssim_noisy:
        score += 20
        feedback.append("Minor noise reduction achieved (+20 pts).")
    else:
        feedback.append("No noise reduction detected.")

    # Criterion: Detail Preservation (30 pts)
    # Must be better than a simple Gaussian blur (which kills details)
    if ssim_restored > (ssim_blur + 0.02):
        score += 30
        feedback.append("Structural details preserved better than blur (+30 pts).")
    elif ssim_restored > ssim_blur:
        score += 15
        feedback.append("Marginal detail preservation (+15 pts).")
    else:
        feedback.append("Result appears blurred or lacks detail.")

    # 4. VLM Workflow Verification (20 pts)
    # Check if they actually opened the FFT window
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=8)
        
        prompt = """
        Review these screenshots of a Fiji/ImageJ session.
        Look for a window titled "FFT of..." or a frequency spectrum display (a black square with a white starburst pattern in the center).
        
        Does the user:
        1. Open an FFT window (frequency spectrum)?
        2. Perform any editing on this spectrum (masking/blacking out spots)?
        
        Return JSON:
        {
            "fft_window_visible": boolean,
            "spectrum_editing_visible": boolean,
            "reasoning": "string"
        }
        """
        
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        
        if vlm_resp and vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("fft_window_visible"):
                vlm_score += 10
                feedback.append("FFT window detected (+10 pts).")
            if parsed.get("spectrum_editing_visible"):
                vlm_score += 10
                feedback.append("Spectrum editing detected (+10 pts).")
        
        score += vlm_score
        
    except Exception as e:
        feedback.append(f"VLM verification skipped due to error: {str(e)}")
        # Grant partial credit if metrics are perfect to avoid punishing infra failure
        if score >= 80:
            score += 20
            feedback.append("Auto-granting workflow points due to strong metric performance.")

    # Final Pass Decision
    if score >= 70:
        passed = True
        
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }