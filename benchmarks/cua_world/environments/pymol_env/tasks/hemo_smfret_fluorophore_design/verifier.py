#!/usr/bin/env python3
"""
Verifier for the Hemoglobin smFRET Fluorophore Design task.

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new, and >30KB
  20 pts - Complete Cysteine Inventory: Report identifies residues 93, 104, and 112
  30 pts - Target Identification: Report specifically identifies B:93 and D:93 as targets
  30 pts - FRET Distance: Report contains a measurement between 35.0 and 45.0 Angstroms
           (The physical SG-SG distance between B:93 and D:93 is ~36.5 Å, isolating it
           from the 104-104 (~22 Å) and 112-112 (~17 Å) pairs).

Pass threshold: 80/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_hemo_smfret_fluorophore_design(traj, env_info, task_info):
    """Verify the Hemoglobin smFRET site selection task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/hemo_smfret_result.json')

    # Copy the JSON result out of the container
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

    # --- Criterion 1: Publication Figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"FRET site figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("FRET site figure not found at expected path")

    # --- Criterion 2 & 3: Report Content / Cysteine IDs (50 pts total) ---
    report_exists = result.get('report_exists', False)
    content = result.get('report_content', '')
    
    if not report_exists or not content.strip():
        parts.append("Report missing or empty")
        return {"passed": False, "score": score, "feedback": " | ".join(parts)}

    # Check for presence of all distinct cysteines (20 pts)
    has_93 = '93' in content
    has_104 = '104' in content
    has_112 = '112' in content

    if has_93 and has_104 and has_112:
        score += 20
        parts.append("Complete Cysteine inventory found (93, 104, 112)")
    elif has_93:
        score += 10
        parts.append("Partial Cysteine inventory found (missing buried cysteines 104/112)")
    else:
        parts.append("Expected cysteine residues not identified in report")

    # Target Identification (30 pts)
    # Ensure chains B & D are correlated with the choice of Cys 93
    has_chain_b = bool(re.search(r'\b[Bb]\b', content))
    has_chain_d = bool(re.search(r'\b[Dd]\b', content))
    
    if has_93 and has_chain_b and has_chain_d:
        score += 30
        parts.append("Target cysteines correctly identified on chains B and D")
    elif has_93:
        score += 10
        parts.append("Cys93 mentioned but chains B and D not clearly specified")

    # --- Criterion 4: FRET SG-SG Distance Calculation (30 pts) ---
    dist_min = metadata.get('fret_distance_min', 35.0)
    dist_max = metadata.get('fret_distance_max', 45.0)
    
    # Extract all numbers (integers or decimals)
    numbers = [float(n) for n in re.findall(r'\b\d+(?:\.\d+)?\b', content)]
    valid_dists = [d for d in numbers if dist_min <= d <= dist_max]

    if valid_dists:
        score += 30
        parts.append(f"Correct FRET distance found: {valid_dists[0]:.2f} \u00c5")
    elif numbers:
        # We cap logging to avoid messy logs if there are many numbers
        parts.append(f"Numbers found in report {numbers[:4]} but none in physical FRET range ({dist_min}-{dist_max} \u00c5)")
    else:
        parts.append("No distance measurements found in report")

    passed = score >= 80
    return {"passed": passed, "score": score, "feedback": " | ".join(parts)}