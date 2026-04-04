#!/usr/bin/env python3
"""Verifier for Build Question Bank and Quiz task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_build_question_bank_and_quiz(traj, env_info, task_info):
    """
    Verify that the agent correctly populated the MATH201 question bank and
    created a randomized mid-term quiz.

    Scoring (100 points total):

    Criterion 1 — Question bank categories pre-check (0 pts, informational only):
        - "Probability Basics" category exists in MATH201 context      [0 pts]
        - "Descriptive Statistics" category exists in MATH201 context  [0 pts]
        Note: categories are pre-created by setup; no points awarded.

    Criterion 2 — Probability Basics questions (25 pts):
        - Category has 3 or more non-random questions                  [20 pts]
        - All 3 questions are multichoice type                         [5 pts]

    Criterion 3 — Descriptive Statistics questions (20 pts):
        - Category has 2 or more non-random questions                  [15 pts]
        - Both questions are truefalse type                            [5 pts]

    Criterion 4 — Quiz created (20 pts):
        - Quiz "MATH201 Mid-Term Examination" (or similar) exists      [20 pts]

    Criterion 5 — Quiz time limit (10 pts):
        - Time limit = 45 minutes = 2700 seconds (±5 min tolerance)    [10 pts]

    Criterion 6 — Quiz max attempts (10 pts):
        - Maximum attempts set to 1                                     [10 pts]

    Criterion 7 — Random question slots (15 pts):
        - Quiz has 4 total slots OR 2+ random-type slots               [10 pts]
        - Both question bank categories represented in random draws     [5 pts]

    Pass threshold: 60 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        try:
            copy_from_env("/tmp/build_question_bank_and_quiz_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_result.name)
            except OSError:
                pass

        score = 0
        feedback_parts = []
        subscores = {}

        # ------------------------------------------------------------------
        # Criterion 1: Question bank categories exist (0 points, informational)
        # Categories are pre-created by setup — no points awarded here.
        # ------------------------------------------------------------------
        prob_cat_found = result.get('prob_cat_found', False)
        stat_cat_found = result.get('stat_cat_found', False)

        crit1_score = 0
        if prob_cat_found:
            feedback_parts.append("Probability Basics category found (pre-existing)")
        else:
            feedback_parts.append("Probability Basics category NOT found (setup error)")

        if stat_cat_found:
            feedback_parts.append("Descriptive Statistics category found (pre-existing)")
        else:
            feedback_parts.append("Descriptive Statistics category NOT found (setup error)")

        subscores["categories_found"] = crit1_score
        logger.info(f"Criterion 1 (categories): {crit1_score}/0 (informational)")

        # ------------------------------------------------------------------
        # Criterion 2: Probability Basics questions (20 points)
        # ------------------------------------------------------------------
        prob_q_count = int(result.get('prob_question_count', 0))
        prob_mc_count = int(result.get('prob_mc_count', 0))

        crit2_score = 0
        if prob_q_count >= 3:
            crit2_score += 20
            feedback_parts.append(f"Probability Basics has {prob_q_count} questions (need 3+)")
        elif prob_q_count == 2:
            crit2_score += 13
            feedback_parts.append(f"Probability Basics has {prob_q_count} questions (need 3)")
        elif prob_q_count == 1:
            crit2_score += 6
            feedback_parts.append(f"Probability Basics has only 1 question (need 3)")
        else:
            feedback_parts.append("Probability Basics has no questions")

        if prob_q_count >= 3 and prob_mc_count >= 3:
            crit2_score += 5
            feedback_parts.append("All Probability Basics questions are multichoice")
        elif prob_mc_count > 0:
            feedback_parts.append(f"Probability Basics: {prob_mc_count}/{prob_q_count} are multichoice (expected all 3)")
        else:
            feedback_parts.append("No multichoice questions found in Probability Basics")

        score += crit2_score
        subscores["prob_questions"] = crit2_score
        logger.info(f"Criterion 2 (prob questions): {crit2_score}/25")

        # ------------------------------------------------------------------
        # Criterion 3: Descriptive Statistics questions (15 points)
        # ------------------------------------------------------------------
        stat_q_count = int(result.get('stat_question_count', 0))
        stat_tf_count = int(result.get('stat_tf_count', 0))

        crit3_score = 0
        if stat_q_count >= 2:
            crit3_score += 15
            feedback_parts.append(f"Descriptive Statistics has {stat_q_count} questions (need 2+)")
        elif stat_q_count == 1:
            crit3_score += 8
            feedback_parts.append("Descriptive Statistics has only 1 question (need 2)")
        else:
            feedback_parts.append("Descriptive Statistics has no questions")

        if stat_q_count >= 2 and stat_tf_count >= 2:
            crit3_score += 5
            feedback_parts.append("Both Descriptive Statistics questions are true/false")
        elif stat_tf_count > 0:
            feedback_parts.append(f"Descriptive Statistics: {stat_tf_count}/{stat_q_count} are truefalse (expected both)")
        else:
            feedback_parts.append("No truefalse questions found in Descriptive Statistics")

        score += crit3_score
        subscores["stat_questions"] = crit3_score
        logger.info(f"Criterion 3 (stat questions): {crit3_score}/20")

        # ------------------------------------------------------------------
        # Criterion 4: Quiz created (15 points)
        # ------------------------------------------------------------------
        quiz_found = result.get('quiz_found', False)
        quiz_name = result.get('quiz_name', '').lower().strip()

        crit4_score = 0
        if quiz_found:
            # Name must contain both "mid" (or "midterm") and "term"/"examination"
            # Accept reasonable variations on the required name
            name_ok = (
                ('mid' in quiz_name or 'midterm' in quiz_name) and
                ('term' in quiz_name or 'exam' in quiz_name or 'examination' in quiz_name)
            )
            if name_ok:
                crit4_score = 20
                feedback_parts.append(f"Quiz '{result.get('quiz_name', '')}' created with correct name")
            else:
                # Quiz exists but name does not match well
                crit4_score = 10
                feedback_parts.append(
                    f"Quiz found but name '{result.get('quiz_name', '')}' does not match "
                    "'MATH201 Mid-Term Examination' (partial credit)"
                )
        else:
            feedback_parts.append("Quiz 'MATH201 Mid-Term Examination' NOT found in MATH201")

        score += crit4_score
        subscores["quiz_created"] = crit4_score
        logger.info(f"Criterion 4 (quiz created): {crit4_score}/20")

        # ------------------------------------------------------------------
        # Criterion 5: Quiz time limit (10 points)
        # 45 minutes = 2700 seconds; accept range 2640-2760 (±1 min extra leniency)
        # ------------------------------------------------------------------
        timelimit = int(result.get('quiz_timelimit_sec', 0))

        crit5_score = 0
        if quiz_found:
            if 2640 <= timelimit <= 2760:
                crit5_score = 10
                feedback_parts.append(f"Quiz time limit correct: {timelimit}s (~45 min)")
            elif 2400 <= timelimit <= 3000:
                # Within 5 minutes either way of 45 min — partial credit
                crit5_score = 5
                feedback_parts.append(
                    f"Quiz time limit close: {timelimit}s (expected 2700s / 45 min)"
                )
            elif timelimit > 0:
                crit5_score = 2
                feedback_parts.append(
                    f"Quiz time limit set but incorrect: {timelimit}s (expected 2700s)"
                )
            else:
                feedback_parts.append("Quiz has no time limit set (expected 45 minutes)")
        else:
            feedback_parts.append("Cannot check time limit — quiz not found")

        score += crit5_score
        subscores["quiz_timelimit"] = crit5_score
        logger.info(f"Criterion 5 (time limit): {crit5_score}/10")

        # ------------------------------------------------------------------
        # Criterion 6: Quiz max attempts (10 points)
        # ------------------------------------------------------------------
        attempts = int(result.get('quiz_attempts', 0))

        crit6_score = 0
        if quiz_found:
            if attempts == 1:
                crit6_score = 10
                feedback_parts.append("Quiz max attempts = 1 (correct)")
            elif attempts > 1:
                feedback_parts.append(f"Quiz attempts = {attempts} (expected 1)")
            else:
                feedback_parts.append("Quiz attempts = 0 (unlimited); expected 1")
        else:
            feedback_parts.append("Cannot check attempts — quiz not found")

        score += crit6_score
        subscores["quiz_attempts"] = crit6_score
        logger.info(f"Criterion 6 (attempts): {crit6_score}/10")

        # ------------------------------------------------------------------
        # Criterion 7: Random question slots (20 points)
        # The quiz should have 4 total slots (2 from each category) and at
        # least 2 random-type slots.  The verifier is lenient because Moodle
        # 4.x stores random slots differently and our SQL may not catch all
        # representations.
        # ------------------------------------------------------------------
        total_slots = int(result.get('quiz_total_slots', 0))
        random_slots = int(result.get('random_slot_count', 0))
        prob_random = int(result.get('prob_random_count', 0))
        stat_random = int(result.get('stat_random_count', 0))

        crit7_score = 0
        if quiz_found:
            # Sub-criterion 7a: Slot count / random slot detection (10 pts)
            if total_slots >= 4:
                crit7_score += 10
                feedback_parts.append(f"Quiz has {total_slots} question slots (expected 4)")
            elif random_slots >= 2:
                # Correct random configuration even if total slot count is odd
                crit7_score += 10
                feedback_parts.append(
                    f"Quiz has {random_slots} random question slots (expected 2+); "
                    f"total slots={total_slots}"
                )
            elif total_slots >= 2:
                crit7_score += 5
                feedback_parts.append(
                    f"Quiz has {total_slots} slots (expected 4); "
                    f"random slots detected={random_slots}"
                )
            elif total_slots >= 1:
                crit7_score += 2
                feedback_parts.append(
                    f"Quiz has {total_slots} slot(s) — random draw configuration incomplete"
                )
            else:
                feedback_parts.append("Quiz has no question slots — no questions added")

            # Sub-criterion 7b: Both categories represented in random draws (5 pts)
            # Accept either the mdl_question qtype='random' approach or total-slots approach
            both_cats_represented = (prob_random >= 1 and stat_random >= 1)
            # Fallback heuristic: if total_slots >= 4 and we cannot detect random type
            # specifically, give partial benefit of the doubt
            if both_cats_represented:
                crit7_score += 5
                feedback_parts.append(
                    "Both categories represented in random draws "
                    f"(prob={prob_random}, stat={stat_random})"
                )
            elif total_slots >= 4 and random_slots == 0:
                # Slots exist but SQL could not confirm random type — partial credit
                crit7_score += 3
                feedback_parts.append(
                    f"4 slots found but random-type detection uncertain "
                    f"(prob_random={prob_random}, stat_random={stat_random})"
                )
            else:
                feedback_parts.append(
                    f"Could not confirm both categories in random draws "
                    f"(prob_random={prob_random}, stat_random={stat_random})"
                )
        else:
            feedback_parts.append("Cannot check question slots — quiz not found")

        score += crit7_score
        subscores["quiz_random_slots"] = crit7_score
        logger.info(f"Criterion 7 (random slots): {crit7_score}/20")

        # ------------------------------------------------------------------
        # Final result
        # ------------------------------------------------------------------
        # Pass requires at minimum: quiz created with correct name AND score >= 60
        quiz_name_ok = subscores.get("quiz_created", 0) >= 20
        passed = score >= 60 and quiz_found and quiz_name_ok

        logger.info(f"Final score: {score}/100, passed={passed}")

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
            "feedback": "Result file not found — export_result.sh may have failed",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}",
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
        }
