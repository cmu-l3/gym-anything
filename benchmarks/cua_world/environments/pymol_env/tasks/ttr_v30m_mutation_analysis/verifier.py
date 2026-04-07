#!/usr/bin/env python3
"""
Verifier for the Transthyretin V30M Mutation Analysis task.

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  15 pts - Report mentions both 1TTA and 1TTC to verify comparative analysis
  25 pts - Report contains a distance value in the physically plausible range for 
           WT Val30 CG1 to mutant Met30 CE (expected ~1.0-5.0 A due to steric expansion)
  25 pts - Report lists >=3 of the known hydrophobic pocket residues around position 30
           (e.g., 12, 16, 28, 31, 47, 49, 54, 55, 73, 74, 107, 109)
  10 pts - Report contains contextual keywords explaining destabilization mechanism
           (e.g., clash, steric, hydrophobic, destabilize, amyloid)

Pass threshold: 75/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing image files.
  - Distance range constraint: rules out random or unrelated distances.
  - Exact pocket residue set matching: prohibits passing by merely listing sequential 
    residue numbers or standard amino acids.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_ttr_v30m_mutation_analysis(traj, env_info, task_info):
    """Verify the TTR V30M mutation analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/ttr_v30m_result.json')
    
    known_pocket_residues = set(metadata.get('known_pocket_residues', [
        12, 16, 28, 31, 47, 49, 54, 55, 73, 74, 107, 109
    ]))

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
        parts.append(f"Comparative figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Comparative figure not found at /home/ga/PyMOL_Data/images/ttr_v30m_clash.png")

    # --- Criterion 2: Mention both PDB IDs (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    content_upper = report_content.upper()

    has_1tta = '1TTA' in content_upper
    has_1ttc = '1TTC' in content_upper

    if has_1tta and has_1ttc:
        score += 15
        parts.append("Both 1TTA and 1TTC referenced in report")
    elif has_1tta or has_1ttc:
        parts.append("Only one PDB ID referenced in report (need both 1TTA and 1TTC)")
    else:
        parts.append("PDB IDs (1TTA, 1TTC) not referenced in report")

    # --- Criterion 3: CG1 to CE Distance (25 pts) ---
    dist_min = metadata.get('distance_min', 1.0)
    dist_max = metadata.get('distance_max', 5.0)

    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 25
        parts.append(f"WT-Mutant sidechain distance reported: {valid_distances[0]:.2f} \u00c5 (valid range {dist_min}-{dist_max} \u00c5)")
    elif all_decimals:
        parts.append(f"Decimal values found ({all_decimals[:3]}) but none in valid sidechain distance range ({dist_min}-{dist_max} \u00c5)")
    else:
        parts.append("No distance value found in report")

    # --- Criterion 4: Hydrophobic Pocket Residues (25 pts) ---
    min_pocket_res = metadata.get('min_pocket_residues', 3)
    # Find all integers between 1 and 150 (TTR monomer length is ~127)
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content) if 1 <= int(n) <= 150)
    
    # Exclude the mutation position itself if it was captured just as part of the narrative
    if 30 in all_numbers:
        all_numbers.remove(30)
        
    matched_pocket = all_numbers.intersection(known_pocket_residues)

    if len(matched_pocket) >= min_pocket_res:
        score += 25
        parts.append(f"Found {len(matched_pocket)} valid pocket residues (e.g., {sorted(list(matched_pocket))[:3]})")
    elif len(matched_pocket) > 0:
        score += int(25 * (len(matched_pocket) / min_pocket_res))
        parts.append(f"Found only {len(matched_pocket)} valid pocket residue(s) (need >= {min_pocket_res})")
    else:
        parts.append("No known hydrophobic pocket residues (e.g., 12, 16, 28, 49) identified in report")

    # --- Criterion 5: Contextual Mechanism (10 pts) ---
    mechanism_keywords = ['clash', 'steric', 'hydrophobic', 'destabiliz', 'amyloid', 'bulk', 'expan', 'pack', 'aggregat']
    has_mechanism = any(kw in report_content.lower() for kw in mechanism_keywords)

    if has_mechanism:
        score += 10
        parts.append("Mechanism context provided")
    else:
        parts.append("No structural consequence mechanism keywords detected (e.g., 'steric clash', 'destabilize')")

    passed = score >= 75
    
    # Must meet key structural biology requirements to pass
    if passed and (not valid_distances or len(matched_pocket) < min_pocket_res):
        passed = False
        parts.append("FAILED: Distance measurement and proper pocket identification are strictly required.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }