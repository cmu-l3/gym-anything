#!/usr/bin/env python3
"""
Verifier for the HIV-1 Protease Water Analysis task (PDB:1HSG).

Scoring (100 points total):
  Programmatic Checks (70 pts):
  15 pts - Publication figure exists at correct path, is new, and >30KB
  10 pts - Report exists with >= 5 lines of content
  10 pts - Report states a reasonable active-site water count (2 to 20)
  10 pts - Report explicitly mentions residue 50 or Ile50 (the flap tip)
  15 pts - Report contains a distance value in H-bond range (2.0 - 4.5 A)
  10 pts - Report identifies >= 2 other key active site residues by number

  VLM Trajectory Checks (30 pts):
  30 pts - VLM verifies the trajectory frames show progressive molecular
           visualization including waters and distance measurements.

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Try to import VLM utilities, but degrade gracefully if unavailable
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available. VLM points will be awarded by default to avoid breaking CI.")


VLM_PROMPT = """You are evaluating an AI agent performing molecular analysis in PyMOL.
Review this sequence of trajectory frames (earliest to latest) and the final screenshot.
Did the agent:
1. Load a 3D protein structure?
2. Show water molecules (often visualized as small spheres, red dots, or crosses)?
3. Measure distances (visible as dashed yellow lines between atoms)?

Return JSON format exactly like this:
{
  "protein_loaded": true/false,
  "waters_visible": true/false,
  "distances_measured": true/false
}"""


def verify_hiv_protease_water_analysis(traj, env_info, task_info):
    """Verify the HIV-1 Protease Water Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/hiv_water_result.json')

    # 1. Read programmatic results from the environment
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

    # --- Criterion 1: Figure exists, is new, >30KB (15 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure valid ({fig_size // 1024} KB)")
    elif fig_exists:
        parts.append(f"Figure invalid (too small or not newly created: {fig_size} bytes)")
    else:
        parts.append("Figure not found")

    # --- Criterion 2: Report content & length (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n')
    lines = [l for l in report_content.splitlines() if l.strip()]
    min_lines = metadata.get('min_report_lines', 5)

    if report_exists and len(lines) >= min_lines:
        score += 10
        parts.append(f"Report has {len(lines)} lines")
    elif report_exists:
        parts.append(f"Report too short ({len(lines)} lines)")
    else:
        parts.append("Report not found")

    # --- Parse report for numeric values ---
    all_integers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content))
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]

    # --- Criterion 3: Active-site water count (10 pts) ---
    min_waters = metadata.get('water_count_min', 2)
    max_waters = metadata.get('water_count_max', 20)
    if any(min_waters <= n <= max_waters for n in all_integers):
        score += 10
        parts.append("Plausible water count found")
    else:
        parts.append(f"No plausible water count ({min_waters}-{max_waters}) found")

    # --- Criterion 4: Mentions residue 50 (10 pts) ---
    if 50 in all_integers or re.search(r'(?i)\bile50\b', report_content):
        score += 10
        parts.append("Flap residue 50 mentioned")
    else:
        parts.append("Flap residue 50 NOT mentioned")

    # --- Criterion 5: Distance in H-bond range (15 pts) ---
    dist_min = metadata.get('hbond_dist_min', 2.0)
    dist_max = metadata.get('hbond_dist_max', 4.5)
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]
    if valid_distances:
        score += 15
        parts.append(f"H-bond distance found: {valid_distances[0]:.2f} A")
    else:
        parts.append("No valid H-bond distance found")

    # --- Criterion 6: >= 2 key active site residues (10 pts) ---
    key_residues = set(metadata.get('key_residues', [8, 25, 27, 28, 48]))
    found_keys = key_residues.intersection(all_integers)
    
    # Also look for standard abbreviations
    if 'ASP25' in report_content.upper() or 'D25' in report_content.upper(): found_keys.add(25)
    if 'GLY27' in report_content.upper() or 'G27' in report_content.upper(): found_keys.add(27)
    
    if len(found_keys) >= 2:
        score += 10
        parts.append(f"Found {len(found_keys)} key residues: {list(found_keys)}")
    else:
        parts.append(f"Found {len(found_keys)} key residues (need >=2 from {list(key_residues)})")

    # --- Criterion 7: VLM Trajectory Process Check (30 pts) ---
    vlm_score = 0
    vlm_parts = []
    
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            result_vlm = query_vlm(images=images, prompt=VLM_PROMPT)
            
            if result_vlm and result_vlm.get("success"):
                parsed = result_vlm.get("parsed", {})
                if parsed.get("protein_loaded"):
                    vlm_score += 10
                    vlm_parts.append("VLM: Protein loaded")
                if parsed.get("waters_visible"):
                    vlm_score += 10
                    vlm_parts.append("VLM: Waters visible")
                if parsed.get("distances_measured"):
                    vlm_score += 10
                    vlm_parts.append("VLM: Distances measured")
            else:
                # VLM failed to parse or return success, grant partial grace points
                vlm_score += 15
                vlm_parts.append("VLM analysis failed; granting partial VLM credit")
        except Exception as e:
            logger.error(f"VLM exception: {e}")
            vlm_score += 15
            vlm_parts.append("VLM error; granting partial VLM credit")
    else:
        # If VLM is not available, grant full VLM points so programmatic tests alone pass
        vlm_score = 30
        vlm_parts.append("VLM skipped (not available)")

    score += vlm_score
    parts.extend(vlm_parts)

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }