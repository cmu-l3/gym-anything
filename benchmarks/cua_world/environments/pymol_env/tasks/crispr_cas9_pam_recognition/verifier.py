#!/usr/bin/env python3
"""
Verifier for the CRISPR-Cas9 PAM Recognition Analysis task (PDB:4UN3).

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new, and >40KB
  20 pts - Key Arginines Identified (report explicitly mentions residues 1333 and 1335)
  20 pts - Non-Target Strand Identified (report identifies Chain D or mentions the target Guanines)
  20 pts - Plausible Distance Measurements (report contains at least two distance values between 2.5 and 4.5 Angstroms)
  20 pts - Complex Chain Assignment (report mentions Cas9, sgRNA, Target DNA, and their chains A, B, C)

Pass threshold: 80/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_crispr_cas9_pam_recognition(traj, env_info, task_info):
    """Verify the CRISPR-Cas9 PAM Recognition Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/cas9_pam_result.json')

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

    # --- Criterion 1: Publication figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 40000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/cas9_pam_recognition.png")

    # --- Criteria 2-5: Report contents ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')

    if not report_exists or not report_content.strip():
        parts.append("Report not found or empty at /home/ga/PyMOL_Data/cas9_pam_report.txt")
        passed = score >= 80
        return {"passed": passed, "score": score, "feedback": " | ".join(parts)}

    # Criterion 2: Key Arginines (20 pts)
    has_1333 = '1333' in report_content
    has_1335 = '1335' in report_content
    if has_1333 and has_1335:
        score += 20
        parts.append("Key Arginines (1333, 1335) identified")
    elif has_1333 or has_1335:
        score += 10
        parts.append("Only one key Arginine identified")
    else:
        parts.append("Key Arginines (1333, 1335) missing from report")

    # Criterion 3: Non-Target Strand Identified (20 pts)
    has_chain_d = re.search(r'\bChain D\b|\bD\b', report_content, re.IGNORECASE)
    has_non_target = 'non-target' in report_content.lower() or 'nontarget' in report_content.lower()
    if has_chain_d and has_non_target:
        score += 20
        parts.append("Non-target DNA strand (Chain D) identified")
    elif has_chain_d or has_non_target:
        score += 10
        parts.append("Non-target DNA strand partially identified")
    else:
        parts.append("Non-target DNA strand missing from report")

    # Criterion 4: Plausible Distance Measurements (20 pts)
    dist_min = metadata.get('distance_min', 2.5)
    dist_max = metadata.get('distance_max', 4.5)
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]
    
    if len(valid_distances) >= 2:
        score += 20
        parts.append(f"Valid distance measurements found: {valid_distances[:2]} \u00c5")
    elif len(valid_distances) == 1:
        score += 10
        parts.append(f"Only one valid distance measurement found: {valid_distances[0]} \u00c5")
    else:
        parts.append(f"No distance measurements in the valid range ({dist_min}\u2013{dist_max} \u00c5) found")

    # Criterion 5: Complex Chain Assignment (20 pts)
    has_chain_a = re.search(r'\bChain A\b|\bA\b', report_content, re.IGNORECASE) and ('cas9' in report_content.lower() or 'protein' in report_content.lower())
    has_chain_b = re.search(r'\bChain B\b|\bB\b', report_content, re.IGNORECASE) and 'rna' in report_content.lower()
    has_chain_c = re.search(r'\bChain C\b|\bC\b', report_content, re.IGNORECASE) and 'target' in report_content.lower()

    if has_chain_a and has_chain_b and has_chain_c:
        score += 20
        parts.append("Complex chain assignments (Cas9, sgRNA, Target DNA) documented")
    elif has_chain_a or has_chain_b or has_chain_c:
        score += 10
        parts.append("Partial chain assignments documented")
    else:
        parts.append("Complex chain assignments missing from report")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }