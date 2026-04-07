#!/usr/bin/env python3
"""Verifier for splunk_metrics_pipeline_conversion task.

Verifies:
1. Index 'auth_metrics' created.
2. Index 'auth_metrics' is explicitly a 'metric' datatype.
3. Saved report 'Auth_Metrics_Rollup' exists and is scheduled.
4. Saved report SPL utilizes 'mcollect' targeting 'auth_metrics'.
5. Index contains data (proves backfill / execution occurred).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_metrics_pipeline_conversion(traj, env_info, task_info):
    """Verify that the agent successfully built and backfilled a metrics pipeline."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_index_name = metadata.get('expected_index_name', 'auth_metrics')
    expected_datatype = metadata.get('expected_datatype', 'metric')
    expected_report_name = metadata.get('expected_report_name', 'Auth_Metrics_Rollup')
    expected_command = metadata.get('expected_command', 'mcollect')

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
    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: Index Exists
    index_exists = analysis.get('index_exists', False)
    if index_exists:
        score += 20
        feedback_parts.append(f"Index '{expected_index_name}' exists")
        subscores['index_exists'] = True
    else:
        feedback_parts.append(f"FAIL: Index '{expected_index_name}' does not exist")
        subscores['index_exists'] = False

    # Criterion 2: Index Datatype is Metric
    datatype = analysis.get('datatype', 'unknown')
    if index_exists and datatype == expected_datatype:
        score += 20
        feedback_parts.append("Index configured correctly as Metrics type")
        subscores['is_metric_type'] = True
    elif index_exists:
        feedback_parts.append(f"FAIL: Index datatype is '{datatype}', expected '{expected_datatype}'")
        subscores['is_metric_type'] = False
    else:
        subscores['is_metric_type'] = False

    # Criterion 3: Scheduled Report Exists
    search_exists = analysis.get('search_exists', False)
    is_scheduled = analysis.get('is_scheduled', False)
    
    if search_exists and is_scheduled:
        score += 20
        feedback_parts.append(f"Scheduled report '{expected_report_name}' exists")
        subscores['report_exists_scheduled'] = True
    elif search_exists:
        score += 10
        feedback_parts.append(f"PARTIAL: Report '{expected_report_name}' exists but is NOT scheduled")
        subscores['report_exists_scheduled'] = False
    else:
        feedback_parts.append(f"FAIL: Report '{expected_report_name}' does not exist")
        subscores['report_exists_scheduled'] = False

    # Criterion 4: Uses mcollect command correctly
    spl = analysis.get('spl', '').lower()
    if search_exists:
        has_mcollect = expected_command in spl
        has_target_idx = expected_index_name in spl
        if has_mcollect and has_target_idx:
            score += 20
            feedback_parts.append("Report SPL correctly uses mcollect targeting the metrics index")
            subscores['uses_mcollect'] = True
        elif has_mcollect:
            score += 10
            feedback_parts.append("PARTIAL: SPL uses mcollect, but does not explicitly target the correct index name")
            subscores['uses_mcollect'] = False
        else:
            feedback_parts.append(f"FAIL: SPL does not use '{expected_command}' command (SPL: {spl[:50]}...)")
            subscores['uses_mcollect'] = False
    else:
        subscores['uses_mcollect'] = False

    # Criterion 5: Metrics index has been backfilled
    total_event_count = analysis.get('total_event_count', 0)
    mstats_count = analysis.get('mstats_count', 0)
    has_data = total_event_count > 0 or mstats_count > 0

    if has_data and index_exists:
        score += 20
        feedback_parts.append(f"Metrics index successfully populated with data (events: {max(total_event_count, mstats_count)})")
        subscores['data_backfilled'] = True
    elif index_exists:
        feedback_parts.append("FAIL: Metrics index is empty. You did not run the search to backfill historical data.")
        subscores['data_backfilled'] = False
    else:
        subscores['data_backfilled'] = False

    # Final Evaluation
    # Note: 80 is the passing threshold as per task design
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "datatype_found": datatype,
            "spl_preview": spl[:100],
            "is_scheduled": is_scheduled,
            "total_event_count": total_event_count,
            "mstats_count": mstats_count
        }
    }