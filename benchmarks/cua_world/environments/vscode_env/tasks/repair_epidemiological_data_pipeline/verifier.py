#!/usr/bin/env python3
"""
Verifier for the repair_epidemiological_data_pipeline task.

Checks whether the agent identified and fixed 5 data processing bugs
in the Python pipeline files.

Each fix is worth 20 points (total 100). Pass threshold: 60.
"""

import sys
import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_date_parsing_bug(src):
    """
    Bug 1 -- Date Scrambling (data_loader.py)
    Original: df['date'] = pd.to_datetime(df['date'])
    Fix: pd.to_datetime(df['date'], dayfirst=True) OR format='%d/%m/%Y'
    """
    if not src:
        return False, "data_loader.py is missing or empty."

    # Valid fixes
    has_dayfirst = bool(re.search(r'dayfirst\s*=\s*True', src, re.IGNORECASE))
    has_format = bool(re.search(r'format\s*=\s*[\'"]%d/%m/%Y[\'"]', src))
    
    if has_dayfirst or has_format:
        return True, "data_loader.py correctly parses European date formats (dayfirst/format)."
        
    # See if they wrote a custom lambda/apply
    has_strptime = bool(re.search(r'strptime', src))
    if has_strptime:
        return True, "data_loader.py appears to use strptime to parse dates correctly."

    return False, "data_loader.py still uses naive pd.to_datetime() without dayfirst=True or format."


def check_missing_data_bug(src):
    """
    Bug 2 -- Missing Early Data (data_loader.py)
    Original: df = df.dropna()
    Fix: df.dropna(subset=['cumulative_cases']) OR df[df['cumulative_cases'].notna()]
    Or removing dropna completely.
    """
    if not src:
        return False, "data_loader.py is missing or empty."

    # Did they leave the original blind dropna()?
    blind_dropna = bool(re.search(r'df\s*=\s*df\.dropna\(\s*\)', src))
    
    if blind_dropna:
        return False, "data_loader.py still drops rows blindly using df.dropna()."

    has_subset = bool(re.search(r'dropna\s*\(\s*subset\s*=', src))
    has_notna = bool(re.search(r'notna\(\)', src) or re.search(r'notnull\(\)', src))
    
    if has_subset or has_notna:
        return True, "data_loader.py correctly targets missing data dropping (using subset or notna)."

    # If dropna is gone completely, it's also fixed
    has_dropna_at_all = bool(re.search(r'dropna', src))
    if not has_dropna_at_all:
        return True, "data_loader.py no longer drops missing data rows."

    return False, "data_loader.py missing data handling could not be verified."


def check_daily_incident_bug(src):
    """
    Bug 3 -- Staircase Daily Cases / Cross-region bleeding (metrics.py)
    Original: df['cumulative_cases'].diff()
    Fix: df.groupby('region')['cumulative_cases'].diff()
    """
    if not src:
        return False, "metrics.py is missing or empty."

    # Look for groupby followed by diff
    has_groupby_diff = bool(
        re.search(r'groupby\s*\([\'"]region[\'"]\).*diff\(\)', src) or 
        re.search(r'groupby\s*\(\s*\[[\'"]region[\'"]\]\s*\).*diff\(\)', src)
    )

    if has_groupby_diff:
        return True, "metrics.py correctly calculates daily cases within region groupings."

    # Check for manual looping
    has_loop_diff = bool(re.search(r'for.*groupby', src) and re.search(r'diff\(\)', src))
    if has_loop_diff:
        return True, "metrics.py calculates diff using a loop over groups."

    return False, "metrics.py still calculates diff() globally across all regions."


def check_population_rate_bug(src):
    """
    Bug 4 -- Microscopic Rates (metrics.py)
    Original: ... * 1000
    Fix: ... * 100000 (or 100_000, 1e5)
    """
    if not src:
        return False, "metrics.py is missing or empty."

    # They should multiply by 100,000
    has_100k = bool(re.search(r'\*\s*100000\b', src) or 
                    re.search(r'\*\s*100_000\b', src) or 
                    re.search(r'\*\s*1e5\b', src, re.IGNORECASE) or
                    re.search(r'\*\s*10\*\*5\b', src))

    has_1k = bool(re.search(r'\*\s*1000\b', src) and not re.search(r'\*\s*100000\b', src))

    if has_100k:
        return True, "metrics.py correctly multiplies by 100,000 for population rates."
        
    if has_1k:
        return False, "metrics.py still multiplies by 1,000 instead of 100,000."

    return False, "metrics.py population scaling multiplier is missing or incorrect."


def check_rolling_average_bug(src):
    """
    Bug 5 -- Chaotic Rolling Averages (metrics.py)
    Original: df.groupby('region')['daily_cases'].transform(lambda x: x.rolling(window...).mean())
    Fix: Needs sort_values('date') before or during rolling calculation.
    """
    if not src:
        return False, "metrics.py is missing or empty."

    # Check for sort_values inside the calculate_rolling_averages function
    # Extract function block
    func_block = ""
    in_func = False
    for line in src.split('\n'):
        if line.startswith('def calculate_rolling_averages'):
            in_func = True
        elif in_func and line.startswith('def '):
            break
        if in_func:
            func_block += line + '\n'

    has_sort = bool(re.search(r'sort_values', func_block))
    has_sort_date = bool(re.search(r'sort_values\s*\([^)]*[\'"]date[\'"]', func_block))

    if has_sort or has_sort_date:
        return True, "metrics.py explicitly sorts by date for rolling averages."

    return False, "metrics.py does not sort data chronologically before calculating rolling averages."


def verify_pipeline_repair(traj, env_info, task_info):
    """
    Main verification logic.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='epi_verify_')
    local_result = os.path.join(temp_dir, "epidemiological_result.json")

    try:
        try:
            copy_from_env("/tmp/epidemiological_result.json", local_result)
        except Exception as e:
            logger.error(f"Failed to copy result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access exported result file: {str(e)}"
            }

        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found or empty"
            }

        with open(local_result, 'r', encoding='utf-8') as f:
            file_contents = json.load(f)

        score = 0
        feedback = []
        
        data_loader_src = file_contents.get("pipeline/data_loader.py", "")
        metrics_src = file_contents.get("pipeline/metrics.py", "")

        # Check 1
        c1, m1 = check_date_parsing_bug(data_loader_src)
        if c1: score += 20
        feedback.append(f"[{'+' if c1 else '-'}] Bug 1: {m1}")

        # Check 2
        c2, m2 = check_missing_data_bug(data_loader_src)
        if c2: score += 20
        feedback.append(f"[{'+' if c2 else '-'}] Bug 2: {m2}")

        # Check 3
        c3, m3 = check_daily_incident_bug(metrics_src)
        if c3: score += 20
        feedback.append(f"[{'+' if c3 else '-'}] Bug 3: {m3}")

        # Check 4
        c4, m4 = check_population_rate_bug(metrics_src)
        if c4: score += 20
        feedback.append(f"[{'+' if c4 else '-'}] Bug 4: {m4}")

        # Check 5
        c5, m5 = check_rolling_average_bug(metrics_src)
        if c5: score += 20
        feedback.append(f"[{'+' if c5 else '-'}] Bug 5: {m5}")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback),
            "subscores": {
                "date_parsing": c1,
                "missing_data": c2,
                "daily_incident": c3,
                "population_rate": c4,
                "rolling_sorting": c5
            }
        }
    finally:
        if os.path.exists(local_result):
            os.unlink(local_result)
        os.rmdir(temp_dir)