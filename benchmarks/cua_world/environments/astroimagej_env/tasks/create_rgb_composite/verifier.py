#!/usr/bin/env python3
"""
Verifier for Create Hubble Palette Color Composite Task.

Verification Strategy (Hybrid: Programmatic + VLM):
1. Output exists & created during task (15 pts) - Anti-gaming
2. Format is correct (PNG) & Color RGB (15 pts)
3. Channel Mappings via Pearson Correlation (30 pts)
   - Red strongly correlates with [SII]
   - Green strongly correlates with H-alpha
   - Blue strongly correlates with [OIII]
4. VLM Verification on Trajectory (40 pts)
   - Checks if 'Merge Channels' workflow was used
   - Checks if final image looks like a well-adjusted nebula composite
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent that created a Hubble Palette color composite of the Eagle Nebula in AstroImageJ.
The Hubble Palette maps Sulfur (SII) to Red, Hydrogen (Ha) to Green, and Oxygen (OIII) to Blue.

Review these trajectory screenshots and the final state:
1. WORKFLOW_COMPLETED: Did the agent load the three separate FITS files and use the 'Merge Channels' (or 'Color Merge') tool to combine them?
2. AESTHETICS_ADJUSTED: Does the final screenshot show a colored nebula (the Pillars of Creation) that looks aesthetically adjusted? It should not be completely pitch black or overwhelmingly washed out/white.

Respond ONLY in valid JSON format:
{
    "workflow_completed": true/false,
    "aesthetics_adjusted": true/false,
    "observations": "brief reasoning"
}
"""

def verify_create_rgb_composite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Read JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result read error: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Checks
    output_exists = result.get("output_exists", False)
    
    if output_exists:
        score += 10
        feedback.append("Output file exists.")
        
        if result.get("created_during_task"):
            score += 5
            feedback.append("File created during the task.")
        else:
            feedback.append("Warning: File not created during task (potential spoof).")
            
        if result.get("format") == "PNG":
            score += 5
            feedback.append("File is a valid PNG.")
            
        if result.get("is_color"):
            score += 10
            feedback.append("Image is an RGB color composite.")
        else:
            feedback.append("Image appears to be Grayscale.")

        # Channel Correlation Verification
        corrs = result.get("correlations", {})
        
        # Red Channel ([SII] mapping)
        r_sii = corrs.get("R", {}).get("SII", 0)
        r_ha = corrs.get("R", {}).get("Ha", 0)
        if r_sii > r_ha and r_sii > 0.2:
            score += 10
            feedback.append(f"Red channel mapped to [SII] correctly (corr: {r_sii:.2f}).")
        else:
            feedback.append(f"Red channel mapping incorrect or weak (SII corr: {r_sii:.2f}).")

        # Green Channel (H-alpha mapping)
        g_ha = corrs.get("G", {}).get("Ha", 0)
        g_oiii = corrs.get("G", {}).get("OIII", 0)
        if g_ha > g_oiii and g_ha > 0.2:
            score += 10
            feedback.append(f"Green channel mapped to H-alpha correctly (corr: {g_ha:.2f}).")
        else:
            feedback.append(f"Green channel mapping incorrect or weak (H-alpha corr: {g_ha:.2f}).")

        # Blue Channel ([OIII] mapping)
        b_oiii = corrs.get("B", {}).get("OIII", 0)
        b_ha = corrs.get("B", {}).get("Ha", 0)
        if b_oiii > b_ha and b_oiii > 0.2:
            score += 10
            feedback.append(f"Blue channel mapped to [OIII] correctly (corr: {b_oiii:.2f}).")
        else:
            feedback.append(f"Blue channel mapping incorrect or weak ([OIII] corr: {b_oiii:.2f}).")
            
    else:
        feedback.append("Output PNG file not found.")

    # 3. VLM Trajectory Verification
    vlm_success = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        if frames and final_frame:
            images = frames + [final_frame]
            try:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    
                    if parsed.get("workflow_completed"):
                        score += 20
                        feedback.append("VLM confirmed Channel Merge workflow was used.")
                        vlm_success = True
                    else:
                        feedback.append("VLM did not detect correct Channel Merge workflow.")
                        
                    if parsed.get("aesthetics_adjusted"):
                        score += 20
                        feedback.append("VLM confirmed final image is aesthetically adjusted.")
                    else:
                        feedback.append("VLM found final image to be poorly adjusted (washed out or too dark).")
                        
            except Exception as e:
                logger.warning(f"VLM verification error: {e}")
                feedback.append("VLM trajectory verification failed.")

    passed = score >= 70 and output_exists and vlm_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }