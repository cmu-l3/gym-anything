#!/usr/bin/env python3
"""
Verifier for the GroEL-GroES Chamber Expansion Analysis task.

Scoring System (100 points total):
  20 pts - Figure exists, is new (post-task-start), and is non-trivial (>50KB)
  20 pts - Report file exists and has content
  20 pts - Correct amino acid identified (THR / Threonine) for residue 261
  20 pts - Cis ring distance is accurate (between 70.0 and 95.0 Å)
  20 pts - Trans ring distance is accurate (between 35.0 and 60.0 Å)

Pass threshold: 80/100 (Must have correct distances and most of the rest)
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_groel_chamber_expansion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/groel_result.json')

    # Copy the result JSON out of the container
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

    # --- 1. Figure Check (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 50000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Chamber figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/groel_chamber_sliced.png")

    # --- 2. Report Check (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and len(report_content.strip()) >= 20:
        score += 20
        parts.append("Report file exists with adequate content")
    elif report_exists:
        score += 10
        parts.append(f"Report file exists but is very short ({len(report_content)} chars)")
    else:
        parts.append("Report file not found")

    # --- 3. Amino Acid Identification (20 pts) ---
    report_lower = report_content.lower()
    if 'thr' in report_lower or 'threonine' in report_lower:
        score += 20
        parts.append("Correct amino acid (THR) identified")
    elif report_exists:
        parts.append("Did not identify THR / Threonine in the report")

    # --- 4 & 5. Distance Validations (20 + 20 pts) ---
    # Look for decimals and integers in the report (excluding commas)
    all_numbers = [float(n) for n in re.findall(r'\b\d+(?:\.\d+)?\b', report_content)]
    
    cis_min = metadata.get('cis_min', 70.0)
    cis_max = metadata.get('cis_max', 95.0)
    trans_min = metadata.get('trans_min', 35.0)
    trans_max = metadata.get('trans_max', 60.0)

    cis_valid = any(cis_min <= d <= cis_max for d in all_numbers)
    trans_valid = any(trans_min <= d <= trans_max for d in all_numbers)

    if cis_valid:
        score += 20
        parts.append(f"Cis ring distance valid (in expected range {cis_min}-{cis_max} \u00c5)")
    else:
        parts.append(f"No valid cis ring distance found (expected {cis_min}-{cis_max} \u00c5)")

    if trans_valid:
        score += 20
        parts.append(f"Trans ring distance valid (in expected range {trans_min}-{trans_max} \u00c5)")
    else:
        parts.append(f"No valid trans ring distance found (expected {trans_min}-{trans_max} \u00c5)")

    # Key threshold gate for successful completion
    passed = score >= 80 and cis_valid and trans_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }