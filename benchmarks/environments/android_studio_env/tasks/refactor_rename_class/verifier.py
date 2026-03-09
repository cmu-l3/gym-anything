#!/usr/bin/env python3
"""Verifier for refactor_rename_class task.

Scoring breakdown (100 points total):
  - CalcEngine.kt no longer exists (old file removed):         10 pts
  - Calculator.kt exists (new file created):                   10 pts
  - Calculator.kt contains class named "Calculator":           15 pts
  - Method renames applied (5 methods, 5 pts each):            25 pts
      doAdd -> add, doSub -> subtract, doMul -> multiply,
      doDiv -> divide, doMod -> modulo
  - CalcActivity.kt references "Calculator" not "CalcEngine":  10 pts
  - CalcActivity.kt uses new method names:                     10 pts
  - Project builds successfully:                               20 pts
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _read_text_from_env(copy_from_env, container_path: str) -> str:
    """Copy a text file out of the container and return its contents."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except Exception as exc:
        logger.debug("Could not read %s: %s", container_path, exc)
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_refactor_rename_class(traj, env_info, task_info):
    """Verify that the CalcEngine class was properly refactored to Calculator."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    project_dir = metadata.get("project_dir", "/home/ga/AndroidStudioProjects/CalculatorApp")
    src_dir = f"{project_dir}/app/src/main/java/com/example/calculator"

    # Read files directly from the container via copy_from_env
    old_file_content = _read_text_from_env(copy_from_env, f"{src_dir}/CalcEngine.kt")
    new_file_content = _read_text_from_env(copy_from_env, f"{src_dir}/Calculator.kt")
    calc_activity_content = _read_text_from_env(copy_from_env, f"{src_dir}/CalcActivity.kt")

    # Read export JSON as supplementary data (for build success)
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")

    # Fall back to export JSON content if direct reads returned empty
    calculator_content = new_file_content
    if not calculator_content:
        calculator_content = result.get('calculator_content', '').strip()
    if not calc_activity_content:
        calc_activity_content = result.get('calc_activity_content', '').strip()

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Criterion 1: CalcEngine.kt no longer exists (10 pts)
    # ================================================================
    old_file_exists = bool(old_file_content)
    # Also check export JSON as fallback
    if not old_file_content and result:
        old_file_exists = result.get('old_file_exists', False)

    details['old_file_exists'] = old_file_exists

    if not old_file_exists:
        score += 10
        feedback_parts.append("Old file CalcEngine.kt removed (10/10)")
    else:
        feedback_parts.append("Old file CalcEngine.kt still exists (0/10)")

    # ================================================================
    # Criterion 2: Calculator.kt exists (10 pts)
    # ================================================================
    new_file_exists = bool(calculator_content)
    details['new_file_exists'] = new_file_exists

    if new_file_exists:
        score += 10
        feedback_parts.append("New file Calculator.kt created (10/10)")
    else:
        feedback_parts.append("New file Calculator.kt not found (0/10)")

    # ================================================================
    # Criterion 3: Calculator.kt contains class "Calculator" (15 pts)
    # ================================================================
    has_new_class_name = bool(re.search(r'\bclass\s+Calculator\b', calculator_content))
    has_old_class_name_in_new_file = bool(re.search(r'\bclass\s+CalcEngine\b', calculator_content))

    details['has_calculator_class'] = has_new_class_name
    details['has_old_class_in_new_file'] = has_old_class_name_in_new_file

    if has_new_class_name and not has_old_class_name_in_new_file:
        score += 15
        feedback_parts.append("Class renamed to Calculator (15/15)")
    elif has_new_class_name:
        score += 8
        feedback_parts.append("Class Calculator found but CalcEngine also present (8/15)")
    else:
        feedback_parts.append("Class not renamed to Calculator (0/15)")

    # ================================================================
    # Criterion 4: Method renames applied (25 pts, 5 per method)
    # ================================================================
    method_renames = {
        'doAdd': 'add',
        'doSub': 'subtract',
        'doMul': 'multiply',
        'doDiv': 'divide',
        'doMod': 'modulo',
    }

    methods_score = 0
    methods_renamed = []
    methods_not_renamed = []

    for old_name, new_name in method_renames.items():
        has_new = bool(re.search(r'\bfun\s+' + re.escape(new_name) + r'\s*\(', calculator_content))
        has_old = bool(re.search(r'\bfun\s+' + re.escape(old_name) + r'\s*\(', calculator_content))

        if has_new and not has_old:
            methods_score += 5
            methods_renamed.append(f"{old_name}->{new_name}")
        elif has_new:
            methods_score += 2
            methods_not_renamed.append(f"{old_name} (new exists but old remains)")
        else:
            methods_not_renamed.append(f"{old_name}->{new_name}")

    score += methods_score
    details['methods_renamed'] = methods_renamed
    details['methods_not_renamed'] = methods_not_renamed

    if methods_renamed:
        feedback_parts.append(f"Methods renamed: {', '.join(methods_renamed)} ({methods_score}/25)")
    if methods_not_renamed:
        feedback_parts.append(f"Methods NOT renamed: {', '.join(methods_not_renamed)}")

    # ================================================================
    # Criterion 5: CalcActivity.kt references "Calculator" (10 pts)
    # ================================================================
    activity_refs_score = 0

    if calc_activity_content:
        uses_new_class = bool(re.search(r'\bCalculator\s*\(', calc_activity_content)) or \
                         bool(re.search(r':\s*Calculator\b', calc_activity_content)) or \
                         bool(re.search(r'\bCalculator\b', calc_activity_content))
        uses_old_class = bool(re.search(r'\bCalcEngine\s*\(', calc_activity_content)) or \
                         bool(re.search(r':\s*CalcEngine\b', calc_activity_content))

        details['activity_uses_new_class'] = uses_new_class
        details['activity_uses_old_class'] = uses_old_class

        if uses_new_class and not uses_old_class:
            activity_refs_score = 10
            feedback_parts.append("CalcActivity.kt references Calculator correctly (10/10)")
        elif uses_new_class:
            activity_refs_score = 5
            feedback_parts.append("CalcActivity.kt has Calculator but CalcEngine refs remain (5/10)")
        else:
            feedback_parts.append("CalcActivity.kt does not reference Calculator (0/10)")
    else:
        feedback_parts.append("CalcActivity.kt content not available (0/10)")

    score += activity_refs_score

    # ================================================================
    # Criterion 6: CalcActivity.kt uses new method names (10 pts)
    # ================================================================
    activity_methods_score = 0

    if calc_activity_content:
        activity_method_renames = {
            'doAdd': 'add',
            'doSub': 'subtract',
            'doMul': 'multiply',
            'doDiv': 'divide',
        }

        new_method_calls = 0
        old_method_calls = 0
        for old_name, new_name in activity_method_renames.items():
            if re.search(r'\.' + re.escape(new_name) + r'\s*\(', calc_activity_content):
                new_method_calls += 1
            if re.search(r'\.' + re.escape(old_name) + r'\s*\(', calc_activity_content):
                old_method_calls += 1

        details['activity_new_method_calls'] = new_method_calls
        details['activity_old_method_calls'] = old_method_calls

        if new_method_calls >= 3 and old_method_calls == 0:
            activity_methods_score = 10
            feedback_parts.append(f"CalcActivity.kt uses new method names ({new_method_calls}/4) (10/10)")
        elif new_method_calls >= 2 and old_method_calls == 0:
            activity_methods_score = 7
            feedback_parts.append(f"CalcActivity.kt partially uses new names ({new_method_calls}/4) (7/10)")
        elif new_method_calls >= 1:
            activity_methods_score = 3
            feedback_parts.append(f"CalcActivity.kt has some new method names but old ones remain (3/10)")
        else:
            feedback_parts.append("CalcActivity.kt does not use new method names (0/10)")
    else:
        feedback_parts.append("CalcActivity.kt content not available for method check (0/10)")

    score += activity_methods_score

    # ================================================================
    # Criterion 7: Project builds successfully (20 pts)
    # ================================================================
    build_success = result.get('build_success', False)

    # Also check by reading gradle output directly
    if not build_success:
        gradle_log = _read_text_from_env(copy_from_env, "/tmp/gradle_output.log")
        if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
            build_success = True

    details['build_success'] = build_success

    if build_success:
        score += 20
        feedback_parts.append("Project builds successfully (20/20)")
    else:
        feedback_parts.append("Project build failed (0/20)")

    # ================================================================
    # Final result
    # ================================================================
    passed = score >= 70
    details['total_score'] = score

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
