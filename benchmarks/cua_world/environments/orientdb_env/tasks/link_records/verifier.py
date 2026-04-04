#!/usr/bin/env python3
"""Stub verifier for link_records task.
Actual verification is done externally via VLM evaluators.

Programmatic check: verify HasFriend edge exists from domi@nek.gov to seari@ubu.edu.
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


def verify_link_records(traj, env_info, task_info):
    """Check that HasFriend edge exists from domi@nek.gov to seari@ubu.edu."""
    result = _sql("demodb", (
        "SELECT @rid FROM HasFriend WHERE "
        "out.Email = 'domi@nek.gov' AND "
        "in.Email = 'seari@ubu.edu'"
    ))
    records = result.get("result", [])

    if not records:
        return {"passed": False, "score": 0,
                "feedback": "No HasFriend edge found from domi@nek.gov to seari@ubu.edu"}

    return {"passed": True, "score": 100,
            "feedback": "HasFriend edge successfully created from Isaac Black (domi@nek.gov) to Rosie Thornton (seari@ubu.edu)"}
