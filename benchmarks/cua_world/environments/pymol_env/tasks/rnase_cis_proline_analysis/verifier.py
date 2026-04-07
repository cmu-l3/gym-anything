#!/usr/bin/env python3
"""
Verifier for the RNase A Cis-Proline Identification task (PDB:7RSA).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  25 pts - Report correctly identifies BOTH cis-prolines (residues 93 and 114)
  25 pts - Report does NOT misidentify the trans-prolines (residues 42 and 117)
  25 pts - Report contains at least one dihedral angle calculation in the cis range
           (-25.0 to +25.0 degrees) representing the omega angle.

Pass threshold: 75/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - Exact residue matching: specifically checks for 93 and 114 (cis) and penalizes
    the inclusion of 42 and 117 (trans), forcing the agent to actually perform the measurement.
  - Plausible angle check: requires numeric proof of a cis peptide bond measurement.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_rnase_cis_proline_analysis(traj, env_info, task_info):
    """Verify the RNase A cis-proline stereochemical analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/rnase_cis_proline_result.json')

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

    # --- Criterion 1: Publication figure (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Cis-peptide figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("Cis-peptide figure not found at /home/ga/PyMOL_Data/images/cis_pro93.png")

    # --- Criterion 2 & 3: Residue identification (50 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    
    cis_prolines = metadata.get('cis_prolines', [93, 114])
    trans_prolines = metadata.get('trans_prolines', [42, 117])
    
    # Check for cis-prolines
    found_cis = []
    for res in cis_prolines:
        if re.search(r'\b' + str(res) + r'\b', report_content):
            found_cis.append(res)
            
    if len(found_cis) == len(cis_prolines):
        score += 25
        parts.append(f"All cis-prolines ({cis_prolines}) correctly identified")
    elif len(found_cis) > 0:
        score += 12
        parts.append(f"Partial cis-proline identification (found {found_cis})")
    else:
        parts.append("Failed to identify the correct cis-proline residues (93, 114)")
        
    # Check for trans-prolines (absence of false positives)
    found_trans = []
    for res in trans_prolines:
        if re.search(r'\b' + str(res) + r'\b', report_content):
            found_trans.append(res)
            
    if report_exists and len(found_trans) == 0:
        score += 25
        parts.append("No trans-prolines misidentified as cis")
    elif len(found_trans) > 0:
        parts.append(f"False positives detected: trans-prolines ({found_trans}) included in report")
    elif not report_exists:
        parts.append("Report not found at /home/ga/PyMOL_Data/cis_proline_report.txt")

    # --- Criterion 4: Plausible omega angle measurement (25 pts) ---
    omega_min = metadata.get('omega_min', -25.0)
    omega_max = metadata.get('omega_max', 25.0)
    
    # Extract floating point numbers (e.g. -4.2, 0.5, 3.14)
    floats = [float(n) for n in re.findall(r'[-+]?\d+\.\d+', report_content)]
    # Extract integers just in case they reported exact 0 or 1
    ints = [int(n) for n in re.findall(r'[-+]?\b\d+\b', report_content)]
    
    # Filter out known residue numbers from the integer list
    known_residues = set(cis_prolines + trans_prolines)
    all_numbers = floats + [i for i in ints if i not in known_residues]
    
    valid_angles = [d for d in all_numbers if omega_min <= d <= omega_max]
    
    if valid_angles:
        score += 25
        parts.append(f"Valid cis-omega angle reported: ~{valid_angles[0]:.2f}\u00b0 (expected near 0\u00b0)")
    elif all_numbers:
        parts.append(f"Numbers found in report but none indicate a cis-omega angle (\u22480\u00b0). Check measurement atoms (CA-C-N-CA).")
    elif report_exists:
        parts.append("No geometric angle measurements found in report")

    # Determine final pass/fail
    passed = (score >= 75)
    feedback = " | ".join(parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }