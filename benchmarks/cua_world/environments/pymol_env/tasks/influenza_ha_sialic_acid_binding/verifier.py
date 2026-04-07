#!/usr/bin/env python3
"""
Verifier for the Influenza HA Sialic Acid Binding Analysis task.

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >40KB
  20 pts - Report exists, is new, and contains at least 5 lines
  20 pts - Report contains >= 2 residues representing the conserved HA receptor base
  20 pts - Report contains >= 3 residues from the 130-loop, 190-helix, or 220-loop
  15 pts - Total unique protein residues listed is within physical reason for 4.0A (5 to 50)

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Established biological binding domains for H1 HA / 1RVZ
CONSERVED_BASE = {98, 153, 183, 195}
LOOP_HELIX = {135, 136, 137, 138, 190, 191, 192, 193, 194, 221, 222, 223, 224, 225, 226, 227, 228}

def verify_influenza_ha_sialic_acid_binding(traj, env_info, task_info):
    """Verify the HA-Sialic Acid receptor binding analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/ha_sialic_acid_result.json')

    # Safely extract container JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found \u2014 export script may not have run"
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

    # 1. Figure check (25 pts)
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 40000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B)")
    else:
        parts.append("Figure not found at expected path")

    # 2. Report check (20 pts)
    report_exists = result.get('report_exists', False)
    report_is_new = result.get('report_is_new', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    
    report_lines = [l for l in report_content.splitlines() if l.strip()]

    if report_exists and report_is_new and len(report_lines) >= 5:
        score += 20
        parts.append(f"Report created with {len(report_lines)} lines")
    elif report_exists and len(report_lines) >= 5:
        score += 10
        parts.append(f"Report exists but may not be new")
    elif report_exists:
        parts.append(f"Report too short ({len(report_lines)} lines)")
    else:
        parts.append("Report not found at expected path")

    # 3. Content parsing (regex extracts structural integers 1-500)
    all_numbers = re.findall(r'\b(\d{1,3})\b', report_content)
    residues = set(int(n) for n in all_numbers if 1 <= int(n) <= 500)

    # 4. Conserved Base check (20 pts)
    found_base = residues.intersection(CONSERVED_BASE)
    min_base = metadata.get('min_conserved_base', 2)
    if len(found_base) >= min_base:
        score += 20
        parts.append(f"Found conserved base residues: {sorted(list(found_base))}")
    elif len(found_base) > 0:
        score += 10
        parts.append(f"Found partial conserved base: {sorted(list(found_base))} (needed {min_base})")
    else:
        parts.append("No conserved base residues found")

    # 5. Loop/Helix check (20 pts)
    found_loops = residues.intersection(LOOP_HELIX)
    min_loops = metadata.get('min_loop_helix', 3)
    if len(found_loops) >= min_loops:
        score += 20
        parts.append(f"Found loop/helix residues: {sorted(list(found_loops))}")
    elif len(found_loops) > 0:
        score += 10
        parts.append(f"Found partial loop/helix residues: {sorted(list(found_loops))} (needed {min_loops})")
    else:
        parts.append("No loop/helix residues found")

    # 6. Unique residues scope check (15 pts)
    min_res = metadata.get('min_unique_residues', 5)
    max_res = metadata.get('max_unique_residues', 50)
    if min_res <= len(residues) <= max_res:
        score += 15
        parts.append(f"Valid scope of residues found ({len(residues)} unique)")
    elif len(residues) > 0:
        parts.append(f"Residue count out of bounds ({len(residues)} found, expected {min_res}-{max_res})")
    else:
        parts.append("No valid residue numbers found in report")

    # Pass check: requires base/loops logic to be fundamentally touched
    residue_criteria_met = len(found_base) >= 1 or len(found_loops) >= 1
    passed = score >= 70 and residue_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }