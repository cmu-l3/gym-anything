#!/usr/bin/env python3
"""
Verifier for the fix_exoplanet_transit_pipeline task.

Checks whether the agent identified and fixed 5 mathematical bugs
in the astronomical time-series processing pipeline.

Scoring (Total 100):
- 15 points per code fix (Regex/AST validation of source) x 5 = 75 points
- 25 points for end-to-end integration (JSON output contains correct astrophysical values)
Pass threshold: 70
"""

import sys
import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_exoplanet_pipeline(traj, env_info, task_info):
    """
    Verify that the exoplanet pipeline bugs were fixed and the data runs correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_period_min = metadata.get('expected_period_min', 3.50)
    expected_period_max = metadata.get('expected_period_max', 3.55)
    expected_depth_min = metadata.get('expected_depth_min', 8500)
    expected_depth_max = metadata.get('expected_depth_max', 11500)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/exoplanet_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    files = result.get("files", {})
    score = 0
    feedback_parts = []

    # ────────────────────────────────────────────────────────
    # 1. Bug Fix Checks (15 points each)
    # ────────────────────────────────────────────────────────

    # Bug 1: data_loader.py (Normalization)
    dl_src = files.get("pipeline/data_loader.py", "")
    if dl_src and not dl_src.startswith("ERROR"):
        still_buggy = bool(re.search(r'median\s*\(\s*df\[[\'"]flux_err[\'"]\]\s*\)', dl_src))
        has_fix = bool(re.search(r'median\s*\(\s*df\[[\'"]flux[\'"]\]\s*\)', dl_src))
        if has_fix and not still_buggy:
            score += 15
            feedback_parts.append("[+] data_loader.py: Normalizes by median flux.")
        else:
            feedback_parts.append("[-] data_loader.py: Still uses flux_err for normalization.")
    else:
        feedback_parts.append("[-] data_loader.py not found.")

    # Bug 2: detrender.py (Odd window length)
    det_src = files.get("pipeline/detrender.py", "")
    if det_src and not det_src.startswith("ERROR"):
        # Check if they enforced odd integer: + 1, | 1, or conditional % 2
        has_fix = bool(
            re.search(r'window_length\s*\+\s*1', det_src) or
            re.search(r'window_length\s*\|\s*1', det_src) or
            re.search(r'%\s*2\s*==\s*0', det_src)
        )
        if has_fix:
            score += 15
            feedback_parts.append("[+] detrender.py: Enforces odd window length for Savgol filter.")
        else:
            feedback_parts.append("[-] detrender.py: Fails to guarantee odd window length.")
    else:
        feedback_parts.append("[-] detrender.py not found.")

    # Bug 3: outlier_rejection.py (Preserve negative dips)
    out_src = files.get("pipeline/outlier_rejection.py", "")
    if out_src and not out_src.startswith("ERROR"):
        # The bug is using np.abs(). We ensure np.abs() or abs() is removed from the mask condition.
        still_buggy = bool(re.search(r'(?:np\.)?abs\s*\(\s*flux\s*-\s*trend\s*\)', out_src))
        if not still_buggy and "flux - trend" in out_src:
            score += 15
            feedback_parts.append("[+] outlier_rejection.py: Removed abs(), preserves transits.")
        else:
            feedback_parts.append("[-] outlier_rejection.py: Still uses abs(), destroying transits.")
    else:
        feedback_parts.append("[-] outlier_rejection.py not found.")

    # Bug 4: transit_search.py (Linear frequency grid)
    ts_src = files.get("pipeline/transit_search.py", "")
    if ts_src and not ts_src.startswith("ERROR"):
        # Fix expects calculating a frequency array, or dividing 1.0 by linspace
        has_fix = bool(
            re.search(r'1\.?0?\s*/\s*np\.linspace', ts_src) or
            re.search(r'1\.?0?\s*/\s*max_period', ts_src) or
            "freq" in ts_src.lower()
        )
        if has_fix:
            score += 15
            feedback_parts.append("[+] transit_search.py: Switched to linear frequency search grid.")
        else:
            feedback_parts.append("[-] transit_search.py: Still uses linear period grid.")
    else:
        feedback_parts.append("[-] transit_search.py not found.")

    # Bug 5: phase_folder.py (Subtract epoch)
    pf_src = files.get("pipeline/phase_folder.py", "")
    if pf_src and not pf_src.startswith("ERROR"):
        has_fix = bool(re.search(r'\(\s*time\s*-\s*t0\s*\)', pf_src))
        if has_fix:
            score += 15
            feedback_parts.append("[+] phase_folder.py: Correctly subtracts t0 for phase folding.")
        else:
            feedback_parts.append("[-] phase_folder.py: Fails to subtract t0.")
    else:
        feedback_parts.append("[-] phase_folder.py not found.")


    # ────────────────────────────────────────────────────────
    # 2. Pipeline Output Integration Check (25 points)
    # ────────────────────────────────────────────────────────
    
    json_output_str = files.get("results/planet_parameters.json", None)
    if json_output_str and not json_output_str.startswith("ERROR"):
        try:
            params = json.loads(json_output_str)
            period = params.get("period_days", 0)
            depth = params.get("transit_depth_ppm", 0)
            
            period_ok = expected_period_min <= period <= expected_period_max
            depth_ok = expected_depth_min <= depth <= expected_depth_max
            
            if period_ok and depth_ok:
                score += 25
                feedback_parts.append(f"[+] Integration: Kepler-8b detected! Period {period:.4f}d, Depth {depth}ppm.")
            else:
                feedback_parts.append(f"[-] Integration: Inaccurate detection. Got Period {period}d, Depth {depth}ppm.")
        except json.JSONDecodeError:
            feedback_parts.append("[-] Integration: results/planet_parameters.json is invalid JSON.")
    else:
        feedback_parts.append("[-] Integration: results/planet_parameters.json was not generated or missing.")

    # ────────────────────────────────────────────────────────
    # Final Result
    # ────────────────────────────────────────────────────────
    passed = score >= metadata.get('pass_threshold', 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }