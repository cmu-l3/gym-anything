#!/usr/bin/env python3
"""
Verifier for protein_structure_nma_bio3d task.

Task: NMA analysis of 1AKE using bio3d.
Scoring (100 points total):
  1. Setup & Installation (10 pts): bio3d installed.
  2. Flexible Residues CSV (40 pts):
     - Exists & New (10 pts)
     - Identifies LID domain residues (120-160) as flexible (15 pts)
     - Identifies NMP domain residues (30-60) as flexible (15 pts)
  3. Visualization (25 pts):
     - Plot exists, new, reasonable size (15 pts)
  4. Trajectory (25 pts):
     - PDB exists, new, is multi-model (10 pts)
     - PDB has frames/models (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_protein_nma(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Result file not found"}
        except json.JSONDecodeError:
            return {"passed": False, "score": 0, "feedback": "Result JSON malformed"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. Installation (10 pts)
    if result.get('bio3d_installed', False):
        score += 10
        feedback.append("bio3d package installed (10/10)")
    else:
        feedback.append("bio3d package NOT installed (0/10)")

    # 2. CSV Analysis (40 pts)
    if result.get('csv_exists') and result.get('csv_is_new'):
        score += 10
        feedback.append("CSV created (10/10)")
        
        # Domain checks
        lid = result.get('lid_domain_flexible', False)
        nmp = result.get('nmp_domain_flexible', False)
        lid_count = result.get('lid_count', 0)
        nmp_count = result.get('nmp_count', 0)
        
        if lid:
            score += 15
            feedback.append(f"Correctly identified LID domain flexibility ({lid_count} residues) (15/15)")
        else:
            feedback.append(f"Failed to identify LID domain flexibility (found {lid_count} residues) (0/15)")
            
        if nmp:
            score += 15
            feedback.append(f"Correctly identified NMP domain flexibility ({nmp_count} residues) (15/15)")
        else:
            feedback.append(f"Failed to identify NMP domain flexibility (found {nmp_count} residues) (0/15)")
            
    else:
        feedback.append("CSV output missing or not created during task (0/40)")

    # 3. Plot (25 pts)
    if result.get('plot_exists') and result.get('plot_is_new'):
        size = result.get('plot_size_kb', 0)
        if size > 5:
            score += 25
            feedback.append("Fluctuation plot created and valid size (25/25)")
        else:
            score += 10
            feedback.append("Fluctuation plot created but suspiciously small (10/25)")
    else:
        feedback.append("Fluctuation plot missing (0/25)")

    # 4. Trajectory (25 pts)
    if result.get('pdb_exists') and result.get('pdb_is_new'):
        if result.get('pdb_has_models', False):
            score += 25
            feedback.append("Trajectory PDB created with multiple models (25/25)")
        else:
            score += 10
            feedback.append("Trajectory PDB created but single model only (static?) (10/25)")
    else:
        feedback.append("Trajectory PDB missing (0/25)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }