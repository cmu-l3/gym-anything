"""Verifier for language_learning_regional on system_settings_env.

Scoring (100 points, pass at 60):
- 20 pts  C1 French added to languages  AppleLanguages contains any "fr*" entry
- 20 pts  C2 Metric units               AppleMeasurementUnits == "Centimeters"
- 20 pts  C3 Celsius temperature        AppleTemperatureUnit == "Celsius"
- 20 pts  C4 24-hour clock              derived: DateFormat has "HH", or ShowAMPM==0,
                                        or AppleICUForce24HourTime==1
- 20 pts  C5 Week starts Monday         AppleFirstWeekday.gregorian == 2

Partial-credit upper bound (Anti-Pattern #4): each criterion is binary → max partial = 0.
Pass threshold 60 > 0.

Reads /tmp/language_learning_regional_result.json produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/language_learning_regional_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "french_language": 0,
        "measurement_units": 0,
        "temperature_unit": 0,
        "clock_24h": 0,
        "first_weekday": 0,
    }


def verify_language_learning_regional(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            logger.warning("copy_from_env failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Could not retrieve result file from sandbox: {exc}",
                    "subscores": _empty_subscores()}
        try:
            with open(local_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            logger.warning("result JSON parse failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Export produced unparseable JSON: {exc}",
                    "subscores": _empty_subscores()}
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    has_french   = bool(data.get("has_french_language", False))
    measurement  = data.get("measurement_units")
    temperature  = data.get("temperature_unit")
    clock_is_24h = bool(data.get("clock_is_24h", False))
    first_weekday = data.get("first_weekday_gregorian")
    # macOS stores AppleFirstWeekday.gregorian as a string on some versions.
    if isinstance(first_weekday, str):
        try:
            first_weekday = int(first_weekday)
        except (ValueError, TypeError):
            first_weekday = None

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: French language (20 pts) ----
    c1_full = c1_baseline = False
    if has_french:
        subscores["french_language"] = 20
        c1_full = True
        feedback.append("French language present in AppleLanguages (+20)")
    else:
        c1_baseline = True
        feedback.append("French language not found in AppleLanguages (+0)")

    # ---- C2: Metric measurement (20 pts) ----
    c2_full = c2_baseline = c2_other = False
    if measurement == "Centimeters":
        subscores["measurement_units"] = 20
        c2_full = True
        feedback.append("Measurement units: Centimeters/Metric (+20)")
    elif measurement == "Inches" or measurement is None:
        c2_baseline = True
        feedback.append("Measurement units still Inches (+0)")
    else:
        c2_other = True
        feedback.append(f"Measurement units: {measurement!r} — not Centimeters (+0)")

    # ---- C3: Celsius (20 pts) ----
    c3_full = c3_baseline = c3_other = False
    if temperature == "Celsius":
        subscores["temperature_unit"] = 20
        c3_full = True
        feedback.append("Temperature unit: Celsius (+20)")
    elif temperature == "Fahrenheit" or temperature is None:
        c3_baseline = True
        feedback.append("Temperature unit still Fahrenheit (+0)")
    else:
        c3_other = True
        feedback.append(f"Temperature unit: {temperature!r} — not Celsius (+0)")

    # ---- C4: 24-hour clock (20 pts) ----
    c4_full = c4_baseline = False
    if clock_is_24h:
        subscores["clock_24h"] = 20
        c4_full = True
        feedback.append("Clock in 24-hour format (+20)")
    else:
        c4_baseline = True
        feedback.append("Clock still in 12-hour format (+0)")

    # ---- C5: Week starts Monday (20 pts) ----
    # gregorian value: 1=Sunday, 2=Monday
    c5_full = c5_baseline = c5_other = False
    if first_weekday == 2:
        subscores["first_weekday"] = 20
        c5_full = True
        feedback.append("Week starts Monday (gregorian=2) (+20)")
    elif first_weekday == 1 or first_weekday is None:
        c5_baseline = True
        feedback.append("Week still starts Sunday (gregorian=1) (+0)")
    else:
        c5_other = True
        feedback.append(f"First weekday: gregorian={first_weekday} — not Monday (+0)")

    full_flags     = [c1_full, c2_full, c3_full, c4_full, c5_full]
    baseline_flags = [c1_baseline, c2_baseline, c3_baseline, c4_baseline, c5_baseline]
    other_flags    = [c2_other, c3_other, c5_other]

    if all(baseline_flags):
        return {"score": 0, "passed": False,
                "feedback": ("No settings changed from baseline. "
                             "Language, units, temperature, clock format, and week start all unchanged."),
                "subscores": _empty_subscores()}

    if any(other_flags) and not any(full_flags):
        return {"score": 0, "passed": False,
                "feedback": ("Wrong target: settings changed but none reached the task's target values. "
                             + " | ".join(feedback)),
                "subscores": _empty_subscores()}

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD

    if passed:
        feedback.insert(0, f"PASSED ({total}/100): French/metric regional profile applied.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
