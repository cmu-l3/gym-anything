#!/usr/bin/env python3
"""
Verifier for the Cytochrome c Cross-Species Structural Conservation task.

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  20 pts - Report explicitly mentions both PDB IDs (1HRC and 1YCC)
  25 pts - Report contains a distance/RMSD value in the plausible range for
           this superposition: 0.3–4.0 Å (expected is ~0.8–1.5 Å)
  20 pts - Report correctly identifies one of the conserved heme-coordinating
           residues (His18 or Met80)
  10 pts - Report has ≥5 lines of content (demonstrates some level of analysis)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files.
  - Plausible RMSD range: cannot pass with an arbitrary integer or 0.
  - Required mentioning of both PDBs prevents analyzing only one protein.
  - Conserved residue check: His18 and Met80 are specific biological facts
    that won't be produced unless specifically analyzed or queried.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_cytochrome_c_species_conservation(traj, env_info, task_info):
    """Verify the Cytochrome c structural comparison task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/cytc_conservation_result.json')

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
        parts.append(f"Superposition figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Superposition figure not found at /home/ga/PyMOL_Data/images/cytc_conservation.png")

    # --- Extract report for textual criteria ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    report_upper = report_content.upper()

    if not report_exists:
        parts.append("Report not found at /home/ga/PyMOL_Data/cytc_conservation_report.txt")
        return {"passed": False, "score": score, "feedback": " | ".join(parts)}

    # --- Criterion 2: Both PDB IDs (20 pts) ---
    has_1hrc = '1HRC' in report_upper
    has_1ycc = '1YCC' in report_upper

    if has_1hrc and has_1ycc:
        score += 20
        parts.append("Both 1HRC and 1YCC referenced in report")
    elif has_1hrc or has_1ycc:
        parts.append("Only one PDB ID referenced in report (needs both 1HRC and 1YCC)")
    else:
        parts.append("Neither 1HRC nor 1YCC found in report")

    # --- Criterion 3: Valid RMSD (25 pts) ---
    rmsd_min = metadata.get('rmsd_min', 0.3)
    rmsd_max = metadata.get('rmsd_max', 4.0)

    # Find all decimal numbers
    decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_rmsds = [d for d in decimals if rmsd_min <= d <= rmsd_max]

    if valid_rmsds:
        score += 25
        parts.append(f"Valid RMSD value found: {valid_rmsds[0]:.3f} \u00c5 (range {rmsd_min}\u2013{rmsd_max} \u00c5)")
    elif decimals:
        parts.append(
            f"Decimals found ({decimals[:3]}) but none in plausible RMSD range "
            f"({rmsd_min}\u2013{rmsd_max} \u00c5)"
        )
    else:
        parts.append("No decimal RMSD value found in report")

    # --- Criterion 4: Conserved heme residues (20 pts) ---
    # Match patterns like: His18, His-18, H18, Histidine 18, Met80, M80, Met-80, Methionine 80
    has_his18 = bool(re.search(r'\b(his|h|histidine)[\s-]?18\b', report_content, re.IGNORECASE))
    has_met80 = bool(re.search(r'\b(met|m|methionine)[\s-]?80\b', report_content, re.IGNORECASE))

    if has_his18 or has_met80:
        score += 20
        found = []
        if has_his18: found.append("His18")
        if has_met80: found.append("Met80")
        parts.append(f"Conserved heme-coordinating residue identified: {', '.join(found)}")
    else:
        parts.append("Did not identify conserved heme-coordinating residues (His18 or Met80)")

    # --- Criterion 5: >= 5 lines of content (10 pts) ---
    lines = [line.strip() for line in report_content.splitlines() if line.strip()]
    min_lines = metadata.get('min_report_lines', 5)

    if len(lines) >= min_lines:
        score += 10
        parts.append(f"Report has sufficient length ({len(lines)} lines)")
    elif len(lines) > 0:
        parts.append(f"Report has insufficient length ({len(lines)} lines, need {min_lines})")
    
    # --- Final determination ---
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }