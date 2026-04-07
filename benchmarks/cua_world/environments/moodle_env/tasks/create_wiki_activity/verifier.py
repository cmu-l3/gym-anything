#!/usr/bin/env python3
"""Verifier for Create Wiki Activity task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_wiki_activity(traj, env_info, task_info):
    """
    Verify that a wiki activity with collaborative pages was created.

    Scoring (100 points):
    - Wiki exists in BIO101 and was newly created (20 points)
    - Wiki name matches "Biology Lab Notebook" (10 points)
    - Wiki mode is "collaborative" (15 points)
    - First page name is correct (10 points)
    - Wiki has description (5 points)
    - Page 1 "Lab Safety Procedures" exists with content "safety goggles" (20 points)
    - Page 2 "Cell Structure Notes" exists with content "mitochondria" (20 points)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_wiki_name = metadata.get('wiki_name', 'Biology Lab Notebook')
    expected_mode = metadata.get('wiki_mode', 'collaborative')
    expected_page1_title = metadata.get('page1_title', 'Lab Safety Procedures')
    expected_page1_fragment = metadata.get('page1_content_fragment', 'safety goggles')
    expected_page2_title = metadata.get('page2_title', 'Cell Structure Notes')
    expected_page2_fragment = metadata.get('page2_content_fragment', 'mitochondria')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_wiki_activity_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Wiki exists and was newly created (20 points)
        wiki_found = result.get('wiki_found', False)
        initial_count = int(result.get('initial_wiki_count', 0))
        current_count = int(result.get('current_wiki_count', 0))
        newly_created = current_count > initial_count

        if wiki_found and newly_created:
            score += 20
            subscores["wiki_created"] = True
            feedback_parts.append(f"Wiki created (count: {initial_count} -> {current_count})")
        elif wiki_found:
            score += 10
            feedback_parts.append("Wiki found but not newly created")
        else:
            feedback_parts.append("Wiki not found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"wiki_created": False}
            }

        # Criterion 2: Wiki name matches (10 points)
        wiki_name = result.get('wiki_name', '').strip()
        if expected_wiki_name.lower() in wiki_name.lower():
            score += 10
            subscores["name_correct"] = True
            feedback_parts.append("Name correct")
        else:
            feedback_parts.append(f"Name mismatch: '{wiki_name}'")

        # Criterion 3: Wiki mode is collaborative (15 points)
        wiki_mode = result.get('wiki_mode', '').lower()
        if wiki_mode == expected_mode:
            score += 15
            subscores["mode_correct"] = True
            feedback_parts.append("Wiki mode: collaborative")
        else:
            feedback_parts.append(f"Wiki mode incorrect: {wiki_mode}")

        # Criterion 4: First page name correct (10 points)
        # Note: Moodle stores first page title in wiki settings AND creates the actual page
        wiki_firstpage = result.get('wiki_firstpage', '').strip()
        if expected_page1_title.lower() in wiki_firstpage.lower():
            score += 10
            subscores["first_page_setting_correct"] = True
            feedback_parts.append("First page setting correct")
        else:
            feedback_parts.append(f"First page setting mismatch: '{wiki_firstpage}'")

        # Criterion 5: Wiki has description (5 points)
        wiki_intro = result.get('wiki_intro', '')
        if wiki_intro and wiki_intro != "NULL":
            score += 5
            subscores["has_description"] = True
            feedback_parts.append("Description added")
        else:
            feedback_parts.append("No description")

        # Criterion 6: Page 1 content verification (20 points)
        page1_found = result.get('page1_found', False)
        page1_content = result.get('page1_content', '').lower()
        if page1_found:
            if expected_page1_fragment.lower() in page1_content:
                score += 20
                subscores["page1_content"] = True
                feedback_parts.append("Page 1 created & content correct")
            else:
                score += 10
                subscores["page1_content"] = False
                feedback_parts.append("Page 1 created but content missing required text")
        else:
            feedback_parts.append("Page 1 not created")

        # Criterion 7: Page 2 content verification (20 points)
        page2_found = result.get('page2_found', False)
        page2_content = result.get('page2_content', '').lower()
        if page2_found:
            if expected_page2_fragment.lower() in page2_content:
                score += 20
                subscores["page2_content"] = True
                feedback_parts.append("Page 2 created & content correct")
            else:
                score += 10
                subscores["page2_content"] = False
                feedback_parts.append("Page 2 created but content missing required text")
        else:
            feedback_parts.append("Page 2 not created")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON Error: {e}"}