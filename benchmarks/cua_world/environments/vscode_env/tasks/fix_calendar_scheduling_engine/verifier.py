#!/usr/bin/env python3
"""
Verifier for the fix_calendar_scheduling_engine task.

Checks whether the agent identified and fixed 5 bugs in the Python scheduling engine.
Each fix is verified through source code structural/regex analysis to ensure
the logic is actually repaired.

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


def check_recurrence_fix(src):
    """
    Bug 1 -- Weekday mapping off-by-one (engine/recurrence.py)
    Original maps MO to 1, but python's weekday() treats Monday as 0.
    Fix options:
    - Change DAY_MAP values to 0-6
    - Use isoweekday() instead of weekday()
    - Add/subtract 1 in the evaluation logic
    """
    if not src:
        return False, "recurrence.py is missing or empty"

    # Fix Option A: DAY_MAP maps 'MO' to 0
    map_fixed = bool(re.search(r"['\"]MO['\"]\s*:\s*0", src))
    
    # Fix Option B: Uses isoweekday() instead of weekday()
    uses_isoweekday = bool(re.search(r'\.isoweekday\(\)', src))
    
    # Fix Option C: Math adjustment
    math_adjusted = bool(
        re.search(r'\.weekday\(\)\s*\+\s*1', src) or
        re.search(r'DAY_MAP\[.*\]\s*-\s*1', src)
    )

    if map_fixed or uses_isoweekday or math_adjusted:
        return True, "recurrence.py correctly aligns Python weekday to standard"

    # If none of the obvious fixes, check if the buggy mapping still exists
    buggy_map = bool(re.search(r"['\"]MO['\"]\s*:\s*1", src))
    still_uses_weekday = bool(re.search(r'\.weekday\(\)', src))
    
    if buggy_map and still_uses_weekday:
        return False, "recurrence.py still uses misaligned weekday() and 1-indexed DAY_MAP"

    return False, "recurrence.py weekday mapping bug could not be verified as fixed"


def check_timezone_fix(src):
    """
    Bug 2 -- timedelta(hours=24) shifts wall-clock (engine/timezone_handler.py)
    Original uses `dt + datetime.timedelta(hours=24)`.
    Fix: Use `datetime.timedelta(days=1)`. Python's native tz-aware datetime
    handles DST transitions correctly when adding a `days` timedelta.
    """
    if not src:
        return False, "timezone_handler.py is missing or empty"

    still_has_hours24 = bool(re.search(r'hours\s*=\s*24', src))
    has_days1 = bool(re.search(r'days\s*=\s*1', src))
    
    if still_has_hours24:
        return False, "timezone_handler.py still adds hours=24 (shifts wall-clock during DST)"
        
    if has_days1:
        return True, "timezone_handler.py correctly uses days=1 for wall-clock preservation"

    return False, "timezone_handler.py DST transition bug could not be verified as fixed"


def check_event_model_fix(src):
    """
    Bug 3 -- Inclusive all-day duration (engine/event_model.py)
    Original calculates duration as `(dtend - dtstart).days + 1`.
    Fix: Remove the `+ 1` because dtend is exclusive per RFC 5545.
    """
    if not src:
        return False, "event_model.py is missing or empty"

    still_has_plus_one = bool(re.search(r'\.days\s*\+\s*1', src))
    has_correct_diff = bool(re.search(r'dtend\s*-\s*.*dtstart\).*\.days', src))

    if still_has_plus_one:
        return False, "event_model.py still incorrectly adds 1 to the duration"
        
    if has_correct_diff and not still_has_plus_one:
        return True, "event_model.py correctly calculates exclusive end-date duration"

    return False, "event_model.py all-day duration bug could not be verified as fixed"


def check_conflict_detector_fix(src):
    """
    Bug 4 -- Inverted overlap logic (engine/conflict_detector.py)
    Original: `return (start_a >= end_b) or (start_b >= end_a)` (returns NO overlap)
    Fix: `start_a < end_b and start_b < end_a` OR `not (...)`
    """
    if not src:
        return False, "conflict_detector.py is missing or empty"

    # Pattern for the original bug (no "not" in front of it)
    bug_pattern = re.search(r'return\s*\(\s*start_a\s*>=\s*end_b\s*\)\s*or\s*\(\s*start_b\s*>=\s*end_a\s*\)', src)
    
    # Pattern for "not (NO overlap)"
    fix_not_pattern = bool(re.search(r'not\s*\(\s*\(?\s*start_a\s*>=\s*end_b', src))
    
    # Pattern for direct overlap logic: start_a < end_b and start_b < end_a
    fix_direct_pattern = bool(
        re.search(r'start_a\s*<\s*end_b', src) and 
        re.search(r'start_b\s*<\s*end_a', src) and
        re.search(r'and', src)
    )
    
    # Pattern for max/min logic
    fix_maxmin_pattern = bool(re.search(r'max\(.*\)\s*<\s*min\(.*\)', src))

    if fix_not_pattern or fix_direct_pattern or fix_maxmin_pattern:
        return True, "conflict_detector.py correctly identifies overlapping intervals"

    if bug_pattern:
        return False, "conflict_detector.py still returns the non-overlap condition"

    return False, "conflict_detector.py overlap logic could not be verified as fixed"


def check_ical_exporter_fix(src):
    """
    Bug 5 -- Wrong datetime format (engine/ical_exporter.py)
    Original uses `dt.isoformat()`
    Fix: Use `dt.strftime("%Y%m%dT%H%M%S")` or string replacement on isoformat to remove hyphens/colons.
    """
    if not src:
        return False, "ical_exporter.py is missing or empty"

    still_relies_solely_on_isoformat = bool(
        re.search(r'return\s+dt.*\.isoformat\(\)\s*\+?\s*["\']Z?["\']?$', src, re.MULTILINE)
    )
    
    uses_strftime = bool(re.search(r'strftime\([\'"][^\'"]*%Y%m%dT%H%M%S[^\'"]*[\'"]\)', src))
    uses_replace = bool(re.search(r'replace\([\'"]-[\'"],\s*[\'"][\'"]\)', src) and re.search(r'replace\([\'"]:[\'"],\s*[\'"][\'"]\)', src))

    if uses_strftime or uses_replace:
        return True, "ical_exporter.py correctly formats RFC 5545 datetimes (without hyphens/colons)"

    if still_relies_solely_on_isoformat:
        return False, "ical_exporter.py still incorrectly uses standard isoformat()"

    return False, "ical_exporter.py datetime formatting could not be verified as fixed"


def verify_calendar_engine(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='calendar_verify_')
    
    try:
        result_src = "/tmp/calendar_result.json"
        local_result = os.path.join(temp_dir, "calendar_result.json")

        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {"passed": False, "score": 0, "feedback": "Exported result file missing or empty."}

        with open(local_result, "r", encoding="utf-8") as f:
            file_contents = json.load(f)

        score = 0
        feedback_parts = []

        # 1. Recurrence
        r_passed, r_msg = check_recurrence_fix(file_contents.get("engine/recurrence.py"))
        if r_passed:
            score += 20
            feedback_parts.append(f"[+] {r_msg} (20/20)")
        else:
            feedback_parts.append(f"[-] {r_msg} (0/20)")

        # 2. Timezone
        tz_passed, tz_msg = check_timezone_fix(file_contents.get("engine/timezone_handler.py"))
        if tz_passed:
            score += 20
            feedback_parts.append(f"[+] {tz_msg} (20/20)")
        else:
            feedback_parts.append(f"[-] {tz_msg} (0/20)")

        # 3. Event Model
        em_passed, em_msg = check_event_model_fix(file_contents.get("engine/event_model.py"))
        if em_passed:
            score += 20
            feedback_parts.append(f"[+] {em_msg} (20/20)")
        else:
            feedback_parts.append(f"[-] {em_msg} (0/20)")

        # 4. Conflict Detector
        cd_passed, cd_msg = check_conflict_detector_fix(file_contents.get("engine/conflict_detector.py"))
        if cd_passed:
            score += 20
            feedback_parts.append(f"[+] {cd_msg} (20/20)")
        else:
            feedback_parts.append(f"[-] {cd_msg} (0/20)")

        # 5. iCal Exporter
        ic_passed, ic_msg = check_ical_exporter_fix(file_contents.get("engine/ical_exporter.py"))
        if ic_passed:
            score += 20
            feedback_parts.append(f"[+] {ic_msg} (20/20)")
        else:
            feedback_parts.append(f"[-] {ic_msg} (0/20)")

        pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
        passed = score >= pass_threshold

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }
        
    finally:
        # Cleanup
        for root, dirs, files in os.walk(temp_dir, topdown=False):
            for name in files:
                os.remove(os.path.join(root, name))
            for name in dirs:
                os.rmdir(os.path.join(root, name))
        os.rmdir(temp_dir)