#!/usr/bin/env python3
"""
Verifier for the Hemoglobin T/R Allostery Analysis task.

Scoring (100 points total):
  30 pts - Publication figure exists at correct path, is new (created after task start),
           and is non-trivial (>30KB — rules out a blank/placeholder image)
  10 pts - RMSD report file exists with non-trivial content (>20 chars)
  35 pts - Report contains a valid RMSD value in the physically plausible range (0.1–6.0 Å)
           The T/R allosteric transition in hemoglobin involves ~1–3 Å RMSD on the alpha
           subunits; values outside 0.1–6.0 indicate a scripting error or fabrication.
  25 pts - Report contains both PDB IDs (4HHB and 1HHO), demonstrating that both
           allosteric states were actually loaded and compared (not just one structure visualized)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: figure must be modified AFTER task start (rules out pre-existing files)
  - RMSD range check: figure+report+both-IDs without valid RMSD = 30+10+0+25=65 < 70 — cannot pass
  - Both PDB IDs required: without both IDs and a valid RMSD the score stays below 70
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_hemoglobin_t_r_allostery_analysis(traj, env_info, task_info):
    """Verify the hemoglobin T/R allostery structural comparison task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/hemo_allostery_result.json')

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

    # --- Criterion 1: Publication figure (30 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 30
        parts.append(f"Superposition figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Superposition figure not found at /home/ga/PyMOL_Data/images/hemo_superposition.png")

    # --- Criterion 2: Report file exists with content (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    # Unescape any JSON-escaped newlines from serialization
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and len(report_content.strip()) >= 20:
        score += 10
        parts.append(f"RMSD report file exists ({len(report_content)} chars)")
    elif report_exists:
        parts.append(f"Report file exists but nearly empty ({len(report_content)} chars)")
    else:
        parts.append("RMSD report not found at /home/ga/PyMOL_Data/hemo_rmsd_report.txt")

    # --- Criterion 3: Valid RMSD value in physically plausible range (35 pts) ---
    # Extract all decimal numbers from report
    rmsd_min = metadata.get('rmsd_min', 0.1)
    rmsd_max = metadata.get('rmsd_max', 6.0)
    numbers = re.findall(r'\d+\.\d+', report_content)
    valid_rmsds = [float(n) for n in numbers if rmsd_min <= float(n) <= rmsd_max]

    if valid_rmsds:
        score += 35
        parts.append(f"Valid RMSD value found: {valid_rmsds[0]:.3f} \u00c5 (range {rmsd_min}\u20136.0 \u00c5)")
    elif numbers:
        parts.append(
            f"Numbers found in report ({numbers[:3]}) but none in plausible RMSD range "
            f"({rmsd_min}\u2013{rmsd_max} \u00c5) \u2014 check superposition calculation"
        )
    else:
        parts.append(
            "No numeric RMSD value found in report — "
            "report must contain the superposition RMSD in Angstroms"
        )

    # --- Criterion 4: Both PDB IDs present in report (25 pts) ---
    has_4hhb = '4HHB' in report_content.upper() or '4hhb' in report_content.lower()
    has_1hho = '1HHO' in report_content.upper() or '1hho' in report_content.lower()

    if has_4hhb and has_1hho:
        score += 25
        parts.append("Both allosteric states documented (4HHB T-state and 1HHO R-state)")
    elif has_4hhb or has_1hho:
        score += 10
        found_id = '4HHB' if has_4hhb else '1HHO'
        missing_id = '1HHO' if has_4hhb else '4HHB'
        parts.append(
            f"Only {found_id} referenced in report — missing {missing_id}; "
            "complete analysis requires both allosteric states"
        )
    else:
        parts.append(
            "Neither 4HHB nor 1HHO found in report — "
            "report must reference both T-state and R-state structures"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }
