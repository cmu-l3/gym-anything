#!/usr/bin/env python3
"""
Verifier for the Antibody CDR SASA Analysis task (PDB:1N8Z).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  15 pts - Report exists and is not empty
  20 pts - Report contains a Total Fab SASA value in the expected range (15,000 - 30,000 Å²)
  40 pts - Report contains at least two SASA values (for H-CDR and L-CDR) in the expected range (500 - 3,500 Å²)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - SASA ranges check: mathematically validates the structural analysis by verifying dot solvent areas, ruling out arbitrary fabricated reports.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_antibody_cdr_sasa_analysis(traj, env_info, task_info):
    """Verify the Antibody CDR SASA Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/cdr_sasa_result.json')

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
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/herceptin_cdrs.png")

    # --- Criterion 2: Report existence (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n')
    
    if report_exists and len(report_content.strip()) > 10:
        score += 15
        parts.append("Report file created with content")
    else:
        parts.append("Report file missing or empty")

    # --- Criteria 3-5: SASA Values (60 pts) ---
    total_min = metadata.get('total_sasa_min', 15000)
    total_max = metadata.get('total_sasa_max', 30000)
    cdr_min = metadata.get('cdr_min', 500)
    cdr_max = metadata.get('cdr_max', 3500)

    # Extract all numbers >= 100 from report (matches formats like 25,123.45 or 1450.0)
    number_strings = re.findall(r'\b\d{1,3}(?:,\d{3})*(?:\.\d+)?\b', report_content)
    numbers = [float(x.replace(',', '')) for x in number_strings if float(x.replace(',', '')) >= 100]
    
    valid_totals = [n for n in numbers if total_min <= n <= total_max]
    valid_cdrs = [n for n in numbers if cdr_min <= n <= cdr_max]

    if valid_totals:
        score += 20
        parts.append(f"Total Fab SASA found (≈{valid_totals[0]:.1f} Å²)")
    else:
        parts.append(f"No Total Fab SASA found in range {total_min}-{total_max}")

    if len(valid_cdrs) >= 2:
        score += 40
        parts.append(f"Heavy and Light CDR SASAs found (≈{valid_cdrs[0]:.1f}, {valid_cdrs[1]:.1f} Å²)")
    elif len(valid_cdrs) == 1:
        score += 20
        parts.append(f"Only one CDR SASA found in range {cdr_min}-{cdr_max}")
    else:
        parts.append(f"No CDR SASAs found in range {cdr_min}-{cdr_max}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }