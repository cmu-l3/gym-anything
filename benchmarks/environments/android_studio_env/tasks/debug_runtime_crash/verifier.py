#!/usr/bin/env python3
"""
Verifier for debug_runtime_crash task.

The NotepadApp has 4 planted runtime bugs:
1. NotepadActivity.kt: formatter/validator are lateinit but never initialized
   -> UninitializedPropertyAccessException
2. NoteFormatter.kt: formatPreview uses unsafe substring(0, maxLength)
   without checking content length -> StringIndexOutOfBoundsException on short content
3. NoteValidator.kt: isNoteComplete calls itself recursively -> StackOverflowError
4. Note.kt: charCount concatenates cleaned length with color int and parses
   -> NumberFormatException

Scoring (100 points total):
- Bug 1 fixed (activity initializes formatter/validator): 20 pts
- Bug 2 fixed (formatter safe substring): 20 pts
- Bug 3 fixed (validator no recursion): 20 pts
- Bug 4 fixed (note charCount correct): 15 pts
- Project still compiles: 25 pts

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
    """Copy a text file out of the container and return its contents."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception as e:
        logger.debug("Could not read %s: %s", path, e)
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _read_json(copy_from_env, path):
    """Copy a JSON file out of the container and return parsed dict."""
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


def verify_debug_runtime_crash(traj, env_info, task_info):
    """Verify all runtime bugs in NotepadApp have been fixed."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/NotepadApp')
    pkg_path = metadata.get('package_path', 'com/example/notepad')
    src_dir = f"{project_dir}/app/src/main/java/{pkg_path}"

    # Read source files directly from the container
    activity = _read_text(copy_from_env, f"{src_dir}/NotepadActivity.kt")
    formatter = _read_text(copy_from_env, f"{src_dir}/NoteFormatter.kt")
    validator = _read_text(copy_from_env, f"{src_dir}/NoteValidator.kt")
    note = _read_text(copy_from_env, f"{src_dir}/Note.kt")

    # Read the export result JSON as supplementary data
    result = _read_json(copy_from_env, "/tmp/task_result.json")

    # Fall back to export JSON content if direct reads returned empty
    if not activity:
        activity = result.get('activity_content', '')
    if not formatter:
        formatter = result.get('formatter_content', '')
    if not validator:
        validator = result.get('validator_content', '')
    if not note:
        note = result.get('note_content', '')

    score = 0
    feedback = []

    # GATE: check if any files were modified
    any_change = (
        result.get('activity_changed', False) or
        result.get('formatter_changed', False) or
        result.get('validator_changed', False) or
        result.get('note_changed', False)
    )
    if not any_change:
        return {"passed": False, "score": 0, "feedback": "No files modified - no bugs fixed"}

    # ================================================================
    # Bug 1: NotepadActivity.kt - formatter/validator must be initialized (20 pts)
    # Fixed if: formatter and validator are initialized (not just lateinit without init)
    # ================================================================
    try:
        # Check if they're initialized directly at declaration
        direct_init_formatter = bool(re.search(
            r'private\s+(val|var)\s+formatter\s*[:=]\s*.*NoteFormatter\s*\(\s*\)',
            activity
        ))
        direct_init_validator = bool(re.search(
            r'private\s+(val|var)\s+validator\s*[:=]\s*.*NoteValidator\s*\(\s*\)',
            activity
        ))
        # Check if they're initialized in onCreate or elsewhere
        oncreate_init_formatter = bool(re.search(
            r'formatter\s*=\s*NoteFormatter\s*\(\s*\)',
            activity
        ))
        oncreate_init_validator = bool(re.search(
            r'validator\s*=\s*NoteValidator\s*\(\s*\)',
            activity
        ))

        formatter_ok = direct_init_formatter or oncreate_init_formatter
        validator_ok = direct_init_validator or oncreate_init_validator

        if formatter_ok and validator_ok:
            score += 20
            feedback.append("Bug1 Activity init: both fixed (20/20)")
        elif formatter_ok or validator_ok:
            score += 10
            feedback.append("Bug1 Activity init: one of two fixed (10/20)")
        else:
            feedback.append("Bug1 Activity init: not fixed (0/20)")
    except Exception as e:
        feedback.append(f"Bug1: error ({e}) (0/20)")

    # ================================================================
    # Bug 2: NoteFormatter.kt - formatPreview safe substring (20 pts)
    # Fixed if: the unsafe substring(0, maxLength) is removed or guarded
    # ================================================================
    try:
        has_unsafe_substring = bool(re.search(
            r'singleLine\.substring\s*\(\s*0\s*,\s*maxLength\s*\)',
            formatter
        ))
        uses_take = bool(re.search(r'\.take\s*\(\s*maxLength\s*\)', formatter))
        has_length_check = bool(re.search(r'singleLine\.length\s*>\s*maxLength', formatter))

        if not has_unsafe_substring and (uses_take or has_length_check):
            score += 20
            feedback.append("Bug2 Formatter: safe substring (20/20)")
        elif not has_unsafe_substring:
            score += 15
            feedback.append("Bug2 Formatter: unsafe substring removed (15/20)")
        elif result.get('formatter_changed', False):
            score += 5
            feedback.append("Bug2 Formatter: modified but issue unclear (5/20)")
        else:
            feedback.append("Bug2 Formatter: not fixed (0/20)")
    except Exception as e:
        feedback.append(f"Bug2: error ({e}) (0/20)")

    # ================================================================
    # Bug 3: NoteValidator.kt - isNoteComplete no recursion (20 pts)
    # Fixed if: isNoteComplete does NOT call isNoteComplete(note) at the end
    # ================================================================
    try:
        # Extract the isNoteComplete method body
        match = re.search(
            r'fun\s+isNoteComplete\s*\([^)]*\)\s*:\s*Boolean\s*\{(.*?)\n    \}',
            validator,
            re.DOTALL
        )
        if match:
            method_body = match.group(1)
            has_self_call = bool(re.search(r'isNoteComplete\s*\(', method_body))
            returns_true = bool(re.search(r'return\s+true', method_body))

            if not has_self_call and returns_true:
                score += 20
                feedback.append("Bug3 Validator: recursion removed (20/20)")
            elif not has_self_call:
                score += 15
                feedback.append("Bug3 Validator: recursion removed (15/20)")
            else:
                feedback.append("Bug3 Validator: still recursive (0/20)")
        elif result.get('validator_changed', False):
            score += 10
            feedback.append("Bug3 Validator: file modified (10/20)")
        else:
            feedback.append("Bug3 Validator: not modified (0/20)")
    except Exception as e:
        feedback.append(f"Bug3: error ({e}) (0/20)")

    # ================================================================
    # Bug 4: Note.kt - charCount correct implementation (15 pts)
    # Fixed if: charCount doesn't use Integer.parseInt with color concatenation
    # ================================================================
    try:
        match = re.search(
            r'fun\s+charCount\s*\(\s*\)\s*:\s*Int\s*\{(.*?)\n    \}',
            note,
            re.DOTALL
        )
        if match:
            method_body = match.group(1)
            has_parse_int = bool(re.search(r'Integer\.parseInt', method_body))
            has_color_ref = bool(re.search(r'color', method_body))
            uses_length = bool(re.search(r'\.length\b', method_body))

            if not has_parse_int and not has_color_ref and uses_length:
                score += 15
                feedback.append("Bug4 charCount: fixed correctly (15/15)")
            elif not has_parse_int:
                score += 10
                feedback.append("Bug4 charCount: parseInt removed (10/15)")
            else:
                feedback.append("Bug4 charCount: still broken (0/15)")
        elif result.get('note_changed', False):
            score += 8
            feedback.append("Bug4 charCount: file modified (8/15)")
        else:
            feedback.append("Bug4 charCount: not modified (0/15)")
    except Exception as e:
        feedback.append(f"Bug4: error ({e}) (0/15)")

    # ================================================================
    # Compilation check (25 pts)
    # ================================================================
    try:
        build_success = result.get('build_success', False)
        if not build_success:
            gradle_log = _read_text(copy_from_env, "/tmp/gradle_output.log")
            if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
                build_success = True

        if build_success:
            score += 25
            feedback.append("Build: succeeded (25/25)")
        else:
            feedback.append("Build: failed (0/25)")
    except Exception as e:
        feedback.append(f"Build: error ({e}) (0/25)")

    # ================================================================
    # Final scoring
    # ================================================================
    passed = score >= 70

    if passed:
        if score == 100:
            feedback.append("All runtime bugs fixed perfectly!")
        elif score >= 85:
            feedback.append("Most runtime bugs fixed successfully")
        else:
            feedback.append("Runtime bugs substantially addressed")
    else:
        feedback.append("Task NOT completed - more fixes needed")

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback)
    }
