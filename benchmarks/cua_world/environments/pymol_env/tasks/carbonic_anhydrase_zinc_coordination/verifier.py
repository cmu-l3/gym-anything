#!/usr/bin/env python3
"""
Verifier for the Carbonic Anhydrase Zinc Coordination Analysis task (PDB: 1CA2).

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  25 pts - Report identifies the 3 key histidine residues (His94, His96, His119)
  25 pts - Report contains at least 3 distance values in the plausible range (1.5–3.0 Å)
  15 pts - Report correctly identifies the coordination geometry as tetrahedral
  15 pts - Report identifies the water/hydroxide molecule as the 4th ligand

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - Zinc-ligand distance range: cannot pass with arbitrary distances
  - Key residue check: Without analyzing the actual structure, an agent cannot guess 
    the exact three histidine numbers (94, 96, 119) for this specific enzyme.
  - Geometry check: Octahedral is the most common geometry guess; tetrahedral must 
    be explicitly discovered/verified.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_carbonic_anhydrase_zinc_coordination(traj, env_info, task_info):
    """Verify the Carbonic Anhydrase Zinc Coordination Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/ca2_zinc_result.json')

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

    # --- Criterion 1: Publication figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Zinc coordination figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/ca2_zinc_coordination.png")

    # --- Criterion 2: Key Histidine Residues (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').lower()
    
    expected_residues = metadata.get('expected_residues', ["94", "96", "119"])
    found_residues = [res for res in expected_residues if re.search(rf'\b{res}\b', report_content)]
    
    if len(found_residues) == 3:
        score += 25
        parts.append(f"All 3 expected histidines found ({', '.join(found_residues)})")
    elif len(found_residues) == 2:
        score += 15
        parts.append(f"Found 2 of 3 histidines ({', '.join(found_residues)})")
    elif len(found_residues) == 1:
        score += 5
        parts.append(f"Found 1 of 3 histidines ({found_residues[0]})")
    else:
        parts.append("Did not identify the expected coordinating histidines (94, 96, 119)")

    # --- Criterion 3: Zinc-ligand distances in range (25 pts) ---
    dist_min = metadata.get('distance_min', 1.5)
    dist_max = metadata.get('distance_max', 3.0)

    # Extract all decimal numbers from report
    all_decimals = [float(n) for n in re.findall(r'\b\d+\.\d+\b', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if len(valid_distances) >= 3:
        score += 25
        parts.append(
            f"Found \u22653 plausible distances ({valid_distances[:3]}) in range {dist_min}\u2013{dist_max} \u00c5"
        )
    elif len(valid_distances) > 0:
        score += 10
        parts.append(
            f"Found {len(valid_distances)} plausible distance(s) "
            f"(valid range {dist_min}\u2013{dist_max} \u00c5, need \u22653)"
        )
    elif all_decimals:
        parts.append(
            f"Numbers found ({all_decimals[:3]}) but none in typical Zn-ligand range "
            f"({dist_min}\u2013{dist_max} \u00c5)"
        )
    else:
        parts.append("No distance measurements found in report")

    # --- Criterion 4: Tetrahedral Geometry (15 pts) ---
    expected_geometry = metadata.get('expected_geometry', 'tetrahedral').lower()
    if expected_geometry in report_content:
        score += 15
        parts.append("Correctly identified tetrahedral geometry")
    elif 'octahedral' in report_content or 'planar' in report_content:
        parts.append("Incorrect geometry identified (expected tetrahedral)")
    else:
        parts.append("Geometry type not found in report")

    # --- Criterion 5: Water/Hydroxide 4th ligand (15 pts) ---
    water_terms = metadata.get('expected_water_terms', ["water", "hoh", "h2o", "hydroxide"])
    found_water = any(term in report_content for term in water_terms)
    
    if found_water:
        score += 15
        parts.append("Correctly identified water/hydroxide as a coordinating ligand")
    else:
        parts.append("Did not identify the coordinating water/hydroxide molecule")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts),
        "details": {
            "figure_score": min_fig_size if fig_exists and fig_size >= min_fig_size else 0,
            "residues_found": len(found_residues),
            "distances_found": len(valid_distances),
            "geometry_correct": expected_geometry in report_content,
            "water_found": found_water
        }
    }