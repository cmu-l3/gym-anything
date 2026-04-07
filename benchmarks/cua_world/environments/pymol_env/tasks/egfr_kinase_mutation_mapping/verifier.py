#!/usr/bin/env python3
"""
Verifier for the EGFR Kinase Mutation Mapping task (PDB: 1M17).

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  15 pts - Report correctly identifies the erlotinib ligand code as AQ4
  25 pts - Report contains a distance value in the physically plausible range for CA-CA 
           between T790 and L858 (expected ~11.2 Å; range 10.5–12.0 Å accepted)
  20 pts - Report lists ≥5 valid protein residues within 4 Å of AQ4
  20 pts - Report explicitly addresses both mutation sites (T790 and L858)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - CA-CA distance range: cannot pass with arbitrary or out-of-range distances
  - Valid pocket residues check: must match real residues from the actual 1M17 structure pocket
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known EGFR 1M17 erlotinib (AQ4) binding pocket residues (within 4 Angstroms)
POCKET_RESIDUES = {
    694, 702, 722, 728, 730, 768, 769, 772, 790, 791, 
    793, 794, 795, 796, 797, 800, 803, 844, 854, 855
}


def verify_egfr_kinase_mutation_mapping(traj, env_info, task_info):
    """Verify the EGFR kinase mutation mapping analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/egfr_task_result.json')

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
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/egfr_mutations.png")

    # Read report
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if not report_exists:
        parts.append("Report not found at /home/ga/PyMOL_Data/egfr_report.txt")
        return {"passed": False, "score": score, "feedback": " | ".join(parts)}

    # --- Criterion 2: Ligand Identification (15 pts) ---
    if "AQ4" in report_content.upper():
        score += 15
        parts.append("Ligand correctly identified (AQ4)")
    else:
        parts.append("Ligand code AQ4 not found in report")

    # --- Criterion 3: CA-CA distance between T790 and L858 (25 pts) ---
    dist_min = metadata.get('distance_min', 10.5)
    dist_max = metadata.get('distance_max', 12.0)

    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 25
        parts.append(f"CA-CA distance reported: {valid_distances[0]:.2f} \u00c5 (valid)")
    elif all_decimals:
        parts.append(f"Decimals found but none in CA-CA distance range ({dist_min}-{dist_max} \u00c5)")
    else:
        parts.append("No distance value found in report")

    # --- Criterion 4: Valid Pocket Residues (20 pts) ---
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{3})\b', report_content))
    valid_found = all_numbers.intersection(POCKET_RESIDUES)
    min_pocket_residues = metadata.get('min_pocket_residues', 5)

    if len(valid_found) >= min_pocket_residues:
        score += 20
        parts.append(f"\u2265{min_pocket_residues} valid pocket residues identified")
    elif len(valid_found) > 0:
        score += 10
        parts.append(f"Only {len(valid_found)} valid pocket residue(s) found")
    else:
        parts.append("No valid pocket residues matching the 1M17/AQ4 structure found")

    # --- Criterion 5: Mutation Sites Addressed (20 pts) ---
    has_790 = "790" in report_content
    has_858 = "858" in report_content

    if has_790 and has_858:
        score += 20
        parts.append("Both mutation sites addressed")
    elif has_790 or has_858:
        score += 10
        parts.append("Only one mutation site addressed")
    else:
        parts.append("Neither mutation site (790, 858) explicitly addressed in report")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }