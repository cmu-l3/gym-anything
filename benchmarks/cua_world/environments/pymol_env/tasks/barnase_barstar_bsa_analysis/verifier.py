#!/usr/bin/env python3
"""
Verifier for the Barnase-Barstar Buried Surface Area (BSA) Analysis task.

Scoring (100 points total):
  15 pts - Publication figure exists at correct path, is new (post-task-start), and >40KB.
  10 pts - BSA text report exists and is new.
  30 pts - Report contains a BSA value in the physically plausible range (1400-1800 Å² for total BSA, 
           or 700-900 Å² for half BSA) indicating correct separate-object SASA calculation.
  25 pts - Report identifies ≥8 known interacting residues from Chain A (Barnase).
  20 pts - VLM verification: Trajectory frames confirm visual criteria (white surface, red footprint, blue cartoon).

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a structural biology visualization trajectory in PyMOL.
The user's goal was to render the Barnase-Barstar protein complex showing a binding footprint.

Examine these trajectory frames (the last one is the final result). Determine if the final image satisfies these visual requirements:
1. "white_surface": Is there a protein structure represented as a solid WHITE surface?
2. "red_footprint": Is there a distinct RED colored patch/footprint located on that white surface?
3. "blue_cartoon": Is there a second protein structure represented as a BLUE cartoon/ribbon bound to the surface?
4. "progression_shown": Do the preceding frames show progression towards this state (e.g., loading, changing representations, coloring)?

Respond with ONLY a JSON object exactly matching this schema:
{
    "white_surface": true/false,
    "red_footprint": true/false,
    "blue_cartoon": true/false,
    "progression_shown": true/false,
    "confidence": "high/medium/low"
}
"""

def verify_barnase_bsa_analysis(traj, env_info, task_info):
    """Verify the BSA and footprint analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/barnase_bsa_result.json')

    # Read the exported results
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    # --- 1. Figure Check (15 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 40000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 15
        feedback_parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 5
        feedback_parts.append(f"Figure exists but timestamp check failed")
    else:
        feedback_parts.append("Figure missing or too small")

    # --- 2. Report Check (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_is_new = result.get('report_is_new', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and report_is_new and len(report_content) > 10:
        score += 10
        feedback_parts.append("Report created")
    else:
        feedback_parts.append("Report missing or invalid")

    # --- 3. BSA Calculation Check (30 pts) ---
    bsa_total_min = metadata.get('bsa_total_min', 1400.0)
    bsa_total_max = metadata.get('bsa_total_max', 1800.0)
    bsa_half_min = metadata.get('bsa_half_min', 700.0)
    bsa_half_max = metadata.get('bsa_half_max', 900.0)

    all_decimals = [float(n) for n in re.findall(r'\b\d{3,4}(?:\.\d+)?\b', report_content)]
    
    valid_total = [d for d in all_decimals if bsa_total_min <= d <= bsa_total_max]
    valid_half = [d for d in all_decimals if bsa_half_min <= d <= bsa_half_max]

    if valid_total:
        score += 30
        feedback_parts.append(f"Correct Total BSA found: {valid_total[0]} \u00c5\u00b2")
    elif valid_half:
        score += 30
        feedback_parts.append(f"Correct Half-BSA found: {valid_half[0]} \u00c5\u00b2")
    elif all_decimals:
        feedback_parts.append(f"BSA values found {all_decimals[:3]} are out of acceptable bounds (indicates incorrect SASA object management)")
    else:
        feedback_parts.append("No valid BSA calculation found")

    # --- 4. Footprint Residue Mapping (25 pts) ---
    known_residues = set(metadata.get('known_interface_residues', [27, 58, 59, 60, 65, 71, 73, 76, 83, 87, 88, 90, 102, 103]))
    min_residues = metadata.get('min_footprint_residues', 8)
    
    # Extract all numbers from the report that could be residue IDs
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content))
    matched_residues = all_numbers.intersection(known_residues)

    if len(matched_residues) >= min_residues:
        score += 25
        feedback_parts.append(f"Footprint successfully mapped ({len(matched_residues)} correct interface residues identified)")
    elif len(matched_residues) > 0:
        score += int((len(matched_residues) / min_residues) * 25)
        feedback_parts.append(f"Partial footprint mapped ({len(matched_residues)}/{min_residues} correct residues)")
    else:
        feedback_parts.append("Failed to correctly map Chain A interface residues")

    # --- 5. VLM Verification (20 pts) ---
    vlm_score = 0
    if VLM_AVAILABLE and query_vlm and fig_exists:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            if final_img:
                frames.append(final_img)
            
            vlm_response = query_vlm(prompt=VLM_PROMPT, images=frames)
            
            if vlm_response and vlm_response.get("success"):
                vlm_data = vlm_response.get("parsed", {})
                
                if vlm_data.get("white_surface"): vlm_score += 5
                if vlm_data.get("red_footprint"): vlm_score += 5
                if vlm_data.get("blue_cartoon"): vlm_score += 5
                if vlm_data.get("progression_shown"): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM Visual Check: {vlm_score}/20 pts")
            else:
                feedback_parts.append("VLM query failed or returned no response")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification encountered an error")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }