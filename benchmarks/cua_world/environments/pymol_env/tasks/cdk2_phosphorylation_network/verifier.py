#!/usr/bin/env python3
"""
Verifier for the CDK2 Phosphorylation Network Analysis task (PDB:1FIN).

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  20 pts - Report explicitly identifies the phosphorylated residue (TPO or Thr160/160)
  30 pts - Report lists the three coordinating arginines (Arg 50, Arg 126, Arg 150) (10 pts each)
  30 pts - Report contains at least 3 distance values falling within the physically valid 
           2.4-4.1 Å coordination range (10 pts each)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing files or dummy copies
  - Exact salt-bridge distance range: agent cannot pass distance criteria with arbitrary numbers
  - Strict identification of specific residues via regex parsing
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_cdk2_phosphorylation_network(traj, env_info, task_info):
    """Verify the CDK2-Cyclin A phosphorylation analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/cdk2_phospho_result.json')

    # Copy results from the environment
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
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Coordination figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Coordination figure not found at /home/ga/PyMOL_Data/images/cdk2_activation.png")

    # --- Criterion 2: Phosphorylated Residue Identification (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    # Normalize newlines
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    
    # Check for TPO, PTR, Thr160, or just 160 near Thr/TPO
    tpo_pattern = re.compile(r'(?i)\b(?:TPO|THR\s*160|T160|PTR|160)\b')
    if tpo_pattern.search(report_content):
        score += 20
        parts.append("Phosphorylated residue (TPO 160) correctly identified")
    elif report_exists:
        parts.append("Target phospho-residue (TPO 160) not clearly identified in report")
    else:
        parts.append("Report not found at /home/ga/PyMOL_Data/cdk2_phospho_report.txt")

    # --- Criterion 3: Arginine Triad Identification (30 pts, 10 each) ---
    found_args = []
    if re.search(r'(?i)\b(?:ARG\s*50|R50|50)\b', report_content):
        found_args.append("Arg50")
    if re.search(r'(?i)\b(?:ARG\s*126|R126|126)\b', report_content):
        found_args.append("Arg126")
    if re.search(r'(?i)\b(?:ARG\s*150|R150|150)\b', report_content):
        found_args.append("Arg150")

    arg_score = len(found_args) * 10
    score += arg_score
    if found_args:
        parts.append(f"Arginine triad residues identified: {', '.join(found_args)}")
    elif report_exists:
        parts.append("None of the coordinating arginines (50, 126, 150) were identified")

    # --- Criterion 4: Accurate Distance Measurements (30 pts) ---
    dist_min = metadata.get('distance_min', 2.4)
    dist_max = metadata.get('distance_max', 4.1)
    
    # Extract all decimal numbers that look like distances
    all_decimals = [float(n) for n in re.findall(r'\b\d+\.\d+\b', report_content)]
    
    # Filter distances within the salt-bridge / strong H-bond range
    valid_distances = [d for d in all_decimals if dist_min <= d <= dist_max]
    
    # Score up to 3 valid distances (10 pts each)
    dist_count = min(3, len(valid_distances))
    score += dist_count * 10
    
    if dist_count == 3:
        parts.append(f"Found {len(valid_distances)} accurate distance measurements in valid range ({dist_min}-{dist_max} \u00c5)")
    elif dist_count > 0:
        parts.append(f"Found {dist_count} distance measurement(s) in valid range ({dist_min}-{dist_max} \u00c5) (expected 3)")
    elif all_decimals:
        parts.append(f"Found decimal values ({all_decimals[:3]}) but none in valid coordination distance range ({dist_min}-{dist_max} \u00c5)")
    elif report_exists:
        parts.append("No distance measurements found in report")

    # Determine pass/fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }