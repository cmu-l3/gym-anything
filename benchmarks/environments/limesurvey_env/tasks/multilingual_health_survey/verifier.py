#!/usr/bin/env python3
"""Verifier for multilingual_health_survey task.

A public health researcher must add Spanish (es) language support to an existing
vaccine hesitancy survey, translate the survey title, translate all 8 questions,
and translate answer options.

Scoring (100 points):
- Spanish language added to survey (25 pts)
- Spanish survey title contains vaccine-related keyword (25 pts)
- At least 6 of 8 questions translated to Spanish (30 pts, partial credit)
- Spanish answer options translated (20 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_multilingual_health_survey(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/multilingual_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    # GATE: Survey must exist
    if not result.get("survey_found", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "Vaccine Acceptance and Hesitancy Study survey not found. "
                "The pre-built survey may have been accidentally deleted."
            )
        }

    # Criterion 1: Spanish language added (25 pts)
    spanish_added = result.get("spanish_added", False)
    total_langs = result.get("total_languages", 0)

    if spanish_added:
        score += 25
        subscores["spanish_language_added"] = True
        feedback_parts.append(f"Spanish (es) language added to survey [25/25]")
    else:
        subscores["spanish_language_added"] = False
        feedback_parts.append(
            f"Spanish language NOT added. Survey only has {total_langs} language(s). "
            "Must add 'es' as an additional language [0/25]"
        )

    # Criterion 2: Spanish survey title contains vaccine-related keyword (25 pts)
    spanish_title = result.get("spanish_survey_title", "")
    title_has_keyword = result.get("spanish_title_has_vaccine_keyword", False)

    # More flexible keyword check
    title_lower = spanish_title.lower()
    spanish_vaccine_words = ["vacun", "vacunas", "aceptaci", "hesitaci",
                              "encuesta", "estudio", "salud", "covid"]
    if not title_has_keyword:
        title_has_keyword = any(w in title_lower for w in spanish_vaccine_words)

    if spanish_added and title_has_keyword:
        score += 25
        subscores["spanish_title"] = True
        feedback_parts.append(
            f"Spanish survey title provided with vaccine-related content: '{spanish_title[:60]}' [25/25]"
        )
    elif spanish_added and spanish_title and len(spanish_title) > 3:
        score += 10
        subscores["spanish_title"] = "partial"
        feedback_parts.append(
            f"Spanish title provided but lacks vaccine terminology: '{spanish_title[:60]}' [10/25]"
        )
    elif spanish_added:
        subscores["spanish_title"] = False
        feedback_parts.append(
            "Spanish language added but no Spanish survey title provided [0/25]"
        )
    else:
        subscores["spanish_title"] = False
        feedback_parts.append("No Spanish survey title (Spanish language not added) [0/25]")

    # Criterion 3: Spanish question translations (30 pts)
    # Full 30 pts for >= 6 questions, partial for fewer
    q_translations = result.get("spanish_question_translations", 0)
    if q_translations >= 6:
        score += 30
        subscores["question_translations"] = True
        feedback_parts.append(
            f"{q_translations}/8 questions translated to Spanish [30/30]"
        )
    elif q_translations >= 4:
        score += 20
        subscores["question_translations"] = "partial"
        feedback_parts.append(
            f"{q_translations}/8 questions translated (need at least 6 for full credit) [20/30]"
        )
    elif q_translations >= 2:
        score += 10
        subscores["question_translations"] = "partial"
        feedback_parts.append(
            f"Only {q_translations}/8 questions translated (need at least 6) [10/30]"
        )
    elif q_translations >= 1:
        score += 5
        subscores["question_translations"] = "partial"
        feedback_parts.append(
            f"Only {q_translations} question translated (need at least 6) [5/30]"
        )
    else:
        subscores["question_translations"] = False
        feedback_parts.append(
            "No Spanish question translations found in database [0/30]"
        )

    # Criterion 4: Spanish answer options translated (20 pts)
    a_translations = result.get("spanish_answer_translations", 0)
    if a_translations >= 10:
        score += 20
        subscores["answer_translations"] = True
        feedback_parts.append(
            f"{a_translations} answer options translated to Spanish [20/20]"
        )
    elif a_translations >= 5:
        score += 12
        subscores["answer_translations"] = "partial"
        feedback_parts.append(
            f"{a_translations} answer options translated (comprehensive translation needs more) [12/20]"
        )
    elif a_translations >= 1:
        score += 5
        subscores["answer_translations"] = "partial"
        feedback_parts.append(
            f"Only {a_translations} answer options translated [5/20]"
        )
    else:
        subscores["answer_translations"] = False
        feedback_parts.append("No Spanish answer option translations found [0/20]")

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "survey_id": result.get("survey_id"),
            "spanish_added": spanish_added,
            "spanish_title": spanish_title[:80] if spanish_title else "",
            "q_translations": q_translations,
            "a_translations": a_translations,
            "total_langs": total_langs,
        }
    }
