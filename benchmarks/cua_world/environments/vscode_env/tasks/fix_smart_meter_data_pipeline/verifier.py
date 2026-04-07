#!/usr/bin/env python3
"""
Verifier for the fix_smart_meter_data_pipeline task.

Checks whether the agent identified and fixed 5 data engineering bugs
across the smart meter telemetry pipeline.

Each fix is worth 20 points (total 100). Pass threshold: 60.
"""

import os
import sys
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_smart_meter_pipeline(traj, env_info, task_info):
    """
    Verify that the agent found and fixed all 5 pipeline bugs.

    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='smart_meter_verify_')

    try:
        result_src = "/tmp/smart_meter_result.json"
        local_result = os.path.join(temp_dir, "smart_meter_result.json")

        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            logger.error(f"Failed to copy result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access result file: {str(e)}"
            }

        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found or empty"
            }

        with open(local_result, 'r') as f:
            file_contents = json.load(f)

        score = 0
        feedback = []

        # Extract contents safely
        def get_content(filename):
            data = file_contents.get(filename, {})
            if isinstance(data, dict):
                return data.get("content", "") or ""
            return ""

        dl_content = get_content("data_loader.py")
        cl_content = get_content("cleaner.py")
        ag_content = get_content("aggregator.py")
        tc_content = get_content("tariff_calculator.py")
        an_content = get_content("anomaly_detector.py")

        # ── Bug 1: Date Parsing (data_loader.py) ──────────
        if not dl_content:
            feedback.append("[-] data_loader.py: file missing or empty (0/20)")
        else:
            has_dayfirst = bool(re.search(r'dayfirst\s*=\s*True', dl_content))
            has_format = bool(re.search(r'format\s*=', dl_content))
            
            if has_dayfirst or has_format:
                score += 20
                feedback.append("[+] data_loader.py: Date parsing ambiguity fixed (20/20)")
            else:
                feedback.append("[-] data_loader.py: pd.to_datetime still lacks format or dayfirst=True (0/20)")

        # ── Bug 2: Missing Data Imputation (cleaner.py) ──────────
        if not cl_content:
            feedback.append("[-] cleaner.py: file missing or empty (0/20)")
        else:
            still_has_fillna_0 = bool(re.search(r'fillna\s*\(\s*0\.?0?\s*\)', cl_content))
            has_interpolate = bool(re.search(r'interpolate\s*\(', cl_content))
            has_ffill = bool(re.search(r'ffill\s*\(', cl_content) or re.search(r'method\s*=\s*[\'"]f?fill[\'"]', cl_content))
            has_bfill = bool(re.search(r'bfill\s*\(', cl_content) or re.search(r'method\s*=\s*[\'"]bfill[\'"]', cl_content))
            
            if (has_interpolate or has_ffill or has_bfill) and not still_has_fillna_0:
                score += 20
                feedback.append("[+] cleaner.py: Imputation correctly uses interpolation or forward-fill (20/20)")
            elif not still_has_fillna_0:
                score += 10
                feedback.append("[~] cleaner.py: fillna(0) removed, but standard time-series imputation not clearly used (10/20)")
            else:
                feedback.append("[-] cleaner.py: Still uses fillna(0.0) which creates artificial drops (0/20)")

        # ── Bug 3: Power to Energy Conversion (aggregator.py) ──────────
        if not ag_content:
            feedback.append("[-] aggregator.py: file missing or empty (0/20)")
        else:
            has_mean = bool(re.search(r'resample\([^)]+\)\.mean\(\)', ag_content))
            has_div_60 = bool(re.search(r'/\s*60\.?0?', ag_content))
            still_has_sum = bool(re.search(r'resample\([^)]+\)\.sum\(\)', ag_content))
            
            if has_mean or (has_div_60 and still_has_sum):
                score += 20
                feedback.append("[+] aggregator.py: kW to kWh energy conversion fixed (20/20)")
            else:
                feedback.append("[-] aggregator.py: Still sums kW directly over an hour without conversion (0/20)")

        # ── Bug 4: Tariff Boundary Condition (tariff_calculator.py) ──────────
        if not tc_content:
            feedback.append("[-] tariff_calculator.py: file missing or empty (0/20)")
        else:
            still_has_le_20 = bool(re.search(r'<=\s*20', tc_content))
            has_lt_20 = bool(re.search(r'<\s*20', tc_content))
            has_le_19 = bool(re.search(r'<=\s*19', tc_content))
            has_isin = bool(re.search(r'isin\(\s*\[17,\s*18,\s*19\]\s*\)', tc_content))
            
            if (has_lt_20 or has_le_19 or has_isin) and not still_has_le_20:
                score += 20
                feedback.append("[+] tariff_calculator.py: Peak tariff boundary corrected (20/20)")
            else:
                feedback.append("[-] tariff_calculator.py: Peak tariff boundary still includes hour 20 (0/20)")

        # ── Bug 5: Rolling Anomaly Detection (anomaly_detector.py) ──────────
        if not an_content:
            feedback.append("[-] anomaly_detector.py: file missing or empty (0/20)")
        else:
            has_rolling = bool(re.search(r'rolling\s*\(', an_content))
            has_ewm = bool(re.search(r'ewm\s*\(', an_content))
            
            if has_rolling or has_ewm:
                score += 20
                feedback.append("[+] anomaly_detector.py: Adaptive rolling window applied for z-score (20/20)")
            else:
                feedback.append("[-] anomaly_detector.py: Still uses global mean/std ignoring seasonal drift (0/20)")

        passed = score >= task_info.get("metadata", {}).get("pass_threshold", 60)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)