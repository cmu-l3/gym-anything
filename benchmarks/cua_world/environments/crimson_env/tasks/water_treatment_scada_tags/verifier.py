#!/usr/bin/env python3
"""Verifier for water_treatment_scada_tags task.

A process engineer configures 5 water-treatment SCADA tags in Red Lion Crimson 3.0
using WHO Drinking Water Quality Guidelines (2022) and AWWA operational standards.

Scoring (100 points total):
  Subtask 1 — Tag Presence & Naming (25 pts):
      All 5 required tags exist with exact names: CT_101, PH_101, TU_101, TT_101, PT_101.
      5 pts per tag.
  Subtask 2 — Data Type = Float (20 pts):
      Each tag uses Float data type (not Integer/Boolean/etc.).  4 pts per tag.
  Subtask 3 — Min/Max Engineering Ranges (30 pts):
      Each tag's Minimum Value and Maximum Value match the WHO/AWWA specification
      within 2 % tolerance.  6 pts per tag (3 per limit).
  Subtask 4 — Engineering Unit Label (25 pts):
      Each tag's Label (Format tab) exactly matches the WHO standards document.
      5 pts per tag.

Pass threshold: 70 / 100.

Anti-Pattern 4 Audit (do-nothing score):
  If agent does nothing → no project saved → export_result.ps1 finds no project →
  result JSON has project_found=false → GATE returns score=0.  ✓

Wrong-target gate:
  If tags are present but none of the 5 required names found → score=0.  ✓

Partial-credit design:
  Each subtask awards independent partial credit, so partial completion
  yields 25–69 points (below pass threshold).  ✓
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/water_treatment_result.json"

EXPECTED_TAGS = [
    {
        "name": "CT_101",
        "description": "Free Chlorine Residual - Primary",
        "data_type": "Float",
        "min_value": 0.01,
        "max_value": 8.00,
        "label": "mg per Liter",
        "alarm_low": 0.20,
        "alarm_high": 4.00,
    },
    {
        "name": "PH_101",
        "description": "Process Water pH - Inlet",
        "data_type": "Float",
        "min_value": 4.00,
        "max_value": 11.00,
        "label": "pH Units",
        "alarm_low": 6.50,
        "alarm_high": 8.50,
    },
    {
        "name": "TU_101",
        "description": "Turbidity Sensor - Coagulation Outlet",
        "data_type": "Float",
        "min_value": 0.00,
        "max_value": 25.00,
        "label": "Nephelometric Turbidity Units",
        "alarm_low": 0.00,
        "alarm_high": 4.00,
    },
    {
        "name": "TT_101",
        "description": "Raw Water Inlet Temperature",
        "data_type": "Float",
        "min_value": 0.00,
        "max_value": 40.00,
        "label": "Degrees Celsius",
        "alarm_low": 1.00,
        "alarm_high": 32.00,
    },
    {
        "name": "PT_101",
        "description": "Distribution Pressure Transmitter",
        "data_type": "Float",
        "min_value": 0.00,
        "max_value": 700.00,
        "label": "Kilopascals",
        "alarm_low": 138.00,
        "alarm_high": 586.00,
    },
]

TOLERANCE_PCT = 2.0  # 2 % relative tolerance for numeric comparisons


def _within_tolerance(actual, expected, tol_pct=TOLERANCE_PCT):
    """Return True if actual is within tol_pct % of expected."""
    if actual is None or expected is None:
        return False
    try:
        a, e = float(actual), float(expected)
    except (TypeError, ValueError):
        return False
    if e == 0.0:
        return abs(a) < 1e-6
    return abs(a - e) / abs(e) * 100.0 <= tol_pct


def _norm_type(s):
    """Normalise data-type string for comparison."""
    if s is None:
        return ""
    s = str(s).strip().lower()
    # Accept "float", "single", "real", "floating point"
    return s


def verify_water_treatment_scada_tags(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # ── Fetch result JSON from VM ────────────────────────────────────────────
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found – export script may have failed or project was not saved",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # ── GATE 1: Do-nothing invariant ─────────────────────────────────────────
    if not result.get("project_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Project file not found at expected path – agent did not save the project",
        }

    if not result.get("export_success"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export Tags failed – project may be empty or Crimson could not open it",
        }

    exported_tags = result.get("tags", [])
    if not exported_tags:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No tags found in exported CSV – agent did not configure any tags",
        }

    # Build lookup: name → row (case-insensitive key)
    tag_map = {str(t.get("name", "")).strip().upper(): t for t in exported_tags}

    # ── GATE 2: Wrong-target rejection ───────────────────────────────────────
    required_names = {e["name"].upper() for e in EXPECTED_TAGS}
    found_required = required_names & set(tag_map.keys())
    if not found_required:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"WRONG TARGET: Tags were created but none of the required names "
                f"({', '.join(sorted(required_names))}) were found. "
                f"Found: {', '.join(sorted(tag_map.keys()))}"
            ),
        }

    score = 0
    feedback_parts = []

    # ── Subtask 1: Tag presence & correct naming (25 pts) ────────────────────
    st1_score = 0
    st1_parts = []
    for exp in EXPECTED_TAGS:
        nm = exp["name"].upper()
        if nm in tag_map:
            st1_score += 5
            st1_parts.append(f"{exp['name']}✓")
        else:
            st1_parts.append(f"{exp['name']}✗")
    score += st1_score
    feedback_parts.append(f"S1-Tags({st1_score}/25): {' '.join(st1_parts)}")

    # ── Subtask 2: Data type = Float (20 pts) ────────────────────────────────
    st2_score = 0
    st2_parts = []
    for exp in EXPECTED_TAGS:
        nm = exp["name"].upper()
        if nm not in tag_map:
            st2_parts.append(f"{exp['name']}=missing")
            continue
        actual_type = _norm_type(tag_map[nm].get("data_type", ""))
        if "float" in actual_type or "single" in actual_type or "real" in actual_type:
            st2_score += 4
            st2_parts.append(f"{exp['name']}✓")
        else:
            st2_parts.append(f"{exp['name']}={actual_type or 'none'}")
    score += st2_score
    feedback_parts.append(f"S2-DataType({st2_score}/20): {' '.join(st2_parts)}")

    # ── Subtask 3: Min/Max engineering ranges (30 pts) ───────────────────────
    st3_score = 0
    st3_parts = []
    for exp in EXPECTED_TAGS:
        nm = exp["name"].upper()
        if nm not in tag_map:
            st3_parts.append(f"{exp['name']}=missing")
            continue
        row = tag_map[nm]
        min_ok = _within_tolerance(row.get("min_value"), exp["min_value"])
        max_ok = _within_tolerance(row.get("max_value"), exp["max_value"])
        pts = (3 if min_ok else 0) + (3 if max_ok else 0)
        st3_score += pts
        min_detail = "ok" if min_ok else "{}!={}".format(row.get("min_value", "?"), exp["min_value"])
        max_detail = "ok" if max_ok else "{}!={}".format(row.get("max_value", "?"), exp["max_value"])
        st3_parts.append("{}(min={},max={})".format(exp["name"], min_detail, max_detail))
    score += st3_score
    feedback_parts.append(f"S3-MinMax({st3_score}/30): {' '.join(st3_parts)}")

    # ── Subtask 4: Engineering unit label (25 pts) ───────────────────────────
    st4_score = 0
    st4_parts = []
    for exp in EXPECTED_TAGS:
        nm = exp["name"].upper()
        if nm not in tag_map:
            st4_parts.append(f"{exp['name']}=missing")
            continue
        row = tag_map[nm]
        # Check both 'label' and 'unit' columns (Crimson may store in either)
        label_actual = str(row.get("label", "") or row.get("unit", "") or "").strip()
        label_expected = exp["label"].strip()
        if label_actual.lower() == label_expected.lower():
            st4_score += 5
            st4_parts.append(f"{exp['name']}✓")
        else:
            st4_parts.append(f"{exp['name']}='{label_actual}'≠'{label_expected}'")
    score += st4_score
    feedback_parts.append(f"S4-Label({st4_score}/25): {' '.join(st4_parts)}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
