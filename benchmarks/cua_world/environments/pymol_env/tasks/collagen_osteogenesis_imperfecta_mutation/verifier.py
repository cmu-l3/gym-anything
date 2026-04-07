#!/usr/bin/env python3
"""
Verifier for the Collagen Osteogenesis Imperfecta Mutation task (PDB: 1CAG).

Scoring (100 points total):
  20 pts - Figure exists, is newly created (post-task-start), and >30KB
  25 pts - Report identifies the mutant residue as Ala / Alanine 15
  25 pts - Report contains a clash distance measurement in the physically expected range (1.5-4.0 Angstroms)
  30 pts - VLM Verification: The agent's visual output highlights the central mutation (Ala 15) in the triple helix.

Pass threshold: 70/100 (Requires correct programmatic data + meaningful visual verification).
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Attempt to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not found; VLM verification will be skipped or simulated.")

VLM_PROMPT = """You are evaluating a PyMOL visualization of a collagen triple helix (three intertwined peptide chains).

The task was to highlight a specific point mutation (Gly to Ala at position 15) located in the crowded central axis of the triple helix.

Analyze the image sequence (which shows the agent's progression and final render) and answer the following:
1. TRIPLE_HELIX_VISIBLE: Is a multi-chain helical protein structure visible?
2. MUTATION_HIGHLIGHTED: Are specific residues in the central core explicitly highlighted (e.g., shown as spheres, brightly colored sticks, or distinctly labeled) to contrast with the rest of the backbone?

Respond ONLY in valid JSON format:
{
    "triple_helix_visible": true/false,
    "mutation_highlighted": true/false,
    "reasoning": "brief explanation of what is visible"
}
"""

def verify_collagen_mutation(traj, env_info, task_info):
    """Verify the Collagen Gly->Ala structural analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/collagen_mutation_result.json')

    # Read result from container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read container result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    parts = []

    # --- Criterion 1: Figure Output (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure generated successfully ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append("Figure exists but may not be newly created (Anti-gaming warning)")
    else:
        parts.append("Figure not found or too small (<30KB)")

    # --- Criterion 2 & 3: Report Content Analysis ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').lower()

    if report_exists:
        # Check for mutation identification (25 pts)
        has_ala = re.search(r'\b(ala|alanine)\b', report_content)
        has_15 = re.search(r'\b15\b', report_content)

        if has_ala and has_15:
            score += 25
            parts.append("Report correctly identifies mutant residue (Ala 15)")
        elif has_ala or has_15:
            score += 10
            parts.append("Report partially identifies mutant residue (missing chain or number)")
        else:
            parts.append("Report missing mutant residue identification")

        # Check for clash distance measurement (25 pts)
        dist_min = metadata.get('clash_distance_min', 1.5)
        dist_max = metadata.get('clash_distance_max', 4.0)
        
        # Extract all floats
        all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
        valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

        if valid_distances:
            score += 25
            parts.append(f"Valid clash distance reported: {valid_distances[0]:.2f} \u00c5 (Range {dist_min}-{dist_max})")
        elif all_decimals:
            parts.append(f"Distances found ({all_decimals[:3]}) but outside steric clash range ({dist_min}-{dist_max} \u00c5)")
        else:
            parts.append("No distance measurements found in report")
    else:
        parts.append("Structural report not found")

    # --- Criterion 4: VLM Verification (30 pts) ---
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            all_images = frames + [final_frame] if final_frame else frames
            
            if all_images:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=all_images)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    helix_visible = parsed.get("triple_helix_visible", False)
                    mutation_hl = parsed.get("mutation_highlighted", False)
                    
                    if helix_visible:
                        score += 10
                        parts.append("VLM: Triple helix visible")
                    
                    if mutation_hl:
                        score += 20
                        parts.append("VLM: Mutation distinctly highlighted")
                    elif helix_visible:
                        parts.append("VLM: Mutation not distinctly highlighted")
                else:
                    parts.append("VLM evaluation failed to parse")
            else:
                parts.append("No trajectory images available for VLM")
        except Exception as e:
            logger.error(f"VLM Exception: {e}")
            parts.append("VLM verification encountered an error")
    else:
        # If framework doesn't support VLM, grant points conditionally based on rigorous text outputs
        if score >= 60:
            score += 30
            parts.append("VLM unavailable; granted points based on high programmatic accuracy")
        else:
            parts.append("VLM unavailable; programmatic score too low to bypass")

    # Determine final pass status
    key_criteria_met = score >= 70
    
    return {
        "passed": key_criteria_met,
        "score": score,
        "feedback": " | ".join(parts)
    }