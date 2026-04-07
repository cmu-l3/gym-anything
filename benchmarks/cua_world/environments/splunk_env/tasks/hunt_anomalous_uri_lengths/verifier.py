#!/usr/bin/env python3
"""Verifier for hunt_anomalous_uri_lengths task.

VERIFICATION STRATEGY:
Evaluates the logical structure of the created SPL query.
- Report exists (20 pts)
- Data Source references web traffic (15 pts)
- Row-level computation (`eval` + `len()`) (20 pts)
- Entity aggregation (`stats` + `avg()` + `max()` + `by`) (25 pts)
- Pipeline Filtering (`where` + `> 60`) (20 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_hunt_anomalous_uri_lengths(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    found_report = analysis.get('found_report', False)
    report_search = analysis.get('report_search', '')
    report_name = analysis.get('report_name', '')
    new_searches = analysis.get('new_searches', [])

    score = 0
    feedback_parts = []
    subscores = {}

    if not new_searches:
        feedback_parts.append("FAIL: No new saved reports or searches were created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts), "subscores": subscores}

    spl = report_search.lower()

    # CRITERION 1: Report Exists with Exact Name (20 points)
    if found_report:
        score += 20
        feedback_parts.append(f"Report named correctly: '{report_name}'")
        subscores['report_named_correctly'] = True
    else:
        feedback_parts.append(f"Report name mismatch (found: '{report_name}')")
        subscores['report_named_correctly'] = False

    # CRITERION 2: Data Source Valid (15 points)
    # Checks that it queries web logs and isn't gaming via makeresults
    valid_source = ('web_logs' in spl or 'tutorial' in spl or 'access' in spl or 'sourcetype' in spl) and 'makeresults' not in spl
    if valid_source:
        score += 15
        feedback_parts.append("Valid web data source queried")
        subscores['data_source_valid'] = True
    else:
        feedback_parts.append("FAIL: Search does not query expected web_logs/tutorial index")
        subscores['data_source_valid'] = False

    # CRITERION 3: Row-level computation (20 points)
    # Must use eval with len()
    has_eval_len = bool(re.search(r'\|\s*eval\s+[^=]+=\s*len\s*\(', spl))
    if has_eval_len:
        score += 20
        feedback_parts.append("Row-level eval len() function used")
        subscores['row_level_eval'] = True
    else:
        feedback_parts.append("FAIL: Missing eval len() computation")
        subscores['row_level_eval'] = False

    # CRITERION 4: Entity aggregation (25 points)
    # Must use stats, avg, max, by
    has_stats = bool(re.search(r'\|\s*stats\s+', spl))
    has_avg = bool(re.search(r'avg\s*\(', spl))
    has_max = bool(re.search(r'max\s*\(', spl))
    has_by = bool(re.search(r'\bby\b', spl))
    entity_agg = has_stats and has_avg and has_max and has_by

    if entity_agg:
        score += 25
        feedback_parts.append("Proper stats aggregation applied")
        subscores['entity_aggregation'] = True
    else:
        missing = [m for m, b in zip(["stats", "avg()", "max()", "by"], [has_stats, has_avg, has_max, has_by]) if not b]
        feedback_parts.append(f"FAIL: Aggregation missing components: {missing}")
        subscores['entity_aggregation'] = False

    # CRITERION 5: Pipeline Ordering & Filtering (20 points)
    # Must use where command with > 60
    has_where = bool(re.search(r'\|\s*where\s+[^>|]+>\s*60', spl))
    if has_where:
        score += 20
        feedback_parts.append("Post-aggregation where filtering correct")
        subscores['pipeline_filtering'] = True
    else:
        feedback_parts.append("FAIL: Missing or incorrect 'where ... > 60' filter")
        subscores['pipeline_filtering'] = False

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "search_query": report_search
        }
    }