#!/usr/bin/env python3
"""
Verifier for the Calmodulin Domain Architecture via Contact Network Analysis task.

Scoring (100 points total):
  20 pts - Contact file exists and contains >= 100 long-range contacts
  10 pts - Contact pairs parsed are valid (in sequence range 1-148, sequence separation |i-j| > 12)
  15 pts - Domain report exists with >= 5 lines and includes structural biology keywords
  10 pts - Report documents a plausible total contact count (50-600)
  10 pts - Report correctly identifies the N-terminal/linker boundary (~residues 60-80)
  10 pts - Report correctly identifies the linker/C-terminal boundary (~residues 85-100)
  15 pts - Domain-colored publication figure exists, is newly created, and > 30KB
  10 pts - Comprehensive contact enumeration: contact list has >= 200 valid contacts

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_calmodulin_contact_network_analysis(traj, env_info, task_info):
    """Verify the calmodulin contact network analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/calmodulin_result.json')

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

    # --- Criterion 1 & 2 & 8: Contacts list file (20 + 10 + 10 pts) ---
    contacts_content = result.get('contacts_content', '')
    min_contacts = metadata.get('min_contacts', 100)
    
    valid_pairs = []
    # Parse each line for two valid residue integers
    for line in contacts_content.splitlines():
        tokens = line.split()
        ints = []
        for t in tokens:
            # Strip common punctuation
            t_clean = t.strip(',;:[]()')
            try:
                ints.append(int(t_clean))
            except ValueError:
                pass
        
        # We need at least two integers per line for a contact pair (res_i, res_j)
        if len(ints) >= 2:
            r1, r2 = ints[0], ints[1]
            # Check if within valid calmodulin residue range
            if 1 <= r1 <= 148 and 1 <= r2 <= 148:
                # Agent was asked to filter out |i - j| <= 12
                if abs(r1 - r2) > 12:
                    valid_pairs.append((r1, r2))

    num_valid = len(valid_pairs)
    if num_valid >= min_contacts:
        score += 20
        score += 10 # Data is from calmodulin and meets distance filter
        parts.append(f"Contact file has {num_valid} valid long-range contacts (>= {min_contacts})")
        if num_valid >= 200:
            score += 10
            parts.append("Comprehensive contact enumeration achieved (>= 200)")
    elif num_valid > 0:
        score += 10 # Give partial credit for valid formatting
        parts.append(f"Only {num_valid} valid long-range contacts found (needed {min_contacts})")
    else:
        parts.append("No valid intra-chain C\u03b1-C\u03b1 long-range contacts found in contacts file")

    # --- Criterion 3 & 4 & 5 & 6: Domain Report Analysis (15 + 10 + 10 + 10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').lower()
    report_lines = [l for l in report_content.splitlines() if l.strip()]

    # Structural keywords check
    keywords = ["n-terminal", "c-terminal", "linker", "helix", "lobe", "domain", "ef-hand"]
    has_keywords = any(kw in report_content for kw in keywords)

    if report_exists and len(report_lines) >= 5 and has_keywords:
        score += 15
        parts.append("Domain report has sufficient depth and structural terminology")
    elif report_exists:
        parts.append("Domain report lacks sufficient lines or structural keywords")

    # Strip floats so we don't accidentally match distances or coordinate values
    text_no_floats = re.sub(r'\d+\.\d+', '', report_content)
    nums_in_report = [int(x) for x in re.findall(r'\b\d+\b', text_no_floats)]

    count_bounds = metadata.get('plausible_contact_count', [50, 600])
    count_plausible = any(count_bounds[0] <= x <= count_bounds[1] for x in nums_in_report)
    if count_plausible:
        score += 10
        parts.append("Plausible contact count documented in report")
    else:
        parts.append("No plausible total contact count (50-600) found in report")

    b1_bounds = metadata.get('boundary_1_range', [60, 80])
    has_boundary_1 = any(b1_bounds[0] <= x <= b1_bounds[1] for x in nums_in_report)
    if has_boundary_1:
        score += 10
        parts.append("N-terminal/linker boundary correctly identified (~60-80)")
    else:
        parts.append("N-terminal/linker boundary missing from report")

    b2_bounds = metadata.get('boundary_2_range', [85, 100])
    has_boundary_2 = any(b2_bounds[0] <= x <= b2_bounds[1] for x in nums_in_report)
    if has_boundary_2:
        score += 10
        parts.append("Linker/C-terminal boundary correctly identified (~85-100)")
    else:
        parts.append("Linker/C-terminal boundary missing from report")

    # --- Criterion 7: Publication Figure (15 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Domain-colored figure created successfully ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 7
        parts.append(f"Figure exists ({fig_size // 1024} KB) but was not newly generated after task start")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/calmodulin_domains.png")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }