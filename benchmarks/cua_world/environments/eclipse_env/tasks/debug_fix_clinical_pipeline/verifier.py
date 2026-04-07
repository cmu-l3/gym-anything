import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_debug_fix_clinical_pipeline(traj, env_info, task_info):
    """
    Verify the debug_fix_clinical_pipeline task.

    Scoring breakdown (100 pts total, pass >= 70):
    - Bug 1 fixed: PatientFilter uses > not >=         (15 pts)
    - Bug 2 fixed: computePopulationBaseline used       (15 pts)
    - Bug 3 fixed: Builder copies sampleSize            (15 pts)
    - Build config fixed: Java 17 in trial-report       (10 pts)
    - Build passes: mvn clean test exit 0               (20 pts)
    - All 15 tests pass                                 (20 pts)
    - Files were actually modified (anti-gaming)         (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env('/tmp/clinical_pipeline_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        logger.warning(f"Could not read result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result: {e}",
            "subscores": {}
        }

    # --- Bug 1: PatientFilter fix (15 pts) ---
    if result.get('bug1_fixed', False):
        score += 15
        subscores['bug1_patientfilter'] = True
        feedback_parts.append("Bug 1 fixed: PatientFilter uses > for minWeeks (15/15)")
    else:
        subscores['bug1_patientfilter'] = False
        feedback_parts.append("Bug 1 NOT fixed: PatientFilter still uses >= (0/15)")

    # --- Bug 2: StatisticalAnalyzer fix (15 pts) ---
    if result.get('bug2_fixed', False):
        score += 15
        subscores['bug2_analyzer'] = True
        feedback_parts.append("Bug 2 fixed: computePopulationBaseline used (15/15)")
    else:
        subscores['bug2_analyzer'] = False
        feedback_parts.append("Bug 2 NOT fixed: still using computeGroupBaseline (0/15)")

    # --- Bug 3: TrialSummary Builder fix (15 pts) ---
    if result.get('bug3_fixed', False):
        score += 15
        subscores['bug3_builder'] = True
        feedback_parts.append("Bug 3 fixed: Builder copies sampleSize (15/15)")
    else:
        subscores['bug3_builder'] = False
        feedback_parts.append("Bug 3 NOT fixed: Builder.build() missing sampleSize copy (0/15)")

    # --- Build config fix (10 pts) ---
    if result.get('build_config_fixed', False):
        score += 10
        subscores['build_config'] = True
        feedback_parts.append("Build config fixed: trial-report uses Java 17 (10/10)")
    else:
        subscores['build_config'] = False
        feedback_parts.append("Build config NOT fixed: trial-report still on Java 11 (0/10)")

    # --- Build passes (20 pts) ---
    build_success = result.get('build_success', False)
    if build_success:
        score += 20
        subscores['build_passes'] = True
        feedback_parts.append("Build passes: mvn clean test succeeded (20/20)")
    else:
        subscores['build_passes'] = False
        exit_code = result.get('build_exit_code', -1)
        feedback_parts.append(f"Build FAILED: exit code {exit_code} (0/20)")

    # --- All tests pass (20 pts) ---
    tests_run = int(result.get('tests_run', 0))
    tests_failed = int(result.get('tests_failed', 0))
    tests_error = int(result.get('tests_error', 0))
    tests_passing = tests_run - tests_failed - tests_error

    if tests_run >= 15 and tests_failed == 0 and tests_error == 0:
        score += 20
        subscores['all_tests_pass'] = True
        feedback_parts.append(f"All {tests_run} tests pass (20/20)")
    elif tests_run > 0:
        # Partial credit: 1 pt per passing test above 8
        partial = min(15, max(0, tests_passing - 8))
        score += partial
        subscores['all_tests_pass'] = False
        feedback_parts.append(
            f"Tests: {tests_passing}/{tests_run} passing, "
            f"{tests_failed} failures, {tests_error} errors ({partial}/20)"
        )
    else:
        subscores['all_tests_pass'] = False
        feedback_parts.append("No tests ran (0/20)")

    # --- Files modified (anti-gaming 5 pts) ---
    files_changed = sum([
        result.get('filter_changed', False),
        result.get('analyzer_changed', False),
        result.get('summary_changed', False),
        result.get('report_pom_changed', False),
    ])
    if files_changed >= 3:
        score += 5
        subscores['files_modified'] = True
        feedback_parts.append(f"{files_changed}/4 target files modified (5/5)")
    elif files_changed >= 1:
        score += 2
        subscores['files_modified'] = 'partial'
        feedback_parts.append(f"Only {files_changed}/4 target files modified (2/5)")
    else:
        subscores['files_modified'] = False
        feedback_parts.append("No target files modified (0/5)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
