"""
Verifier for pnw_vfr_tour_plan task.

Scoring (100 points total), pass threshold = 76:
  GATE : PNW_TOUR.csv must exist (else score = 0)
  Sectional chart selected              : 25 pts
  KSEA in PNW_TOUR plan                : 25 pts
  KPDX in PNW_TOUR plan                : 20 pts
  KEUG in PNW_TOUR plan                : 15 pts
  KMFR in PNW_TOUR plan                : 15 pts

Threshold = 76 prevents passing on KSEA + KPDX + KEUG + KMFR alone (75 pts).
All four airports plus the chart change are required for a passing score.
"""

import os
import re
import logging
import tempfile

logger = logging.getLogger(__name__)


def check_pnw_vfr_tour_plan(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    feedback = []
    score = 0

    with tempfile.TemporaryDirectory() as tmp:
        pnw_plan_path = os.path.join(tmp, "avare_pnw_tour_plan.txt")
        pnw_found_path = os.path.join(tmp, "avare_pnw_found.txt")
        prefs_xml_path = os.path.join(tmp, "avare_pnw_prefs.xml")

        pnw_content = ""
        pnw_found = False
        prefs_content = ""

        try:
            copy_from_env("/sdcard/avare_pnw_found.txt", pnw_found_path)
            with open(pnw_found_path, "r") as f:
                pnw_found = f.read().strip().lower() == "true"
        except Exception as e:
            logger.warning("Could not retrieve pnw_found flag: %s", e)

        try:
            copy_from_env("/sdcard/avare_pnw_tour_plan.txt", pnw_plan_path)
            with open(pnw_plan_path, "r", errors="replace") as f:
                pnw_content = f.read()
        except Exception as e:
            logger.warning("Could not retrieve PNW_TOUR plan: %s", e)

        try:
            copy_from_env("/sdcard/avare_pnw_prefs.xml", prefs_xml_path)
            with open(prefs_xml_path, "r", errors="replace") as f:
                prefs_content = f.read()
        except Exception as e:
            logger.warning("Could not retrieve prefs: %s", e)

        # -------------------------------------------------------------- #
        # GATE: PNW_TOUR.csv must exist                                   #
        # -------------------------------------------------------------- #
        no_pnw = (
            not pnw_found
            or not pnw_content.strip()
            or pnw_content.strip() == "NO_PNW_TOUR"
        )
        if no_pnw:
            return {
                "passed": False,
                "score": 0,
                "feedback": "PNW_TOUR.csv not found. Create and save the tour plan with name PNW_TOUR.",
            }

        plan_upper = pnw_content.upper()

        # -------------------------------------------------------------- #
        # Criterion 1 – Sectional chart is selected (25 pts)             #
        # -------------------------------------------------------------- #
        try:
            chart_score = _check_chart_sectional(prefs_content)
            score += chart_score
            if chart_score > 0:
                feedback.append("Sectional (VFR) chart is selected. (+25)")
            else:
                feedback.append("Chart does not appear to be Sectional/VFR. (+0)")
        except Exception as e:
            logger.warning("Chart check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 2 – KSEA in PNW_TOUR plan (25 pts)                  #
        # -------------------------------------------------------------- #
        try:
            if "KSEA" in plan_upper:
                score += 25
                feedback.append("KSEA (Seattle) found in PNW_TOUR plan. (+25)")
            else:
                feedback.append("KSEA (Seattle-Tacoma) not found in PNW_TOUR plan. (+0)")
        except Exception as e:
            logger.warning("KSEA check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 3 – KPDX in PNW_TOUR plan (20 pts)                  #
        # -------------------------------------------------------------- #
        try:
            if "KPDX" in plan_upper:
                score += 20
                feedback.append("KPDX (Portland) found in PNW_TOUR plan. (+20)")
            else:
                feedback.append("KPDX (Portland) not found in PNW_TOUR plan. (+0)")
        except Exception as e:
            logger.warning("KPDX check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 4 – KEUG in PNW_TOUR plan (15 pts)                  #
        # -------------------------------------------------------------- #
        try:
            if "KEUG" in plan_upper:
                score += 15
                feedback.append("KEUG (Eugene) found in PNW_TOUR plan. (+15)")
            else:
                feedback.append("KEUG (Eugene) not found in PNW_TOUR plan. (+0)")
        except Exception as e:
            logger.warning("KEUG check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 5 – KMFR in PNW_TOUR plan (15 pts)                  #
        # -------------------------------------------------------------- #
        try:
            if "KMFR" in plan_upper:
                score += 15
                feedback.append("KMFR (Medford) found in PNW_TOUR plan. (+15)")
            else:
                feedback.append("KMFR (Medford/Rogue Valley) not found in PNW_TOUR plan. (+0)")
        except Exception as e:
            logger.warning("KMFR check failed: %s", e)

    passed = score >= 76
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }


# ------------------------------------------------------------------ #
# Helpers                                                             #
# ------------------------------------------------------------------ #

def _check_chart_sectional(prefs_xml: str) -> int:
    """Return 25 if chart is Sectional (VFR), else 0.

    If the preference is absent, Avare's default is Sectional → award points.
    """
    if not prefs_xml or "<map>" not in prefs_xml:
        return 25  # Default is Sectional

    pattern = re.compile(
        r'<string\s+name="([^"]*chart[^"]*)"[^>]*>([^<]*)</string>',
        re.IGNORECASE,
    )
    matches = pattern.findall(prefs_xml)
    if not matches:
        return 25  # Key absent → Avare default (Sectional)

    for name, value in matches:
        val_lower = value.strip().lower()
        if "sectional" in val_lower or ("vfr" in val_lower and "ifr" not in val_lower):
            return 25
        if "ifr" in val_lower:
            return 0

    return 0
