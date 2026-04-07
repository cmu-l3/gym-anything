#!/usr/bin/env python3
"""
Verifier for the DNA Anthracycline Intercalation Analysis task (PDB:1D12).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  25 pts - Report contains PDB ID (1D12) and the correct 3-letter ligand code (DM1)
  25 pts - Report lists two adjacent flanking DNA residue numbers (e.g., 1 and 2, or 5 and 6)
  25 pts - Report contains a distance value in the physically plausible range for a stretched 
           (intercalated) DNA step C1'-C1' distance: 7.0–9.5 Angstroms. 

Pass threshold: 75/100 (Requires correct distance measurement and accurate target reporting)

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files.
  - C1'-C1' stretched distance range: normal DNA base steps are ~4.5-5.5 A. By requiring 
    7.0-9.5 A, the verifier ensures the agent actually measured the *intercalated* step 
    where the DNA backbone is physically stretched by the drug, proving domain analysis.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_dna_anthracycline_intercalation(traj, env_info, task_info):
    """Verify the DNA-anthracycline intercalation analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/dna_intercalation_result.json')

    # Copy the JSON result from the environment container
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
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    parts = []

    # --- Criterion 1: Publication figure (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Figure created successfully ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may be stale/pre-existing")
    elif fig_exists:
        parts.append(f"Figure exists but is too small ({fig_size} bytes) — likely a placeholder")
    else:
        parts.append("Figure not found at expected path")

    # --- Read Report Content ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    
    # --- Criterion 2: PDB ID and Ligand Identification (25 pts) ---
    pdb_id = metadata.get('pdb_id', '1D12')
    valid_ligands = metadata.get('ligand_ids', ['DM1', 'DOX', 'ADM', 'DXR'])
    
    has_pdb = bool(re.search(rf'\b{pdb_id}\b', report_content, re.IGNORECASE))
    has_ligand = any(re.search(rf'\b{lig}\b', report_content, re.IGNORECASE) for lig in valid_ligands)
    
    if has_pdb and has_ligand:
        score += 25
        parts.append(f"PDB ID ({pdb_id}) and intercalator ligand correctly identified")
    elif has_pdb or has_ligand:
        score += 10
        parts.append("Report missing either the PDB ID or the correct ligand name")
    else:
        parts.append("Report missing both PDB ID and ligand name")

    # --- Criterion 3: Identification of Adjacent Flanking Residues (25 pts) ---
    # Extract all digits to see if any two integers are adjacent (abs(a-b) == 1)
    all_numbers = [int(n) for n in re.findall(r'\b(\d{1,2})\b', report_content)]
    adjacent_pair_found = False
    
    # Check all pairs in the text
    for i in range(len(all_numbers)):
        for j in range(i+1, len(all_numbers)):
            if abs(all_numbers[i] - all_numbers[j]) == 1:
                adjacent_pair_found = True
                break
        if adjacent_pair_found:
            break
            
    if report_exists and adjacent_pair_found:
        score += 25
        parts.append("Adjacent flanking DNA residue numbers identified")
    elif report_exists:
        parts.append("Could not find adjacent flanking residue numbers (e.g., 1 and 2) in the report")

    # --- Criterion 4: C1'-C1' Distance in Intercalation Range (25 pts) ---
    dist_min = metadata.get('distance_min', 7.0)
    dist_max = metadata.get('distance_max', 9.5)

    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]

    if valid_distances:
        score += 25
        parts.append(
            f"Stretched C1'-C1' distance reported: {valid_distances[0]:.2f} \u00c5 "
            f"(valid range {dist_min}-{dist_max} \u00c5)"
        )
    elif all_decimals:
        parts.append(
            f"Decimal values found ({all_decimals[:3]}) but none fall in the intercalated "
            f"distance range ({dist_min}-{dist_max} \u00c5) - measured non-intercalated step?"
        )
    else:
        parts.append("No distance measurement found in the report")

    passed = score >= 75 and bool(valid_distances)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }