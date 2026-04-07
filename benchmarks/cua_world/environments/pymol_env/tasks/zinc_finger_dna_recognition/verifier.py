#!/usr/bin/env python3
"""
Verifier for the Zinc Finger DNA Recognition Analysis task (PDB: 1AAY).

Evaluates the agent's performance through multiple independent signals:
  15 pts - Output figure exists, is newly created, and size > 30KB.
  25 pts - Report identifies the 4 coordination residues (C34, C37, H50, H54).
  20 pts - Report contains a coordination distance between 1.9 and 2.5 Angstroms.
  20 pts - Report correctly identifies Guanine as the target base for Arg46.
  20 pts - VLM Verification using trajectory frames to ensure actual workflow progression.

Pass threshold: 75/100
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_zinc_finger_dna_recognition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/zif268_result.json')
    
    # 1. Load result data
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
    parts = []

    # 2. Programmatic Verification
    
    # Criterion A: Figure check (15 pts)
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure created successfully ({fig_size // 1024} KB).")
    elif fig_exists and fig_size >= min_fig_size:
        score += 5
        parts.append("Figure exists but may not be newly generated.")
    else:
        parts.append("Figure not found or too small.")

    report_content = result.get('report_content', '').lower()

    # Criterion B: Coordination residues (25 pts)
    # Zif268 Finger 2 coordination residues: 34, 37, 50, 54
    found_nums = set(re.findall(r'\b\d{2}\b', report_content))
    required_nums = {'34', '37', '50', '54'}
    matched_nums = required_nums.intersection(found_nums)
    
    if len(matched_nums) == 4:
        score += 25
        parts.append("All 4 coordination residues (34, 37, 50, 54) identified.")
    elif len(matched_nums) > 0:
        score += int(25 * (len(matched_nums) / 4))
        parts.append(f"Identified {len(matched_nums)}/4 coordination residues.")
    else:
        parts.append("Finger 2 coordination residues not identified.")

    # Criterion C: Coordination distance (20 pts)
    dist_min = metadata.get('distance_min', 1.9)
    dist_max = metadata.get('distance_max', 2.5)
    floats = [float(x) for x in re.findall(r'\b\d+\.\d+\b', report_content)]
    valid_dist = any(dist_min <= f <= dist_max for f in floats)
    
    if valid_dist:
        score += 20
        parts.append("Valid zinc coordination distance reported.")
    elif floats:
        parts.append(f"Distances found but outside typical {dist_min}-{dist_max} A range.")
    else:
        parts.append("No coordination distance reported.")

    # Criterion D: Target DNA base (20 pts)
    has_guanine = bool(re.search(r'\b(guanine|gua|dg)\b', report_content))
    if not has_guanine:
        has_guanine = bool(re.search(r'\bg\b', report_content))
        
    if has_guanine:
        score += 20
        parts.append("Arg46 target base (Guanine) identified.")
    else:
        parts.append("Arg46 target base not correctly identified.")

    # 3. VLM Verification (20 pts)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        vlm_prompt = """You are verifying an agent's trajectory in completing a PyMOL task.
The task involves analyzing a Zinc Finger-DNA complex, measuring a zinc coordination distance, and finding a hydrogen bond.
Look at this sequence of screenshots and assess:
1. Is the PyMOL interface open with a 3D molecular structure loaded?
2. Is there evidence of structural analysis (e.g., zooming into a pocket, making selections, displaying distance measurement dashes, or sequence viewing)?
3. Is there meaningful progression across the frames (not just the same static view)?

Respond strictly in JSON format:
{
    "structure_loaded": true/false,
    "analysis_evidence": true/false,
    "meaningful_progression": true/false
}"""
        vlm_result = query_vlm(images=images, prompt=vlm_prompt)
        
        if vlm_result and vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            if parsed.get('structure_loaded'): vlm_score += 5
            if parsed.get('analysis_evidence'): vlm_score += 10
            if parsed.get('meaningful_progression'): vlm_score += 5
            parts.append(f"VLM trajectory verification: {vlm_score}/20 pts.")
        else:
            parts.append("VLM trajectory verification failed or returned empty.")
    except ImportError:
        parts.append("VLM utilities unavailable; skipping visual trajectory check.")
    except Exception as e:
        parts.append(f"VLM verification error: {e}")

    score += vlm_score
    
    # Final pass logic (needs 75 points and the target base identified to prevent total guessing)
    key_criteria_met = has_guanine and fig_is_new
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }