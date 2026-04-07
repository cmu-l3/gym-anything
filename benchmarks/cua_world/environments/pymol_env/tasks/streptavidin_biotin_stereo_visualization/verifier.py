#!/usr/bin/env python3
"""
Verifier for the Streptavidin-Biotin Stereo Visualization Task.

Scoring (100 points total):
  25 pts - Figure exists at correct path, is >30KB, and created AFTER task start.
  25 pts - Aspect ratio (width/height) of PNG is >= 1.5, verifying stereo pair view format.
  25 pts - Report identifies the PDB ID (1STP) and ligand name (BTN or BIOTIN).
  25 pts - Report lists at least 3 of the 4 key Tryptophan residues forming the
           hydrophobic box (79, 92, 108, 120).

VLM Trajectory Verification:
  Samples frames to verify that PyMOL was used and stereo rendering (split view) is visually present.
  Will override passing status to False if obvious spoofing is detected.
"""

import json
import os
import re
import tempfile
import logging

# Check for VLM framework availability
try:
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).parent.parent.parent))
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logger = logging.getLogger(__name__)

# Known Tryptophan residues in 1STP biotin pocket
KNOWN_TRP_RESIDUES = {79, 92, 108, 120}

def verify_streptavidin_biotin_stereo_visualization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/streptavidin_result.json')

    # Copy result JSON from container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # --- Criterion 1: Figure Exists & Valid (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Figure created successfully ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but was not modified during the task (stale)")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/streptavidin_stereo.png")

    # --- Criterion 2: Stereo Aspect Ratio (25 pts) ---
    fig_width = result.get('figure_width', 0)
    fig_height = result.get('figure_height', 0)
    min_ar = metadata.get('min_aspect_ratio', 1.5)

    ar = (fig_width / fig_height) if fig_height > 0 else 0

    if fig_exists and ar >= min_ar:
        score += 25
        parts.append(f"Image aspect ratio {ar:.2f} satisfies stereo requirement (\u2265{min_ar})")
    elif fig_exists and fig_height > 0:
        parts.append(f"Image aspect ratio {ar:.2f} is too narrow for a stereo pair (\u2265{min_ar} required)")
    elif fig_exists:
        parts.append("Could not determine image aspect ratio")

    # --- Criterion 3: Report Basic Content (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').upper()
    
    has_1stp = '1STP' in report_content
    has_btn = 'BTN' in report_content or 'BIOTIN' in report_content

    if report_exists and has_1stp and has_btn:
        score += 25
        parts.append("Report contains correct PDB ID (1STP) and ligand name (BTN/Biotin)")
    elif report_exists and (has_1stp or has_btn):
        score += 12
        parts.append("Report missing either PDB ID or ligand name")
    elif report_exists:
        parts.append("Report exists but missing PDB ID and ligand name")
    else:
        parts.append("Report not found at /home/ga/PyMOL_Data/streptavidin_pocket.txt")

    # --- Criterion 4: Tryptophan Box (25 pts) ---
    all_numbers = set(int(n) for n in re.findall(r'\b\d{2,3}\b', report_content))
    trps_found = all_numbers.intersection(KNOWN_TRP_RESIDUES)
    min_trp = metadata.get('min_trp_required', 3)

    if report_exists and len(trps_found) >= min_trp:
        score += 25
        parts.append(f"Found {len(trps_found)} key Trp residues: {sorted(list(trps_found))}")
    elif report_exists and len(trps_found) > 0:
        score += 10
        parts.append(f"Found only {len(trps_found)} key Trp residues (need \u2265{min_trp})")
    elif report_exists:
        parts.append("No key Trp pocket residues (79, 92, 108, 120) identified in report")

    # --- VLM Verification (Anti-Spoofing Check) ---
    vlm_passed = True
    if VLM_AVAILABLE and fig_exists and score >= 50:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = (
                    "Look at these screenshots of a PyMOL session chronologically. "
                    "1. Did the agent load a protein structure and zoom in on a binding pocket? "
                    "2. Is stereo rendering enabled (i.e., the PyMOL viewport is split and shows two nearly identical images side-by-side for 3D viewing)? "
                    "Respond strictly in JSON format: {\"used_pymol\": true/false, \"stereo_enabled\": true/false}"
                )
                vlm_res = query_vlm(images=images, prompt=prompt)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    used_pymol = parsed.get("used_pymol", False)
                    stereo_enabled = parsed.get("stereo_enabled", False)
                    
                    if not used_pymol:
                        parts.append("VLM Check Failed: PyMOL usage not detected.")
                        vlm_passed = False
                    elif not stereo_enabled:
                        parts.append("VLM Check Failed: Stereo rendering not visually detected.")
                        vlm_passed = False
                    else:
                        parts.append("VLM confirms PyMOL usage and stereo rendering.")
        except Exception as e:
            logger.warning(f"VLM verification failed to execute: {e}")

    # --- Final Assessment ---
    key_criteria_met = (fig_exists and fig_is_new and len(trps_found) >= min_trp and ar >= min_ar)
    passed = (score >= 70) and key_criteria_met and vlm_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }