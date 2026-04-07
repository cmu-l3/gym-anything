#!/usr/bin/env python3
"""Verifier for heat_treat_modbus_config task.

A controls engineer configures a Modbus TCP device and 8 process tags in Crimson 3.0.
6 tags are PLC-mapped to holding registers, and 2 tags are LOCAL (computed values).
Mapping the local tags to Modbus is a disqualifying error.

Scoring (100 points total):
  Subtask 1 — Device Configuration (10 pts):
      Device named Furnace_PLC, IP 192.168.10.20, Port 502.
  Subtask 2 — Tag Presence & Naming (20 pts):
      All 8 required tags exist. 2.5 pts per tag.
  Subtask 3 — Data Type = Float (16 pts):
      Each tag uses Float data type. 2 pts per tag.
  Subtask 4 — Min/Max Engineering Ranges (24 pts):
      Each tag's min/max matches the specification within 2 %. 1.5 pts per limit.
  Subtask 5 — Register Mapping (18 pts):
      6 PLC tags mapped to correct Modbus holding register addresses. 3 pts per tag.
  Subtask 6 — Engineering Unit Label (12 pts):
      Each tag's Label matches the standards document. 1.5 pts per tag.

Pass threshold: 70 / 100.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/heat_treat_modbus_result.json"

EXPECTED_PLC_TAGS = [
    {"name": "TT_601", "data_type": "Float", "min_value": 0.0, "max_value": 2000.0, "address": "40001", "label": "Degrees Fahrenheit"},
    {"name": "TT_602", "data_type": "Float", "min_value": 0.0, "max_value": 2000.0, "address": "40003", "label": "Degrees Fahrenheit"},
    {"name": "TT_603", "data_type": "Float", "min_value": 0.0, "max_value": 400.0,  "address": "40005", "label": "Degrees Fahrenheit"},
    {"name": "PT_601", "data_type": "Float", "min_value": -5.0, "max_value": 15.0,  "address": "40007", "label": "Inches Water Column"},
    {"name": "AT_601", "data_type": "Float", "min_value": 0.0, "max_value": 2.0,    "address": "40009", "label": "Percent Carbon"},
    {"name": "FT_601", "data_type": "Float", "min_value": 0.0, "max_value": 2000.0, "address": "40011", "label": "Gallons per Minute"}
]

EXPECTED_LOCAL_TAGS = [
    {"name": "HRC_601", "data_type": "Float", "min_value": 0.0, "max_value": 70.0, "label": "Rockwell C"},
    {"name": "CT_601",  "data_type": "Float", "min_value": 0.0, "max_value": 1440.0, "label": "Minutes"}
]

ALL_TAGS = EXPECTED_PLC_TAGS + EXPECTED_LOCAL_TAGS
TOLERANCE_PCT = 2.0


def _within_tol(actual, expected, tol=TOLERANCE_PCT):
    if actual is None or expected is None:
        return False
    try:
        a, e = float(actual), float(expected)
    except (TypeError, ValueError):
        return False
    if e == 0.0:
        return abs(a) < 1e-6
    return abs(a - e) / abs(e) * 100.0 <= tol


def _norm_type(s):
    return str(s or "").strip().lower()


def _norm_str(s):
    return str(s or "").strip()


def verify_heat_treat_modbus_config(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found – project not saved or export failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file read error: {e}"}

    # GATE 0: Do-nothing protection
    if not result.get("project_found"):
        return {"passed": False, "score": 0, "feedback": "Project not found. Ensure project is saved as heat_treat_modbus.c3."}

    exported = result.get("tags", [])
    if not exported:
        return {"passed": False, "score": 0, "feedback": "No tags found in the project. Agent configured nothing."}

    tag_map = {str(t.get("name", "")).strip().upper(): t for t in exported}

    # GATE 1: Wrong target
    req_upper = {e["name"].upper() for e in ALL_TAGS}
    if not (req_upper & set(tag_map.keys())):
        return {"passed": False, "score": 0, "feedback": "WRONG TARGET: None of the required process tags were found."}

    # GATE 2: Wrong mapping (Disqualifying error)
    wrong_mapping = result.get("wrong_mapping_tags", [])
    if wrong_mapping:
        return {"passed": False, "score": 0, "feedback": f"WRONG MAPPING: LOCAL software tags {wrong_mapping} were incorrectly mapped to a device."}

    score = 0
    feedback = []

    # S1: Communication Device (10 pts)
    dev = result.get("device_config", {})
    s1 = 0
    if dev.get("name") == "Furnace_PLC": s1 += 4
    if dev.get("ip") == "192.168.10.20": s1 += 3
    if dev.get("port") == "502": s1 += 3
    score += s1
    feedback.append(f"S1-Device({s1}/10)")

    # S2: Tag Presence (20 pts, 2.5/tag)
    s2 = sum(2.5 for e in ALL_TAGS if e["name"].upper() in tag_map)
    score += s2
    feedback.append(f"S2-Presence({s2}/20)")

    # S3: Data Type = Float (16 pts, 2/tag)
    s3 = 0
    for e in ALL_TAGS:
        nm = e["name"].upper()
        if nm in tag_map:
            t = _norm_type(tag_map[nm].get("data_type"))
            if any(x in t for x in ["float", "real", "single"]):
                s3 += 2
    score += s3
    feedback.append(f"S3-DataType({s3}/16)")

    # S4: Min/Max Engineering Ranges (24 pts, 1.5/limit)
    s4 = 0
    for e in ALL_TAGS:
        nm = e["name"].upper()
        if nm in tag_map:
            if _within_tol(tag_map[nm].get("min_value"), e["min_value"]): s4 += 1.5
            if _within_tol(tag_map[nm].get("max_value"), e["max_value"]): s4 += 1.5
    score += s4
    feedback.append(f"S4-Ranges({s4}/24)")

    # S5: Register Mapping (18 pts, 3/tag for 6 PLC tags)
    s5 = 0
    for e in EXPECTED_PLC_TAGS:
        nm = e["name"].upper()
        if nm in tag_map:
            addr = _norm_str(tag_map[nm].get("address")).lstrip('0')
            expected_addr = e["address"].lstrip('0')
            zero_idx = str(int(e["address"]) - 40001)
            
            # Accepts 40001, 1, or embedded substring
            if expected_addr and (addr == expected_addr or addr == zero_idx or expected_addr in _norm_str(tag_map[nm].get("address"))):
                s5 += 3
    score += s5
    feedback.append(f"S5-Mapping({s5}/18)")

    # S6: Engineering Unit Label (12 pts, 1.5/tag)
    s6 = 0
    for e in ALL_TAGS:
        nm = e["name"].upper()
        if nm in tag_map:
            u = _norm_str(tag_map[nm].get("units")).lower()
            if u and (e["label"].lower() in u or u in e["label"].lower()):
                s6 += 1.5
    score += s6
    feedback.append(f"S6-Labels({s6}/12)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback),
        "details": result
    }