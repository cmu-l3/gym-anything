#!/usr/bin/env python3
"""Shared CMDBuild REST API helpers for OpenMaint task scripts."""

import base64
import json
import os
import re
import sys
import urllib.request
import urllib.error

BASE = "http://localhost:8090/cmdbuild/services/rest/v3"

_BASIC_AUTH = base64.b64encode(b"admin:admin").decode()


def api(method, path, token, data=None):
    url = f"{BASE}/{path}"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Basic {_BASIC_AUTH}",
    }
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        print(f"API HTTP {e.code}: {method} {path}", file=sys.stderr)
        try:
            print(e.read().decode()[:500], file=sys.stderr)
        except Exception:
            pass
        return None
    except Exception as e:
        print(f"API error: {method} {path}: {e}", file=sys.stderr)
        return None


def get_token():
    """Return a sentinel token.  Auth is handled via HTTP Basic in api()."""
    return "basic"


def create_card(cls, attrs, token):
    resp = api("POST", f"classes/{cls}/cards", token, attrs)
    if resp and "data" in resp:
        return resp["data"].get("_id")
    return None


def update_card(cls, card_id, attrs, token):
    return api("PUT", f"classes/{cls}/cards/{card_id}", token, attrs)


def get_cards(cls, token, limit=100, filter_str=None):
    params = f"limit={limit}"
    if filter_str:
        params += f"&{filter_str}"
    resp = api("GET", f"classes/{cls}/cards?{params}", token)
    return resp.get("data", []) if resp else []


def get_card(cls, card_id, token):
    resp = api("GET", f"classes/{cls}/cards/{card_id}", token)
    return resp.get("data", {}) if resp else {}


def delete_card(cls, card_id, token):
    return api("DELETE", f"classes/{cls}/cards/{card_id}", token)


def count_cards(cls, token):
    resp = api("GET", f"classes/{cls}/cards?limit=1", token)
    if resp and "meta" in resp:
        return resp["meta"].get("total", 0)
    return 0


def list_classes(token):
    resp = api("GET", "classes?limit=500", token)
    return resp.get("data", []) if resp else []


def find_class(pattern, token):
    for c in list_classes(token):
        name = c.get("_id", "") or c.get("name", "")
        desc = c.get("description", "")
        if re.search(pattern, name, re.IGNORECASE):
            return name
        if re.search(pattern, desc, re.IGNORECASE):
            return name
    return None


def find_all_classes(pattern, token):
    results = []
    for c in list_classes(token):
        name = c.get("_id", "") or c.get("name", "")
        desc = c.get("description", "")
        combined = f"{name} {desc}"
        if re.search(pattern, combined, re.IGNORECASE):
            results.append(name)
    return results


def get_class_attributes(cls, token):
    resp = api("GET", f"classes/{cls}/attributes?limit=200", token)
    return resp.get("data", []) if resp else []


def get_buildings(token):
    return get_cards("Building", token, limit=50)


def get_lookup_values(lookup_type, token):
    resp = api("GET", f"lookup_types/{lookup_type}/values?limit=200", token)
    return resp.get("data", []) if resp else []


def list_processes(token):
    resp = api("GET", "processes?limit=500", token)
    return resp.get("data", []) if resp else []


def find_process(pattern, token):
    for p in list_processes(token):
        name = p.get("_id", "") or p.get("name", "")
        desc = p.get("description", "")
        if re.search(pattern, name, re.IGNORECASE):
            return name
        if re.search(pattern, desc, re.IGNORECASE):
            return name
    return None


def get_process_attributes(process_id, token):
    resp = api("GET", f"processes/{process_id}/attributes?limit=200", token)
    return resp.get("data", []) if resp else []


def get_process_instances(process_id, token, limit=100):
    resp = api("GET", f"processes/{process_id}/instances?limit={limit}", token)
    return resp.get("data", []) if resp else []


def get_process_instance(process_id, instance_id, token):
    resp = api("GET", f"processes/{process_id}/instances/{instance_id}", token)
    return resp.get("data", {}) if resp else {}


def create_process_instance(process_id, attrs, token):
    resp = api("POST", f"processes/{process_id}/instances", token, attrs)
    if resp and "data" in resp:
        return resp["data"].get("_id")
    return None


def update_process_instance(process_id, instance_id, attrs, token):
    return api("PUT", f"processes/{process_id}/instances/{instance_id}", token, attrs)


def count_process_instances(process_id, token):
    resp = api("GET", f"processes/{process_id}/instances?limit=1", token)
    if resp and "meta" in resp:
        return resp["meta"].get("total", 0)
    return 0


def detect_class_type(name, token):
    """Detect whether a name is a card class or process class.
    Returns ("card", name), ("process", name), or (None, None).
    """
    for p in list_processes(token):
        pid = p.get("_id", "") or p.get("name", "")
        if pid == name:
            return "process", name
    for c in list_classes(token):
        cid = c.get("_id", "") or c.get("name", "")
        if cid == name:
            return "card", name
    return None, None


def find_maintenance_class(token):
    """Find the corrective maintenance class/process in OpenMaint.
    Returns (type, name) where type is "card" or "process".
    """
    for pattern in [r"CorrectiveMaint", r"CorrectiveActivity", r"Corrective",
                    r"MaintenanceTicket", r"WorkOrder"]:
        name = find_process(pattern, token)
        if name:
            return "process", name
    for pattern in [r"^Ticket$", r"CorrectiveActivity", r"CorrectiveMaintenance",
                    r"WorkOrder", r"^Request$", r"ServiceRequest"]:
        name = find_class(pattern, token)
        if name:
            return "card", name
    return None, None


def find_pm_class(token):
    """Find the preventive maintenance class/process in OpenMaint.
    Returns (type, name) where type is "card" or "process".
    """
    for pattern in [r"PreventiveMaint", r"PreventiveActivity", r"Preventive",
                    r"PlannedMaint", r"ScheduledMaint"]:
        name = find_process(pattern, token)
        if name:
            return "process", name
    for pattern in [r"PreventiveActivity", r"PreventiveMaintenance", r"^PM$",
                    r"PlannedActivity", r"ScheduledMaintenance"]:
        name = find_class(pattern, token)
        if name:
            return "card", name
    return None, None


def get_records(cls_type, cls_name, token, limit=100):
    """Get records from either a card class or process class."""
    if cls_type == "process":
        return get_process_instances(cls_name, token, limit)
    return get_cards(cls_name, token, limit)


def get_record(cls_type, cls_name, record_id, token):
    """Get a single record from either a card class or process class."""
    if cls_type == "process":
        return get_process_instance(cls_name, record_id, token)
    return get_card(cls_name, record_id, token)


def create_record(cls_type, cls_name, attrs, token):
    """Create a record in either a card class or process class."""
    if cls_type == "process":
        return create_process_instance(cls_name, attrs, token)
    return create_card(cls_name, attrs, token)


def count_records(cls_type, cls_name, token):
    """Count records in either a card class or process class."""
    if cls_type == "process":
        return count_process_instances(cls_name, token)
    return count_cards(cls_name, token)


def get_record_attributes(cls_type, cls_name, token):
    """Get attributes for either a card class or process class."""
    if cls_type == "process":
        return get_process_attributes(cls_name, token)
    return get_class_attributes(cls_name, token)


def save_baseline(path, data):
    with open(path, "w") as f:
        json.dump(data, f)


def load_baseline(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}
