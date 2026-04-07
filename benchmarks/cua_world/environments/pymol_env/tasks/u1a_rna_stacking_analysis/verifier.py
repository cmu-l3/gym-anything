#!/usr/bin/env python3
"""
Verifier for the U1A RNA Pi-Stacking Analysis task (PDB:1URN).

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  10 pts - Structural analysis report exists and has content
  20 pts - Report correctly identifies the RNA base stacking with Tyr13 as Cytosine 10 (C 10)
  20 pts - Report correctly identifies the RNA base stacking with Phe56 as Adenine 11 (A 11)
  30 pts - Report contains measured distances for the pairs in the physically plausible 
           pi-stacking range (3.0 - 4.5 Å). (15 pts per valid distance reported).

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing image files
  - Distance range: rules out arbitrary distances, requires actual measurement
  - Specific residue matching: prevents random sequence dumping from passing, 
    regex matches standard nomenclature (e.g. C 10, Cytosine 10, A 11)
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_u1a_rna_stacking_analysis(traj, env_info, task_info):
    """Verify the U1A-RNA pi-stacking analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/u1a_stacking_result.json')

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
        parts.append(f"Stacking figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Stacking figure not found at /home/ga/PyMOL_Data/images/u1a_rna_stacking.png")

    # --- Criterion 2: Report file exists (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and len(report_content.strip()) >= 15:
        score += 10
        parts.append(f"Report file exists ({len(report_content)} chars)")
    elif report_exists:
        parts.append("Report file exists but is nearly empty")
    else:
        parts.append("Report not found at /home/ga/PyMOL_Data/rna_stacking_report.txt")

    # --- Criterion 3 & 4: Specific Residue Identification (40 pts) ---
    tyr13_pattern = metadata.get('tyr13_pair_regex', r'(?i)(C\s*10|CYT\s*10|Cytosine\s*10)')
    phe56_pattern = metadata.get('phe56_pair_regex', r'(?i)(A\s*11|ADE\s*11|Adenine\s*11)')

    found_c10 = bool(re.search(tyr13_pattern, report_content))
    found_a11 = bool(re.search(phe56_pattern, report_content))

    if found_c10:
        score += 20
        parts.append("Correctly identified Tyr13 pairing with Cytosine 10")
    else:
        parts.append("Did not identify Cytosine 10 (C 10) as the Tyr13 stacking partner")

    if found_a11:
        score += 20
        parts.append("Correctly identified Phe56 pairing with Adenine 11")
    else:
        parts.append("Did not identify Adenine 11 (A 11) as the Phe56 stacking partner")

    # --- Criterion 5 & 6: Distance measurements (30 pts) ---
    dist_min = metadata.get('distance_min', 3.0)
    dist_max = metadata.get('distance_max', 4.5)

    # Extract all decimal values from report
    all_decimals = [float(n) for n in re.findall(r'\b\d+\.\d+\b', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if len(valid_distances) >= 2:
        score += 30
        parts.append(f"\u22652 valid pi-stacking distances reported (e.g., {valid_distances[:2]} \u00c5)")
    elif len(valid_distances) == 1:
        score += 15
        parts.append(f"1 valid pi-stacking distance reported ({valid_distances[0]} \u00c5); expected 2")
    elif all_decimals:
        parts.append(
            f"Decimals found ({all_decimals[:3]}) but none in typical pi-stacking range "
            f"({dist_min}\u2013{dist_max} \u00c5) — check measurements"
        )
    else:
        parts.append("No distance measurements found in report")

    # Final tally
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }