#!/usr/bin/env python3
"""
Verifier for the SARS-CoV-2 N501Y Mutagenesis task.

Verification Strategy & Scoring (100 points total):
  15 pts - Mutated PDB exists, is new, and has a valid size (>400KB to ensure full complex).
  25 pts - Mutagenesis validated: PyMOL successfully saved Chain E Residue 501 as 'TYR'.
  15 pts - Anti-gaming: The control unmutated backbone coordinates exactly match the WT 6M0J 
           structure (proves they did in silico mutagenesis, not just downloading a mutant PDB).
  15 pts - Report contains an OH-OH distance in the valid range (2.0 - 5.0 Å).
  15 pts - Publication figure exists, is new, and >30KB.
  15 pts - VLM verification of the PyMOL trajectory frames showing interaction & measurements.
"""

import json
import math
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

def verify_sars_cov_2_n501y_mutagenesis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/sars_cov_2_n501y_result.json')

    # Copy and load result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    # Extract exported data
    pdb_data = result.get('agent_pdb', {})
    fig_data = result.get('figure', {})
    rep_data = result.get('report', {})

    # =========================================================
    # 1. PDB File Check (15 pts)
    # =========================================================
    min_pdb_size = metadata.get('min_pdb_size_bytes', 400000)
    if pdb_data.get('exists') and pdb_data.get('is_new') and pdb_data.get('size_bytes', 0) > min_pdb_size:
        score += 15
        feedback.append("Mutated PDB file saved successfully with adequate size.")
    elif pdb_data.get('exists'):
        feedback.append(f"PDB exists but is invalid (Size: {pdb_data.get('size_bytes')} bytes, New: {pdb_data.get('is_new')}).")
    else:
        feedback.append("Mutated PDB file was not found.")

    # =========================================================
    # 2. Mutagenesis Validation (25 pts)
    # =========================================================
    mut_res_name = pdb_data.get('chainE_res501_name')
    if mut_res_name == 'TYR':
        score += 25
        feedback.append("Successfully identified N501Y mutation in saved PDB.")
    elif mut_res_name:
        feedback.append(f"Chain E Residue 501 is '{mut_res_name}', expected 'TYR' (mutation failed).")
    else:
        feedback.append("Could not find Chain E Residue 501 in saved PDB.")

    # =========================================================
    # 3. Coordinate Anti-Gaming (15 pts)
    # =========================================================
    wt_A41 = metadata.get('wt_A41_CA_coord', [-20.489, 21.056, -4.510])
    wt_E500 = metadata.get('wt_E500_CA_coord', [-29.620, 27.604, 3.738])
    agent_A41 = pdb_data.get('chainA_res41_CA_coord')
    agent_E500 = pdb_data.get('chainE_res500_CA_coord')

    anti_gaming_passed = False
    if agent_A41 and agent_E500:
        dist_A41 = math.dist(agent_A41, wt_A41)
        dist_E500 = math.dist(agent_E500, wt_E500)
        # Accept if coordinates are identical to wild-type within 0.1A rounding error
        if dist_A41 < 0.1 and dist_E500 < 0.1:
            score += 15
            anti_gaming_passed = True
            feedback.append("Control coordinates match wild-type (in silico mutation verified).")
        else:
            feedback.append(f"Control coordinates do not match WT (A41 shift: {dist_A41:.2f}Å, E500 shift: {dist_E500:.2f}Å). Did you download a pre-mutated PDB?")
    else:
        feedback.append("Could not find control coordinates in PDB to verify WT backbone.")

    # =========================================================
    # 4. Report Distance Measurement (15 pts)
    # =========================================================
    dist_min = metadata.get('expected_distance_min', 2.0)
    dist_max = metadata.get('expected_distance_max', 5.0)
    report_content = rep_data.get('content', '')
    
    # Extract decimals from text
    decimals = [float(n) for n in re.findall(r'\b\d+\.\d+\b', report_content)]
    valid_distances = [d for d in decimals if dist_min <= d <= dist_max]
    
    if rep_data.get('exists') and valid_distances:
        score += 15
        feedback.append(f"Report contains valid OH-OH interaction distance: {valid_distances[0]} Å.")
    elif decimals:
        feedback.append(f"Report found but no distance in valid {dist_min}-{dist_max}Å range (found: {decimals}).")
    elif rep_data.get('exists'):
        feedback.append("Report found but contains no parseable decimal distances.")
    else:
        feedback.append("Distance report file not found.")

    # =========================================================
    # 5. Image Check (15 pts)
    # =========================================================
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)
    if fig_data.get('exists') and fig_data.get('is_new') and fig_data.get('size_bytes', 0) > min_fig_size:
        score += 15
        feedback.append("Interaction visualization figure successfully saved.")
    elif fig_data.get('exists'):
        feedback.append(f"Figure exists but invalid (Size: {fig_data.get('size_bytes')}B, New: {fig_data.get('is_new')}).")
    else:
        feedback.append("Interaction figure not found.")

    # =========================================================
    # 6. VLM Trajectory Verification (15 pts)
    # =========================================================
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
            
            prompt = (
                "You are analyzing screenshots of an agent using PyMOL to perform mutagenesis and measurement. "
                "Assess the sequence of screenshots:\n"
                "1. Did the user open PyMOL's mutagenesis wizard/tool or show evidence of mutating a residue?\n"
                "2. Is there evidence of a distance measurement (dashed line with Angstrom value) in the 3D viewport?\n"
                "3. Does the visualization focus on a zoomed-in interaction between residues (sticks representation)?\n"
                "Respond with a JSON object containing a single boolean field 'valid_workflow_observed' and 'reasoning'."
            )
            
            query_vlm = env_info.get('query_vlm')
            if query_vlm and frames:
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('valid_workflow_observed', False):
                        score += 15
                        feedback.append("VLM verified correct workflow and visualization steps in PyMOL.")
                    else:
                        feedback.append(f"VLM did not observe correct workflow: {parsed.get('reasoning', '')}")
                else:
                    feedback.append("VLM query failed or returned no response.")
        except Exception as e:
            feedback.append(f"VLM Exception: {e}")
    else:
        # Give grace points if VLM is completely unavailable but they passed primary criteria
        if score >= 85:
            score += 15
            feedback.append("VLM unavailable, assuming valid workflow based on perfect programmatic score.")

    # Define pass condition
    key_criteria_met = (mut_res_name == 'TYR' and anti_gaming_passed)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }