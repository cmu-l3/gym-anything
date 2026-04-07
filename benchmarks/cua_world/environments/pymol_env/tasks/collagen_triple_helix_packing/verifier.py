#!/usr/bin/env python3
"""
Verifier for the Collagen Triple Helix Packing Analysis task (PDB:1BKV).

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  15 pts - Report file exists and contains meaningful content (>20 chars)
  20 pts - Report correctly identifies the modeled Glycine count (~30)
  20 pts - Report correctly identifies the modeled Hydroxyproline count (~30)
  20 pts - Report contains an inter-chain Gly-Gly C-alpha distance in the
           physically plausible range for collagen packing (4.0 - 6.0 Angstroms)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing image files
  - Distance range constraint: rules out arbitrary distance measurements
  - Regex contexts: verifies values are associated with specific names (Gly, Hyp) to avoid false positives
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_collagen_triple_helix_packing(traj, env_info, task_info):
    """Verify the Collagen Triple Helix Analysis task results."""
    
    # CRITICAL: Always use copy_from_env to read results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/collagen_result.json')

    # Copy the result JSON from the container environment safely
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
        parts.append(f"Collagen figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/collagen_core.png")

    # --- Criterion 2: Report existence (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')

    if report_exists and len(report_content.strip()) >= 20:
        score += 15
        parts.append(f"Report file exists ({len(report_content)} chars)")
    elif report_exists:
        score += 5
        parts.append(f"Report file exists but nearly empty ({len(report_content)} chars)")
    else:
        parts.append("Report not found at /home/ga/PyMOL_Data/collagen_report.txt")

    # --- Criterion 3: GLY Count (20 pts) ---
    # Due to missing atoms/disordered terminal residues, we allow ranges 27-30
    if report_exists:
        gly_lines = [l for l in report_content.lower().splitlines() if 'gly' in l]
        gly_found = False
        
        for line in gly_lines:
            nums = re.findall(r'\b(2[7-9]|30)\b', line)
            if nums:
                gly_found = True
                break
        
        if gly_found:
            score += 20
            parts.append("Correct Glycine count identified (\u224830)")
        else:
            # Fallback for poorly formatted text without clear context
            if re.search(r'\b(2[7-9]|30)\b', report_content):
                score += 10
                parts.append("Found number \u224830 in report, but not clearly linked to Glycine")
            else:
                parts.append("Correct Glycine count (\u224830) not found in report")

    # --- Criterion 4: HYP Count (20 pts) ---
    if report_exists:
        hyp_lines = [l for l in report_content.lower().splitlines() if 'hyp' in l or 'hydroxyproline' in l]
        hyp_found = False
        
        for line in hyp_lines:
            nums = re.findall(r'\b(2[7-9]|30)\b', line)
            if nums:
                hyp_found = True
                break
        
        if hyp_found:
            score += 20
            parts.append("Correct Hydroxyproline count identified (\u224830)")
        else:
            if not gly_found and re.search(r'\b(2[7-9]|30)\b', report_content):
                score += 10
                parts.append("Found number \u224830 in report, but not clearly linked to Hydroxyproline")
            else:
                parts.append("Correct Hydroxyproline count (\u224830) not found in report")

    # --- Criterion 5: Distance check (20 pts) ---
    if report_exists:
        dist_min = metadata.get('distance_min', 4.0)
        dist_max = metadata.get('distance_max', 6.0)
        
        # Get all decimals and potential explicit integer distance numbers
        all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
        all_ints = [float(n) for n in re.findall(r'\b([456])\b', report_content)]
        all_numbers = all_decimals + all_ints
        
        valid_distances = [d for d in all_numbers if dist_min <= d <= dist_max]
        
        if valid_distances:
            score += 20
            parts.append(f"Gly-Gly distance reported: {valid_distances[0]:.2f} \u00c5 (valid range {dist_min}\u2013{dist_max} \u00c5)")
        else:
            parts.append(f"No distance value found in the valid inter-chain core packing range ({dist_min}\u2013{dist_max} \u00c5)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }