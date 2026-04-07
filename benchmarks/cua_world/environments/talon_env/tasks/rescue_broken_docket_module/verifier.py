#!/usr/bin/env python3
"""
Verifier for rescue_broken_docket_module task.

A partially-built Talon module has bugs and missing functionality.
The agent must fix all bugs and complete the module.

Scoring breakdown:
  Bug fixes (50 pts):
    - Bug A: CSV path corrected (includes /data/)         10 pts
    - Bug B: datetime format parses YYYY-MM-DD HH:MM      10 pts
    - Bug C: .talon calls docket_search (not docket_find)  8 pts
    - Bug D: list name consistent (docket_field singular)  12 pts
    - Bug E: all 10 CSV columns in .talon-list             10 pts
  New functionality (30 pts):
    - docket_judge_workload function exists                  8 pts
    - docket_high_priority function exists                   8 pts
    - docket_export_report function exists                   8 pts
    - voice commands for all 3 new actions                   6 pts
  Report output (20 pts):
    - Report file exists                                     5 pts
    - Report contains total case count (80)                  5 pts
    - Report contains per-judge data                         5 pts
    - Report contains active high-priority cases             5 pts
  Total: 100 pts. Pass threshold: 65.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_rescue_broken_docket_module(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result_path = task_info.get('metadata', {}).get(
        'result_file', 'C:\\Users\\Docker\\rescue_broken_docket_module_result.json'
    )

    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp.close()
    try:
        copy_from_env(result_path, temp.name)
        with open(temp.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found - export_result.ps1 may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        try:
            os.unlink(temp.name)
        except OSError:
            pass

    score = 0
    feedback_parts = []

    # Helper to unescape content from the export JSON
    def unescape(s):
        return s.replace('\\n', '\n').replace('\\t', '\t')

    # ------------------------------------------------------------------
    # Bug A: CSV path must include /data/ subdirectory
    # ------------------------------------------------------------------
    py_content = result.get('py_content', '')
    py_src = unescape(py_content)

    if not py_content:
        feedback_parts.append("MISSING docket_engine.py")
    else:
        # Check that the path contains /data/ or \\data\\
        if re.search(r'workspace[/\\]+data[/\\]+court_docket\.csv', py_src):
            score += 10
            feedback_parts.append("PASS BugA: CSV path includes /data/ subdirectory")
        elif re.search(r'court_docket\.csv', py_src):
            feedback_parts.append("FAIL BugA: CSV path found but missing /data/ subdirectory")
        else:
            feedback_parts.append("FAIL BugA: no CSV path reference found in docket_engine.py")

    # ------------------------------------------------------------------
    # Bug B: datetime format must parse YYYY-MM-DD HH:MM
    # ------------------------------------------------------------------
    if py_content:
        # The broken format was '%m/%d/%Y'. Correct is '%Y-%m-%d %H:%M' (or equivalent).
        # Check that the old broken format is gone and a plausible correct one is present.
        has_broken_format = bool(re.search(r'%m/%d/%Y', py_src))
        has_year_first = bool(re.search(r'%Y', py_src))
        has_hour_minute = bool(re.search(r'%[HI].*%M', py_src))

        if not has_broken_format and has_year_first and has_hour_minute:
            score += 10
            feedback_parts.append("PASS BugB: datetime format appears corrected to year-first with time")
        elif has_broken_format:
            feedback_parts.append("FAIL BugB: still using broken %m/%d/%Y format")
        else:
            feedback_parts.append("FAIL BugB: datetime format unclear or removed")

    # ------------------------------------------------------------------
    # Bug C: .talon must call user.docket_search (not user.docket_find)
    # ------------------------------------------------------------------
    talon_content = result.get('talon_content', '')
    talon_src = unescape(talon_content)

    if not talon_content:
        feedback_parts.append("MISSING docket.talon")
    else:
        has_find = bool(re.search(r'user\.docket_find', talon_src))
        has_search = bool(re.search(r'user\.docket_search', talon_src))

        if has_search and not has_find:
            score += 8
            feedback_parts.append("PASS BugC: .talon correctly calls user.docket_search")
        elif has_find:
            feedback_parts.append("FAIL BugC: .talon still calls user.docket_find")
        else:
            feedback_parts.append("FAIL BugC: no docket_search or docket_find call found in .talon")

    # ------------------------------------------------------------------
    # Bug D: list name consistency — all 3 files must use docket_field (singular)
    # ------------------------------------------------------------------
    list_content = result.get('list_content', '')
    list_src = unescape(list_content)

    d_score = 0
    d_checks = 0

    # Check Python: mod.list("docket_field") — this was already correct, just verify not broken
    if py_content:
        if re.search(r'mod\.list\(\s*["\']docket_field["\']', py_src):
            d_checks += 1

    # Check .talon: should use {user.docket_field} not {user.docket_fields}
    if talon_content:
        has_plural_talon = bool(re.search(r'user\.docket_fields', talon_src))
        has_singular_talon = bool(re.search(r'user\.docket_field\b', talon_src))
        if has_singular_talon and not has_plural_talon:
            d_checks += 1

    # Check .talon-list: header should say "list: user.docket_field"
    if list_content:
        list_lines = list_src.splitlines()
        list_header = next((l.strip() for l in list_lines if l.strip().startswith('list:')), '')
        if list_header == 'list: user.docket_field':
            d_checks += 1

    if d_checks == 3:
        score += 12
        feedback_parts.append("PASS BugD: list name consistent across all 3 files (docket_field)")
    elif d_checks >= 2:
        score += 6
        feedback_parts.append(f"PARTIAL BugD: list name fixed in {d_checks}/3 files")
    else:
        feedback_parts.append(f"FAIL BugD: list name still inconsistent ({d_checks}/3 files correct)")

    # ------------------------------------------------------------------
    # Bug E: .talon-list must have all 10 CSV columns
    # ------------------------------------------------------------------
    required_columns = {
        'case_number', 'case_type', 'defendant', 'plaintiff', 'attorney',
        'judge', 'next_hearing', 'courtroom', 'status', 'priority'
    }

    if list_content:
        # Find all "spoken: value" lines after the separator
        mapped_values = set()
        past_separator = False
        for line in list_src.splitlines():
            stripped = line.strip()
            if stripped == '-':
                past_separator = True
                continue
            if past_separator and ':' in stripped and not stripped.startswith('#'):
                value = stripped.split(':', 1)[1].strip()
                mapped_values.add(value)

        matched = required_columns & mapped_values
        if len(matched) >= 10:
            score += 10
            feedback_parts.append("PASS BugE: all 10 CSV columns mapped in .talon-list")
        elif len(matched) >= 7:
            score += 5
            feedback_parts.append(f"PARTIAL BugE: {len(matched)}/10 CSV columns mapped")
        else:
            feedback_parts.append(f"FAIL BugE: only {len(matched)}/10 CSV columns mapped")
    else:
        feedback_parts.append("FAIL BugE: .talon-list file missing")

    # ------------------------------------------------------------------
    # New functionality: three new Python action methods
    # ------------------------------------------------------------------
    new_functions = {
        'docket_judge_workload': 8,
        'docket_high_priority': 8,
        'docket_export_report': 8,
    }

    if py_content:
        for func_name, points in new_functions.items():
            # Look for def <func_name> in the Python source
            if re.search(rf'def\s+{func_name}\s*\(', py_src):
                score += points
                feedback_parts.append(f"PASS NewFunc: {func_name} defined")
            else:
                feedback_parts.append(f"FAIL NewFunc: {func_name} not found in docket_engine.py")

    # ------------------------------------------------------------------
    # New voice commands in .talon for the 3 new actions
    # ------------------------------------------------------------------
    if talon_content:
        new_cmds_found = 0
        for func_name in new_functions:
            if re.search(rf'user\.{func_name}', talon_src):
                new_cmds_found += 1
        if new_cmds_found == 3:
            score += 6
            feedback_parts.append("PASS NewCmds: all 3 new voice commands present")
        elif new_cmds_found > 0:
            score += 2 * new_cmds_found
            feedback_parts.append(f"PARTIAL NewCmds: {new_cmds_found}/3 new voice commands present")
        else:
            feedback_parts.append("FAIL NewCmds: no new voice commands found in .talon")

    # ------------------------------------------------------------------
    # Report file: existence and content accuracy
    # ------------------------------------------------------------------
    report_content = result.get('report_content', '')
    report_src = unescape(report_content)
    report_exists = result.get('report_exists', False)

    if report_exists and report_content:
        score += 5
        feedback_parts.append("PASS Report: docket_report.txt exists")

        # Check for total case count (80)
        if re.search(r'\b80\b', report_src):
            score += 5
            feedback_parts.append("PASS Report: contains total case count 80")
        else:
            feedback_parts.append("FAIL Report: total case count 80 not found")

        # Check for per-judge data (at least 3 of 5 judge names)
        judge_names = [
            'Robert Smith', 'Lisa Chen', 'Marcus Williams',
            'Patricia O\'Brien', 'David Park'
        ]
        judges_found = sum(1 for j in judge_names if j in report_src)
        if judges_found >= 3:
            score += 5
            feedback_parts.append(f"PASS Report: {judges_found}/5 judge names found")
        else:
            feedback_parts.append(f"FAIL Report: only {judges_found}/5 judge names found")

        # Check for active high-priority case data
        # Look for at least a few known active+high case numbers
        known_active_high = [
            '2024-CF-001234', '2024-CF-001891', '2024-PV-000567',
            '2024-CF-002301', '2024-CF-002567', '2024-CF-002801',
            '2024-CF-003012', '2024-PV-001023'
        ]
        ah_found = sum(1 for c in known_active_high if c in report_src)
        if ah_found >= 4:
            score += 5
            feedback_parts.append(f"PASS Report: {ah_found} active high-priority case numbers found")
        elif ah_found >= 2:
            score += 2
            feedback_parts.append(f"PARTIAL Report: only {ah_found} active high-priority case numbers found")
        else:
            feedback_parts.append(f"FAIL Report: active high-priority case data insufficient ({ah_found} found)")
    elif report_exists:
        score += 5
        feedback_parts.append("PASS Report: file exists but is empty")
    else:
        feedback_parts.append("FAIL Report: docket_report.txt not found")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
