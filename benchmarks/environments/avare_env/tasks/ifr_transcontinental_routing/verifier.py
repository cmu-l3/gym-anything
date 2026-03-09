"""
Verifier for ifr_transcontinental_routing task.

Scoring (100 points total), pass threshold = 76:
  GATE : At least one plan file saved (else score = 0)
  Chart type is IFR Low-Altitude   : 25 pts
  KLAX in any saved plan           : 25 pts
  KJFK in any saved plan           : 25 pts
  >= 6 waypoints in a single plan  : 25 pts

Threshold = 76 prevents passing on any 3-of-4 combination (max 75).
"""

import os
import re
import logging
import tempfile

logger = logging.getLogger(__name__)


def check_ifr_transcontinental_routing(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    feedback = []
    score = 0

    with tempfile.TemporaryDirectory() as tmp:
        plans_txt = os.path.join(tmp, "avare_trans_plans.txt")
        prefs_xml = os.path.join(tmp, "avare_trans_prefs.xml")
        plan_count_txt = os.path.join(tmp, "avare_trans_plan_count.txt")

        plans_content = ""
        prefs_content = ""
        plan_count = 0

        try:
            copy_from_env("/sdcard/avare_trans_plans.txt", plans_txt)
            with open(plans_txt, "r", errors="replace") as f:
                plans_content = f.read()
        except Exception as e:
            logger.warning("Could not retrieve plans file: %s", e)

        try:
            copy_from_env("/sdcard/avare_trans_plan_count.txt", plan_count_txt)
            with open(plan_count_txt, "r") as f:
                plan_count = int(f.read().strip())
        except Exception as e:
            logger.warning("Could not retrieve plan count: %s", e)

        try:
            copy_from_env("/sdcard/avare_trans_prefs.xml", prefs_xml)
            with open(prefs_xml, "r", errors="replace") as f:
                prefs_content = f.read()
        except Exception as e:
            logger.warning("Could not retrieve prefs: %s", e)

        # -------------------------------------------------------------- #
        # GATE: at least one plan saved                                    #
        # -------------------------------------------------------------- #
        no_plans = (
            plan_count == 0
            or not plans_content.strip()
            or plans_content.strip() == "NO_PLANS"
        )
        if no_plans:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No flight plan was saved. Build and save the transcontinental route.",
            }

        # -------------------------------------------------------------- #
        # Criterion 1 – IFR Low-Altitude chart (25 pts)                  #
        # -------------------------------------------------------------- #
        try:
            chart_score = _check_chart_ifr_low(prefs_content)
            score += chart_score
            if chart_score > 0:
                feedback.append("IFR Low-Altitude chart is selected. (+25)")
            else:
                feedback.append("Chart does not appear to be IFR Low-Altitude. (+0)")
        except Exception as e:
            logger.warning("Chart check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 2 – KLAX in any saved plan (25 pts)                  #
        # -------------------------------------------------------------- #
        try:
            if "KLAX" in plans_content.upper():
                score += 25
                feedback.append("KLAX (Los Angeles departure) found in plan. (+25)")
            else:
                feedback.append("KLAX not found in any saved plan. (+0)")
        except Exception as e:
            logger.warning("KLAX check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 3 – KJFK in any saved plan (25 pts)                  #
        # -------------------------------------------------------------- #
        try:
            if "KJFK" in plans_content.upper():
                score += 25
                feedback.append("KJFK (New York destination) found in plan. (+25)")
            else:
                feedback.append("KJFK not found in any saved plan. (+0)")
        except Exception as e:
            logger.warning("KJFK check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 4 – >= 6 waypoints in a single plan (25 pts)         #
        # -------------------------------------------------------------- #
        try:
            max_wps = _max_waypoints_in_plan(plans_content)
            if max_wps >= 6:
                score += 25
                feedback.append(f"Plan has {max_wps} waypoints (>= 6 required). (+25)")
            else:
                feedback.append(
                    f"Longest plan has {max_wps} waypoints; at least 6 needed. (+0)"
                )
        except Exception as e:
            logger.warning("Waypoint count check failed: %s", e)

    passed = score >= 76
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }


# ------------------------------------------------------------------ #
# Helpers                                                             #
# ------------------------------------------------------------------ #

def _check_chart_ifr_low(prefs_xml: str) -> int:
    """Return 25 if chart is IFR Low-Altitude, else 0."""
    if not prefs_xml or "<map>" not in prefs_xml:
        return 0
    pattern = re.compile(
        r'<string\s+name="([^"]*chart[^"]*)"[^>]*>([^<]*)</string>',
        re.IGNORECASE,
    )
    matches = pattern.findall(prefs_xml)
    if not matches:
        return 0
    for name, value in matches:
        val_lower = value.strip().lower()
        if "ifr" in val_lower and ("low" in val_lower or "enroute" in val_lower):
            return 25
        if "enroute" in val_lower and "low" in val_lower:
            return 25
    return 0


def _max_waypoints_in_plan(plans_content: str) -> int:
    """Return the maximum waypoint count found in any single plan section."""
    max_wps = 0
    current_lines = []
    in_section = False
    for line in plans_content.splitlines():
        stripped = line.strip()
        if stripped.startswith("===") and stripped.endswith("==="):
            if in_section and current_lines:
                wps = _count_waypoints(current_lines)
                max_wps = max(max_wps, wps)
            current_lines = []
            in_section = True
        elif in_section and stripped:
            current_lines.append(stripped)
    if in_section and current_lines:
        wps = _count_waypoints(current_lines)
        max_wps = max(max_wps, wps)
    return max_wps


def _count_waypoints(lines):
    if not lines:
        return 0
    first = lines[0].upper()
    start = 1 if ("IDENT" in first or "NAME" in first or "TYPE" in first) else 0
    return sum(1 for l in lines[start:] if l.strip())
