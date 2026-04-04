#!/usr/bin/env python3
"""Stub verifier for create_index task.
Actual verification is done externally via VLM evaluators.

Programmatic check: verify a NOTUNIQUE index exists on Hotels.Name in demodb.
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


def verify_create_index(traj, env_info, task_info):
    """Check that a NOTUNIQUE index exists on Hotels.Name."""
    data = _api("/database/demodb")
    for cls in data.get("classes", []):
        if cls["name"] == "Hotels":
            indexes = cls.get("indexes", [])
            for idx in indexes:
                idx_name = idx.get("name", "")
                idx_fields = idx.get("fields", [])
                idx_type = idx.get("type", "").upper()
                # Must be on the Name field
                on_name_field = "Hotels.Name" in idx_name or "Name" in idx_fields
                if not on_name_field:
                    continue
                # Must be NOTUNIQUE type
                if idx_type != "NOTUNIQUE":
                    return {"passed": False, "score": 50,
                            "feedback": (f"Index '{idx_name}' on Hotels.Name found but type is "
                                         f"'{idx_type}', expected 'NOTUNIQUE'")}
                return {"passed": True, "score": 100,
                        "feedback": f"NOTUNIQUE index '{idx_name}' on Hotels.Name found"}
            return {"passed": False, "score": 0,
                    "feedback": "No index found on Hotels.Name property"}

    return {"passed": False, "score": 0, "feedback": "Hotels class not found in demodb"}
