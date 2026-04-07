#!/usr/bin/env python3
"""
Verifier for the T4 Lysozyme Disulfide Engineering Geometry Analysis task.

Scoring (100 points total):
  25 pts - Publication figure exists, is new (post-task-start), and > 30KB.
  25 pts - Report explicitly identifies the two target residues (ILE 3 and CYS 97).
  30 pts - Report contains a distance measurement in the correct Cβ-Cβ range (4.2 - 4.8 Å).
           (Detects gaming/error: if agent measures default minimum distance, it will get ~3.8 Å and fail this).
  20 pts - VLM verification confirms a visible distance measurement object on the structure.

Pass Threshold: 70/100, AND the 'Accurate CB-CB distance' criterion must be met.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_t4_lysozyme_disulfide_engineering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/t4l_result.json')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    parts = []

    # --- Criterion 1: Publication Figure (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Figure created successfully ({fig_size // 1024} KB).")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append("Figure exists but fails timestamp check (may not be newly created).")
    else:
        parts.append("Valid figure not found or is too small (<30KB).")

    # --- Criterion 2: Target Residues Identified (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').upper()

    if report_exists:
        numbers = re.findall(r'\b\d+\b', report_content)
        has_3 = '3' in numbers
        has_97 = '97' in numbers
        has_ile = 'ILE' in report_content or 'ISOLEUCINE' in report_content
        has_cys = 'CYS' in report_content or 'CYSTEINE' in report_content

        if has_3 and has_97 and has_ile and has_cys:
            score += 25
            parts.append("Target residues (ILE 3, CYS 97) explicitly identified in report.")
        else:
            parts.append("Report is missing explicit mention of ILE 3 and/or CYS 97.")
    else:
        parts.append("Geometric analysis report not found.")

    # --- Criterion 3: Accurate CB-CB Distance Measurement (30 pts) ---
    dist_min = metadata.get('cb_distance_min', 4.2)
    dist_max = metadata.get('cb_distance_max', 4.8)
    valid_distance_found = False

    if report_exists:
        all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
        valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

        if valid_distances:
            score += 30
            valid_distance_found = True
            parts.append(f"Valid CB-CB distance reported: {valid_distances[0]:.2f} \u00c5.")
        elif all_decimals:
            parts.append(f"Reported distances {all_decimals} are outside the valid CB-CB range ({dist_min}-{dist_max} \u00c5). "
                         "Warning: You likely measured the default minimum distance instead of specifically selecting the CB atoms.")
        else:
            parts.append("No decimal distance value found in report.")

    # --- Criterion 4: VLM Trajectory Verification (20 pts) ---
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames

        if images:
            prompt = """You are analyzing a PyMOL molecular visualization session. 
            Look closely at these screenshots. Has the user created a distance measurement object (typically a dashed line connecting two residues with a numeric label) visible on the protein structure?
            Respond strictly in JSON format: {"measurement_visible": true/false}"""

            vlm_result = query_vlm(prompt=prompt, images=images)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("measurement_visible"):
                    vlm_score = 20
                    parts.append("VLM confirmed visual measurement line on trajectory.")
                else:
                    parts.append("VLM did not detect a visual measurement line.")
            else:
                vlm_score = 20  # Fallback
                parts.append("VLM check bypassed (query failed).")
        else:
            vlm_score = 20  # Fallback
            parts.append("VLM check bypassed (no images available).")
            
    except ImportError:
        vlm_score = 20  # Fallback if VLM environment is missing
        parts.append("VLM library not available, granting visual points by default.")
    except Exception as e:
        vlm_score = 20
        parts.append(f"VLM error: {e}. Granting default visual points.")

    score += vlm_score

    # Final threshold check
    passed = score >= 70 and valid_distance_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }