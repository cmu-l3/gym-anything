#!/usr/bin/env python3
"""
Verifier for openice_test_suite_execution task.

Scoring Criteria (100 points total):
1. Test Execution (40 pts):
   - New JUnit XML artifacts found (proof that tests were actually run).
   - Counts > 0 for tests executed.
2. Report Existence (20 pts):
   - Report file exists, is recent, and has sufficient content.
3. Report Content (30 pts):
   - Contains Git commit hash.
   - Contains numeric statistics (Tests, Failures, etc.).
   - Mentions module names.
4. Data Consistency (10 pts):
   - Reported numbers match XML ground truth within tolerance.
   
Pass Threshold: 50 points (must have at least run tests OR written a very convincing report with evidence)
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

def verify_openice_test_suite_execution(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Test Execution (XML Artifacts)
    xml_count = result.get('xml_files_found', 0)
    stats = result.get('stats_from_xml', {})
    tests_run = stats.get('tests', 0)
    
    if xml_count > 0 and tests_run > 0:
        score += 40
        feedback_parts.append(f"Tests executed successfully ({tests_run} tests in {xml_count} files)")
    elif xml_count > 0:
        score += 20
        feedback_parts.append("Test artifacts created but show 0 tests run (build failure?)")
    else:
        feedback_parts.append("No new test execution artifacts found")
        
    # 2. Verify Report Existence
    report = result.get('report', {})
    report_exists = report.get('exists', False)
    report_content = report.get('content_snippet', "")
    
    if report_exists and len(report_content) > 100:
        score += 20
        feedback_parts.append("Report file exists with content")
    elif report_exists:
        score += 5
        feedback_parts.append("Report file exists but content is sparse")
    else:
        feedback_parts.append("Report file missing")

    # 3. Verify Report Content Analysis
    content_score = 0
    ground_truth = result.get('ground_truth', {})
    git_hash = ground_truth.get('git_hash', "UNKNOWN")
    
    if report_exists:
        # Check for Git Hash
        if git_hash in report_content or (len(git_hash) >= 7 and git_hash[:7] in report_content):
            content_score += 10
            feedback_parts.append("Report includes correct Git hash")
        
        # Check for statistics (regex for numbers associated with test keywords)
        # e.g., "Tests: 50", "Passed: 45", "Total: 100"
        if re.search(r'(tests?|total|run).{0,10}\d+', report_content, re.IGNORECASE):
            content_score += 10
            feedback_parts.append("Report includes test statistics")
            
        # Check for module names
        modules = result.get('modules_tested', "").split(',')
        found_modules = [m for m in modules if m and m in report_content]
        if found_modules:
            content_score += 10
            feedback_parts.append(f"Report references tested modules ({len(found_modules)} found)")
        
        score += content_score

    # 4. Data Consistency (Cross-Validation)
    consistency_score = 0
    if report_exists and tests_run > 0:
        # Try to find the total reported in the text
        # Look for the exact number of tests run
        if str(tests_run) in report_content:
            consistency_score += 10
            feedback_parts.append("Reported statistics match XML data")
    
    score += consistency_score

    # Final verdict
    passed = score >= 50
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "xml_files": xml_count,
            "tests_run": tests_run,
            "report_exists": report_exists,
            "modules": result.get('modules_tested')
        }
    }