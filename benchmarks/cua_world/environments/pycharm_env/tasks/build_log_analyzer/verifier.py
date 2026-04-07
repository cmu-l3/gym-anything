#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_log_analyzer(traj, env_info, task_info):
    """
    Verify the build_log_analyzer task.
    
    Scoring:
    - Parser tests pass: 35 pts
    - Stats tests pass: 40 pts
    - Anomaly tests pass: 20 pts
    - Clean run (no stubs, no errors): 5 pts
    
    Anti-gaming:
    - Files must be modified
    - Tests must NOT be modified
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    task_name = "build_log_analyzer"
    result_path = "/tmp/task_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}

    score = 0
    feedback_parts = []
    
    # Metadata
    metadata = task_info.get('metadata', {})
    points_parser = metadata.get('points_parser', 35)
    points_stats = metadata.get('points_stats', 40)
    points_anomaly = metadata.get('points_anomaly', 20)
    
    # 1. Check Parser Implementation (35 pts)
    # 4 tests in test_parser
    parser_passed = result.get('parser_tests_passed', 0)
    modified_parser = result.get('modified_parser', False)
    
    if parser_passed >= 4 and modified_parser:
        score += points_parser
        feedback_parts.append(f"Parser implemented and tests pass ({points_parser}/{points_parser})")
    elif parser_passed > 0:
        partial = int((parser_passed / 4) * points_parser)
        score += partial
        feedback_parts.append(f"Parser partially working: {parser_passed}/4 tests ({partial}/{points_parser})")
    else:
        feedback_parts.append("Parser tests failed or file not modified")

    # 2. Check Stats Implementation (40 pts)
    # 3 tests in test_stats
    stats_passed = result.get('stats_tests_passed', 0)
    modified_stats = result.get('modified_stats', False)
    
    if stats_passed >= 3 and modified_stats:
        score += points_stats
        feedback_parts.append(f"Stats implemented and tests pass ({points_stats}/{points_stats})")
    elif stats_passed > 0:
        partial = int((stats_passed / 3) * points_stats)
        score += partial
        feedback_parts.append(f"Stats partially working: {stats_passed}/3 tests ({partial}/{points_stats})")
    else:
        feedback_parts.append("Stats tests failed or file not modified")

    # 3. Check Anomaly Implementation (20 pts)
    # 3 tests in test_anomaly
    anomaly_passed = result.get('anomaly_tests_passed', 0)
    modified_anomaly = result.get('modified_anomaly', False)
    
    if anomaly_passed >= 3 and modified_anomaly:
        score += points_anomaly
        feedback_parts.append(f"Anomaly detection implemented and tests pass ({points_anomaly}/{points_anomaly})")
    elif anomaly_passed > 0:
        partial = int((anomaly_passed / 3) * points_anomaly)
        score += partial
        feedback_parts.append(f"Anomaly detection partially working: {anomaly_passed}/3 tests ({partial}/{points_anomaly})")
    else:
        feedback_parts.append("Anomaly tests failed or file not modified")

    # 4. Clean Run Bonus (5 pts)
    stubs = result.get('stubs_remaining', True)
    if not stubs and result.get('pytest_exit_code') == 0:
        score += 5
        feedback_parts.append("Clean run bonus (+5)")

    # Anti-gaming: Tests Modified
    if result.get('tests_modified', False):
        score = 0
        feedback_parts = ["CRITICAL: Test files were modified. Score reset to 0."]

    passed = score >= metadata.get('pass_threshold', 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }