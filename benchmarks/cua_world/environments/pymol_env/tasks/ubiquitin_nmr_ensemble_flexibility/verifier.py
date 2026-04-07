#!/usr/bin/env python3
"""
Verifier for the Ubiquitin NMR Ensemble Conformational Flexibility Analysis task.

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new, and is non-trivial (>30KB)
  15 pts - Flexibility report exists and contains ≥8 lines of content
  25 pts - Report identifies the highly flexible C-terminal tail by containing 
           residue numbers 72, 73, 74, 75, or 76
  20 pts - Report contains at least 5 distinct residue numbers (integers in range 1-76),
           indicating genuine per-residue extraction
  15 pts - Report mentions the number "10" representing the 10 conformers/states in 1D3Z

Pass threshold: 60/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_ubiquitin_nmr_ensemble_flexibility(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/ubq_nmr_result.json')

    # Execute safe copy from container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found \u2014 export script may not have run"
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
        parts.append(f"Ensemble figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("Ensemble figure not found at expected path")

    # --- Criterion 2: Report lines (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    report_lines = [l.strip() for l in report_content.splitlines() if l.strip()]
    min_lines = metadata.get('min_report_lines', 8)

    if report_exists and len(report_lines) >= min_lines:
        score += 15
        parts.append(f"Flexibility report has {len(report_lines)} lines")
    elif report_exists and len(report_lines) >= 3:
        score += 7
        parts.append(f"Report has only {len(report_lines)} lines (need \u2265{min_lines})")
    elif report_exists:
        parts.append(f"Report file exists but has too few entries ({len(report_lines)} lines)")
    else:
        parts.append("Flexibility report not found at expected path")

    # --- Criterion 3: C-terminal residues (25 pts) ---
    # The hallmark of ubiquitin's NMR ensemble is extreme flexibility at the C-terminus (72-76)
    c_term_pattern = re.compile(r'\b(72|73|74|75|76)\b')
    if c_term_pattern.search(report_content):
        score += 25
        parts.append("C-terminal tail residues (72-76) correctly identified in report")
    elif report_exists:
        parts.append("C-terminal tail residues (72-76) missing from flexibility report")

    # --- Criterion 4: \u22655 distinct residue numbers (20 pts) ---
    all_numbers = re.findall(r'\b(\d{1,3})\b', report_content)
    # Ubiquitin has exactly 76 residues
    residue_candidates = set(int(n) for n in all_numbers if 1 <= int(n) <= 76)

    if len(residue_candidates) >= 5:
        score += 20
        sample = sorted(residue_candidates)[:5]
        parts.append(f"Report contains \u22655 valid residue numbers (e.g., {sample})")
    elif len(residue_candidates) >= 2:
        score += 10
        parts.append(f"Report contains only {len(residue_candidates)} valid residue numbers (need \u22655)")
    elif report_exists:
        parts.append("Report lacks explicit per-residue numbering")

    # --- Criterion 5: Mentions 10 conformers (15 pts) ---
    # Ensures the agent acknowledged this was an NMR model with exactly 10 states
    if re.search(r'\b10\b', report_content):
        score += 15
        parts.append("Report correctly identifies 10 states/conformers")
    elif report_exists:
        parts.append("Report does not mention the 10 conformers (missing number '10')")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }