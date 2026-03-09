#!/usr/bin/env python3
"""Verifier for Setup Competency Framework task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_competency_framework(traj, env_info, task_info):
    """
    Verify that a competency framework was created, populated, and linked to
    the PSY301 course and its activities.

    Scoring (100 points):
    - Criterion 1: Competency framework "edu-psych-comp" (or similar) exists — 20 points
    - Criterion 2: Framework has all 3 required competencies — 25 points
        (partial: 8 pts per competency found, rounded: 3=25, 2=16, 1=8)
    - Criterion 3: PSY301 has at least 1 course-competency link — 20 points
    - Criterion 4: "Learning Theories Essay" activity has a competency linked — 15 points
    - Criterion 5: "Assessment Design Project" activity has a competency linked — 20 points

    Pass threshold: 60 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_result.name
        temp_result.close()
        try:
            copy_from_env("/tmp/setup_competency_framework_result.json", temp_path)
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

        # Baseline: note whether any new frameworks were created
        initial_count = int(result.get('initial_framework_count', 0))
        current_count = int(result.get('current_framework_count', 0))
        if current_count <= initial_count and not result.get('framework_found', False):
            feedback_parts.append(
                f"No new framework created (count: {initial_count} -> {current_count})"
            )

        # ------------------------------------------------------------------
        # Criterion 1: Framework exists — 20 points
        # ------------------------------------------------------------------
        if result.get('framework_found', False):
            score += 20
            subscores['framework_exists'] = True
            shortname = result.get('framework_shortname', '')
            fullname = result.get('framework_fullname', '')
            feedback_parts.append(
                f"Framework found: shortname='{shortname}', fullname='{fullname}'"
            )
        else:
            subscores['framework_exists'] = False
            feedback_parts.append(
                "Competency framework 'edu-psych-comp' not found"
            )

        # ------------------------------------------------------------------
        # Criterion 2: All 3 competencies present — 25 points
        # (8 pts each, capped at 25 when all three are present)
        # ------------------------------------------------------------------
        learning_theories_ok = result.get('learning_theories_exists', False)
        dev_psych_ok = result.get('dev_psych_exists', False)
        assessment_ok = result.get('assessment_exists', False)

        found_count = sum([
            bool(learning_theories_ok),
            bool(dev_psych_ok),
            bool(assessment_ok),
        ])

        if found_count == 3:
            comp_points = 25
            subscores['all_competencies'] = True
            feedback_parts.append("All 3 required competencies present in framework")
        elif found_count == 2:
            comp_points = 16
            subscores['all_competencies'] = False
            missing = []
            if not learning_theories_ok:
                missing.append("Learning Theories and Applications")
            if not dev_psych_ok:
                missing.append("Developmental Psychology")
            if not assessment_ok:
                missing.append("Educational Assessment and Measurement")
            feedback_parts.append(
                f"2 of 3 competencies found; missing: {', '.join(missing)}"
            )
        elif found_count == 1:
            comp_points = 8
            subscores['all_competencies'] = False
            present = []
            if learning_theories_ok:
                present.append("Learning Theories and Applications")
            if dev_psych_ok:
                present.append("Developmental Psychology")
            if assessment_ok:
                present.append("Educational Assessment and Measurement")
            feedback_parts.append(
                f"Only 1 of 3 competencies found: {', '.join(present)}"
            )
        else:
            comp_points = 0
            subscores['all_competencies'] = False
            if result.get('framework_found', False):
                total_comps = int(result.get('competency_count', 0))
                feedback_parts.append(
                    f"No required competencies found in framework "
                    f"(framework has {total_comps} competencies total)"
                )
            else:
                feedback_parts.append("No competencies checked (framework not found)")

        score += comp_points

        # ------------------------------------------------------------------
        # Criterion 3: PSY301 has at least 1 course-competency link — 20 points
        # ------------------------------------------------------------------
        course_comp_count = int(result.get('course_comp_count', 0))
        if course_comp_count >= 1:
            score += 20
            subscores['course_linked'] = True
            feedback_parts.append(
                f"PSY301 course has {course_comp_count} competency link(s)"
            )
        else:
            subscores['course_linked'] = False
            feedback_parts.append(
                "PSY301 course has no competency links "
                "(competencies not linked to course)"
            )

        # ------------------------------------------------------------------
        # Criterion 4: "Learning Theories Essay" activity linked — 15 points
        # ------------------------------------------------------------------
        essay_linked = result.get('essay_comp_linked', False)
        essay_cmid = result.get('essay_cmid', '')

        if essay_linked:
            score += 15
            subscores['essay_linked'] = True
            feedback_parts.append(
                f"'Learning Theories Essay' (cmid={essay_cmid}) has competency linked"
            )
        else:
            subscores['essay_linked'] = False
            if essay_cmid:
                feedback_parts.append(
                    f"'Learning Theories Essay' (cmid={essay_cmid}) has no competency linked"
                )
            else:
                feedback_parts.append(
                    "'Learning Theories Essay' activity not found or has no competency linked"
                )

        # ------------------------------------------------------------------
        # Criterion 5: "Assessment Design Project" activity linked — 20 points
        # ------------------------------------------------------------------
        assessment_linked = result.get('assessment_comp_linked', False)
        assessment_cmid = result.get('assessment_cmid', '')

        if assessment_linked:
            score += 20
            subscores['assessment_linked'] = True
            feedback_parts.append(
                f"'Assessment Design Project' (cmid={assessment_cmid}) has competency linked"
            )
        else:
            subscores['assessment_linked'] = False
            if assessment_cmid:
                feedback_parts.append(
                    f"'Assessment Design Project' (cmid={assessment_cmid}) has no competency linked"
                )
            else:
                feedback_parts.append(
                    "'Assessment Design Project' activity not found or has no competency linked"
                )

        # Pass requires >= 60 points AND the framework must exist
        passed = (
            score >= 60
            and subscores.get('framework_exists', False)
        )

        logger.info(
            "Competency framework verification: score=%d, passed=%s, subscores=%s",
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
