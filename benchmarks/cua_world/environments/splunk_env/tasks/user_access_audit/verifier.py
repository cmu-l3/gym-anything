#!/usr/bin/env python3
"""Verifier for user_access_audit task.

Checks for any new Splunk lookup file with >=5 rows, a lookup definition,
and any new saved report that uses a lookup command — regardless of names chosen.

Scoring (each criterion = 20 points, total = 100):
1. At least one new lookup file exists in Splunk
2. New lookup file has >=5 data rows
3. At least one new lookup definition is configured
4. At least one new saved search was created
5. New saved search references a lookup (lookup/inputlookup command)
"""

import json, tempfile, os, re, logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 80
MIN_LOOKUP_ROWS = 5


def verify_user_access_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/user_access_audit_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name): os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    lookup_file_exists = analysis.get('lookup_file_exists', False)
    lookup_row_count = analysis.get('lookup_row_count', 0)
    lookup_def_exists = analysis.get('lookup_def_exists', False)
    found_report = analysis.get('found_report', False)
    report_name = analysis.get('report_name', '')
    report_search = analysis.get('report_search', '')
    report_uses_lookup = analysis.get('report_uses_lookup', False)

    score = 0
    feedback = []
    subscores = {}

    # Criterion 1: Lookup file created
    if lookup_file_exists:
        score += POINTS_PER_CRITERION
        feedback.append("Lookup file created in Splunk")
        subscores['lookup_file_created'] = True
    else:
        feedback.append("FAIL: No lookup file found in Splunk lookups directory")
        subscores['lookup_file_created'] = False

    # Criterion 2: Lookup has enough rows
    if lookup_row_count >= MIN_LOOKUP_ROWS:
        score += POINTS_PER_CRITERION
        feedback.append(f"Lookup has {lookup_row_count} rows (>={MIN_LOOKUP_ROWS} required)")
        subscores['lookup_has_enough_rows'] = True
    elif lookup_file_exists and lookup_row_count == 0:
        # File exists but couldn't read rows (permissions/path issue) — give partial credit
        score += POINTS_PER_CRITERION // 2
        feedback.append(f"Lookup file exists but row count unavailable (partial credit)")
        subscores['lookup_has_enough_rows'] = 'partial'
    else:
        feedback.append(f"FAIL: Lookup has {lookup_row_count} rows, need at least {MIN_LOOKUP_ROWS}")
        subscores['lookup_has_enough_rows'] = False

    # Criterion 3: Lookup definition configured
    if lookup_def_exists:
        score += POINTS_PER_CRITERION
        feedback.append("Lookup definition configured in Splunk")
        subscores['lookup_def_configured'] = True
    else:
        feedback.append("FAIL: No lookup definition found (must configure via Settings > Lookups > Lookup definitions)")
        subscores['lookup_def_configured'] = False

    # Criterion 4: New saved report created
    if found_report:
        score += POINTS_PER_CRITERION
        feedback.append(f"New saved report created: '{report_name}'")
        subscores['report_created'] = True
    else:
        feedback.append("FAIL: No new saved search/report found")
        subscores['report_created'] = False

    # Criterion 5: Report uses lookup command
    if report_uses_lookup:
        score += POINTS_PER_CRITERION
        feedback.append("Report search uses a lookup command (lookup/inputlookup)")
        subscores['report_uses_lookup'] = True
    else:
        feedback.append("FAIL: Report search must use a lookup command (e.g., '| lookup ... username')")
        subscores['report_uses_lookup'] = False

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "lookup_row_count": lookup_row_count,
            "report_name": report_name,
            "report_search_preview": report_search[:200] if report_search else "",
        }
    }
