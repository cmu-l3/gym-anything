"""
Verifier for emergency_diversion_plan task.

Scoring (100 points total), pass threshold = 70:
  GATE : EMER.csv must exist (else score = 0)
  KSFO in EMER plan                        : 40 pts
  Acceptable Bay Area alternate in EMER    : 60 pts

Acceptable alternates: KHAF, KSQL, KPAO, KLVK, KCCR, KWVI, KSJC, KNUQ, KOAK, KAPC
"""

import os
import logging
import tempfile

logger = logging.getLogger(__name__)

ACCEPTABLE_ALTERNATES = {
    "KHAF", "KSQL", "KPAO", "KLVK", "KCCR",
    "KWVI", "KSJC", "KNUQ", "KOAK", "KAPC",
}


def check_emergency_diversion_plan(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    feedback = []
    score = 0

    with tempfile.TemporaryDirectory() as tmp:
        emer_plan_path = os.path.join(tmp, "avare_emer_plan.txt")
        emer_found_path = os.path.join(tmp, "avare_emer_found.txt")

        emer_content = ""
        emer_found = False

        try:
            copy_from_env("/sdcard/avare_emer_found.txt", emer_found_path)
            with open(emer_found_path, "r") as f:
                emer_found = f.read().strip().lower() == "true"
        except Exception as e:
            logger.warning("Could not retrieve emer_found flag: %s", e)

        try:
            copy_from_env("/sdcard/avare_emer_plan.txt", emer_plan_path)
            with open(emer_plan_path, "r", errors="replace") as f:
                emer_content = f.read()
        except Exception as e:
            logger.warning("Could not retrieve EMER plan content: %s", e)

        # -------------------------------------------------------------- #
        # GATE: EMER.csv must exist                                       #
        # -------------------------------------------------------------- #
        no_emer = (
            not emer_found
            or not emer_content.strip()
            or emer_content.strip() == "NO_EMER"
        )
        if no_emer:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No EMER.csv plan file found. Create and save the diversion plan named EMER.",
            }

        # -------------------------------------------------------------- #
        # Criterion 1 – KSFO in EMER plan (40 pts)                       #
        # -------------------------------------------------------------- #
        try:
            if "KSFO" in emer_content.upper():
                score += 40
                feedback.append("KSFO (position fix) found in EMER plan. (+40)")
            else:
                feedback.append("KSFO not found in EMER plan. (+0)")
        except Exception as e:
            logger.warning("KSFO check failed: %s", e)

        # -------------------------------------------------------------- #
        # Criterion 2 – Acceptable Bay Area alternate in EMER plan (60 pts)#
        # -------------------------------------------------------------- #
        try:
            emer_upper = emer_content.upper()
            found_alternate = None
            for alt in ACCEPTABLE_ALTERNATES:
                if alt in emer_upper:
                    found_alternate = alt
                    break
            if found_alternate:
                score += 60
                feedback.append(
                    f"Acceptable alternate {found_alternate} found in EMER plan. (+60)"
                )
            else:
                feedback.append(
                    "No accepted Bay Area alternate found in EMER plan. "
                    f"Expected one of: {', '.join(sorted(ACCEPTABLE_ALTERNATES))}. (+0)"
                )
        except Exception as e:
            logger.warning("Alternate check failed: %s", e)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
