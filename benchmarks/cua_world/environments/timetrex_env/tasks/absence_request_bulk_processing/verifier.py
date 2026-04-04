import json
import os
import tempfile


# status_id meanings in TimeTrex request table
STATUS_PENDING = "10"
STATUS_APPROVED = "20"
STATUS_DENIED = "30"

# Expected outcome per policy (approve=20, deny=30)
EXPECTED = {
    "lisa_anderson_status": STATUS_APPROVED,    # 1-day Sick → approve
    "tom_peterson_status": STATUS_DENIED,        # 3-day Vacation → deny
    "olivia_martinez_status": STATUS_APPROVED,   # 2-day Vacation → approve
    "kevin_chang_status": STATUS_DENIED,         # 5-day Vacation → deny
    "sandra_brown_status": STATUS_APPROVED,      # 1-day Sick → approve
}

LABELS = {
    "lisa_anderson_status": "Lisa Anderson (1-day Sick → approve)",
    "tom_peterson_status": "Tom Peterson (3-day Vacation → deny)",
    "olivia_martinez_status": "Olivia Martinez (2-day Vacation → approve)",
    "kevin_chang_status": "Kevin Chang (5-day Vacation → deny)",
    "sandra_brown_status": "Sandra Brown (1-day Sick → approve)",
}


def verify_absence_request_bulk_processing(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "absence_request_bulk_processing"
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

    # Anti-gaming: if all statuses are already non-Pending and we never ran, that's a fluke
    # but we can't detect it without a baseline; rely on do-nothing test returning all "10"
    score = 0
    parts = []
    points_per = 20  # 5 requests × 20 pts = 100

    for key, expected_status in EXPECTED.items():
        actual = str(result.get(key, STATUS_PENDING)).strip()
        label = LABELS[key]

        if actual == expected_status:
            score += points_per
            action = "approved" if expected_status == STATUS_APPROVED else "denied"
            parts.append(f"{label}: correctly {action} ({points_per}/{points_per})")
        elif actual == STATUS_PENDING:
            parts.append(f"{label}: still Pending (0/{points_per})")
        else:
            action_actual = "approved" if actual == STATUS_APPROVED else "denied"
            action_expected = "approved" if expected_status == STATUS_APPROVED else "denied"
            parts.append(f"{label}: wrong action — got {action_actual}, expected {action_expected} (0/{points_per})")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts) if parts else "No criteria evaluated",
    }
