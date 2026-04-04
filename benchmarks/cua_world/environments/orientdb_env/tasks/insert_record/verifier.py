#!/usr/bin/env python3
"""Stub verifier for insert_record task.
Actual verification is done externally via VLM evaluators.

Programmatic check: verify Portugal record exists in Countries with correct Type.
"""
import urllib.request
import json
import base64


def _sql(db, command):
    auth = base64.b64encode(b"root:GymAnything123!").decode()
    data = json.dumps({"command": command}).encode()
    req = urllib.request.Request(
        f"http://localhost:2480/command/{db}/sql",
        data=data,
        headers={"Authorization": f"Basic {auth}", "Content-Type": "application/json"},
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except Exception:
        return {}


def verify_insert_record(traj, env_info, task_info):
    """Check that Portugal was inserted with Name='Portugal' and Type='European'."""
    result = _sql("demodb", "SELECT Name, Type FROM Countries WHERE Name='Portugal'")
    records = result.get("result", [])

    if not records:
        return {"passed": False, "score": 0,
                "feedback": "No Countries record found with Name='Portugal'"}

    rec = records[0]
    actual_type = rec.get("Type", "")

    if actual_type != "European":
        return {"passed": False, "score": 50,
                "feedback": (f"Portugal found but Type='{actual_type}', "
                             f"expected Type='European'")}

    return {"passed": True, "score": 100,
            "feedback": f"Portugal inserted correctly: Name='Portugal', Type='European'"}
