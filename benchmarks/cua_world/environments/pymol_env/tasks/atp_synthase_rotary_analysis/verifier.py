#!/usr/bin/env python3
"""
Verifier for the ATP Synthase F1 Domain Rotary Mechanism Analysis task.

Scoring (100 points total):
  20 pts - Publication figure exists, is new (created after task start), and >50KB
  15 pts - Report specifically identifies the 3 β subunit chains (D, E, F)
  20 pts - Report correctly identifies ≥2 nucleotide binding states (ANP/AMPPNP, ADP, empty/none)
  20 pts - Report contains ≥2 pairwise RMSD values in the expected range (0.5 - 5.0 Å)
  15 pts - Report demonstrates mechanistic understanding by using ≥3 key terms
  10 pts - Report is substantive (≥10 lines)

Pass threshold: 65/100

Anti-gaming:
  - figure_is_new gate: image must be rendered AFTER task starts
  - RMSD check: Arbitrary or fabricated numbers out of range 0.5-5.0 Å will fail
  - Specific identification: Requires actual chain letters (D, E, F) and real nucleotide codes
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_atp_synthase_rotary_analysis(traj, env_info, task_info):
    """Verify the ATP Synthase F1 Rotary Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/f1_rotary_result.json')

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
    min_fig_size = metadata.get('min_figure_size_bytes', 50000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"F1-ATPase figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely an incomplete render")
    else:
        parts.append("F1-ATPase figure not found at /home/ga/PyMOL_Data/images/atp_synthase_f1.png")

    # --- Preparation for report criteria ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    report_content_lower = report_content.lower()

    if not report_exists or not report_content.strip():
        parts.append("Report not found or empty.")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(parts)
        }

    # --- Criterion 2: Identifies β subunit chains D, E, F (15 pts) ---
    chain_matches = set()
    for chain in ['D', 'E', 'F']:
        # Match "Chain D", "chain D", or standalone "D" surrounded by word boundaries
        if re.search(rf'\bchain[\s_:-]*{chain}\b', report_content, re.IGNORECASE) or \
           re.search(rf'\b{chain}\b', report_content):
            chain_matches.add(chain)
            
    if len(chain_matches) == 3:
        score += 15
        parts.append("Correctly identified \u03b2 subunit chains D, E, and F")
    elif len(chain_matches) > 0:
        score += 5
        parts.append(f"Identified some, but not all expected chains (found: {', '.join(chain_matches)})")
    else:
        parts.append("Failed to explicitly identify the \u03b2 subunit chains (D, E, F)")

    # --- Criterion 3: Identifies bound nucleotides (20 pts) ---
    nucleotides_found = set()
    for nuc in metadata.get('expected_nucleotides', []):
        if nuc.lower() in report_content_lower:
            # Map AMPPNP to ANP for counting simplicity
            if nuc.lower() in ['anp', 'amppnp']:
                nucleotides_found.add('ANP')
            elif nuc.lower() in ['empty', 'none']:
                nucleotides_found.add('Empty')
            else:
                nucleotides_found.add(nuc.upper())

    if len(nucleotides_found) >= 2:
        score += 20
        parts.append(f"Identified multiple \u03b2 subunit binding states: {', '.join(nucleotides_found)}")
    elif len(nucleotides_found) == 1:
        score += 10
        parts.append(f"Only identified one nucleotide state ({list(nucleotides_found)[0]})")
    else:
        parts.append("Did not identify the nucleotide occupancies (ANP/ADP/Empty)")

    # --- Criterion 4: Pairwise RMSD values (20 pts) ---
    rmsd_min = metadata.get('rmsd_min', 0.5)
    rmsd_max = metadata.get('rmsd_max', 5.0)
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_rmsds = [d for d in all_decimals if rmsd_min <= d <= rmsd_max]

    if len(valid_rmsds) >= 2:
        score += 20
        parts.append(f"Found \u22652 pairwise RMSD values in valid range (e.g., {valid_rmsds[:2]})")
    elif len(valid_rmsds) == 1:
        score += 10
        parts.append(f"Found only one valid RMSD value in range ({valid_rmsds[0]})")
    elif all_decimals:
        parts.append(f"Found numeric data ({all_decimals[:3]}), but none in the expected RMSD range ({rmsd_min}-{rmsd_max} \u00c5)")
    else:
        parts.append("No pairwise RMSD measurements found in report")

    # --- Criterion 5: Mechanistic Analysis terms (15 pts) ---
    mechanistic_terms = metadata.get('mechanistic_terms', [])
    found_terms = [term for term in mechanistic_terms if term in report_content_lower]
    
    if len(found_terms) >= 3:
        score += 15
        parts.append(f"Demonstrated mechanistic understanding (terms: {', '.join(found_terms[:3])})")
    elif len(found_terms) > 0:
        score += 5
        parts.append(f"Limited mechanistic description (found terms: {', '.join(found_terms)})")
    else:
        parts.append("Mechanistic context lacking in report")

    # --- Criterion 6: Report Length (10 pts) ---
    lines = [line for line in report_content.splitlines() if line.strip()]
    if len(lines) >= 10:
        score += 10
        parts.append(f"Report is substantive ({len(lines)} lines)")
    elif len(lines) >= 4:
        score += 5
        parts.append(f"Report is brief ({len(lines)} lines)")
    else:
        parts.append("Report is too short")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }