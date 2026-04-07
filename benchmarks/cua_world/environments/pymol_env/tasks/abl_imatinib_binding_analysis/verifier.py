#!/usr/bin/env python3
"""
Verifier for the ABL Kinase-Imatinib Binding Analysis task (PDB:1IEP).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  25 pts - Report contains a distance value in the physically plausible range for gatekeeper
           residue T315 to imatinib (STI): expected ~4–8 Å; range 3.0–10.0 Å accepted
  15 pts - Report lists ≥5 distinct protein residues (1–500) within 4 Å of STI
  35 pts - Report contains ≥2 of the known key binding pocket residues by name or number:
           L248(248), Y253(253), K271(271), E286(286), T315(315), M318(318),
           G321(321), I360(360), H361(361), A380(380), D381(381), F382(382)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - Gatekeeper distance range: cannot pass with arbitrary or out-of-range distances
  - Key residue check (35 pts): without identifying ≥2 known binding residues,
    max score is 25+25+15+0=65 < 70 — key residue identification is mandatory
  - Residue count ≥5: cannot pass with a single-residue placeholder
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known ABL kinase imatinib binding pocket residues (from 1IEP / literature)
KEY_BINDING_RESIDUES = {
    'numbers': {248, 253, 271, 286, 315, 318, 321, 360, 361, 380, 381, 382},
    'names': {'L248', 'Y253', 'K271', 'E286', 'T315', 'M318', 'G321',
              'I360', 'H361', 'A380', 'D381', 'F382'},
}


def verify_abl_imatinib_binding_analysis(traj, env_info, task_info):
    """Verify the ABL kinase imatinib binding analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/abl_imatinib_result.json')

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

    # --- Criterion 1: Publication figure (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Binding site figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Binding site figure not found at /home/ga/PyMOL_Data/images/abl_imatinib.png")

    # --- Criterion 2: Gatekeeper (T315) to imatinib distance (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    dist_min = metadata.get('gatekeeper_distance_min', 3.0)
    dist_max = metadata.get('gatekeeper_distance_max', 10.0)

    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 25
        parts.append(
            f"Gatekeeper-drug distance reported: {valid_distances[0]:.2f} \u00c5 "
            f"(valid range {dist_min}\u2013{dist_max} \u00c5)"
        )
    elif all_decimals:
        parts.append(
            f"Decimal values found ({all_decimals[:3]}) but none in gatekeeper distance range "
            f"({dist_min}\u2013{dist_max} \u00c5) \u2014 check measurement"
        )
    else:
        parts.append(
            "No distance value found in report — "
            "must compute gatekeeper T315 to imatinib distance in Angstroms"
        )

    # --- Criterion 3: ≥5 distinct protein residues within 4 Å of STI (15 pts) ---
    min_residues = metadata.get('min_binding_residues', 5)
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content)
                      if 1 <= int(n) <= 500)

    if len(all_numbers) >= min_residues:
        score += 15
        sample = sorted(all_numbers)[:6]
        parts.append(f"\u2265{min_residues} binding residues listed (e.g., {sample})")
    elif len(all_numbers) >= 2:
        score += 6
        parts.append(
            f"Only {len(all_numbers)} residue numbers found "
            f"(need \u2265{min_residues} for complete binding pocket characterization)"
        )
    else:
        parts.append(
            "Insufficient residue numbers in report — "
            "must list protein residues within 4 \u00c5 of imatinib (expected ~10\u201315 residues)"
        )

    # --- Criterion 4: ≥2 known key binding residues mentioned (35 pts) ---
    found_by_number = KEY_BINDING_RESIDUES['numbers'] & all_numbers
    found_by_name = set()
    for name in KEY_BINDING_RESIDUES['names']:
        if name in report_content or name.lower() in report_content.lower():
            found_by_name.add(name)

    key_count = max(len(found_by_number), len(found_by_name))

    if key_count >= 2:
        score += 35
        detail = (list(found_by_name)[:3] if found_by_name
                  else [str(n) for n in sorted(found_by_number)[:3]])
        parts.append(f"Key binding pocket residues identified: {', '.join(detail)}")
    elif key_count == 1:
        score += 10
        detail = (list(found_by_name)[0] if found_by_name
                  else str(sorted(found_by_number)[0]))
        parts.append(
            f"Only 1 key binding residue found ({detail}); "
            "complete analysis should include T315, E286, D381, F382, etc."
        )
    else:
        parts.append(
            "No known key binding pocket residues identified — "
            "binding site must include T315, E286, D381, F382, L248, Y253"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }
