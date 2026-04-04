#!/usr/bin/env python3
"""
Verifier for fix_and_extend_calculator task.

Bugs to fix:
1. onPercentPressed uses .toDouble() instead of .toDoubleOrNull() — crashes on empty/invalid input
2. onNegatePressed uses .toDouble() instead of .toDoubleOrNull() — crashes on empty input

Features to add:
3. History display: change from takeLast(5) to takeLast(10)
4. Memory indicator: add visual "M" display when memory is non-zero

Scoring (100 points total):
- Bug 1 fixed (percent safe): 15 pts
- Bug 2 fixed (negate safe): 15 pts
- History extended to 10: 15 pts
- Memory indicator added: 20 pts
- Project compiles: 35 pts

Pass threshold: 70/100
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _read_text(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _read_json(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_fix_and_extend_calculator(traj, env_info, task_info):
    """Verify calculator bugs fixed and features added."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/CalculatorApp')
    pkg_path = metadata.get('package_path', 'com/example/calculator')
    src_dir = f"{project_dir}/app/src/main/java/{pkg_path}"

    activity = _read_text(copy_from_env, f"{src_dir}/CalcActivity.kt")
    engine = _read_text(copy_from_env, f"{src_dir}/CalcEngine.kt")
    layout = _read_text(copy_from_env, f"{project_dir}/app/src/main/res/layout/activity_calc.xml")

    result = _read_json(copy_from_env, "/tmp/task_result.json")
    if not activity: activity = result.get('activity_content', '')
    if not engine: engine = result.get('engine_content', '')
    if not layout: layout = result.get('layout_content', '')

    score = 0
    feedback = []

    # GATE
    any_change = (
        result.get('activity_changed', False) or
        result.get('engine_changed', False) or
        result.get('layout_changed', False)
    )
    if not any_change:
        return {"passed": False, "score": 0, "feedback": "No files modified"}

    # ================================================================
    # Bug 1: onPercentPressed safe input handling (15 pts)
    # ================================================================
    try:
        percent_match = re.search(
            r'fun\s+onPercentPressed\s*\(\s*\)\s*\{(.*?)\n    \}',
            activity,
            re.DOTALL
        )
        if percent_match:
            body = percent_match.group(1)
            uses_safe = bool(re.search(r'toDoubleOrNull', body))
            has_guard = bool(re.search(r'\?\s*:\s*return|if\s*\(.*isEmpty|if\s*\(.*isBlank|try\s*\{', body))
            uses_unsafe = bool(re.search(r'currentInput\.toDouble\(\)', body))

            if uses_safe or (has_guard and not uses_unsafe):
                score += 15
                feedback.append("Bug1 Percent: safe handling (15/15)")
            elif has_guard:
                score += 10
                feedback.append("Bug1 Percent: partial guard (10/15)")
            elif not uses_unsafe:
                score += 8
                feedback.append("Bug1 Percent: unsafe removed (8/15)")
            else:
                feedback.append("Bug1 Percent: still unsafe (0/15)")
        elif result.get('activity_changed', False):
            score += 5
            feedback.append("Bug1 Percent: activity changed (5/15)")
        else:
            feedback.append("Bug1 Percent: not found (0/15)")
    except Exception as e:
        feedback.append(f"Bug1: error ({e}) (0/15)")

    # ================================================================
    # Bug 2: onNegatePressed safe input handling (15 pts)
    # ================================================================
    try:
        negate_match = re.search(
            r'fun\s+onNegatePressed\s*\(\s*\)\s*\{(.*?)\n    \}',
            activity,
            re.DOTALL
        )
        if negate_match:
            body = negate_match.group(1)
            uses_safe = bool(re.search(r'toDoubleOrNull', body))
            has_guard = bool(re.search(r'\?\s*:\s*return|if\s*\(.*isEmpty|if\s*\(.*isBlank|try\s*\{', body))
            uses_unsafe = bool(re.search(r'currentInput\.toDouble\(\)', body))

            if uses_safe or (has_guard and not uses_unsafe):
                score += 15
                feedback.append("Bug2 Negate: safe handling (15/15)")
            elif has_guard:
                score += 10
                feedback.append("Bug2 Negate: partial guard (10/15)")
            elif not uses_unsafe:
                score += 8
                feedback.append("Bug2 Negate: unsafe removed (8/15)")
            else:
                feedback.append("Bug2 Negate: still unsafe (0/15)")
        elif result.get('activity_changed', False):
            score += 5
            feedback.append("Bug2 Negate: activity changed (5/15)")
        else:
            feedback.append("Bug2 Negate: not found (0/15)")
    except Exception as e:
        feedback.append(f"Bug2: error ({e}) (0/15)")

    # ================================================================
    # Feature 1: History extended to 10 entries (15 pts)
    # ================================================================
    try:
        # Check for takeLast(10) or similar
        has_ten = bool(re.search(r'takeLast\s*\(\s*10\s*\)', activity))
        has_five = bool(re.search(r'takeLast\s*\(\s*5\s*\)', activity))
        has_larger = bool(re.search(r'takeLast\s*\(\s*([6-9]|[1-9]\d+)\s*\)', activity))

        if has_ten:
            score += 15
            feedback.append("History: extended to 10 (15/15)")
        elif has_larger and not has_five:
            score += 10
            feedback.append("History: extended but not to 10 (10/15)")
        elif not has_five:
            score += 5
            feedback.append("History: changed from 5 (5/15)")
        else:
            feedback.append("History: still 5 entries (0/15)")
    except Exception as e:
        feedback.append(f"History: error ({e}) (0/15)")

    # ================================================================
    # Feature 2: Memory indicator (20 pts)
    # ================================================================
    try:
        # Check layout for memory indicator element
        has_memory_in_layout = bool(re.search(r'memory|mem_indicator|memoryIndicator', layout, re.IGNORECASE))
        # Check activity for memory display logic
        has_memory_check = bool(re.search(r'memRecall|mem\s*!=\s*0|mem\s*>\s*0|memory.*visible|indicator', activity, re.IGNORECASE))
        has_memory_view = bool(re.search(r'findViewById.*mem|binding.*mem|memoryView|memIndicator', activity, re.IGNORECASE))

        m_score = 0
        if has_memory_in_layout: m_score += 10
        if has_memory_check: m_score += 5
        if has_memory_view: m_score += 5

        score += min(m_score, 20)
        feedback.append(f"Memory indicator: ({min(m_score, 20)}/20)")
    except Exception as e:
        feedback.append(f"Memory indicator: error ({e}) (0/20)")

    # ================================================================
    # Compilation (35 pts)
    # ================================================================
    try:
        build_success = result.get('build_success', False)
        if not build_success:
            gradle_log = _read_text(copy_from_env, "/tmp/gradle_output.log")
            if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
                build_success = True

        if build_success:
            score += 35
            feedback.append("Build: succeeded (35/35)")
        else:
            feedback.append("Build: failed (0/35)")
    except Exception as e:
        feedback.append(f"Build: error ({e}) (0/35)")

    passed = score >= 70

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback)
    }
