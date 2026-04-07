#!/usr/bin/env python3
"""
Verifier for the H-Ras p21 Nucleotide Binding Analysis task (PDB:5P21).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  25 pts - Report contains a distance value in the physically plausible range for G12 Cα
           to GNP gamma-phosphate (PG atom): expected ~3.5–7.0 Å based on crystal structure;
           range 3.0–8.0 Å accepted to allow for alternative measurement choices
  15 pts - Report lists ≥5 distinct protein residues (1–170) within 3.5 Å of GNP
  35 pts - Report contains ≥2 of the known key GTP-binding residues by name or number:
           G10(10), G12(12), G13(13), K16(16), T35(35), G60(60), Q61(61)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - G12-GNP distance range: cannot pass with arbitrary or out-of-range distances
  - Key residue check (35 pts): without identifying ≥2 known binding residues,
    max score is 25+25+15+0=65 < 70 — key residue identification is mandatory
  - Residue count ≥5: cannot pass with a single-residue placeholder; combined with
    key residue check, pure fabrication fails (distance in range + 5 random = 25+25+15=65 < 70)
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known Ras p21 GTP-binding residues (from 5P21 / literature)
# NOTE: G12 excluded — the task description explicitly asks to measure from G12, so its
# mention is "free" (Lesson 16: keyword contamination). Key residue detection must require
# residues the agent discovers through actual analysis, not those given in the prompt.
KEY_BINDING_RESIDUES = {
    'numbers': {10, 13, 16, 35, 57, 60, 61, 63, 116, 119},
    'names': {'G10', 'G13', 'K16', 'T35', 'A59', 'G60', 'Q61', 'E63', 'N116', 'D119'},
}


def verify_ras_p21_nucleotide_binding(traj, env_info, task_info):
    """Verify the H-Ras p21 GppNHp nucleotide binding analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/ras_nucleotide_result.json')

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
        parts.append(f"Nucleotide binding site figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Binding site figure not found at /home/ga/PyMOL_Data/images/ras_nucleotide.png")

    # --- Criterion 2: G12 Cα to GNP gamma-phosphate distance (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    dist_min = metadata.get('g12_to_gnp_distance_min', 3.0)
    dist_max = metadata.get('g12_to_gnp_distance_max', 8.0)

    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 25
        parts.append(
            f"G12-GNP distance reported: {valid_distances[0]:.2f} \u00c5 "
            f"(valid range {dist_min}\u2013{dist_max} \u00c5)"
        )
    elif all_decimals:
        parts.append(
            f"Decimal values found ({all_decimals[:3]}) but none in G12-GNP distance range "
            f"({dist_min}\u2013{dist_max} \u00c5) \u2014 check measurement"
        )
    else:
        parts.append(
            "No distance value found in report — "
            "must compute G12 C\u03b1 to GNP gamma-phosphate (PG) distance in Angstroms"
        )

    # --- Criterion 3: ≥5 distinct protein residues within 3.5 Å of GNP (15 pts) ---
    min_residues = metadata.get('min_binding_residues', 5)
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content)
                      if 1 <= int(n) <= 170)
    ras_residues = set(n for n in all_numbers if 1 <= n <= 170)

    if len(ras_residues) >= min_residues:
        score += 15
        sample = sorted(ras_residues)[:6]
        parts.append(f"\u2265{min_residues} binding residues listed (e.g., {sample})")
    elif len(ras_residues) >= 2:
        score += 6
        parts.append(
            f"Only {len(ras_residues)} residue numbers found "
            f"(need \u2265{min_residues} for complete binding site characterization)"
        )
    else:
        parts.append(
            "Insufficient residue numbers in report — "
            "must list protein residues within 3.5 \u00c5 of GNP (expected ~8\u201312 residues)"
        )

    # --- Criterion 4: ≥2 known key binding residues mentioned (35 pts) ---
    found_by_number = KEY_BINDING_RESIDUES['numbers'] & ras_residues
    found_by_name = set()
    for name in KEY_BINDING_RESIDUES['names']:
        if name in report_content or name.lower() in report_content.lower():
            found_by_name.add(name)

    key_count = max(len(found_by_number), len(found_by_name))

    if key_count >= 2:
        score += 35
        detail = (list(found_by_name)[:3] if found_by_name
                  else [str(n) for n in sorted(found_by_number)[:3]])
        parts.append(f"Key GTP-binding residues identified: {', '.join(detail)}")
    elif key_count == 1:
        score += 14
        detail = (list(found_by_name)[0] if found_by_name
                  else str(sorted(found_by_number)[0]))
        parts.append(
            f"Only 1 key binding residue found ({detail}); "
            "complete analysis should include G10, G12, G13, K16, T35, G60, Q61"
        )
    else:
        parts.append(
            "No known key GTP-binding residues identified — "
            "binding site must include G10, G12, G13, K16, T35, G60, Q61"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }
