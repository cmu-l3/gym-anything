#!/usr/bin/env python3
"""
Verifier for the GFP Chromophore Environment Analysis task (PDB:1GFL).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  20 pts - Report exists and contains >= 8 lines of content
  30 pts - Report contains >= 6 distinct valid residue numbers (1-238) and <= 35 
           (to prevent dumping the entire sequence)
  25 pts - Report identifies >= 2 of the critical H-bond network residues for the 
           chromophore: 96 (Arg96), 148 (His148), 222 (Glu222)

Pass threshold: 70/100

Anti-gaming checks:
  - figure_is_new gate rules out pre-existing file copying
  - Upper limit on distinct residues ensures the agent actually filtered for local contacts
    rather than listing all residues in the entire protein.
  - Key H-bond residues (96, 148, 222) are deeply buried and specific to the CRO pocket,
    making simple generic templated lists fail.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_gfp_chromophore_environment(traj, env_info, task_info):
    """Verify the GFP chromophore environment analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/gfp_chromophore_result.json')

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
        parts.append(f"GFP chromophore figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("GFP chromophore figure not found at expected path")

    # --- Criterion 2: Report content length (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    
    lines = [line.strip() for line in report_content.splitlines() if line.strip()]
    min_lines = metadata.get('min_report_lines', 8)

    if report_exists and len(lines) >= min_lines:
        score += 20
        parts.append(f"Report contains sufficient content ({len(lines)} lines)")
    elif report_exists and len(lines) > 0:
        score += 10
        parts.append(f"Report exists but is too brief ({len(lines)} lines, need >= {min_lines})")
    else:
        parts.append("Report not found or empty")

    # --- Criterion 3: Distinct valid residue numbers (30 pts) ---
    # GFP is 238 residues. Extract integers in that range.
    all_numbers = re.findall(r'\b(\d{1,3})\b', report_content)
    residue_candidates = set(int(n) for n in all_numbers if 1 <= int(n) <= 238)
    
    min_distinct = metadata.get('min_distinct_residues', 6)
    max_distinct = metadata.get('max_distinct_residues', 35)

    # Exclude 66 (the chromophore itself) from being the only entity counting towards contacts
    if 66 in residue_candidates:
        contact_candidates = residue_candidates - {66}
    else:
        contact_candidates = residue_candidates

    if min_distinct <= len(contact_candidates) <= max_distinct:
        score += 30
        parts.append(f"Report contains {len(contact_candidates)} reasonable contact residue numbers")
    elif len(contact_candidates) > max_distinct:
        score += 5
        parts.append(f"Report lists too many residues ({len(contact_candidates)}). Contact filtering failed.")
    elif len(contact_candidates) > 0:
        score += 10
        parts.append(f"Report contains only {len(contact_candidates)} contact residue numbers (need >= {min_distinct})")
    else:
        parts.append("Report contains no valid protein contact residue numbers")

    # --- Criterion 4: Key H-bond network residues (25 pts) ---
    # Key residues for GFP fluorescence: R96, H148, E222
    key_residues = metadata.get('key_residues', [96, 148, 222])
    found_key_residues = [r for r in key_residues if r in residue_candidates]

    if len(found_key_residues) >= 2:
        score += 25
        parts.append(f"Identified >= 2 key chromophore H-bond residues (found: {found_key_residues})")
    elif len(found_key_residues) == 1:
        score += 10
        parts.append(f"Identified only 1 key chromophore H-bond residue (found: {found_key_residues})")
    else:
        parts.append("Did not identify the critical H-bond residues (R96, H148, E222)")

    # Complete Pass logic
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }