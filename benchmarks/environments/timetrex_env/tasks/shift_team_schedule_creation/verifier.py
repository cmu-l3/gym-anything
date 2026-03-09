import json
import os
import tempfile


def verify_shift_team_schedule_creation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "shift_team_schedule_creation"
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

    entries = result.get("entries", [])

    # Anti-gaming: if initial_count was already 12, something is wrong
    initial = int(result.get("initial_count", 0))
    total = int(result.get("total_schedules", 0))
    if initial >= 12 and total >= 12:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Initial schedule count was already >=12; baseline contaminated",
        }

    # Score: each of 12 entries is worth ~8 points. Full credit = 96 + 4 bonus for all correct.
    # We score based on: entry found (4pts) + start_ok (2pts) + end_ok (2pts) = 8pts each
    found_count = 0
    time_correct_count = 0
    issues = []

    for entry in entries:
        emp = entry.get("emp", "?")
        date = entry.get("date", "?")
        found = entry.get("found", False)
        start_ok = entry.get("start_ok", False)
        end_ok = entry.get("end_ok", False)

        if found:
            found_count += 1
            if start_ok and end_ok:
                time_correct_count += 1
            else:
                actual_start = entry.get("start_actual", "?")
                actual_end = entry.get("end_actual", "?")
                issues.append(f"{emp} on {date}: wrong times (got {actual_start[:5] if actual_start else '?'}-{actual_end[:5] if actual_end else '?'})")
        else:
            issues.append(f"{emp} on {date}: not found")

    # Score: 6 pts per entry found + 2 bonus per entry with correct times = max 96 + partial bonuses
    score = found_count * 6 + time_correct_count * 2
    # Normalize to 100 (max = 12*8 = 96 → we give 4 bonus if all 12 have correct times)
    if time_correct_count == 12:
        score += 4

    score = min(score, 100)
    passed = score >= 60

    parts = [
        f"Schedules found: {found_count}/12",
        f"Times correct: {time_correct_count}/12",
    ]
    if issues:
        parts.append("Issues: " + "; ".join(issues[:5]))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts),
    }
