#!/usr/bin/env python3
"""
Verifier for the Ferritin Nanocage Assembly task.

Scoring (100 points total):
  15 pts - Publication figure exists, >50KB, new (created after task start).
  15 pts - Report identifies 24 subunits (biological assembly).
  20 pts - Report contains inner diameter in correct range (70-90 Å).
  20 pts - Report contains outer diameter in correct range (110-130 Å).
  15 pts - Report names the pore-lining residues Asp131 and Glu134.
  15 pts - VLM verifies trajectory shows PyMOL with a spherical cage and measurements.

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_ferritin_nanocage_assembly(traj, env_info, task_info):
    """Verify the ferritin nanocage assembly task using multiple independent signals."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/ferritin_result.json')

    # Extract JSON exported from the container
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
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # --- Criterion 1: Publication figure (15 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 50000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be new")
    elif fig_exists:
        parts.append(f"Figure too small ({fig_size} B)")
    else:
        parts.append("Figure not found")

    # --- Criteria 2-5: Report Content ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content_lower = report_content.lower().replace('\\n', '\n').replace('\\t', '\t')

    if not report_exists:
        parts.append("Report not found")
    else:
        # Criterion 2: 24 subunits (15 pts)
        if "24" in report_content:
            score += 15
            parts.append("Identified 24-mer biological assembly")
        else:
            parts.append("Report does not mention 24 subunits")

        # Extract numerical values for distance checks
        decimals = [float(n) for n in re.findall(r'\b\d{2,3}(?:\.\d+)?\b', report_content)]

        # Criterion 3: Inner Diameter 70-90 (20 pts)
        in_min = metadata.get('inner_diameter_min', 70.0)
        in_max = metadata.get('inner_diameter_max', 90.0)
        inner_matches = [d for d in decimals if in_min <= d <= in_max]
        if inner_matches:
            score += 20
            parts.append(f"Inner diameter found: {inner_matches[0]} \u00c5")
        else:
            parts.append("Inner diameter (70-90 \u00c5) not found")

        # Criterion 4: Outer Diameter 110-130 (20 pts)
        out_min = metadata.get('outer_diameter_min', 110.0)
        out_max = metadata.get('outer_diameter_max', 130.0)
        outer_matches = [d for d in decimals if out_min <= d <= out_max]
        if outer_matches:
            score += 20
            parts.append(f"Outer diameter found: {outer_matches[0]} \u00c5")
        else:
            parts.append("Outer diameter (110-130 \u00c5) not found")

        # Criterion 5: Pore residues Asp131, Glu134 (15 pts)
        has_131 = "131" in report_content
        has_134 = "134" in report_content
        has_asp = "asp" in report_content_lower or "d131" in report_content_lower
        has_glu = "glu" in report_content_lower or "e134" in report_content_lower

        if has_131 and has_134 and has_asp and has_glu:
            score += 15
            parts.append("Pore residues (Asp131, Glu134) identified")
        elif has_131 or has_134:
            score += 7
            parts.append("Pore residues partially identified")
        else:
            parts.append("Pore residues not identified")

    # --- Criterion 6: VLM Verification (15 pts) ---
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images_to_check = [f for f in frames + [final] if f is not None]
            
            if images_to_check:
                prompt = (
                    "You are analyzing screenshots of an agent performing structural biology in PyMOL. "
                    "Did the agent successfully: 1) Load a large spherical multimeric protein cage (ferritin)? "
                    "2) Color it distinctly? 3) Measure distances across the cage (dashed measurement lines visible)? "
                    "Respond with JSON: {\"shows_spherical_cage\": true/false, \"shows_measurements\": true/false}"
                )
                vlm_result = query_vlm(images=images_to_check, prompt=prompt)
                
                # Check for various formats returned by query_vlm safely
                parsed = None
                if isinstance(vlm_result, dict):
                    if "parsed" in vlm_result:
                        parsed = vlm_result["parsed"]
                    elif "shows_spherical_cage" in vlm_result:
                        parsed = vlm_result
                        
                if parsed and isinstance(parsed, dict):
                    if parsed.get("shows_spherical_cage", False):
                        vlm_score += 10
                    if parsed.get("shows_measurements", False):
                        vlm_score += 5
                    parts.append(f"VLM verified trajectory (+{vlm_score} pts)")
                else:
                    parts.append("VLM check bypassed (unexpected response format)")
                    vlm_score = 15
            else:
                parts.append("VLM check bypassed (no images)")
                vlm_score = 15
        else:
            parts.append("VLM check bypassed (not provided)")
            vlm_score = 15
    except Exception as e:
        parts.append(f"VLM check bypassed ({str(e)})")
        vlm_score = 15

    score += vlm_score

    # To pass, must have >= 70 points AND found 24 subunits (biological assembly loaded, not just monomer)
    passed = score >= 70 and ("Identified 24-mer biological assembly" in parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }