import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_jacoco_coverage_enforcement(traj, env_info, task_info):
    """
    Verify the JaCoCo coverage enforcement task.

    Scoring breakdown (100 pts total, pass >= 70):
    - JaCoCo plugin declared in pom.xml (15 pts)
    - Test files >= 3 new (15 pts)
    - Mockito usage in tests (20 pts)
    - JaCoCo HTML report exists after build (20 pts)
    - Line coverage >= 70% (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    min_coverage = int(metadata.get('min_coverage_pct', 70))

    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env('/tmp/jacoco_result.json', tmp_path)
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

    initial_jacoco = int(result.get('initial_jacoco_count', 0))
    jacoco_pom = int(result.get('jacoco_pom_count', 0))
    new_jacoco = jacoco_pom - initial_jacoco

    # --- Criterion 1: JaCoCo in pom.xml (15 pts) ---
    if new_jacoco >= 3:  # At least a few jacoco references (plugin + executions)
        score += 15
        subscores['jacoco_configured'] = True
        feedback_parts.append(f"JaCoCo plugin configured in pom.xml (15/15)")
    elif new_jacoco >= 1:
        score += 7
        subscores['jacoco_configured'] = 'partial'
        feedback_parts.append(f"JaCoCo partially configured ({new_jacoco} references) (7/15)")
    else:
        subscores['jacoco_configured'] = False
        feedback_parts.append("JaCoCo NOT configured in pom.xml (0/15)")

    # --- Criterion 2: Test files (15 pts) ---
    new_test_count = int(result.get('new_test_count', 0))
    current_test_count = int(result.get('current_test_count', 0))

    if new_test_count >= 3:
        score += 15
        subscores['test_files'] = True
        feedback_parts.append(f"{new_test_count} new test files created (15/15)")
    elif new_test_count >= 2:
        score += 10
        subscores['test_files'] = 'partial'
        feedback_parts.append(f"{new_test_count} new test files created (10/15)")
    elif new_test_count >= 1:
        score += 5
        subscores['test_files'] = 'partial'
        feedback_parts.append(f"Only {new_test_count} new test file(s) created (5/15)")
    else:
        subscores['test_files'] = False
        feedback_parts.append("No new test files created (0/15)")

    # --- Criterion 3: Mockito usage (20 pts) ---
    mockito_count = int(result.get('mockito_count', 0))
    if mockito_count >= 10:
        score += 20
        subscores['mockito_used'] = True
        feedback_parts.append(f"Mockito heavily used ({mockito_count} usages) (20/20)")
    elif mockito_count >= 5:
        score += 15
        subscores['mockito_used'] = 'partial'
        feedback_parts.append(f"Mockito used ({mockito_count} usages) (15/20)")
    elif mockito_count >= 1:
        score += 7
        subscores['mockito_used'] = 'partial'
        feedback_parts.append(f"Mockito minimally used ({mockito_count} usages) (7/20)")
    else:
        subscores['mockito_used'] = False
        feedback_parts.append("Mockito NOT used in tests (0/20)")

    # --- Criterion 4: JaCoCo HTML report exists (20 pts) ---
    report_html = result.get('report_html_exists', False)
    report_xml = result.get('report_xml_exists', False)
    build_success = result.get('build_success', False)

    if report_html and build_success:
        score += 20
        subscores['report_generated'] = True
        feedback_parts.append("JaCoCo HTML report generated (20/20)")
    elif report_html:
        score += 15
        subscores['report_generated'] = 'partial'
        feedback_parts.append("JaCoCo HTML report exists but build had issues (15/20)")
    elif build_success and report_xml:
        score += 10
        subscores['report_generated'] = 'partial'
        feedback_parts.append("XML report exists, HTML report missing (10/20)")
    else:
        subscores['report_generated'] = False
        feedback_parts.append("JaCoCo HTML report NOT generated (0/20)")

    # --- Criterion 5: Coverage >= 70% (30 pts) ---
    coverage_pct = int(result.get('coverage_pct', 0))
    html_coverage = int(result.get('html_coverage', 0))
    # Use whichever is higher (both derived from jacoco output)
    effective_coverage = max(coverage_pct, html_coverage)

    if effective_coverage >= min_coverage:
        score += 30
        subscores['coverage_met'] = True
        feedback_parts.append(f"Line coverage {effective_coverage}% >= {min_coverage}% target (30/30)")
    elif effective_coverage >= min_coverage - 15:
        partial = 15
        score += partial
        subscores['coverage_met'] = 'partial'
        feedback_parts.append(f"Line coverage {effective_coverage}% (close to {min_coverage}% target) ({partial}/30)")
    elif effective_coverage >= 30:
        partial = 8
        score += partial
        subscores['coverage_met'] = 'partial'
        feedback_parts.append(f"Line coverage {effective_coverage}% (below {min_coverage}% target) ({partial}/30)")
    else:
        subscores['coverage_met'] = False
        feedback_parts.append(f"Line coverage {effective_coverage}% (far below {min_coverage}% target) (0/30)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
