#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_aquaporin_npa_motif_analysis(traj, env_info, task_info):
    """Verify the Aquaporin NPA motif analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/aqp1_npa_result.json')

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

    # --- Criterion 1: Publication figure (25 pts) & Report existence (10 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Internal pore figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("Internal pore figure not found at /home/ga/PyMOL_Data/images/aqp1_npa_motifs.png")

    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').lower()
    
    if report_exists and len(report_content) > 50:
        score += 10
        parts.append("Report file created with content")
    elif report_exists:
        parts.append("Report file created but too short")
    else:
        parts.append("Report file not found")

    # --- Criterion 2: Identifies Asn78 and Asn194 (30 pts) ---
    expected_residues = metadata.get('expected_residues', [78, 194])
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content) if 1 <= int(n) <= 500)
    
    if all(r in all_numbers for r in expected_residues):
        score += 30
        parts.append(f"Both Asn{expected_residues[0]} and Asn{expected_residues[1]} identified")
    elif any(r in all_numbers for r in expected_residues):
        score += 15
        parts.append("Only one of the expected NPA asparagine residues was identified")
    else:
        parts.append("Did not identify the correct NPA asparagine residue numbers (78, 194)")

    # --- Criterion 3: Reports ND2-ND2 distance (20 pts) ---
    dist_min = metadata.get('distance_min', 3.0)
    dist_max = metadata.get('distance_max', 6.5)

    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 20
        parts.append(
            f"ND2-ND2 distance reported: {valid_distances[0]:.2f} \u00c5 "
            f"(valid range {dist_min}\u2013{dist_max} \u00c5)"
        )
    elif all_decimals:
        parts.append(
            f"Decimal values found ({all_decimals[:3]}) but none in ND2-ND2 distance range "
            f"({dist_min}\u2013{dist_max} \u00c5) \u2014 check measurement"
        )
    else:
        parts.append("No valid distance measurement found in report")

    # --- Criterion 4: Mentions functional role (15 pts) ---
    functional_keywords = metadata.get('functional_keywords', ["proton", "grotthuss", "dipole", "orientation", "flip", "reorient"])
    found_keywords = [kw for kw in functional_keywords if kw in report_content]

    if found_keywords:
        score += 15
        parts.append(f"Functional role mentioned (keywords: {', '.join(found_keywords)})")
    else:
        parts.append("Did not mention functional role (e.g. proton conduction, dipole, orientation)")

    passed = score >= 70 and all(r in all_numbers for r in expected_residues) and fig_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }