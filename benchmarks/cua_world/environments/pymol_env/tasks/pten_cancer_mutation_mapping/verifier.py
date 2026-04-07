#!/usr/bin/env python3
"""
Verifier for the PTEN Cancer Mutation Mapping task (PDB:1D5R).

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new (post-task-start), and >40KB.
  10 pts - Structural report exists and contains ≥10 lines.
  30 pts - Domain mapping correctly identifies the 'Phosphatase' and 'C2' domains in the report
           and lists all 5 mutation residue numbers.
  40 pts - Distance measurements (10 pts each) correctly recorded for the 4 CA-CA distances
           from C124 to G129, R130, C211, and D331 (within ±1.0 Å of ground truth coordinates).

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_pten_cancer_mutation_mapping(traj, env_info, task_info):
    """Verify the PTEN Cancer Mutation Mapping task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/pten_mutation_result.json')
    gt_path = metadata.get('gt_json', '/tmp/pten_ground_truth.json')

    # Load result JSON
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env(result_path, tmp_res.name)
        with open(tmp_res.name, 'r') as f:
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
            os.unlink(tmp_res.name)
        except Exception:
            pass

    # Load ground truth distances JSON
    gt = {}
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_gt.close()
    try:
        copy_from_env(gt_path, tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
    finally:
        try:
            os.unlink(tmp_gt.name)
        except Exception:
            pass

    score = 0
    parts = []

    # --- Criterion 1: Publication figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 40000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/pten_mutations.png")

    # --- Criterion 2: Report Generation (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
    report_lines = [l.strip() for l in report_content.splitlines() if l.strip()]
    min_lines = metadata.get('min_report_lines', 10)

    if report_exists and len(report_lines) >= min_lines:
        score += 10
        parts.append(f"Report has {len(report_lines)} lines")
    elif report_exists and len(report_lines) > 0:
        score += 5
        parts.append(f"Report has only {len(report_lines)} lines (expected \u2265{min_lines})")
    else:
        parts.append("Report not found or empty at /home/ga/PyMOL_Data/pten_mutation_report.txt")

    # --- Criterion 3: Domain Mapping (30 pts) ---
    content_lower = report_content.lower()
    has_phosphatase = "phosphatase" in content_lower
    has_c2 = "c2" in content_lower
    
    missing_res = [r for r in [124, 129, 130, 211, 331] if str(r) not in content_lower]
    
    domain_score = 0
    if has_phosphatase and has_c2:
        domain_score += 15
        parts.append("Both Phosphatase and C2 domains mentioned")
    elif has_phosphatase or has_c2:
        domain_score += 7
        parts.append("Only one of Phosphatase/C2 domains mentioned")
    else:
        parts.append("Neither domain mentioned")
        
    if not missing_res:
        domain_score += 15
        parts.append("All 5 mutated residues mentioned in report")
    else:
        parts.append(f"Missing mentions for residues: {missing_res}")
        
    score += domain_score

    # --- Criterion 4: Distance Measurements (40 pts) ---
    dist_score = 0
    if not gt:
        parts.append("WARNING: Ground truth data missing, giving full distance points automatically.")
        dist_score = 40
    else:
        numbers = re.findall(r'\d+\.\d+', report_content)
        floats = [float(n) for n in numbers]
        
        for r_id in ['129', '130', '211', '331']:
            expected = gt.get(r_id)
            if expected:
                if any(abs(f - expected) <= 1.0 for f in floats):
                    dist_score += 10
                    parts.append(f"Distance C124-C{r_id} correct (~{expected:.1f} \u00c5)")
                else:
                    parts.append(f"Distance C124-C{r_id} incorrect/missing (expected ~{expected:.1f} \u00c5)")
            else:
                dist_score += 10
                
    score += dist_score

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }