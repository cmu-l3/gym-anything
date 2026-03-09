import json
import os
import tempfile


def verify_increase_test_coverage(traj, env_info, task_info):
    """
    Verify that the agent increased test coverage of the clinical_validator library:
      Coverage >= 50% (20 pts): partial progress
      Coverage >= 65% (20 pts additional): approaching goal
      Coverage >= 75% (25 pts additional): goal achieved
      All tests pass (20 pts): no regressions
      Demographics >= 70% coverage (5 pts): module-level criterion
      Labs >= 70% coverage (5 pts): module-level criterion
      Medications >= 70% coverage (5 pts): module-level criterion
    Pass threshold: 60 (requires at least 75% coverage OR 65% + no regression)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available",
        }

    task_name = "increase_test_coverage"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result JSON malformed: {e}",
        }

    score = 0
    parts = []
    issues = []

    coverage = result.get("total_coverage_pct", 0)
    all_pass = result.get("all_tests_pass", False)
    tests_passed = result.get("tests_passed", 0)
    tests_failed = result.get("tests_failed", 0)

    # No-regression check (worth 20 pts)
    if all_pass:
        score += 20
        parts.append(f"All {tests_passed} tests pass — no regressions (20/20)")
    else:
        issues.append(
            f"Test regression: {tests_failed} test(s) failing. "
            "All original tests must continue to pass."
        )

    # Coverage tiers
    if coverage >= 50:
        score += 20
        parts.append(f"Coverage >= 50% achieved: {coverage}% (20/20)")
    else:
        issues.append(
            f"Coverage {coverage}% is below 50%. "
            "Add tests for error paths and boundary values."
        )

    if coverage >= 65:
        score += 20
        parts.append(f"Coverage >= 65% achieved: {coverage}% (+20)")
    else:
        issues.append(f"Coverage {coverage}% has not reached 65%.")

    if coverage >= 75:
        score += 25
        parts.append(f"Coverage target met: {coverage}% >= 75% (+25)")
    else:
        issues.append(
            f"Coverage {coverage}% has not reached the 75% target. "
            f"Need {75 - coverage} more percentage points."
        )

    # Per-module bonuses (5 pts each)
    dem_cov = result.get("demographics_coverage_pct", 0)
    lab_cov = result.get("labs_coverage_pct", 0)
    med_cov = result.get("medications_coverage_pct", 0)

    if dem_cov >= 70:
        score += 5
        parts.append(f"Demographics coverage {dem_cov}% >= 70% (+5)")
    else:
        issues.append(f"Demographics coverage {dem_cov}% < 70%")

    if lab_cov >= 70:
        score += 5
        parts.append(f"Labs coverage {lab_cov}% >= 70% (+5)")
    else:
        issues.append(f"Labs coverage {lab_cov}% < 70%")

    if med_cov >= 70:
        score += 5
        parts.append(f"Medications coverage {med_cov}% >= 70% (+5)")
    else:
        issues.append(f"Medications coverage {med_cov}% < 70%")

    score = min(score, 100)
    passed = score >= 60

    summary = (
        f"Score: {score}/100 | "
        f"Coverage: {coverage}% (demographics={dem_cov}%, labs={lab_cov}%, medications={med_cov}%) | "
        f"Tests: {tests_passed} passing, {tests_failed} failing"
    )

    all_feedback = parts + issues
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{summary} | " + " | ".join(all_feedback) if all_feedback else summary,
    }
