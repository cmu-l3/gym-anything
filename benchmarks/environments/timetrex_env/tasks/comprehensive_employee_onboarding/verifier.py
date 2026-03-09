import json
import os
import tempfile


def verify_comprehensive_employee_onboarding(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "comprehensive_employee_onboarding"
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
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON invalid: {e}"}

    score = 0
    parts = []

    # ---- Criterion 1: Wage (30 pts) ----
    raw_wage = result.get("wage", "")
    wage_date = result.get("wage_effective_date", "")
    wage_ok = False
    if raw_wage:
        try:
            actual_wage = round(float(raw_wage), 2)
            if abs(actual_wage - 19.50) < 0.005:
                wage_ok = True
        except ValueError:
            pass

    date_ok = "2026-02-01" in (wage_date or "")

    if wage_ok and date_ok:
        score += 30
        parts.append("Wage $19.50 effective 2026-02-01 (30/30)")
    elif wage_ok:
        score += 20
        parts.append(f"Wage $19.50 correct but effective date wrong (got '{wage_date}') (20/30)")
    elif raw_wage:
        try:
            actual_wage = round(float(raw_wage), 2)
            parts.append(f"Wage wrong: got ${actual_wage:.2f}, expected $19.50 (0/30)")
        except ValueError:
            parts.append(f"Wage not numeric: '{raw_wage}' (0/30)")
    else:
        parts.append("No wage record found for Robert Nakamura (0/30)")

    # ---- Criterion 2: Week 1 schedule (35 pts) ----
    week1 = result.get("week1", [])
    w1_found = sum(1 for e in week1 if e.get("found", False))
    w1_correct = sum(1 for e in week1 if e.get("found") and e.get("start_ok") and e.get("end_ok"))

    if w1_correct == 5:
        score += 35
        parts.append("Week 1 schedule: all 5 days correct 07:00-15:00 (35/35)")
    elif w1_found == 5 and w1_correct < 5:
        score += 20
        issues = [e["date"] for e in week1 if not (e.get("start_ok") and e.get("end_ok"))]
        parts.append(f"Week 1: 5 days found but wrong times on {issues} (20/35)")
    elif w1_found > 0:
        score += w1_found * 4
        parts.append(f"Week 1: only {w1_found}/5 days scheduled ({w1_found * 4}/35)")
    else:
        parts.append("Week 1 (Mar 9-13): no schedule entries found (0/35)")

    # ---- Criterion 3: Week 2 schedule (35 pts) ----
    week2 = result.get("week2", [])
    w2_found = sum(1 for e in week2 if e.get("found", False))
    w2_correct = sum(1 for e in week2 if e.get("found") and e.get("start_ok") and e.get("end_ok"))

    if w2_correct == 5:
        score += 35
        parts.append("Week 2 schedule: all 5 days correct 07:00-15:00 (35/35)")
    elif w2_found == 5 and w2_correct < 5:
        score += 20
        issues = [e["date"] for e in week2 if not (e.get("start_ok") and e.get("end_ok"))]
        parts.append(f"Week 2: 5 days found but wrong times on {issues} (20/35)")
    elif w2_found > 0:
        score += w2_found * 4
        parts.append(f"Week 2: only {w2_found}/5 days scheduled ({w2_found * 4}/35)")
    else:
        parts.append("Week 2 (Mar 16-20): no schedule entries found (0/35)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts) if parts else "No criteria met",
    }
