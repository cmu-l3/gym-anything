#!/usr/bin/env python3
"""
Verifier for the T4 Lysozyme Hydrophobic Cavity Creation task.

Scoring (100 points total):
  20 pts - Publication figure exists, is newly created (post-task-start), and non-trivial (>30KB).
  10 pts - Text report file exists with non-trivial content (>20 chars).
  30 pts - Report contains a valid Cα distance value in the plausible range (0.1–1.5 Å).
           This verifies the structural alignment step.
  30 pts - Report correctly identifies ≥4 specific cavity-lining residue numbers
           associated with the L99A pocket (84, 87, 88, 99, 102, 103, 111, 114, 118).
           This verifies the distance-based contact selection.
  10 pts - VLM verifies trajectory progression (loading structures, superposition visible).

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known cavity-lining residues around the L99A/benzene pocket in 4W52
KNOWN_CAVITY_RESIDUES = {84, 87, 88, 99, 102, 103, 111, 114, 118}


def verify_t4_lysozyme_hydrophobic_cavity(traj, env_info, task_info):
    """Verify the T4 lysozyme mutant comparison and cavity analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/t4_cavity_result.json')

    # Extract result JSON from the agent environment
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            try:
                os.unlink(tmp.name)
            except Exception:
                pass

    score = 0
    parts = []

    # --- Criterion 1: Figure Validation (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Superposition figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Superposition figure not found at expected path")

    # --- Criterion 2: Report Exists (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and len(report_content.strip()) >= 20:
        score += 10
        parts.append(f"Analysis report exists ({len(report_content)} chars)")
    elif report_exists:
        parts.append(f"Analysis report is too short ({len(report_content)} chars)")
    else:
        parts.append("Analysis report not found at expected path")

    # --- Criterion 3: Backbone Cα Distance Check (30 pts) ---
    dist_min = metadata.get('ca_distance_min', 0.1)
    dist_max = metadata.get('ca_distance_max', 1.5)
    
    # Extract all decimal values from the report to find distance
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 30
        parts.append(f"Valid C\u03b1 distance reported: {valid_distances[0]:.2f} \u00c5")
    elif all_decimals:
        parts.append(f"Decimal values found but none in acceptable structural alignment range ({dist_min}-{dist_max} \u00c5)")
    else:
        parts.append("No numeric distance value found in report")

    # --- Criterion 4: Cavity Residue Identification Check (30 pts) ---
    min_residues = metadata.get('min_cavity_residues', 4)
    # Extract integers that could represent residue numbers
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content))
    
    found_cavity_residues = all_numbers.intersection(KNOWN_CAVITY_RESIDUES)
    
    if len(found_cavity_residues) >= min_residues:
        score += 30
        parts.append(f"\u2265{min_residues} correct cavity residues identified")
    elif len(found_cavity_residues) > 0:
        partial_score = int(30 * (len(found_cavity_residues) / min_residues))
        score += partial_score
        parts.append(f"Only {len(found_cavity_residues)} correct cavity residues identified (need \u2265{min_residues})")
    else:
        parts.append("No correct cavity-lining residues found in the report")

    # --- Criterion 5: VLM Trajectory Process Verification (10 pts) ---
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            # Extract image frames safely if the module isn't available
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
            except ImportError:
                images = [step.get('observation', {}).get('rgb_screen') for step in traj 
                          if step.get('observation', {}).get('rgb_screen') is not None]
                if len(images) > 4:
                    step_size = len(images) // 4
                    images = images[::step_size][:3] + [images[-1]]
            
            if images:
                vlm_prompt = """You are analyzing trajectory frames of an agent working in PyMOL.
The task involves superimposing two protein structures (T4 lysozyme mutant and WT) and analyzing a ligand binding pocket.
Did the agent:
1. Load multiple protein structures?
2. Display a clear superposition of structures?
3. Use structural visualization (like highlighting side chains, zooming, or coloring)?

Reply in valid JSON format:
{
    "structures_loaded": true/false,
    "superposition_visible": true/false,
    "meaningful_interaction": true/false
}
"""
                vlm_res = query_vlm(prompt=vlm_prompt, images=images)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('structures_loaded') and parsed.get('superposition_visible'):
                        score += 10
                        parts.append("VLM verified trajectory progression")
                    else:
                        parts.append("VLM trajectory check failed to see superposition")
        except Exception as e:
            logger.warning(f"VLM verification skipped due to error: {e}")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(parts)}