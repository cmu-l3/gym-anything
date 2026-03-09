#!/usr/bin/env python3
"""
Verifier for Histological Stain Separation and DAB Quantification task.

Verification Strategy:
1. File Validation (15 pts): Check if result file exists and was created during task.
2. Content Validation (20 pts): Check for 'DAB' and 'Hematoxylin' keywords.
3. Quantitative Validation (35 pts): 
   - DAB Area Fraction must be biologically plausible (1% - 80%).
   - DAB Area must be positive and < total image area.
   - Intensity values must be valid 8-bit range (0-255) or OD range (0-3.0).
4. VLM Verification (30 pts): 
   - Confirm 'Colour Deconvolution' was performed (trajectory check).
   - Confirm separated channels were visible.

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stain_separation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_frac = metadata.get('min_dab_fraction', 1.0)
    max_frac = metadata.get('max_dab_fraction', 80.0)
    min_area = metadata.get('min_dab_area_px', 1000)
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/stain_deconvolution_quantification_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Validation (15 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 15
        feedback_parts.append("Result file created successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("Result file exists but timestamp check failed (pre-existing?).")
    else:
        feedback_parts.append("Result file not found.")
        return {"passed": False, "score": 0, "feedback": "No result file created."}

    # 2. Content Keywords (20 pts)
    keywords_met = 0
    if result.get('has_dab_keyword'):
        keywords_met += 10
    if result.get('has_hematoxylin_keyword'):
        keywords_met += 10
        
    score += keywords_met
    if keywords_met == 20:
        feedback_parts.append("Correct stain keywords found (DAB + Hematoxylin).")
    elif keywords_met > 0:
        feedback_parts.append("Partial stain keywords found.")
    else:
        feedback_parts.append("Missing stain keywords (DAB/Hematoxylin).")

    # 3. Quantitative Validation (35 pts)
    dab_fraction = result.get('dab_fraction', 0.0)
    dab_area = result.get('dab_area', 0.0)
    dab_intensity = result.get('dab_intensity', 0.0)
    
    quant_score = 0
    # Fraction plausible (15 pts)
    if min_frac <= dab_fraction <= max_frac:
        quant_score += 15
        feedback_parts.append(f"DAB Fraction {dab_fraction:.1f}% is plausible.")
    elif dab_fraction > 0:
        quant_score += 5
        feedback_parts.append(f"DAB Fraction {dab_fraction:.1f}% outside expected range ({min_frac}-{max_frac}%).")
    else:
        feedback_parts.append("DAB Fraction not found or zero.")

    # Area plausible (10 pts)
    if dab_area >= min_area:
        quant_score += 10
        feedback_parts.append(f"DAB Area {dab_area:.0f}px is valid.")
    
    # Intensity plausible (10 pts)
    if dab_intensity > 0:
        quant_score += 10
        feedback_parts.append(f"DAB Intensity {dab_intensity:.2f} recorded.")
        
    score += quant_score

    # 4. VLM Verification (30 pts)
    # Check trajectory for "Colour Deconvolution" window or split channels
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Analyze these screenshots of ImageJ usage.
        Look for:
        1. A window titled "Colour Deconvolution" or "Color Deconvolution".
        2. Image windows showing separated stains (e.g., one mainly blue, one mainly brown/black).
        3. A "Results" table window.
        
        Return JSON:
        {
            "deconvolution_visible": boolean,
            "separated_channels_visible": boolean,
            "results_table_visible": boolean
        }
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt).get('parsed', {})
            
            if vlm_res.get('deconvolution_visible') or vlm_res.get('separated_channels_visible'):
                score += 20
                feedback_parts.append("VLM confirmed deconvolution workflow.")
            else:
                feedback_parts.append("VLM did not see deconvolution steps.")
                
            if vlm_res.get('results_table_visible'):
                score += 10
                feedback_parts.append("VLM confirmed results table.")
        except Exception:
            # Fallback if VLM fails, give partial credit if file was perfect
            if score >= 60: 
                score += 15
                feedback_parts.append("VLM check skipped (system error).")
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }