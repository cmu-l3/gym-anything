#!/usr/bin/env python3
"""
Verifier for the DHFR-Methotrexate Electron Density Validation task.

Scoring (100 points total):
  15 pts - Output figure exists, is new (> task start), and >30KB
  15 pts - Text report contains the correct heavy atom count for methotrexate (33)
  20 pts - Text report lists >= 3 correct contact residue numbers from the known active site
  15 pts - Session file (.pse) exists, is new, and >100KB
  25 pts - Session programmatic API check confirms existence of an `object:map` (volumetric data)
           and an `object:mesh` (contoured mesh)
  10 pts - Session programmatic API check confirms MTX ligand is actively loaded

Pass threshold: 70/100

Anti-gaming measures:
  - Strict timestamp checking for all 3 output files prevents using stale files.
  - Verification loads the `.pse` session into the PyMOL API to ensure volumetric
    map/mesh objects were actually created, preventing UI faking or generic molecule loads.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Subset of known DHFR residues interacting with Methotrexate within 4.0 Angstroms (PDB: 1RX2)
KNOWN_CONTACT_RESIDUES = {5, 7, 8, 27, 28, 31, 50, 52, 54, 57, 94, 100, 113}
MTX_HEAVY_ATOMS = 33

def verify_dhfr_electron_density_validation(traj, env_info, task_info):
    """Verify the electron density mapping task via file outputs and session API analysis."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/dhfr_mtx_result.json')

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

    # --- Criterion 1: Image Verification (15 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_new = result.get('figure_is_new', False)
    fig_size = result.get('figure_size_bytes', 0)
    
    if fig_exists and fig_new and fig_size > 30000:
        score += 15
        parts.append("Figure created successfully.")
    elif fig_exists:
        parts.append(f"Figure exists but failed validation (size: {fig_size}B, new: {fig_new}).")
    else:
        parts.append("Figure missing.")

    # --- Criterion 2 & 3: Report Verification (15 + 20 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    
    if report_exists:
        # Check heavy atom count (33)
        if str(MTX_HEAVY_ATOMS) in report_content:
            score += 15
            parts.append("MTX heavy atom count (33) found in report.")
        else:
            parts.append("MTX heavy atom count (33) NOT found in report.")
            
        # Check contact residues
        # Find all 1-to-3 digit numbers in the report
        reported_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content))
        valid_found = reported_numbers.intersection(KNOWN_CONTACT_RESIDUES)
        
        if len(valid_found) >= 3:
            score += 20
            parts.append(f"Found {len(valid_found)} valid contact residues (e.g., {sorted(list(valid_found))[:3]}).")
        elif len(valid_found) > 0:
            score += 10
            parts.append(f"Only found {len(valid_found)} valid contact residues (needs >=3).")
        else:
            parts.append("No valid contact residues identified in report.")
    else:
        parts.append("Report file missing.")

    # --- Criterion 4: Session File Basic Verification (15 pts) ---
    session_exists = result.get('session_exists', False)
    session_new = result.get('session_is_new', False)
    session_size = result.get('session_size_bytes', 0)
    
    if session_exists and session_new and session_size > 100000:
        score += 15
        parts.append("Session file saved successfully.")
    elif session_exists:
        parts.append(f"Session exists but failed validation (size: {session_size}B, new: {session_new}).")
    else:
        parts.append("Session file missing.")

    # --- Criterion 5 & 6: Session API Programmatic Validation (25 + 10 pts) ---
    inspection = result.get('session_inspection', {})
    
    if inspection.get('session_loaded'):
        objects = inspection.get('objects', {})
        types_present = list(objects.values())
        
        # Look for volumetric objects
        has_map = any('map' in t for t in types_present)
        has_mesh = any('mesh' in t for t in types_present)
        
        if has_map and has_mesh:
            score += 25
            parts.append("Session contains both volumetric map and contoured mesh.")
        elif has_map:
            score += 10
            parts.append("Session contains volumetric map, but NO contoured mesh.")
        elif has_mesh:
            score += 10
            parts.append("Session contains contoured mesh, but NO raw volumetric map.")
        else:
            parts.append("Session lacks volumetric map and mesh objects.")
            
        # Look for MTX ligand
        mtx_atoms = inspection.get('mtx_atoms', 0)
        if mtx_atoms > 0:
            score += 10
            parts.append("MTX ligand is present in the session structure.")
        else:
            parts.append("MTX ligand is missing from the session structure.")
    else:
        parts.append("Failed to programmatically load and inspect the PyMOL session file.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }