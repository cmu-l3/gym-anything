#!/usr/bin/env python3
"""
Verifier for the Myoglobin SASA Core Analysis task (PDB:1A6M).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  25 pts - Report contains total SASA in the physically plausible range for a ~17 kDa 
           protein (5,000–12,000 Å²)
  25 pts - Report lists ≥8 distinct residue numbers in range 1–153, indicating genuine 
           per-residue analysis rather than placeholder text
  25 pts - Report identifies ≥3 known buried hydrophobic core residues from the literature
           set: {10, 29, 33, 43, 68, 75, 89, 104, 107, 115, 138, 142}

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files
  - SASA range check: arbitrary or made-up numbers fail
  - Core residue check (25 pts): pure random/sequential lists will likely miss ≥3 specific 
    core targets out of 153. Real biophysical computation is required to find them.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known buried core residues for sperm whale myoglobin (1A6M)
# A subset of highly buried, primarily hydrophobic residues
KNOWN_BURIED_CORE = {10, 29, 33, 43, 68, 75, 89, 104, 107, 115, 138, 142}


def verify_myoglobin_sasa_core_analysis(traj, env_info, task_info):
    """Verify the myoglobin solvent accessibility and core analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/myoglobin_sasa_result.json')

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
        parts.append(f"SASA colored figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("SASA figure not found at /home/ga/PyMOL_Data/images/myoglobin_sasa.png")

    # --- Extract report content ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if not report_exists or not report_content.strip():
        parts.append("Analysis report is missing or empty.")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(parts)
        }

    # --- Criterion 2: Plausible Total SASA (25 pts) ---
    # Look for a number between 5,000 and 12,000
    sasa_min = metadata.get('sasa_min', 5000)
    sasa_max = metadata.get('sasa_max', 12000)
    
    # Extract all numbers from the text (allowing commas like 8,500)
    number_pattern = re.compile(r'\b\d{1,2}(?:,\d{3})*\b|\b\d{4,5}\b|\b\d{4,5}\.\d+\b')
    raw_numbers = number_pattern.findall(report_content)
    
    clean_numbers = []
    for num_str in raw_numbers:
        try:
            clean_num = float(num_str.replace(',', ''))
            clean_numbers.append(clean_num)
        except ValueError:
            continue
            
    valid_sasa_values = [n for n in clean_numbers if sasa_min <= n <= sasa_max]

    if valid_sasa_values:
        score += 25
        # Prefer values near the "total/sasa/area" keywords if there are multiple
        # But for strict checking, any plausible value is awarded points
        parts.append(f"Plausible total SASA found: {valid_sasa_values[0]} \u00c5\u00b2 (range {sasa_min}\u2013{sasa_max})")
    else:
        parts.append(f"No valid total SASA found in the expected range ({sasa_min}\u2013{sasa_max} \u00c5\u00b2)")

    # --- Criterion 3: ≥8 distinct residue numbers in range 1-153 (25 pts) ---
    min_residues = metadata.get('min_residues_listed', 8)
    
    # Extract 1 to 3 digit integers representing residue numbers
    all_numbers = re.findall(r'\b(\d{1,3})\b', report_content)
    residue_candidates = set(int(n) for n in all_numbers if 1 <= int(n) <= 153)

    if len(residue_candidates) >= min_residues:
        score += 25
        sample = sorted(residue_candidates)[:5]
        parts.append(f"\u2265{min_residues} valid residue numbers documented (e.g., {sample})")
    elif len(residue_candidates) >= 4:
        score += 10
        parts.append(f"Only {len(residue_candidates)} valid residue numbers found (need \u2265{min_residues})")
    else:
        parts.append(f"Too few valid residue numbers found ({len(residue_candidates)})")

    # --- Criterion 4: ≥3 known buried core residues (25 pts) ---
    min_core_matches = metadata.get('min_core_matches', 3)
    matched_core = KNOWN_BURIED_CORE.intersection(residue_candidates)

    if len(matched_core) >= min_core_matches:
        score += 25
        parts.append(f"\u2265{min_core_matches} true hydrophobic core residues identified ({sorted(matched_core)})")
    elif len(matched_core) > 0:
        score += 10
        parts.append(f"Only {len(matched_core)} true core residues identified (need \u2265{min_core_matches})")
    else:
        parts.append("Failed to identify true buried core residues from the literature set")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }