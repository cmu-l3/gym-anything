#!/usr/bin/env python3
"""
Verifier for audit_and_deduplicate_commands task.

Three duplicate voice triggers are seeded across multiple .talon files:
  1. "go to line"  — in editor_commands.talon AND productivity_commands.talon
  2. "open terminal" — in editor_commands.talon AND productivity_commands.talon
  3. "save file"  — in general_commands.talon AND productivity_commands.talon

The resolution is: keep the more specific (app-scoped) version in
productivity_commands.talon, and comment out or remove the duplicate in
editor_commands.talon / general_commands.talon.

Scoring breakdown (100 pts total):
  - "go to line" duplicate resolved (one copy disabled):   20 pts
  - "open terminal" duplicate resolved:                    20 pts
  - "save file" duplicate resolved:                        20 pts
  - No .talon files deleted (all 3 still exist):           15 pts
  - audit_report.txt created and references all 3 issues:  25 pts
  Pass threshold: 60 pts.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DUPLICATE_TRIGGERS = ['go to line', 'open terminal', 'save file']


def _get_active_command_triggers(talon_text):
    """
    Return the set of active (non-commented) top-level command trigger phrases
    found after the '-' separator in a .talon file body.
    """
    lines = talon_text.splitlines()
    in_body = False
    triggers = set()
    for line in lines:
        stripped = line.strip()
        if stripped == '-':
            in_body = True
            continue
        if not in_body:
            continue
        if stripped.startswith('#') or not stripped:
            continue
        # Top-level command line (not indented)
        if not line.startswith((' ', '\t')) and ':' in stripped:
            trigger = stripped.split(':', 1)[0].strip().lower()
            triggers.add(trigger)
    return triggers


def _is_trigger_disabled(talon_text, trigger):
    """
    Check if a trigger has been commented out (prefixed with #) in the file.
    """
    lines = talon_text.splitlines()
    in_body = False
    for line in lines:
        stripped = line.strip()
        if stripped == '-':
            in_body = True
            continue
        if not in_body:
            continue
        # Commented version of the trigger
        if stripped.startswith('#') and trigger in stripped.lower():
            return True
    return False


def _report_mentions_trigger(report_text, trigger):
    """Check if the audit report mentions this trigger."""
    return trigger.lower() in report_text.lower()


def verify_audit_and_deduplicate_commands(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata    = task_info.get('metadata', {})
    result_path = metadata.get('result_file',
                               'C:\\Users\\Docker\\audit_and_deduplicate_commands_result.json')

    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp.close()
    try:
        copy_from_env(result_path, temp.name)
        with open(temp.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.ps1 may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        try:
            os.unlink(temp.name)
        except OSError:
            pass

    score = 0
    feedback_parts = []

    editor_text       = result.get('editor_content',      '').replace('\\n', '\n').replace('\\t', '\t')
    general_text      = result.get('general_content',     '').replace('\\n', '\n').replace('\\t', '\t')
    productivity_text = result.get('productivity_content','').replace('\\n', '\n').replace('\\t', '\t')
    report_text       = result.get('report_content',      '').replace('\\n', '\n').replace('\\t', '\t')
    report_exists     = result.get('report_exists', False)

    editor_triggers       = _get_active_command_triggers(editor_text)
    general_triggers      = _get_active_command_triggers(general_text)
    productivity_triggers = _get_active_command_triggers(productivity_text)

    logger.info(f"Editor active triggers: {editor_triggers}")
    logger.info(f"General active triggers: {general_triggers}")
    logger.info(f"Productivity active triggers: {productivity_triggers}")

    # ------------------------------------------------------------------
    # Criterion 1: "go to line" duplicate resolved (20 pts)
    # Correct: active in productivity_commands only, disabled/removed from editor_commands
    # ------------------------------------------------------------------
    gol_in_editor       = 'go to line' in editor_triggers
    gol_in_productivity = 'go to line' in productivity_triggers
    gol_commented_editor = _is_trigger_disabled(editor_text, 'go to line')

    if not gol_in_editor and gol_in_productivity:
        score += 20
        feedback_parts.append("PASS C1: 'go to line' resolved — active only in productivity_commands.talon")
    elif gol_commented_editor and gol_in_productivity:
        score += 20
        feedback_parts.append("PASS C1: 'go to line' resolved — commented out in editor_commands.talon")
    elif gol_in_editor and gol_in_productivity:
        feedback_parts.append("FAIL C1: 'go to line' still active in BOTH editor_commands and productivity_commands")
    elif not gol_in_editor and not gol_in_productivity:
        score += 10
        feedback_parts.append("PARTIAL C1: 'go to line' removed from both files (kept the more specific one too)")
    else:
        feedback_parts.append("FAIL C1: 'go to line' conflict not properly resolved")

    # ------------------------------------------------------------------
    # Criterion 2: "open terminal" duplicate resolved (20 pts)
    # ------------------------------------------------------------------
    ot_in_editor       = 'open terminal' in editor_triggers
    ot_in_productivity = 'open terminal' in productivity_triggers
    ot_commented_editor = _is_trigger_disabled(editor_text, 'open terminal')

    if not ot_in_editor and ot_in_productivity:
        score += 20
        feedback_parts.append("PASS C2: 'open terminal' resolved — active only in productivity_commands.talon")
    elif ot_commented_editor and ot_in_productivity:
        score += 20
        feedback_parts.append("PASS C2: 'open terminal' resolved — commented out in editor_commands.talon")
    elif ot_in_editor and ot_in_productivity:
        feedback_parts.append("FAIL C2: 'open terminal' still active in BOTH editor_commands and productivity_commands")
    elif not ot_in_editor and not ot_in_productivity:
        score += 10
        feedback_parts.append("PARTIAL C2: 'open terminal' removed from both files")
    else:
        feedback_parts.append("FAIL C2: 'open terminal' conflict not properly resolved")

    # ------------------------------------------------------------------
    # Criterion 3: "save file" duplicate resolved (20 pts)
    # ------------------------------------------------------------------
    sf_in_general      = 'save file' in general_triggers
    sf_in_productivity = 'save file' in productivity_triggers
    sf_commented_general = _is_trigger_disabled(general_text, 'save file')

    if not sf_in_general and sf_in_productivity:
        score += 20
        feedback_parts.append("PASS C3: 'save file' resolved — active only in productivity_commands.talon")
    elif sf_commented_general and sf_in_productivity:
        score += 20
        feedback_parts.append("PASS C3: 'save file' resolved — commented out in general_commands.talon")
    elif sf_in_general and sf_in_productivity:
        feedback_parts.append("FAIL C3: 'save file' still active in BOTH general_commands and productivity_commands")
    elif not sf_in_general and not sf_in_productivity:
        score += 10
        feedback_parts.append("PARTIAL C3: 'save file' removed from both files")
    else:
        feedback_parts.append("FAIL C3: 'save file' conflict not properly resolved")

    # ------------------------------------------------------------------
    # Criterion 4: All 3 .talon files still exist (not deleted) (15 pts)
    # ------------------------------------------------------------------
    files_present = sum([
        bool(editor_text.strip()),
        bool(general_text.strip()),
        bool(productivity_text.strip()),
    ])
    if files_present == 3:
        score += 15
        feedback_parts.append("PASS C4: All 3 .talon files preserved (not deleted)")
    elif files_present == 2:
        score += 7
        feedback_parts.append(f"PARTIAL C4: only {files_present}/3 .talon files still present (agent deleted one)")
    else:
        feedback_parts.append(f"FAIL C4: only {files_present}/3 .talon files still present")

    # ------------------------------------------------------------------
    # Criterion 5: audit_report.txt created and mentions all 3 conflicts (25 pts)
    # ------------------------------------------------------------------
    if not report_exists or not report_text.strip():
        feedback_parts.append("FAIL C5: audit_report.txt not created")
    else:
        mentions = [t for t in DUPLICATE_TRIGGERS if _report_mentions_trigger(report_text, t)]
        if len(mentions) == 3:
            score += 25
            feedback_parts.append("PASS C5: audit_report.txt mentions all 3 conflicts")
        elif len(mentions) == 2:
            score += 15
            feedback_parts.append(f"PARTIAL C5: audit_report.txt mentions only {len(mentions)}/3 conflicts "
                                   f"(missing: {[t for t in DUPLICATE_TRIGGERS if t not in mentions]})")
        elif len(mentions) == 1:
            score += 8
            feedback_parts.append(f"PARTIAL C5: audit_report.txt mentions only {len(mentions)}/3 conflicts")
        else:
            feedback_parts.append("FAIL C5: audit_report.txt does not mention any of the 3 duplicate triggers")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
