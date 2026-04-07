#!/usr/bin/env python3
"""
Verifier for SARS-CoV-2 Mpro Paxlovid Electron Density Validation task.

Verification Criteria (100 pts total):
  20 pts - Publication figure exists, was created after task start, and is >30KB.
  20 pts - Nirmatrelvir ligand correctly identified as `4WI` by reading the sequence/structure.
  20 pts - Catalytic active site residue correctly identified as `Cys 145`.
  20 pts - Contour level used for the generated isomesh is reported as `1.0`.
  20 pts - Measured covalent bond distance reported in a physically plausible range
           for a carbon-sulfur covalent bond (1.6 - 2.0 Å).
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_paxlovid_density(traj, env_info, task_info):
    """Verify the Paxlovid electron density and covalent bond measurement task."""
    
    # Use copy_from_env to fetch JSON exported out of container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/paxlovid_density_result.json')

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

    # Criterion 1: Figure Validity (20 points)
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Density figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("Density figure not found at /home/ga/PyMOL_Data/images/paxlovid_density.png")

    # Read Report Content
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    # Criterion 2: Ligand Identification (20 points)
    if re.search(r'\b4WI\b', report_content, re.IGNORECASE):
        score += 20
        parts.append("Correctly identified nirmatrelvir ligand (4WI)")
    else:
        parts.append("Failed to identify ligand 4WI in report")

    # Criterion 3: Catalytic Residue Identification (20 points)
    has_cys = re.search(r'\bCYS\b|\bCysteine\b', report_content, re.IGNORECASE)
    has_145 = re.search(r'\b145\b', report_content)
    if has_cys and has_145:
        score += 20
        parts.append("Correctly identified catalytic residue (Cys 145)")
    elif has_cys or has_145:
        parts.append("Partially identified catalytic residue (missing Cys or 145)")
    else:
        parts.append("Failed to identify catalytic residue Cys 145")

    # Criterion 4: Contour Level (20 points)
    if re.search(r'\b1\.0\b', report_content) or re.search(r'\b1\s*(sigma|\u03c3)\b', report_content, re.IGNORECASE):
        score += 20
        parts.append("Contour level explicitly stated as 1.0")
    else:
        parts.append("Contour level (1.0) not explicitly found in report")

    # Criterion 5: Bond Distance Measurement (20 points)
    # Extracts all decimal values and checks if any fall in the tight physically-plausible range (C-S covalent bond)
    dist_min = metadata.get('bond_distance_min', 1.6)
    dist_max = metadata.get('bond_distance_max', 2.0)
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 20
        parts.append(f"Valid covalent bond distance reported: {valid_distances[0]:.2f} \u00c5")
    elif all_decimals:
        parts.append(f"Distances found ({all_decimals[:3]}) but none in covalent range ({dist_min}-{dist_max} \u00c5)")
    else:
        parts.append("No distance value found in report")

    # Overall Evaluation (Must achieve 80 / 100 to pass)
    passed = (score >= 80)
    feedback = " | ".join(parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }