#!/usr/bin/env python3
"""
Verifier for the PROTAC Ternary Complex Analysis task (PDB:5T35).

Scoring (100 points total):
  20 pts - Publication figure exists, is new (post-task-start), and >50KB
  10 pts - Plain text report exists with content
  20 pts - PROTAC ligand identifier (MZ1) is correctly documented in the report
  25 pts - Exact integer count of BRD4 neo-interface residues (chain D < 4.0A of chain A)
           matches the PyMOL-computed ground truth (±1 tolerance for atom indexing/hydrogen differences)
  25 pts - Exact integer count of BRD4 ligand-interface residues (chain D < 4.0A of MZ1)
           matches the PyMOL-computed ground truth (±1 tolerance)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - Precise matching of dynamically calculated ground truth from container API ensures
    the agent must actually perform the calculation instead of hallucinating.
  - Numbers in the report are parsed generically (all integers extracted); it is highly
    improbable to randomly guess two distinct double-digit residue counts.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_protac_ternary_complex_analysis(traj, env_info, task_info):
    """Verify the PROTAC ternary complex interface analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/protac_result.json')

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

    # --- Criterion 1: Publication figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 50000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Ternary complex figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/protac_complex.png")

    # --- Criterion 2 & 3: Report Exists (10 pts) and Mentions MZ1 (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and len(report_content.strip()) > 5:
        score += 10
        parts.append("Analysis report exists")
        
        if "MZ1" in report_content.upper():
            score += 20
            parts.append("PROTAC ligand (MZ1) identified in report")
        else:
            parts.append("PROTAC ligand identifier (MZ1) missing from report")
    else:
        parts.append("Report not found or empty at /home/ga/PyMOL_Data/protac_report.txt")

    # --- Criterion 4 & 5: Interface Counts (25 pts each) ---
    # Retrieve Ground Truth
    gt_neo = result.get("gt_neo_count", 16)
    gt_lig = result.get("gt_lig_count", 24)
    
    # Extract all integers from the report text to find matches
    # Excluding common numbers from prompt: 4 (from 4.0A distance)
    raw_nums = re.findall(r'\b\d+\b', report_content)
    candidate_nums = [int(n) for n in raw_nums if int(n) != 4]
    
    neo_match = False
    lig_match = False

    # Check for Neo-Interface Match (Tolerance ±1)
    for n in candidate_nums:
        if abs(n - gt_neo) <= 1:
            neo_match = True
            break
            
    if neo_match:
        score += 25
        parts.append(f"Accurate BRD4-VHL neo-interface residue count found (~{gt_neo})")
    elif candidate_nums:
        parts.append(f"Numbers extracted ({candidate_nums[:5]}...) do not match neo-interface ground truth ({gt_neo})")
    else:
        parts.append("No numeric residue counts found in report")

    # Check for Ligand-Interface Match (Tolerance ±1)
    for n in candidate_nums:
        if abs(n - gt_lig) <= 1:
            lig_match = True
            break
            
    if lig_match:
        score += 25
        parts.append(f"Accurate BRD4-MZ1 interface residue count found (~{gt_lig})")
    elif candidate_nums and not neo_match:
        parts.append(f"Numbers extracted do not match ligand-interface ground truth ({gt_lig})")
    elif candidate_nums:
        parts.append(f"Ligand interface count ({gt_lig}) missing from report")

    # Pass threshold evaluation
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }