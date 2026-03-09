#!/usr/bin/env python3
"""Stub verifier for create_database task.
Actual verification is done externally via VLM evaluators.

Programmatic check: verify LibraryDB database was created in OrientDB.
"""
import urllib.request
import json
import base64


def _api(path):
    auth = base64.b64encode(b"root:GymAnything123!").decode()
    req = urllib.request.Request(
        f"http://localhost:2480{path}",
        headers={"Authorization": f"Basic {auth}"},
        method="GET"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except Exception:
        return {}


def verify_create_database(traj, env_info, task_info):
    """Check that LibraryDB database was created."""
    data = _api("/listDatabases")
    databases = data.get("databases", [])

    # Case-insensitive check
    db_names_lower = [d.lower() for d in databases]
    if "librarydb" in db_names_lower:
        actual_name = databases[db_names_lower.index("librarydb")]
        return {"passed": True, "score": 100,
                "feedback": f"LibraryDB database created successfully (found as '{actual_name}')"}

    return {"passed": False, "score": 0,
            "feedback": f"LibraryDB not found. Available databases: {sorted(databases)}"}
