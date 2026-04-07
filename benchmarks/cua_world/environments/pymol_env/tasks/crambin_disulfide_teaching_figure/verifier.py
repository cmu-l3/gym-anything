#!/usr/bin/env python3
"""
Verifier for the Crambin Disulfide Teaching Figure task.

Scoring (100 points total):
  20 pts - Figure exists at correct path, is new (post-task-start), and >30KB
  15 pts - Structural report exists with >= 5 lines of content
  15 pts - Report correctly identifies exactly 3 disulfide bonds
  20 pts - Report contains >= 4 of the 6 correct cysteine residue numbers (3, 4, 16, 26, 32, 40)
  15 pts - Report contains >= 2 SG-SG distance values in the plausible range (1.5 - 2.8 Å)
  15 pts - Report explicitly mentions both secondary structure types (helices and sheets/strands)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing image files.
  - specific residue numbers: random guessing won't hit the specific {3, 4, 16, 26, 32, 40} set.
  - distance range: ensures actual measurements were taken rather than arbitrary numbers.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known disulfide-forming cysteines in 1CRN
KNOWN_CYSTEINES = {3, 4, 16, 26, 32, 40}

def verify_crambin_disulfide_teaching_figure(traj, env_info, task_info):
    """Verify the Crambin disulfide and secondary structure teaching figure task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/crambin_result.json')

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

    # --- Criterion 1: Figure exists and is substantial (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Teaching figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("Teaching figure not found at /home/ga/PyMOL_Data/images/crambin_teaching.png")

    # --- Criterion 2: Report existence and length (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    report_lines = [l.strip() for l in report_content.splitlines() if l.strip()]
    min_lines = metadata.get('min_report_lines', 5)

    if report_exists and len(report_lines) >= min_lines:
        score += 15
        parts.append(f"Structural report exists with {len(report_lines)} lines")
    elif report_exists and len(report_lines) > 0:
        score += 5
        parts.append(f"Report is very short ({len(report_lines)} lines)")
    else:
        parts.append("Structural report missing or empty")

    # --- Criterion 3: Disulfide bond count (15 pts) ---
    expected_disulfides = metadata.get('expected_disulfides', 3)
    if re.search(r'\b3\s+(disulfide|bond|pair)', report_content, re.IGNORECASE) or \
       re.search(r'(disulfide|bond|pair)s?.*?\b3\b', report_content, re.IGNORECASE) or \
       re.search(r'\bthree\b.*?(disulfide|bond|pair)', report_content, re.IGNORECASE):
        score += 15
        parts.append("Correctly identified 3 disulfide bonds")
    else:
        parts.append("Did not clearly identify exactly 3 disulfide bonds")

    # --- Criterion 4: Correct cysteine residues (20 pts) ---
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,2})\b', report_content))
    matched_cysteines = all_numbers.intersection(KNOWN_CYSTEINES)
    
    if len(matched_cysteines) >= 4:
        score += 20
        parts.append(f"Identified specific disulfide cysteines: {sorted(list(matched_cysteines))}")
    elif len(matched_cysteines) >= 2:
        score += 10
        parts.append(f"Partially identified cysteines: {sorted(list(matched_cysteines))}")
    else:
        parts.append("Did not identify the specific cysteine residue numbers (e.g., Cys3, Cys40)")

    # --- Criterion 5: SG-SG Distance Measurements (15 pts) ---
    dist_min = metadata.get('sg_distance_min', 1.5)
    dist_max = metadata.get('sg_distance_max', 2.8)
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if len(valid_distances) >= 2:
        score += 15
        parts.append(f"Found valid SG-SG distances (e.g., {valid_distances[0]:.2f} \u00c5, {valid_distances[1]:.2f} \u00c5)")
    elif len(valid_distances) == 1:
        score += 7
        parts.append(f"Found one valid distance: {valid_distances[0]:.2f} \u00c5")
    elif len(all_decimals) > 0:
        parts.append(f"Decimals found but none in range {dist_min}-{dist_max} \u00c5")
    else:
        parts.append("No distance measurements found in report")

    # --- Criterion 6: Secondary structure mentions (15 pts) ---
    has_helix = bool(re.search(r'\b(helix|helices|alpha)\b', report_content, re.IGNORECASE))
    has_sheet = bool(re.search(r'\b(sheet|strand|beta)\b', report_content, re.IGNORECASE))
    
    if has_helix and has_sheet:
        score += 15
        parts.append("Secondary structure summary included (helices and sheets)")
    elif has_helix or has_sheet:
        score += 7
        parts.append("Secondary structure summary partial (missing either helix or sheet)")
    else:
        parts.append("No secondary structure summary found")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }