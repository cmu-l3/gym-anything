#!/usr/bin/env python3
"""
Verifier for the Maltose-Binding Protein Conformational Morph task.

Scoring (100 points total):
  15 pts - Multi-state PDB file exists and was created during the task.
  20 pts - Morph PDB contains ≥ 30 states (models), validating the morph generation.
  15 pts - Structural integrity: The first and last models contain > 2000 atoms 
           (prevents spoofing with empty models, ensures polymer is present).
  20 pts - Report contains a valid RMSD value in the physically plausible range (1.0 - 4.5 Å).
  15 pts - Report correctly identifies 1OMP as the open state and 1ANF as the closed state.
  15 pts - Publication figure exists, is new (post-task-start), and is non-trivial (>30KB).

Pass threshold: 80/100

Anti-gaming:
  - Timestamp checks (file_is_new) prevent pre-existing files from scoring.
  - Structural integrity checks (atom counts) ensure the agent didn't just write 
    empty `MODEL` tags to a file to pass the model count check.
  - RMSD bounding ensures proper structural alignment was executed.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_mbp_conformational_morph(traj, env_info, task_info):
    """Verify the MBP conformational morph task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/mbp_morph_result.json')

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

    # --- Criterion 1: Morph PDB Existence (15 pts) ---
    pdb_exists = result.get('pdb_exists', False)
    pdb_is_new = result.get('pdb_is_new', False)
    
    if pdb_exists and pdb_is_new:
        score += 15
        parts.append("Morph PDB file created successfully")
    elif pdb_exists:
        parts.append("Morph PDB exists but may not be newly created")
    else:
        parts.append("Morph PDB not found at ~/PyMOL_Data/mbp_morph.pdb")

    # --- Criterion 2: Morph PDB Model Count (20 pts) ---
    pdb_models = result.get('pdb_models', 0)
    expected_models = metadata.get('expected_models', 30)
    
    if pdb_models >= expected_models:
        score += 20
        parts.append(f"Morph contains {pdb_models} states (\u2265{expected_models} expected)")
    elif pdb_models > 1:
        score += 10
        parts.append(f"Morph contains only {pdb_models} states (expected \u2265{expected_models})")
    elif pdb_exists:
        parts.append(f"PDB file has only {pdb_models} state(s) — morph generation failed")

    # --- Criterion 3: Morph PDB Structural Integrity (15 pts) ---
    atoms_first = result.get('pdb_atoms_first', 0)
    atoms_last = result.get('pdb_atoms_last', 0)
    min_atoms = metadata.get('min_atoms_per_model', 2000)
    
    if atoms_first >= min_atoms and atoms_last >= min_atoms:
        score += 15
        parts.append(f"Structural integrity passed (first frame: {atoms_first} atoms, last frame: {atoms_last} atoms)")
    elif pdb_exists:
        parts.append(f"Structural integrity failed (first frame: {atoms_first} atoms, last frame: {atoms_last} atoms; min expected: {min_atoms})")

    # --- Criterion 4: Report valid RMSD (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    
    rmsd_min = metadata.get('rmsd_min', 1.0)
    rmsd_max = metadata.get('rmsd_max', 4.5)
    
    numbers = re.findall(r'\d+\.\d+', report_content)
    valid_rmsds = [float(n) for n in numbers if rmsd_min <= float(n) <= rmsd_max]
    
    if valid_rmsds:
        score += 20
        parts.append(f"Valid RMSD reported: {valid_rmsds[0]:.3f} \u00c5 (range {rmsd_min}\u2013{rmsd_max} \u00c5)")
    elif numbers:
        parts.append(f"Numbers found in report ({numbers[:3]}) but none in plausible RMSD range ({rmsd_min}\u2013{rmsd_max} \u00c5)")
    else:
        parts.append("No numeric RMSD value found in report")

    # --- Criterion 5: Report open/closed state mapping (15 pts) ---
    content_lower = report_content.lower()
    
    has_open_1omp = ('1omp' in content_lower and 'open' in content_lower)
    has_closed_1anf = ('1anf' in content_lower and 'closed' in content_lower)
    
    if has_open_1omp and has_closed_1anf:
        score += 15
        parts.append("Report correctly maps 1OMP to open state and 1ANF to closed state")
    elif '1omp' in content_lower and '1anf' in content_lower:
        score += 5
        parts.append("Report mentions 1OMP and 1ANF but lacks clear open/closed mapping")
    else:
        parts.append("Report does not adequately identify 1OMP and 1ANF states")

    # --- Criterion 6: Publication Figure (15 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)
    
    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Superposition figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 5
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but is too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Superposition figure not found")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }