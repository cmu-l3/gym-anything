#!/usr/bin/env python3
"""Verifier for Setup Cohort Enrollment task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_cohort_enrollment(traj, env_info, task_info):
    """
    Verify that cohort enrollment was configured correctly:
      - Cohort "Engineering Program Cohort 2024" (idnumber eng2024) created
      - All 5 engineering students added to the cohort
      - Cohort sync enrollment configured for CS110
      - Cohort sync enrollment configured for ENG110
      - All 5 cohort members enrolled in both CS110 and ENG110

    Scoring (100 points):
    - Criterion 1: Cohort "eng2024" / "Engineering Program Cohort 2024" exists — 15 points
    - Criterion 2: All 5 required members in cohort — 25 points
        (5 pts per member: alice, bob, carol, dave, emma)
    - Criterion 3: Cohort sync enrollment configured for CS110 — 20 points
    - Criterion 4: Cohort sync enrollment configured for ENG110 — 20 points
    - Criterion 5: All 5 cohort members enrolled in CS110 — 10 points
        (5 pts if at least 3 of 5 are enrolled)
    - Criterion 6: All 5 cohort members enrolled in ENG110 — 10 points
        (5 pts if at least 3 of 5 are enrolled)

    Pass threshold: 60 points.
    Wrong-target: if cohort not found, return score=0 immediately.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_result.name
        temp_result.close()
        try:
            copy_from_env("/tmp/setup_cohort_enrollment_result.json", temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except OSError:
                pass

        score = 0
        feedback_parts = []
        subscores = {}

        # ------------------------------------------------------------------
        # Wrong-target guard: cohort must exist to earn any points
        # ------------------------------------------------------------------
        cohort_found = result.get('cohort_found', False)
        if not cohort_found:
            logger.info("Cohort 'eng2024' not found — returning score=0")
            return {
                "passed": False,
                "score": 0,
                "feedback": "Cohort 'eng2024' not created — no points awarded",
                "subscores": {"cohort_exists": False},
            }

        # ------------------------------------------------------------------
        # Criterion 1: Cohort exists — 15 points
        # ------------------------------------------------------------------
        # (We already confirmed cohort_found=True above)
        score += 15
        subscores['cohort_exists'] = True
        cohort_name = result.get('cohort_name', '')
        cohort_idnumber = result.get('cohort_idnumber', '')
        feedback_parts.append(
            f"Cohort found: name='{cohort_name}', idnumber='{cohort_idnumber}'"
        )

        # Baseline sanity note
        initial_count = int(result.get('initial_cohort_count', 0))
        current_count = int(result.get('current_cohort_count', 0))
        if current_count <= initial_count:
            feedback_parts.append(
                f"Note: cohort count did not increase ({initial_count} -> {current_count})"
            )

        # ------------------------------------------------------------------
        # Criterion 2: All 5 required members in cohort — 25 points (5 each)
        # ------------------------------------------------------------------
        member_fields = [
            ('alice_in_cohort', 'eng_alice'),
            ('bob_in_cohort',   'eng_bob'),
            ('carol_in_cohort', 'eng_carol'),
            ('dave_in_cohort',  'eng_dave'),
            ('emma_in_cohort',  'eng_emma'),
        ]
        members_found = 0
        missing_members = []
        for field, username in member_fields:
            if int(result.get(field, 0)) > 0:
                members_found += 1
            else:
                missing_members.append(username)

        member_score = members_found * 5
        score += member_score
        subscores['cohort_members'] = (members_found == 5)

        if members_found == 5:
            feedback_parts.append("All 5 required students added to cohort")
        elif members_found > 0:
            feedback_parts.append(
                f"{members_found}/5 cohort members found; missing: {', '.join(missing_members)}"
            )
        else:
            cohort_total = int(result.get('cohort_member_count', 0))
            feedback_parts.append(
                f"None of the 5 required students found in cohort "
                f"(cohort has {cohort_total} members total)"
            )

        # ------------------------------------------------------------------
        # Criterion 3: Cohort sync enrollment configured for CS110 — 20 points
        # ------------------------------------------------------------------
        cs110_sync = int(result.get('cs110_cohort_sync_configured', 0))
        if cs110_sync > 0:
            score += 20
            subscores['cs110_sync_configured'] = True
            feedback_parts.append("Cohort sync enrollment configured for CS110")
        else:
            subscores['cs110_sync_configured'] = False
            feedback_parts.append(
                "Cohort sync enrollment NOT configured for CS110 "
                "(no matching row in mdl_enrol with enrol='cohort')"
            )

        # ------------------------------------------------------------------
        # Criterion 4: Cohort sync enrollment configured for ENG110 — 20 points
        # ------------------------------------------------------------------
        eng110_sync = int(result.get('eng110_cohort_sync_configured', 0))
        if eng110_sync > 0:
            score += 20
            subscores['eng110_sync_configured'] = True
            feedback_parts.append("Cohort sync enrollment configured for ENG110")
        else:
            subscores['eng110_sync_configured'] = False
            feedback_parts.append(
                "Cohort sync enrollment NOT configured for ENG110 "
                "(no matching row in mdl_enrol with enrol='cohort')"
            )

        # ------------------------------------------------------------------
        # Criterion 5: All 5 cohort members enrolled in CS110 — 10 points
        #   Full credit (10) if all 5 enrolled; partial (5) if >= 3 enrolled
        # ------------------------------------------------------------------
        cs110_enrolled = int(result.get('cs110_cohort_enrolled_count', 0))
        if cs110_enrolled >= 5:
            score += 10
            subscores['cs110_all_enrolled'] = True
            feedback_parts.append(f"All 5 cohort members enrolled in CS110")
        elif cs110_enrolled >= 3:
            score += 5
            subscores['cs110_all_enrolled'] = False
            feedback_parts.append(
                f"{cs110_enrolled}/5 cohort members enrolled in CS110 (partial credit)"
            )
        else:
            subscores['cs110_all_enrolled'] = False
            feedback_parts.append(
                f"Only {cs110_enrolled}/5 cohort members enrolled in CS110"
            )

        # ------------------------------------------------------------------
        # Criterion 6: All 5 cohort members enrolled in ENG110 — 10 points
        #   Full credit (10) if all 5 enrolled; partial (5) if >= 3 enrolled
        # ------------------------------------------------------------------
        eng110_enrolled = int(result.get('eng110_cohort_enrolled_count', 0))
        if eng110_enrolled >= 5:
            score += 10
            subscores['eng110_all_enrolled'] = True
            feedback_parts.append(f"All 5 cohort members enrolled in ENG110")
        elif eng110_enrolled >= 3:
            score += 5
            subscores['eng110_all_enrolled'] = False
            feedback_parts.append(
                f"{eng110_enrolled}/5 cohort members enrolled in ENG110 (partial credit)"
            )
        else:
            subscores['eng110_all_enrolled'] = False
            feedback_parts.append(
                f"Only {eng110_enrolled}/5 cohort members enrolled in ENG110"
            )

        # ------------------------------------------------------------------
        # Pass/fail decision
        # ------------------------------------------------------------------
        passed = score >= 60

        logger.info(
            "Cohort enrollment verification: score=%d, passed=%s, subscores=%s",
            score, passed, subscores
        )

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}",
        }
    except Exception as e:
        logger.error("Verification error: %s", e, exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
        }
