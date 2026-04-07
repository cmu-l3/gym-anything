#!/usr/bin/env python3
"""
Verifier for the Biotin Electron Density Mesh Task.

Verification relies on parsing the `/tmp/biotin_mesh_result.json` which
incorporates a headless `pymol` script execution to definitively verify the 
volumetric data types inside the generated PyMOL session file.

Scoring (100 points total):
  - 20 pts: Publication PNG figure exists, is new, and is reasonably sized (>25KB).
  - 20 pts: PyMOL session (.pse) exists, is new, and >100KB (maps are large).
  - 15 pts: The PyMOL session contains an `object:map` (verifies fetch type=2fofc).
  - 25 pts: The PyMOL session contains an `object:mesh` (verifies isomesh generation).
  - 20 pts: The written report documents the correct PDB (1STP), Ligand (BTN), and 
            contains plausible numeric parameters for sigma and carve buffer.

Pass threshold: 70/100 (Cannot pass without generating the mesh object inside PyMOL)
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_biotin_electron_density_mesh(traj, env_info, task_info):
    """Verify the Biotin Electron Density Mesh task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/biotin_mesh_result.json')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, 
            "score": 0,
            "feedback": "Result file not found — export script may not have run."
        }
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not read result: {e}"
        }
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # --- Criterion 1: Rendered Figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 25000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure created correctly ({fig_size // 1024} KB).")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created.")
    elif fig_exists:
        parts.append(f"Figure exists but is too small ({fig_size} B).")
    else:
        parts.append("Figure not found at the expected path.")

    # --- Criterion 2: PyMOL Session File (20 pts) ---
    session_exists = result.get('session_exists', False)
    session_size = result.get('session_size_bytes', 0)
    session_is_new = result.get('session_is_new', False)
    min_session_size = metadata.get('min_session_size_bytes', 100000)

    if session_exists and session_is_new and session_size >= min_session_size:
        score += 20
        parts.append(f"Session file saved correctly ({session_size // 1024} KB).")
    elif session_exists and session_size >= min_session_size:
        score += 10
        parts.append(f"Session exists ({session_size // 1024} KB) but may not be newly created.")
    elif session_exists:
        parts.append(f"Session exists but is too small ({session_size} B).")
    else:
        parts.append("PyMOL session file not found.")

    # --- Criterion 3 & 4: Inspect PyMOL Objects (15 + 25 pts) ---
    session_data = result.get('session_data', {})
    has_map = session_data.get('has_map', False)
    has_mesh = session_data.get('has_mesh', False)

    if has_map:
        score += 15
        parts.append("Volumetric map object (2mFo-DFc) found in session.")
    else:
        parts.append("No map object found in session. Was `fetch 1stp, type=2fofc` executed?")

    if has_mesh:
        score += 25
        parts.append("Isomesh object found in session.")
    else:
        parts.append("No mesh object found in session. Isomesh generation failed or wasn't saved.")

    # --- Criterion 5: Parameter Report (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    
    if report_exists and len(report_content.strip()) > 10:
        report_score = 0
        
        # Check for target strings
        if '1stp' in report_content.lower():
            report_score += 5
        if 'btn' in report_content.lower() or 'biotin' in report_content.lower():
            report_score += 5
            
        # Check for plausible parameters (numbers between 0.5 and 5.0 cover both sigma and buffer)
        numbers = re.findall(r'\b\d+(?:\.\d+)?\b', report_content)
        valid_params = [float(n) for n in numbers if 0.5 <= float(n) <= 5.0]
        
        if len(valid_params) >= 2:
            report_score += 10
            parts.append(f"Report contains required identifiers and plausible parameters (e.g. {valid_params[:2]}).")
        elif len(valid_params) >= 1:
            report_score += 5
            parts.append(f"Report is missing some numeric parameters. Found: {valid_params}")
        else:
            parts.append("Report is missing the required numeric parameters (sigma and/or carve).")
            
        score += report_score
    else:
        parts.append("Density report file not found or is empty.")

    # --- Final Assessment ---
    passed = score >= 70 and has_mesh

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts),
        "details": {
            "figure_ok": fig_exists and fig_is_new,
            "session_ok": session_exists and session_is_new,
            "has_map": has_map,
            "has_mesh": has_mesh
        }
    }