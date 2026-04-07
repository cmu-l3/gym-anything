#!/usr/bin/env python3
"""
Verifier for Determine Limiting Magnitude of VLT M12 Observation task.

Multi-Criteria Verification:
1. Results file exists and was created during the task (Anti-gaming)
2. Contains sufficient measurements (>= 8 stars)
3. Physical consistency check (Spearman correlation between V_mag and S/N must be negative)
4. Limiting magnitude determined accurately against real-data ground truth
5. VLM verification of the process using trajectory frames
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_verify_trajectory(query_vlm, traj):
    """Uses VLM to verify that aperture photometry occurred in AstroImageJ."""
    if not query_vlm:
        return {"passed": False, "confidence": "none"}
        
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return {"passed": False, "confidence": "none"}

    prompt = """You are verifying an agent's completion of an astronomical measurement task in AstroImageJ.
    
Look at these chronological screenshots and determine:
1. Is a FITS image loaded showing a grayscale star field?
2. Did the agent use aperture photometry tools? Look for circular apertures placed over stars.
3. Is there a measurement/results window visible showing tabular numeric data?
4. Is there meaningful progression across the frames (not just the same empty screen)?

Respond strictly in JSON format:
{
    "fits_loaded": true/false,
    "apertures_visible": true/false,
    "results_table_visible": true/false,
    "meaningful_progression": true/false,
    "confidence": "low/medium/high"
}
"""
    try:
        res = query_vlm(images=frames, prompt=prompt)
        if res and res.get("success"):
            return res.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM Trajectory query failed: {e}")
        
    return {"passed": False, "confidence": "none"}

def verify_limiting_magnitude(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # -------------------------------------------------------------------------
    # 1. Load exported results & ground truth
    # -------------------------------------------------------------------------
    result = {}
    gt = {}
    
    try:
        # Load Result
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_res.name)
        
        # Load Ground Truth
        tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/limiting_mag_ground_truth.json", tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt = json.load(f)
        os.unlink(tmp_gt.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load environment state files: {e}"}

    # -------------------------------------------------------------------------
    # 2. File Check & Anti-gaming (15 pts)
    # -------------------------------------------------------------------------
    file_exists = result.get("file_exists", False)
    created_during_task = result.get("created_during_task", False)
    content = result.get("file_content", "")
    
    if file_exists and created_during_task:
        score += 15
        feedback.append("Results file created successfully.")
    elif file_exists:
        feedback.append("Results file exists but was not modified during the task (possible gaming).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    else:
        feedback.append("Results file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # -------------------------------------------------------------------------
    # 3. Parse Data & Check Measurement Counts (25 pts)
    # -------------------------------------------------------------------------
    # Format: Star_ID  V_mag  Source_Counts  Sky_Background  SNR
    measurements = []
    lines = content.strip().split('\n')
    for line in lines:
        line = line.strip()
        # Look for data rows starting with 'S' and containing floats
        if re.match(r'^S\d+\s+', line):
            parts = line.split()
            if len(parts) >= 5:
                try:
                    v_mag = float(parts[1])
                    snr = float(parts[4])
                    measurements.append((v_mag, snr))
                except ValueError:
                    continue
                    
    num_measured = len(measurements)
    if num_measured >= 8:
        score += 25
        feedback.append(f"Measured {num_measured} stars (met minimum of 8).")
    elif num_measured > 0:
        score += int(25 * (num_measured / 8))
        feedback.append(f"Measured {num_measured} stars (less than requested 8).")
    else:
        feedback.append("Failed to parse valid star measurements from text file.")

    # -------------------------------------------------------------------------
    # 4. Physical Consistency Check (Spearman Rank Correlation) (15 pts)
    # Fainter stars (higher V_mag) MUST have lower SNR.
    # -------------------------------------------------------------------------
    physics_passed = False
    if num_measured >= 4:
        v_mags = [m[0] for m in measurements]
        snrs = [m[1] for m in measurements]
        
        # Calculate rank correlation (manual to avoid strict scipy dependencies)
        def rank(arr):
            seq = sorted(arr)
            return [seq.index(v) for v in arr]
            
        rank_v = rank(v_mags)
        rank_snr = rank(snrs)
        
        n = len(v_mags)
        d_sq = sum((rank_v[i] - rank_snr[i])**2 for i in range(n))
        spearman_corr = 1 - (6 * d_sq) / (n * (n**2 - 1))
        
        # Strong negative correlation expected
        if spearman_corr <= -0.4:
            physics_passed = True
            score += 15
            feedback.append(f"S/N trend physically consistent (corr: {spearman_corr:.2f}).")
        else:
            feedback.append(f"S/N trend violates physics (corr: {spearman_corr:.2f}). Values may be fabricated.")
    else:
        feedback.append("Not enough points to check physical consistency.")

    # -------------------------------------------------------------------------
    # 5. Extract Limiting Magnitude & Compare with Ground Truth (25 pts)
    # -------------------------------------------------------------------------
    lim_mag_match = re.search(r'LIMITING_MAGNITUDE[:\s]+([0-9.]+)', content)
    if lim_mag_match:
        reported_lim = float(lim_mag_match.group(1))
        gt_lim = gt.get("limiting_magnitude", 20.0)
        
        error = abs(reported_lim - gt_lim)
        if error <= 1.0:
            score += 25
            feedback.append(f"Limiting magnitude highly accurate: {reported_lim} (GT: {gt_lim:.2f}).")
        elif error <= 2.5:
            score += 15
            feedback.append(f"Limiting magnitude within acceptable range: {reported_lim} (GT: {gt_lim:.2f}).")
        else:
            score += 5
            feedback.append(f"Limiting magnitude inaccurate: {reported_lim} (GT: {gt_lim:.2f}).")
    else:
        feedback.append("Keyword LIMITING_MAGNITUDE not found in output file.")

    # -------------------------------------------------------------------------
    # 6. VLM Trajectory Process Verification (20 pts)
    # -------------------------------------------------------------------------
    vlm_result = _vlm_verify_trajectory(query_vlm, traj)
    
    fits_loaded = vlm_result.get("fits_loaded", False)
    apertures = vlm_result.get("apertures_visible", False)
    results_vis = vlm_result.get("results_table_visible", False)
    
    vlm_score = 0
    if fits_loaded: vlm_score += 5
    if apertures: vlm_score += 10
    if results_vis: vlm_score += 5
    
    score += vlm_score
    if vlm_score >= 15:
        feedback.append("VLM verified photometry workflow from trajectory.")
    else:
        feedback.append("VLM found partial/missing visual evidence of workflow.")

    # -------------------------------------------------------------------------
    # Final Decision
    # -------------------------------------------------------------------------
    passed = (score >= 60) and physics_passed and (lim_mag_match is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "num_measured": num_measured,
            "physics_passed": physics_passed,
            "vlm_verification_score": vlm_score
        }
    }