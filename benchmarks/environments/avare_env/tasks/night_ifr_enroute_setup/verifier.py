"""
Verifier for night_ifr_enroute_setup task.

Scoring (100 points total), pass threshold = 75:
  Night Mode enabled in Avare settings : 35 pts
  Chart type is IFR Low-Altitude       : 35 pts
  KSFO in any saved plan               : 20 pts
  KDEN in any saved plan               : 10 pts

Note: completing only KSFO + KDEN (30 pts) or only Night + IFR (70 pts)
      never reaches 75, so all three sub-tasks must be substantially done.
"""

import os
import re
import logging
import tempfile

logger = logging.getLogger(__name__)


def check_night_ifr_enroute_setup(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    feedback = []
    score = 0

    with tempfile.TemporaryDirectory() as tmp:
        plans_txt = os.path.join(tmp, "avare_night_ifr_plans.txt")
        prefs_xml = os.path.join(tmp, "avare_night_ifr_prefs.xml")
        plan_count_txt = os.path.join(tmp, "avare_night_ifr_plan_count.txt")

        plans_content = ""
        prefs_content = ""
        plan_count = 0

        try:
            copy_from_env("/sdcard/avare_night_ifr_plans.txt", plans_txt)
            with open(plans_txt, "r", errors="replace") as f:
                plans_content = f.read()
        except Exception as e:
            logger.warning("Could not retrieve plans file: %s", e)

        try:
            copy_from_env("/sdcard/avare_night_ifr_plan_count.txt", plan_count_txt)
            with open(plan_count_txt, "r") as f:
                plan_count = int(f.read().strip())
        except Exception as e:
            logger.warning("Could not retrieve plan count: %s", e)

        try:
            copy_from_env("/sdcard/avare_night_ifr_prefs.xml", prefs_xml)
            with open(prefs_xml, "r", errors="replace") as f:
                prefs_content = f.read()
        except Exception as e:
            logger.warning("Could not retrieve prefs: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 1 – Night Mode is enabled (35 pts)                    #
        # -------------------------------------------------------------- #
        try:
            night_score = _check_night_mode(prefs_content)
            score += night_score
            if night_score > 0:
                feedback.append("Night Mode is enabled. (+35)")
            else:
                feedback.append("Night Mode does not appear to be enabled. (+0)")
        except Exception as e:
            logger.warning("Night mode check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 2 – Chart type is IFR Low-Altitude (35 pts)          #
        # -------------------------------------------------------------- #
        try:
            chart_score = _check_chart_ifr_low(prefs_content)
            score += chart_score
            if chart_score > 0:
                feedback.append("IFR Low-Altitude chart is selected. (+35)")
            else:
                feedback.append("Chart does not appear to be IFR Low-Altitude. (+0)")
        except Exception as e:
            logger.warning("Chart type check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 3 – KSFO in any saved plan (20 pts)                  #
        # -------------------------------------------------------------- #
        try:
            no_plans = (
                plan_count == 0
                or not plans_content.strip()
                or plans_content.strip() == "NO_PLANS"
            )
            if not no_plans and "KSFO" in plans_content.upper():
                score += 20
                feedback.append("KSFO (departure) found in saved plan. (+20)")
            else:
                feedback.append("KSFO not found in any saved plan. (+0)")
        except Exception as e:
            logger.warning("KSFO check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 4 – KDEN in any saved plan (10 pts)                  #
        # -------------------------------------------------------------- #
        try:
            no_plans = (
                plan_count == 0
                or not plans_content.strip()
                or plans_content.strip() == "NO_PLANS"
            )
            if not no_plans and "KDEN" in plans_content.upper():
                score += 10
                feedback.append("KDEN (destination Denver) found in saved plan. (+10)")
            else:
                feedback.append("KDEN not found in any saved plan. (+0)")
        except Exception as e:
            logger.warning("KDEN check failed: %s", e)

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }


# ------------------------------------------------------------------ #
# Helpers                                                             #
# ------------------------------------------------------------------ #

def _check_night_mode(prefs_xml: str) -> int:
    """Return 35 if Night Mode is enabled, else 0."""
    if not prefs_xml or "<map>" not in prefs_xml:
        return 0

    # Look for boolean or string element whose name contains "night"
    # Boolean form: <boolean name="NightMode" value="true" />
    bool_pattern = re.compile(
        r'<boolean\s+name="([^"]*night[^"]*)"[^>]*/?>',
        re.IGNORECASE,
    )
    for m in bool_pattern.finditer(prefs_xml):
        full_tag = m.group(0)
        if 'value="true"' in full_tag.lower():
            return 35

    # String form: <string name="NightMode">true</string>
    str_pattern = re.compile(
        r'<string\s+name="([^"]*night[^"]*)"[^>]*>([^<]*)</string>',
        re.IGNORECASE,
    )
    for name, value in str_pattern.findall(prefs_xml):
        if value.strip().lower() in ("true", "1", "yes", "on"):
            return 35

    return 0


def _check_chart_ifr_low(prefs_xml: str) -> int:
    """Return 35 if chart type preference indicates IFR Low-Altitude, else 0."""
    if not prefs_xml or "<map>" not in prefs_xml:
        return 0

    # Look for string element whose name contains "chart"
    pattern = re.compile(
        r'<string\s+name="([^"]*chart[^"]*)"[^>]*>([^<]*)</string>',
        re.IGNORECASE,
    )
    matches = pattern.findall(prefs_xml)
    if not matches:
        return 0

    for name, value in matches:
        val_lower = value.strip().lower()
        # Accept "ifr low", "ifr_low", "enroute low", "low enroute", etc.
        if ("ifr" in val_lower and "low" in val_lower) or "enroute" in val_lower:
            return 35
        if "low" in val_lower and "ifr" in val_lower:
            return 35

    return 0
