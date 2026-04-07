#!/usr/bin/env python3
"""
Verifier for the HIV-1 RT Allosteric Inhibition Analysis task.

Scoring System (100 points total):
  20 pts - Figure Generation: PNG exists, >40KB, created after task start.
  10 pts - Report Existence: Text report exists and has >5 lines.
  10 pts - Chain Identification: Mentions p66 and p51 (or chains A and B).
  20 pts - Triad Identification: Mentions catalytic triad aspartates (110, 185, 186).
  20 pts - Distance Measurement: Reports physically plausible distance (8.0-15.0 Å) between sites.
  20 pts - Pocket Residues: Lists at least 3 genuine NNRTI pocket residues.

Pass threshold: 70/100 AND Distance Measurement successfully met.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_hiv_rt_allosteric_inhibition(traj, env_info, task_info):
    """Verify the HIV-1 RT allosteric inhibition structural analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/rt_allostery_result.json')
    min_fig_size = metadata.get('min_figure_size_bytes', 40000)
    dist_min = metadata.get('distance_min', 8.0)
    dist_max = metadata.get('distance_max', 15.0)
    triad_residues = metadata.get('catalytic_triad', [110, 185, 186])
    known_pocket = set(metadata.get('known_pocket_residues', []))

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
    distance_met = False

    # --- Criterion 1: Figure Generation (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at expected path")

    # --- Criterion 2: Report Existence (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    report_lines = [l for l in report_content.splitlines() if l.strip()]

    if report_exists and len(report_lines) > 5:
        score += 10
        parts.append(f"Report has sufficient content ({len(report_lines)} lines)")
    elif report_exists:
        score += 5
        parts.append(f"Report is sparse ({len(report_lines)} lines)")
    else:
        parts.append("Analysis report not found")

    if not report_exists:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(parts)
        }

    # --- Criterion 3: Chain Identification (10 pts) ---
    content_lower = report_content.lower()
    has_p66_a = 'p66' in content_lower or 'chain a' in content_lower
    has_p51_b = 'p51' in content_lower or 'chain b' in content_lower

    if has_p66_a and has_p51_b:
        score += 10
        parts.append("Subunits p66 and p51 identified")
    elif has_p66_a or has_p51_b:
        score += 5
        parts.append("Only one subunit (p66 or p51) clearly identified")
    else:
        parts.append("Subunit identities (p66/p51) not found in report")

    # --- Criterion 4: Triad Identification (20 pts) ---
    all_numbers = [int(n) for n in re.findall(r'\b(\d{1,4})\b', report_content)]
    
    triad_found = [res for res in triad_residues if res in all_numbers]
    if len(triad_found) == 3:
        score += 20
        parts.append("All catalytic triad residues (110, 185, 186) identified")
    elif len(triad_found) > 0:
        score += 10
        parts.append(f"Partial triad identified: {triad_found}")
    else:
        parts.append("Catalytic triad residues not identified")

    # --- Criterion 5: Distance Measurement (20 pts) ---
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 20
        distance_met = True
        parts.append(f"Distance reported: {valid_distances[0]:.2f} \u00c5 (valid range {dist_min}-{dist_max})")
    elif all_decimals:
        parts.append(f"Decimals found (e.g., {all_decimals[:2]}) but outside valid physical distance ({dist_min}-{dist_max} \u00c5)")
    else:
        parts.append("No decimal distance measurement found in report")

    # --- Criterion 6: Pocket Residues (20 pts) ---
    found_pocket = set(all_numbers).intersection(known_pocket)

    if len(found_pocket) >= 3:
        score += 20
        parts.append(f"Valid pocket residues identified: {sorted(list(found_pocket))}")
    elif len(found_pocket) > 0:
        score += 10
        parts.append(f"Only {len(found_pocket)} true pocket residues identified (need \u22653)")
    else:
        parts.append("No valid NNRTI binding pocket residues identified")

    # Assess overall pass condition
    passed = (score >= 70) and distance_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }