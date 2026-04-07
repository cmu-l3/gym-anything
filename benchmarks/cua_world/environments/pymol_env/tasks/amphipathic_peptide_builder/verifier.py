#!/usr/bin/env python3
"""
Verifier for Antimicrobial Peptide Amphipathic Helix Builder task.

Scoring System (100 points total):
  30 pts - PDB file exists, was created during task, and matches target sequence
  30 pts - Exported PDB contains an ideal alpha-helical geometry (CA1 to CA20 distance ≈ 28.5 Å)
  20 pts - Text report accurately extracts the length, sequence, and basic residue counts
  20 pts - Publication figure rendered correctly (>10KB)

Pass threshold: 70/100, requires both PDB sequence matching and valid alpha helical geometry
(proving the model was synthesized and not arbitrarily folded).
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_amphipathic_peptide_builder(traj, env_info, task_info):
    """Verify the peptide builder task execution."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/peptide_builder_result.json')
    
    target_sequence = metadata.get('target_sequence', 'KWKLFKKIGIGKFLHSAKKF')
    basic_residue_count = str(metadata.get('basic_residue_count', 8))
    min_dist = metadata.get('ideal_ca_distance_min', 27.0)
    max_dist = metadata.get('ideal_ca_distance_max', 30.0)
    min_fig_size = metadata.get('min_figure_size_bytes', 10000)

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # 1. PDB Validity & Sequence Check (30 pts)
    pdb_exists = result.get('pdb_exists', False)
    pdb_is_new = result.get('pdb_is_new', False)
    pdb_sequence = result.get('pdb_sequence', '')
    
    pdb_valid = False
    if pdb_exists and pdb_is_new:
        if target_sequence in pdb_sequence:
            score += 30
            pdb_valid = True
            parts.append("PDB exported correctly with exact target sequence.")
        elif len(pdb_sequence) >= 10:
            score += 10
            parts.append(f"PDB exported but sequence doesn't match target. Got: {pdb_sequence[:20]}...")
        else:
            parts.append("PDB exported but contains no valid peptide sequence.")
    elif pdb_exists:
        parts.append("PDB file exists but was not created during the task (timestamp check failed).")
    else:
        parts.append("PDB file not found.")

    # 2. Ideal Helical Geometry Check (30 pts)
    # Proves the agent actually built an alpha helix (1.5 Å rise per residue) rather than a straight chain or coil
    ca_distance = result.get('ca_distance')
    geometry_valid = False
    
    if ca_distance is not None:
        if min_dist <= ca_distance <= max_dist:
            score += 30
            geometry_valid = True
            parts.append(f"Ideal helical geometry confirmed (CA distance: {ca_distance:.2f} \u00c5).")
        else:
            parts.append(f"Built geometry is not an ideal alpha helix (CA distance: {ca_distance:.2f} \u00c5, expected {min_dist}-{max_dist} \u00c5).")
    else:
        parts.append("Could not measure CA distance from PDB (missing atoms/residues).")

    # 3. Report Data Accuracy (20 pts)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n')
    
    if report_exists:
        report_score = 0
        
        # Check if sequence is mentioned
        if target_sequence in report_content:
            report_score += 5
            parts.append("Report mentions correct sequence.")
        
        # Look for matching distance decimals in the text
        distances = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
        if any(min_dist <= d <= max_dist for d in distances):
            report_score += 10
            parts.append("Report documents correct distance measurement.")
            
        # Check basic residue count (8 or "eight")
        numbers = re.findall(r'\b\d+(?:\.\d+)?\b', report_content)
        if basic_residue_count in numbers or 'eight' in report_content.lower():
            report_score += 5
            parts.append("Report documents correct basic residue count (8).")
            
        if report_score == 0 and len(report_content) > 10:
            parts.append("Report exists but is missing required accurate data.")
            
        score += report_score
    else:
        parts.append("Report file not found.")

    # 4. Image Rendered (20 pts)
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    
    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure rendered correctly ({fig_size // 1024} KB).")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists but might not be newly created ({fig_size // 1024} KB).")
    elif fig_exists:
        parts.append(f"Figure exists but is too small ({fig_size} bytes - likely incomplete).")
    else:
        parts.append("Figure not found.")

    # Threshold Check
    passed = score >= 70 and pdb_valid and geometry_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }