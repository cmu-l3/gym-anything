#!/usr/bin/env python3
"""
Verifier for the Estrogen Receptor Antagonism Mechanism (Helix 12) task.

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  10 pts - Report file exists and contains >50 characters of text
  20 pts - Ligand Identification: explicitly names both EST/estradiol and OHT/tamoxifen
  20 pts - Structural Domain: explicitly references "Helix 12" or "H12"
  30 pts - Quantitative Measurement: report contains a distance between 14.0 and 24.0 Å

Pass threshold: 70/100
CRITICAL: The quantitative measurement criterion MUST be met to pass. Unaligned structures
will have an Asp545-Asp545 distance of ~43 Å. Only an actual structural alignment will 
yield the ~17.5 Å distance. This guarantees the core scientific workflow was executed.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_estrogen_receptor_antagonism(traj, env_info, task_info):
    """Verify the ER-alpha antagonism mechanism structural alignment task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/er_antagonism_result.json')

    # Load the result payload from the container
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
    
    # Flags for critical criteria
    measurement_passed = False

    # --- Criterion 1: Publication figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure created successfully ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but timestamp indicates it might not be new")
    elif fig_exists:
        parts.append(f"Figure exists but is too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/er_helix12_shift.png")

    # --- Criterion 2: Report existence (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content_clean = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and len(report_content_clean.strip()) > 50:
        score += 10
        parts.append(f"Report file exists with adequate content ({len(report_content_clean)} chars)")
    elif report_exists:
        parts.append(f"Report file exists but is nearly empty ({len(report_content_clean)} chars)")
    else:
        parts.append("Report not found at /home/ga/PyMOL_Data/er_antagonism_report.txt")

    # Lowercase text for keyword matching
    report_lower = report_content_clean.lower()

    # --- Criterion 3: Ligand Identification (20 pts) ---
    has_est = any(kw in report_lower for kw in ['est', 'estradiol'])
    has_oht = any(kw in report_lower for kw in ['oht', 'tamoxifen', '4-hydroxytamoxifen'])
    
    if has_est and has_oht:
        score += 20
        parts.append("Both ligands (agonist/EST and antagonist/OHT) identified in report")
    elif has_est or has_oht:
        score += 10
        parts.append("Only one of the ligands (EST or OHT) was identified in the report")
    else:
        parts.append("Neither ligand was explicitly identified in the report")

    # --- Criterion 4: Structural Domain / Helix 12 (20 pts) ---
    has_helix_12 = any(kw in report_lower for kw in ['helix 12', 'h12', 'helix-12', 'helix12'])
    if has_helix_12:
        score += 20
        parts.append("Structural domain (Helix 12) successfully identified in report")
    else:
        parts.append("Report missing reference to the displaced structural domain (Helix 12)")

    # --- Criterion 5: Quantitative Measurement (30 pts) ---
    dist_min = metadata.get('distance_min', 14.0)
    dist_max = metadata.get('distance_max', 24.0)

    # Find all decimal numbers in the text
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content_clean)]
    
    # Check if any decimal falls into the valid alignment distance range
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 30
        measurement_passed = True
        parts.append(
            f"Valid alignment distance reported: {valid_distances[0]:.2f} \u00c5 "
            f"(expected {dist_min}-{dist_max} \u00c5)"
        )
    elif all_decimals:
        # Distance without alignment is ~43A
        if any(d > 40.0 for d in all_decimals):
            parts.append(f"Reported distance ~{max(all_decimals)} \u00c5 indicates alignment was NOT performed before measuring")
        else:
            parts.append(
                f"Numeric values found ({all_decimals[:3]}) but none match the expected alignment "
                f"distance ({dist_min}-{dist_max} \u00c5)"
            )
    else:
        parts.append("No numeric distance value found in the report")

    # --- Final Assessment ---
    # The quantitative measurement proves the structural alignment happened.
    # Without it, the task fundamentally fails the scientific workflow.
    if score >= 70 and measurement_passed:
        passed = True
    else:
        passed = False
        if score >= 70 and not measurement_passed:
            parts.append("CRITICAL FAILURE: Sufficient points reached, but quantitative measurement of aligned structures failed or is missing.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }