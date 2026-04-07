#!/usr/bin/env python3
"""Verifier for microrna_structure_folding task."""

import json
import os
import re
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_microrna_structure_folding(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/microrna_task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON: {e}"
        }

    # 1. GenBank file exists & valid (15 pts)
    c1 = 0
    if result.get("gb_exists", False):
        if result.get("gb_valid", False):
            c1 = 15
            feedback_parts.append("Valid GenBank file created (+15)")
        else:
            c1 = 5
            feedback_parts.append("GenBank file created but format is invalid (+5)")
    else:
        feedback_parts.append("GenBank file MISSING (0)")
    score += c1
    subscores["gb_file_valid"] = c1

    # 2. Sequence completeness (15 pts)
    c2 = 0
    seq_count = result.get("gb_seq_count", 0)
    if seq_count >= 3:
        c2 = 15
        feedback_parts.append("All 3 sequences present in GenBank file (+15)")
    elif seq_count > 0:
        c2 = seq_count * 5
        feedback_parts.append(f"{seq_count}/3 sequences present (+{c2})")
    else:
        feedback_parts.append("Sequences missing from GenBank file (0)")
    score += c2
    subscores["gb_completeness"] = c2

    # 3. Structure annotations (20 pts)
    c3 = 0
    if result.get("gb_has_structure", False):
        c3 = 20
        feedback_parts.append("Structural annotations found in GenBank file (+20)")
    else:
        feedback_parts.append("No structural annotations found in GenBank file (0)")
    score += c3
    subscores["gb_structures"] = c3

    # 4. Report file created (10 pts)
    c4 = 0
    if result.get("report_exists", False):
        c4 = 10
        feedback_parts.append("Report file created (+10)")
    else:
        feedback_parts.append("Report file MISSING (0)")
    score += c4
    subscores["report_exists"] = c4

    # Process report content
    report_content = ""
    if result.get("report_exists", False):
        b64_content = result.get("report_content_b64", "")
        try:
            report_content = base64.b64decode(b64_content).decode("utf-8")
        except Exception:
            pass

    # 5. Valid MFE values (20 pts)
    c5 = 0
    # Looking for negative floating point numbers or integers, e.g. -33.50, -22.1, -40
    mfe_matches = re.findall(r'-\d+\.\d+|-\d+', report_content)
    if len(mfe_matches) >= 3:
        c5 = 20
        feedback_parts.append("Found 3+ negative MFE values in report (+20)")
    elif len(mfe_matches) > 0:
        c5 = len(mfe_matches) * 6
        feedback_parts.append(f"Found {len(mfe_matches)} negative MFE values in report (+{c5})")
    else:
        feedback_parts.append("No valid negative MFE values found in report (0)")
    score += c5
    subscores["mfe_values"] = c5

    # 6. Valid dot-bracket strings (20 pts)
    c6 = 0
    # Looking for strings that only contain (, ), and . and are at least 30 chars long
    dot_bracket_matches = re.findall(r'[().]{30,}', report_content)
    
    valid_db_count = 0
    found_lengths = set()
    for db in dot_bracket_matches:
        db_len = len(db)
        open_count = db.count('(')
        close_count = db.count(')')
        
        # Check if length matches one of the expected sequences (80, 64, 72)
        # Check if parentheses are balanced (RNA secondary structures must have balanced stems)
        if open_count == close_count and db_len in [64, 72, 80]:
            found_lengths.add(db_len)
            valid_db_count += 1
            
    if len(found_lengths) == 3:
        c6 = 20
        feedback_parts.append("Found 3 valid dot-bracket strings with correct lengths and balanced parens (+20)")
    elif len(found_lengths) > 0:
        c6 = len(found_lengths) * 6
        feedback_parts.append(f"Found {len(found_lengths)} valid dot-bracket strings (+{c6})")
    else:
        feedback_parts.append("No valid dot-bracket strings matching sequence lengths found (0)")
    score += c6
    subscores["dot_bracket"] = c6

    passed = score >= 70 and c1 > 0 and c6 > 0
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }