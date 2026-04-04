import json
import os
import tempfile


def verify_payroll_wage_audit_correction(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "payroll_wage_audit_correction"
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(f"/tmp/{task_name}_result.json", tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON invalid: {e}"}

    # Expected correct wages (as floats, with tolerance)
    CORRECT = {
        "victoria_chen": {"wage": 26.50, "date": "2026-01-01"},
        "marcus_williams": {"wage": 32.00, "date": "2026-01-01"},
        "patricia_nguyen": {"wage": 22.75, "date": "2026-01-01"},
    }

    score = 0
    parts = []

    def wage_correct(result_key, expected_wage, label):
        nonlocal score
        raw = result.get(result_key, "")
        if not raw:
            parts.append(f"{label}: no wage found (0/33)")
            return False
        try:
            actual = round(float(raw), 2)
        except ValueError:
            parts.append(f"{label}: wage not numeric (0/33)")
            return False
        if abs(actual - expected_wage) < 0.005:
            score += 33
            parts.append(f"{label}: wage correct ${actual:.2f} (33/33)")
            return True
        else:
            parts.append(f"{label}: wage wrong — got ${actual:.2f}, expected ${expected_wage:.2f} (0/33)")
            return False

    def date_correct(result_key, expected_date, label):
        raw = result.get(result_key, "")
        if not raw:
            return False
        # Accept "2026-01-01" anywhere in the string
        return expected_date in raw

    wage_correct("victoria_chen_wage", CORRECT["victoria_chen"]["wage"], "Victoria Chen")
    wage_correct("marcus_williams_wage", CORRECT["marcus_williams"]["wage"], "Marcus Williams")
    wage_correct("patricia_nguyen_wage", CORRECT["patricia_nguyen"]["wage"], "Patricia Nguyen")

    # Bonus point for getting the third one exactly right (brings total to 100 if all correct)
    # Adjust: 33+33+34 = 100
    # Recalculate: give 34 for patricia to reach 100
    # Actually let's redo: 34+33+33 for chen+williams+nguyen
    # The wage_correct above gave 33 each = 99. Add 1 bonus if all three correct.
    if score == 99:
        score = 100
        parts.append("All three wages corrected (+1 rounding bonus)")

    # Effective date spot-check (informational, not scored separately)
    date_issues = []
    for emp_key, emp_data in CORRECT.items():
        result_date_key = f"{emp_key}_effective_date"
        if not date_correct(result_date_key, emp_data["date"], emp_key):
            date_issues.append(emp_key.replace("_", " ").title())

    if date_issues:
        parts.append(f"Effective date may be wrong for: {', '.join(date_issues)} (dates not scored separately but should be 2026-01-01)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts) if parts else "No criteria met",
    }
