import json
import os
import tempfile


def verify_fix_security_vulnerabilities(traj, env_info, task_info):
    """
    Verify that the agent fixed all 4 OWASP-class vulnerabilities in the inventory API:
      Vuln 1 (25 pts): Hardcoded JWT secret replaced with environment variable
      Vuln 2 (25 pts): SQL injection in search_items fixed with parameterized query
      Vuln 3 (25 pts): IDOR in get_item fixed with ownership check
      Vuln 4 (25 pts): Path traversal in export_item_report fixed with path sanitization
    Bonus: All functional tests still pass (required for partial credit on each)
    Pass threshold: 60 (must fix at least 2-3 vulnerabilities)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available",
        }

    task_name = "fix_security_vulnerabilities"
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

    functional_ok = result.get("functional_tests_ok", False)
    if not functional_ok:
        issues.append(
            "WARNING: Some functional tests are failing — fixes may have broken existing behavior"
        )

    # Criterion 1: Hardcoded JWT secret
    if result.get("vuln1_hardcoded_secret_fixed", False):
        score += 25
        parts.append("Vuln 1 fixed: JWT secret loaded from environment variable (25/25)")
    else:
        issues.append(
            "Vuln 1 NOT fixed: JWT_SECRET is still hardcoded in app/auth.py — "
            "must use os.environ['JWT_SECRET'] or os.getenv('JWT_SECRET')"
        )

    # Criterion 2: SQL injection
    if result.get("vuln2_sql_injection_fixed", False):
        score += 25
        parts.append("Vuln 2 fixed: SQL injection remediated with parameterized query (25/25)")
    else:
        issues.append(
            "Vuln 2 NOT fixed: search_items still uses f-string interpolation in SQL — "
            "must use parameterized query with ? placeholder"
        )

    # Criterion 3: IDOR
    if result.get("vuln3_idor_fixed", False):
        score += 25
        parts.append("Vuln 3 fixed: IDOR remediated with ownership check in get_item (25/25)")
    else:
        issues.append(
            "Vuln 3 NOT fixed: get_item still returns items for any authenticated user regardless of ownership — "
            "must check that item.owner_id == current_user.sub"
        )

    # Criterion 4: Path traversal
    if result.get("vuln4_path_traversal_fixed", False):
        score += 25
        parts.append("Vuln 4 fixed: Path traversal prevented in export_item_report (25/25)")
    else:
        issues.append(
            "Vuln 4 NOT fixed: export_item_report still uses item['location'] directly in file path — "
            "must sanitize with os.path.basename() or validate resolved path stays within REPORTS_BASE_DIR"
        )

    score = min(score, 100)
    passed = score >= 60

    tests_passed = result.get("tests_passed", 0)
    tests_failed = result.get("tests_failed", 0)
    summary = f"Score: {score}/100 | Tests: {tests_passed} passing, {tests_failed} failing"

    all_feedback = parts + issues
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{summary} | " + " | ".join(all_feedback) if all_feedback else summary,
    }
