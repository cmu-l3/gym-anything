"""
Verifier for vfr_navaid_routing task.

Scoring (100 points total), pass threshold = 76:
  GATE : At least one plan file saved (else score = 0)
  KSFO   in any saved plan  : 30 pts
  KLAS   in any saved plan  : 30 pts
  >= 5 waypoints in a plan  : 25 pts
  Chart type is Sectional   : 15 pts

Threshold = 76 prevents passing on KSFO+KLAS+default_Sectional alone (75 pts).
The waypoint count criterion is required to pass.
"""

import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def check_vfr_navaid_routing(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    feedback = []
    score = 0

    # ------------------------------------------------------------------ #
    # Pull exported files from the Android device                         #
    # ------------------------------------------------------------------ #
    with tempfile.TemporaryDirectory() as tmp:
        plans_txt = os.path.join(tmp, "avare_plans_combined.txt")
        prefs_xml = os.path.join(tmp, "avare_prefs.xml")
        plan_count_txt = os.path.join(tmp, "avare_plan_count.txt")

        plans_content = ""
        prefs_content = ""
        plan_count = 0

        try:
            copy_from_env("/sdcard/avare_plans_combined.txt", plans_txt)
            with open(plans_txt, "r", errors="replace") as f:
                plans_content = f.read()
        except Exception as e:
            logger.warning("Could not retrieve plans combined file: %s", e)

        try:
            copy_from_env("/sdcard/avare_plan_count.txt", plan_count_txt)
            with open(plan_count_txt, "r") as f:
                plan_count = int(f.read().strip())
        except Exception as e:
            logger.warning("Could not retrieve plan count: %s", e)

        try:
            copy_from_env("/sdcard/avare_prefs.xml", prefs_xml)
            with open(prefs_xml, "r", errors="replace") as f:
                prefs_content = f.read()
        except Exception as e:
            logger.warning("Could not retrieve prefs XML: %s", e)

        # -------------------------------------------------------------- #
        # GATE: at least one plan file must have been saved               #
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
                "feedback": "No flight plan was saved. Save the plan in Avare before finishing.",
            }

        # -------------------------------------------------------------- #
        # Criterion 1 – KSFO appears in any plan (30 pts)                 #
        # -------------------------------------------------------------- #
        try:
            if "KSFO" in plans_content.upper():
                score += 30
                feedback.append("KSFO (departure) found in saved plan. (+30)")
            else:
                feedback.append("KSFO (San Francisco) not found in any saved plan. (+0)")
        except Exception as e:
            logger.warning("KSFO check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 2 – KLAS appears in any plan (30 pts)                 #
        # -------------------------------------------------------------- #
        try:
            if "KLAS" in plans_content.upper():
                score += 30
                feedback.append("KLAS (destination Las Vegas) found in saved plan. (+30)")
            else:
                feedback.append("KLAS (Las Vegas) not found in any saved plan. (+0)")
        except Exception as e:
            logger.warning("KLAS check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 3 – >= 5 waypoints in at least one plan (25 pts)      #
        # Each plan section is demarcated by "=== <name>.csv ==="         #
        # Waypoints are non-blank, non-header lines after the header row. #
        # -------------------------------------------------------------- #
        try:
            max_wps = 0
            current_section_lines = []
            in_section = False
            for line in plans_content.splitlines():
                stripped = line.strip()
                if stripped.startswith("===") and stripped.endswith("==="):
                    # Evaluate previous section
                    if in_section and current_section_lines:
                        wps = _count_waypoints(current_section_lines)
                        max_wps = max(max_wps, wps)
                    current_section_lines = []
                    in_section = True
                elif in_section:
                    if stripped:
                        current_section_lines.append(stripped)
            # Final section
            if in_section and current_section_lines:
                wps = _count_waypoints(current_section_lines)
                max_wps = max(max_wps, wps)

            if max_wps >= 5:
                score += 25
                feedback.append(
                    f"Plan has {max_wps} waypoints (>= 5 required). (+25)"
                )
            else:
                feedback.append(
                    f"Longest plan has {max_wps} waypoints; at least 5 needed. (+0)"
                )
        except Exception as e:
            logger.warning("Waypoint count check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 4 – Chart is Sectional (VFR), not IFR (15 pts)       #
        # Search SharedPreferences XML for chart-type-related keys.       #
        # -------------------------------------------------------------- #
        try:
            chart_score = _check_chart_type(prefs_content, "sectional")
            score += chart_score
            if chart_score > 0:
                feedback.append("Chart type is Sectional (VFR). (+15)")
            else:
                feedback.append(
                    "Chart type does not appear to be Sectional. Ensure VFR Sectional is selected. (+0)"
                )
        except Exception as e:
            logger.warning("Chart type check failed: %s", e)

    # ------------------------------------------------------------------ #
    # Final result                                                        #
    # ------------------------------------------------------------------ #
    passed = score >= 76
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }


# ------------------------------------------------------------------ #
# Helpers                                                             #
# ------------------------------------------------------------------ #

def _count_waypoints(lines):
    """Count waypoints in a plan section.

    Avare CSV plan format first line is a header row starting with "IDENT".
    Each subsequent non-blank line is one waypoint.
    """
    if not lines:
        return 0
    # If first line looks like a header, skip it
    first = lines[0].upper()
    start = 1 if ("IDENT" in first or "NAME" in first or "TYPE" in first) else 0
    return sum(1 for l in lines[start:] if l.strip())


def _check_chart_type(prefs_xml: str, expected: str) -> int:
    """Return 15 if prefs indicate the expected chart type, else 0.

    Searches for any <string name="...chart..." ...>VALUE</string> element
    case-insensitively.  Avare typically stores chart type as a string pref
    whose name contains "chart" and whose value contains "sectional" for VFR.
    If the preference is absent (old version, never changed), assume Sectional
    (the default) and award the points.
    """
    if not prefs_xml or "<map>" not in prefs_xml:
        # Could not read prefs; give benefit of the doubt if plans exist
        return 15

    prefs_lower = prefs_xml.lower()
    # Look for any element whose name attribute contains "chart"
    import re
    pattern = re.compile(
        r'<string\s+name="([^"]*chart[^"]*)"[^>]*>([^<]*)</string>',
        re.IGNORECASE,
    )
    matches = pattern.findall(prefs_xml)
    if not matches:
        # Key absent → Avare default is Sectional
        return 15

    for name, value in matches:
        val_lower = value.strip().lower()
        if "sectional" in val_lower or "vfr" in val_lower:
            return 15
        if "ifr" in val_lower or "low" in val_lower or "high" in val_lower:
            return 0

    # Key present but value unclear → conservative
    return 0
