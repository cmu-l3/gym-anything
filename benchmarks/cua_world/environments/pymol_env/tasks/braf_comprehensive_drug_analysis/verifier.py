#!/usr/bin/env python3
"""
Verifier for the BRAF Comprehensive Drug Analysis task.

Scoring Breakdown (100 points total, 5 parts):

  Part 1 - Binding Pocket Characterization (25 pts):
    8 pts  - Pocket figure exists, is new, and >= min size.
    7 pts  - Report lists >= 12 pocket residues in plausible BRAF kinase range,
             with >= 4 matching known pocket residue subset.
    5 pts  - Residue classification present (hydrophobic/polar/charged with counts).
    5 pts  - >= 3 of 5 distance measurements in plausible range.

  Part 2 - DFG Conformational Dynamics (20 pts):
    5 pts  - DFG comparison figure exists, is new, and >= min size.
    5 pts  - RMSD value in plausible range.
    5 pts  - Phe595 displacement in plausible range.
    5 pts  - >= 2 back-pocket residues listed.

  Part 3 - Buried Surface Area (15 pts):
    5 pts  - Surface figure exists, is new, and >= min size.
    5 pts  - >= 2 SASA values in plausible range reported.
    5 pts  - BSA value in plausible range reported.

  Part 4 - Gatekeeper Mutation (20 pts):
    5 pts  - Mutation figure exists, is new, and >= min size.
   10 pts  - Mutation distance measurement(s) in plausible range.
    5 pts  - Steric clash determination present (yes/no).

  Part 5 - Report Quality (20 pts):
   10 pts  - Report exists, is new, has >= 5 section headers, >= 30 non-empty lines.
    5 pts  - Session file exists.
    5 pts  - Report mentions both PDB IDs (3OG7 and 1UWH).

Pass threshold: 60/100  (configurable via metadata)

Anti-gaming:
  - All figures checked for is_new (mtime > task_start_ts).
  - Pocket residue numbers validated against BRAF kinase domain range.
  - Distance/RMSD/BSA ranges catch fabricated values.
  - Section header requirement prevents trivial reports.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def _check_figure(result_figures, name, min_size):
    """Check a single figure: exists, new, meets size threshold.
    Returns (points_earned, feedback_string)."""
    fig = result_figures.get(name, {})
    exists = fig.get('exists', False)
    size = fig.get('size_bytes', 0)
    is_new = fig.get('is_new', False)

    if exists and is_new and size >= min_size:
        return 5, f"Figure '{name}' OK ({size // 1024} KB)"
    elif exists and size >= min_size:
        return 2, f"Figure '{name}' exists ({size // 1024} KB) but may not be new"
    elif exists:
        return 0, f"Figure '{name}' too small ({size} B)"
    else:
        return 0, f"Figure '{name}' not found"


def verify_braf_comprehensive_drug_analysis(traj, env_info, task_info):
    """Verify the comprehensive BRAF drug analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/braf_comprehensive_result.json')

    # --- Load exported result JSON from container ---
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found - export script may not have run."
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
    min_fig_size = metadata.get('min_figure_size_bytes', 25000)

    # Extract report content once
    report_data = result.get('report', {})
    report_exists = report_data.get('exists', False)
    report_is_new = report_data.get('is_new', False)
    report_content = report_data.get('content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    content_lower = report_content.lower()
    report_lines = report_data.get('line_count', 0)

    figures = result.get('figures', {})

    # =========================================================================
    # PART 1: Binding Pocket Characterization (25 pts)
    # =========================================================================

    # 1a. Pocket figure (8 pts)
    fig = figures.get('pocket', {})
    if fig.get('exists') and fig.get('is_new') and fig.get('size_bytes', 0) >= min_fig_size:
        score += 8
        parts.append(f"Pocket figure OK ({fig['size_bytes'] // 1024} KB)")
    elif fig.get('exists') and fig.get('size_bytes', 0) >= min_fig_size:
        score += 4
        parts.append("Pocket figure exists but timestamp failed")
    else:
        parts.append("Pocket figure missing or too small")

    # 1b. Pocket residues identified (7 pts)
    # Look for residue listings in SECTION 1 of the report
    res_range_min = metadata.get('pocket_residue_range_min', 460)
    res_range_max = metadata.get('pocket_residue_range_max', 620)
    min_pocket = metadata.get('min_pocket_residues', 12)
    known_subset = set(metadata.get('known_pocket_residues_subset',
                                     [471, 483, 505, 529, 530, 531, 532, 535, 594, 595]))
    min_known = metadata.get('min_known_pocket_matches', 4)

    # Extract all 3-digit numbers from report that fall in BRAF kinase domain range
    all_residue_nums = set()
    for n in re.findall(r'\b(\d{3})\b', report_content):
        val = int(n)
        if res_range_min <= val <= res_range_max:
            all_residue_nums.add(val)

    matched_known = all_residue_nums.intersection(known_subset)

    if len(all_residue_nums) >= min_pocket and len(matched_known) >= min_known:
        score += 7
        parts.append(f"Pocket: {len(all_residue_nums)} residues, {len(matched_known)} known matches")
    elif len(all_residue_nums) >= min_pocket:
        score += 4
        parts.append(f"Pocket: {len(all_residue_nums)} residues but only {len(matched_known)} known matches")
    elif len(all_residue_nums) > 0:
        score += 2
        parts.append(f"Pocket: only {len(all_residue_nums)} residues found (need {min_pocket})")
    else:
        parts.append("No pocket residues identified in report")

    # 1c. Residue classification (5 pts)
    has_hydrophobic = bool(re.search(r'hydrophobic\b', content_lower))
    has_polar = bool(re.search(r'\bpolar\b', content_lower))
    has_charged = bool(re.search(r'charged\b', content_lower))
    # Check that at least 2 numeric counts accompany the classification
    classification_numbers = re.findall(
        r'(?:hydrophobic|polar|charged)\D{0,20}(\d{1,2})', content_lower)

    if has_hydrophobic and has_polar and has_charged and len(classification_numbers) >= 2:
        score += 5
        parts.append("Residue classification complete")
    elif (has_hydrophobic or has_polar or has_charged) and len(classification_numbers) >= 1:
        score += 2
        parts.append("Partial residue classification")
    else:
        parts.append("Residue classification missing")

    # 1d. Distance measurements (5 pts)
    dist_min = metadata.get('distance_plausible_min', 2.0)
    dist_max = metadata.get('distance_plausible_max', 20.0)

    # Extract section 2 content for distance measurements
    section2_match = re.search(
        r'section\s*2.*?(?=section\s*3|$)', content_lower, re.DOTALL)
    section2_text = section2_match.group(0) if section2_match else content_lower

    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', section2_text)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if len(valid_distances) >= 3:
        score += 5
        parts.append(f"Distances: {len(valid_distances)} valid measurements")
    elif len(valid_distances) >= 1:
        score += 2
        parts.append(f"Distances: only {len(valid_distances)} valid (need 3+)")
    else:
        parts.append("No valid distance measurements found")

    # =========================================================================
    # PART 2: DFG Conformational Dynamics (20 pts)
    # =========================================================================

    # 2a. DFG comparison figure (5 pts)
    pts, fb = _check_figure(figures, 'dfg', min_fig_size)
    score += pts
    parts.append(fb)

    # 2b. RMSD value (5 pts)
    rmsd_min = metadata.get('rmsd_min', 0.3)
    rmsd_max = metadata.get('rmsd_max', 5.0)

    section3_match = re.search(
        r'section\s*3.*?(?=section\s*4|$)', content_lower, re.DOTALL)
    section3_text = section3_match.group(0) if section3_match else content_lower

    rmsd_found = False
    # Look for RMSD keyword near a number
    rmsd_pattern = re.findall(r'rmsd\D{0,30}(\d+\.\d+)', section3_text)
    if not rmsd_pattern:
        # Also try number followed by RMSD
        rmsd_pattern = re.findall(r'(\d+\.\d+)\D{0,20}rmsd', section3_text)
    if not rmsd_pattern:
        # Fallback: any decimal in section 3 within RMSD range
        rmsd_pattern = [n for n in re.findall(r'\d+\.\d+', section3_text)]

    for val_str in rmsd_pattern:
        val = float(val_str)
        if rmsd_min <= val <= rmsd_max:
            score += 5
            parts.append(f"RMSD: {val:.2f} A")
            rmsd_found = True
            break
    if not rmsd_found:
        parts.append("No valid RMSD found in report")

    # 2c. Phe595 displacement (5 pts)
    disp_min = metadata.get('phe595_displacement_min', 3.0)
    disp_max = metadata.get('phe595_displacement_max', 15.0)

    phe_found = False
    # Look for phe595 or displacement near a number in section 3
    phe_pattern = re.findall(r'(?:phe\s*595|f595|displacement)\D{0,40}(\d+\.\d+)', section3_text)
    if not phe_pattern:
        phe_pattern = re.findall(r'(\d+\.\d+)\D{0,30}(?:phe\s*595|f595|displacement)', section3_text)
    for val_str in phe_pattern:
        val = float(val_str)
        if disp_min <= val <= disp_max:
            score += 5
            parts.append(f"Phe595 displacement: {val:.2f} A")
            phe_found = True
            break
    if not phe_found:
        # Fallback: any decimal in section 3 in displacement range
        for val_str in re.findall(r'\d+\.\d+', section3_text):
            val = float(val_str)
            if disp_min <= val <= disp_max:
                score += 3
                parts.append(f"Possible Phe595 displacement: {val:.2f} A (no label)")
                phe_found = True
                break
    if not phe_found:
        parts.append("No Phe595 displacement found")

    # 2d. Back-pocket residues (5 pts)
    back_pocket_match = re.search(
        r'back.?pocket', content_lower)
    # Count residue-like 3-digit numbers near "back-pocket" or in section 3
    bp_residues = set()
    if back_pocket_match:
        # Get text around "back-pocket" keyword
        start = max(0, back_pocket_match.start() - 50)
        end = min(len(report_content), back_pocket_match.end() + 300)
        bp_region = report_content[start:end]
        for n in re.findall(r'\b(\d{3})\b', bp_region):
            val = int(n)
            if res_range_min <= val <= res_range_max:
                bp_residues.add(val)

    if not bp_residues and section3_text:
        # Fallback: look for residue numbers in section 3 that are NOT in the main pocket
        for n in re.findall(r'\b(\d{3})\b', section3_text if section3_match else ''):
            val = int(n)
            if res_range_min <= val <= res_range_max:
                bp_residues.add(val)

    if len(bp_residues) >= 2:
        score += 5
        parts.append(f"Back-pocket: {len(bp_residues)} residues identified")
    elif len(bp_residues) >= 1:
        score += 2
        parts.append(f"Back-pocket: only {len(bp_residues)} residue")
    else:
        parts.append("No back-pocket residues identified")

    # =========================================================================
    # PART 3: Buried Surface Area (15 pts)
    # =========================================================================

    # 3a. Surface figure (5 pts)
    pts, fb = _check_figure(figures, 'surface', min_fig_size)
    score += pts
    parts.append(fb)

    # 3b. SASA values (5 pts)
    sasa_min = metadata.get('sasa_min', 50.0)
    sasa_max = metadata.get('sasa_max', 6000.0)

    section4_match = re.search(
        r'section\s*4.*?(?=section\s*5|$)', content_lower, re.DOTALL)
    section4_text = section4_match.group(0) if section4_match else ''

    sasa_vals = []
    for val_str in re.findall(r'\d+\.\d+', section4_text):
        val = float(val_str)
        if sasa_min <= val <= sasa_max:
            sasa_vals.append(val)
    # Also check for integer SASA values (common output format)
    for val_str in re.findall(r'\b(\d{3,4})\b', section4_text):
        val = float(val_str)
        if sasa_min <= val <= sasa_max and val not in sasa_vals:
            sasa_vals.append(val)

    if len(sasa_vals) >= 2:
        score += 5
        parts.append(f"SASA values: {len(sasa_vals)} found")
    elif len(sasa_vals) >= 1:
        score += 2
        parts.append(f"SASA: only {len(sasa_vals)} value found")
    else:
        parts.append("No valid SASA values found")

    # 3c. BSA value (5 pts)
    bsa_min = metadata.get('bsa_min', 50.0)
    bsa_max = metadata.get('bsa_max', 2500.0)

    bsa_found = False
    bsa_pattern = re.findall(r'(?:bsa|buried\s+surface)\D{0,30}(\d+\.?\d*)', section4_text)
    if not bsa_pattern:
        bsa_pattern = re.findall(r'(\d+\.?\d*)\D{0,20}(?:bsa|buried)', section4_text)
    for val_str in bsa_pattern:
        val = float(val_str)
        if bsa_min <= val <= bsa_max:
            score += 5
            parts.append(f"BSA: {val:.1f} A^2")
            bsa_found = True
            break
    if not bsa_found:
        # Fallback: difference between two largest SASA values
        if len(sasa_vals) >= 2:
            sorted_sasa = sorted(sasa_vals, reverse=True)
            diff = sorted_sasa[0] - sorted_sasa[1]
            if bsa_min <= diff <= bsa_max:
                score += 3
                parts.append(f"Implicit BSA (difference): {diff:.1f} A^2")
                bsa_found = True
    if not bsa_found:
        parts.append("No valid BSA value found")

    # =========================================================================
    # PART 4: Gatekeeper Resistance Mutation (20 pts)
    # =========================================================================

    # 4a. Mutation figure (5 pts)
    pts, fb = _check_figure(figures, 'mutation', min_fig_size)
    score += pts
    parts.append(fb)

    # 4b. Mutation distance measurements (10 pts)
    clash_dist_min = metadata.get('clash_distance_min', 1.0)
    clash_dist_max = metadata.get('clash_distance_max', 12.0)

    section5_match = re.search(
        r'section\s*5.*?(?=section\s*6|$)', content_lower, re.DOTALL)
    section5_text = section5_match.group(0) if section5_match else ''

    mut_distances = []
    for val_str in re.findall(r'\d+\.\d+', section5_text):
        val = float(val_str)
        if clash_dist_min <= val <= clash_dist_max:
            mut_distances.append(val)

    if len(mut_distances) >= 2:
        score += 10
        parts.append(f"Mutation distances: {len(mut_distances)} values reported")
    elif len(mut_distances) >= 1:
        score += 5
        parts.append(f"Mutation distances: only {len(mut_distances)} value")
    else:
        parts.append("No mutation distance measurements found")

    # 4c. Steric clash determination (5 pts)
    has_clash_keyword = bool(re.search(r'clash|steric', section5_text))
    has_determination = bool(re.search(r'\b(yes|no)\b', section5_text))

    if has_clash_keyword and has_determination:
        score += 5
        parts.append("Clash assessment present with determination")
    elif has_clash_keyword:
        score += 2
        parts.append("Clash mentioned but no clear yes/no determination")
    else:
        parts.append("No steric clash assessment found")

    # =========================================================================
    # PART 5: Report Quality (20 pts)
    # =========================================================================

    # 5a. Report structure (10 pts)
    section_headers = re.findall(r'section\s*\d', content_lower)
    min_sections = 5
    min_lines = 30

    if report_exists and report_is_new and len(section_headers) >= min_sections and report_lines >= min_lines:
        score += 10
        parts.append(f"Report structure: {len(section_headers)} sections, {report_lines} lines")
    elif report_exists and report_is_new and report_lines >= 15:
        score += 5
        parts.append(f"Report exists ({report_lines} lines) but structure incomplete")
    elif report_exists:
        score += 2
        parts.append("Report exists but may not be new or is too short")
    else:
        parts.append("Report not found")

    # 5b. Session file (5 pts)
    session_exists = result.get('session', {}).get('exists', False)
    if session_exists:
        score += 5
        parts.append("Session file saved")
    else:
        parts.append("Session file not found")

    # 5c. Both PDB IDs mentioned (5 pts)
    has_3og7 = '3og7' in content_lower
    has_1uwh = '1uwh' in content_lower
    if has_3og7 and has_1uwh:
        score += 5
        parts.append("Both PDB IDs (3OG7, 1UWH) referenced")
    elif has_3og7 or has_1uwh:
        score += 2
        parts.append("Only one PDB ID referenced")
    else:
        parts.append("Neither PDB ID found in report")

    # =========================================================================
    # FINAL SCORING
    # =========================================================================
    pass_threshold = metadata.get('pass_threshold', 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }
