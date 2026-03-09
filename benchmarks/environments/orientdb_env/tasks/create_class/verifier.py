#!/usr/bin/env python3
"""Stub verifier for create_class task.
Actual verification is done externally via VLM evaluators.

Programmatic check: verify 'Airports' class exists in demodb with all required
properties (Name mandatory, IATA_Code, City) and extends V.
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


def verify_create_class(traj, env_info, task_info):
    """Check that Airports class exists with all required properties."""
    data = _api("/database/demodb")
    classes = {c["name"]: c for c in data.get("classes", [])}

    if "Airports" not in classes:
        return {"passed": False, "score": 0,
                "feedback": "Airports class not found in demodb"}

    airports = classes["Airports"]

    # Check superclass extends V
    superclasses = airports.get("superClasses", airports.get("superClass", []))
    if isinstance(superclasses, str):
        superclasses = [superclasses]
    if "V" not in superclasses:
        return {"passed": False, "score": 30,
                "feedback": f"Airports class does not extend V (superClasses={superclasses})"}

    props = {p["name"]: p for p in airports.get("properties", [])}
    missing = []

    # Check Name property exists
    if "Name" not in props:
        missing.append("Name (String, mandatory)")
    else:
        # Check mandatory flag
        if not props["Name"].get("mandatory", False):
            return {"passed": False, "score": 60,
                    "feedback": "Airports.Name exists but is not set to mandatory=true"}

    # Check IATA_Code property
    if "IATA_Code" not in props:
        missing.append("IATA_Code (String)")

    # Check City property
    if "City" not in props:
        missing.append("City (String)")

    if missing:
        return {"passed": False, "score": 50,
                "feedback": f"Airports class is missing properties: {missing}"}

    return {"passed": True, "score": 100,
            "feedback": (f"Airports class created correctly: extends V, "
                         f"properties {sorted(props.keys())} with Name mandatory=true")}
