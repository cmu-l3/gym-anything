#!/usr/bin/env python3
"""
Verifier for Nucleosome Histone-DNA Contact Analysis task (PDB:1AOI).

Scoring (100 points total):
  25 pts - Figure exists, is new (post-task-start), size > 40 KB
  25 pts - Report mentions all 4 histone types (H2A, H2B, H3, H4)
  25 pts - Report lists >=8 distinct residue numbers as contacts
  25 pts - Report contains >=3 Arg or Lys residues among contacts

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_nucleosome_histone_dna_contacts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/nucleosome_result.json')

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
    min_fig_size = metadata.get('min_figure_size_bytes', 40960)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/nucleosome_contacts.png")

    # --- Criterion 2: Mentions all 4 histone types (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').upper()
    
    if report_exists:
        has_h2a = "H2A" in report_content
        has_h2b = "H2B" in report_content
        has_h3 = "H3" in report_content
        has_h4 = "H4" in report_content
        
        histones_found = sum([has_h2a, has_h2b, has_h3, has_h4])
        if histones_found == 4:
            score += 25
            parts.append("All 4 histone types identified")
        elif histones_found > 0:
            score += 5 * histones_found
            parts.append(f"Only {histones_found}/4 histone types identified")
        else:
            parts.append("No histone types (H2A, H2B, H3, H4) identified in report")
    else:
        parts.append("Report not found at /home/ga/PyMOL_Data/nucleosome_report.txt")

    # --- Criterion 3: >=8 distinct residue numbers (25 pts) ---
    min_contacts = metadata.get('min_contact_residues', 8)
    if report_exists:
        # Residues in histones are typically 1-150
        all_numbers = re.findall(r'\b(\d{1,3})\b', report_content)
        residue_candidates = set(int(n) for n in all_numbers if 1 <= int(n) <= 150)
        
        if len(residue_candidates) >= min_contacts:
            score += 25
            parts.append(f"\u2265{min_contacts} distinct contact residues documented")
        elif len(residue_candidates) >= 1:
            score += 10
            parts.append(f"Only {len(residue_candidates)} contact residue(s) documented (need \u2265{min_contacts})")
        else:
            parts.append("No valid residue numbers found in report")

    # --- Criterion 4: >=3 Arg or Lys residues among contacts (25 pts) ---
    min_basic = metadata.get('min_arg_lys_residues', 3)
    if report_exists:
        # Match 3-letter codes ARG/LYS or 1-letter codes R/K followed by numbers
        arg_lys_3 = re.findall(r'\b(ARG|LYS)\b', report_content)
        arg_lys_1 = re.findall(r'\b[RK]\d{1,3}\b', report_content)
        basic_count = len(arg_lys_3) + len(arg_lys_1)
        
        if basic_count >= min_basic:
            score += 25
            parts.append("Basic residues (Arg/Lys) correctly identified in contacts")
        elif basic_count > 0:
            score += 10
            parts.append(f"Only {basic_count} basic residue(s) identified (need \u2265{min_basic})")
        else:
            parts.append("No basic residues (Arg/Lys) identified among contacts")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }