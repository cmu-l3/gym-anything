#!/usr/bin/env python3
"""
Verifier for the Antibody-Antigen Interface Mapping task (PDB:1DVF).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new, and is non-trivial (>30KB)
  20 pts - Interface report contains ≥3 explicit contact pairs in chain:residue notation
           involving BOTH antibody (A or B) AND antigen (C) chains
  35 pts - Report identifies ≥4 epitope residues from chain C (lysozyme) matching the
           known D1.3/HEL epitope: 18, 21, 22, 43, 45, 96–99, 116–120
  20 pts - Report mentions a total contact count (any integer 5–200 adjacent to "contact",
           "interaction", "pair", "residue", or "atom")

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - Epitope check (35 pts) is the heaviest criterion — without ≥4 known epitope residues
    the max score is 25+20+0+20=65 < 70, so correct epitope identification is mandatory.
  - Contact pair chain check: requires C-chain involvement — A:45--B:91 antibody-only pairs fail.
  - Known epitope residues: fabricated or wrong-protein residue lists will miss the 9+ residues
    in the known epitope set {18,21,22,43,45,96,97,98,99,116,117,118,119,120}.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known D1.3/lysozyme epitope residues in chain C (from literature)
KNOWN_EPITOPE = {18, 21, 22, 43, 45, 96, 97, 98, 99, 116, 117, 118, 119, 120}


def verify_antibody_antigen_interface_mapping(traj, env_info, task_info):
    """Verify the D1.3 antibody – lysozyme interface mapping task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/dvf_interface_result.json')

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
        parts.append(f"Interface figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Interface figure not found at /home/ga/PyMOL_Data/images/dvf_interface.png")

    # --- Criterion 2: ≥3 explicit contact pairs involving antigen chain C (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    # Pattern: single chain letter [A/B/C] followed by optional separator then 1-3 digit residue
    chain_res_pattern = re.compile(r'\b([ABC])[\s:_-]?(\d{1,3})\b')
    contact_pair_pattern = re.compile(
        r'([ABC])[\s:_-]?(\d{1,3})\s*[-\u2013\u2014:,\s]+([ABC])[\s:_-]?(\d{1,3})',
        re.IGNORECASE
    )

    contact_pairs = contact_pair_pattern.findall(report_content)
    # Filter: pairs must involve both antibody (A or B) and antigen (C) chains
    valid_pairs = [
        p for p in contact_pairs
        if ('C' in (p[0].upper(), p[2].upper()) and
            (p[0].upper() in ('A', 'B') or p[2].upper() in ('A', 'B')))
    ]
    min_contacts = metadata.get('min_contacts_reported', 3)

    if len(valid_pairs) >= min_contacts:
        score += 20
        parts.append(f"{len(valid_pairs)} antibody\u2013antigen contact pairs documented")
    elif len(valid_pairs) >= 1:
        score += 8
        parts.append(
            f"Only {len(valid_pairs)} explicit contact pair(s) found "
            f"(need \u2265{min_contacts})"
        )
    elif report_exists and len(report_content.strip()) > 20:
        parts.append(
            "Report exists but lacks explicit chain:residue contact pairs "
            "(format: e.g., 'A:45 -- C:97')"
        )
    else:
        parts.append("Interface report not found or empty at /home/ga/PyMOL_Data/dvf_interface_report.txt")

    # --- Criterion 3: ≥4 known epitope residues from chain C (35 pts) ---
    # Extract all chain C residue numbers from report
    chain_c_residues = set()
    for m in chain_res_pattern.finditer(report_content):
        if m.group(1).upper() == 'C':
            chain_c_residues.add(int(m.group(2)))
    # Also check plain numbers that match known epitope (fallback if chain label absent)
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content)
                      if 1 <= int(n) <= 130)
    chain_c_known = chain_c_residues & KNOWN_EPITOPE
    all_known = all_numbers & KNOWN_EPITOPE
    found_epitope = chain_c_known if chain_c_known else all_known

    min_epitope = metadata.get('min_epitope_residues', 4)

    if len(found_epitope) >= min_epitope:
        score += 35
        parts.append(
            f"Epitope mapped: {len(found_epitope)} known epitope residues identified "
            f"(e.g., {sorted(found_epitope)[:4]})"
        )
    elif len(found_epitope) >= 2:
        score += 14
        parts.append(
            f"Partial epitope: only {len(found_epitope)} known epitope residues found "
            f"(need \u2265{min_epitope}; known epitope includes 18,21,22,43,45,96-99,116-120)"
        )
    else:
        parts.append(
            "Insufficient epitope residues identified — "
            "lysozyme epitope includes residues 18, 21, 22, 43, 45, 96\u201399, 116\u2013120"
        )

    # --- Criterion 4: Total contact count mentioned (20 pts) ---
    count_patterns = re.findall(
        r'(\d+)\s*(?:contact|interaction|pair|residue|atom)',
        report_content, re.IGNORECASE
    )
    plausible_counts = [int(n) for n in count_patterns if 5 <= int(n) <= 200]

    if plausible_counts:
        score += 20
        parts.append(f"Interface contact count reported: {plausible_counts[0]} contacts")
    else:
        parts.append(
            "No interface contact count found in report — "
            "report should state total number of contacts (expected ~15\u201330 at 4 \u00c5 cutoff)"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }
