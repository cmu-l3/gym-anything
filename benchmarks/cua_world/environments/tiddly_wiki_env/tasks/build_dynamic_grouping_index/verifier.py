#!/usr/bin/env python3
"""Verifier for build_dynamic_grouping_index task."""

import json
import tempfile
import os

def verify_dynamic_grouping(traj, env_info, task_info):
    """
    Verify the dynamic index using a combination of programmatic inspection
    (anti-gaming check) and output node rendering (accuracy & scope).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    tiddler_exists = result.get('tiddler_exists', False)
    task_start = result.get('task_start', 0)
    mtime = result.get('tiddler_mtime', 0)
    
    if tiddler_exists:
        # File timestamp must verify it wasn't there before execution
        if mtime > 0 and mtime < task_start:
            feedback_parts.append("FAIL: Tiddler was created before task started (mtime check)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        score += 10
        feedback_parts.append("Tiddler exists and was created during task")
    else:
        feedback_parts.append("FAIL: Tiddler not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Verify Tag
    tags = result.get('tags', '')
    if 'Index' in tags:
        feedback_parts.append("Has 'Index' tag")
    else:
        feedback_parts.append("Missing 'Index' tag")

    raw_text = result.get('raw_text', '').lower()
    html = result.get('rendered_html', '')

    # 1. Anti-gaming check (20 points)
    # The list widget must be used and values must not be hardcoded
    if '<$list' in raw_text:
        hardcoded_words = ['scorsese', 'coppola', 'tarantino', 'kazan', 'godfather', 'pulp fiction']
        if any(w in raw_text for w in hardcoded_words):
            feedback_parts.append("FAIL: Hardcoded data detected in wikitext")
        else:
            score += 20
            feedback_parts.append("Dynamic listing verified (no hardcoding)")
    else:
        feedback_parts.append("FAIL: No <$list> widget used")

    # 2. Scope Accuracy (15 points)
    if html:
        html_lower = html.lower()
        if 'kazan' not in html_lower and 'salesman' not in html_lower and 'streetcar' not in html_lower:
            score += 15
            feedback_parts.append("Correct scope (Plays excluded)")
        else:
            feedback_parts.append("FAIL: Play data (Elia Kazan) incorrectly included")
    
    # 3. Correct Grouping (20 points)
    if html:
        directors_found = 0
        for d in ['Scorsese', 'Coppola', 'Tarantino']:
            if d in html:
                directors_found += 1
                
        if directors_found == 3:
            score += 20
            feedback_parts.append("All 3 film directors found in HTML")
        else:
            score += directors_found * 5
            feedback_parts.append(f"Found {directors_found}/3 film directors")

    # 4. Content Formatting (15 points)
    years = ['1972', '1974', '1979', '1976', '1980', '1990', '1992', '1994']
    formatted_years = 0
    for y in years:
        if f"({y})" in html:
            formatted_years += 1
            
    if formatted_years >= 6:
        score += 15
        feedback_parts.append(f"Years formatted in parentheses ({formatted_years}/8)")
    elif formatted_years > 0:
        score += 5
        feedback_parts.append(f"Some years formatted in parentheses ({formatted_years}/8)")
    else:
        feedback_parts.append("FAIL: Release years not found or not formatted in parentheses")

    # 5. Chronological Sort (20 points)
    if html:
        sort_score = 0
        # Check relative ordering index of titles in the rendered list
        idx_gf = html.find("Godfather")
        idx_conv = html.find("Conversation")
        idx_apoc = html.find("Apocalypse")
        if 0 <= idx_gf < idx_conv < idx_apoc:
            sort_score += 7

        idx_td = html.find("Taxi Driver")
        idx_rb = html.find("Raging Bull")
        idx_gf2 = html.find("Goodfellas")
        if 0 <= idx_td < idx_rb < idx_gf2:
            sort_score += 7
            
        idx_rd = html.find("Reservoir Dogs")
        idx_pf = html.find("Pulp Fiction")
        if 0 <= idx_rd < idx_pf:
            sort_score += 6
            
        score += sort_score
        if sort_score == 20:
            feedback_parts.append("Chronological sort correct for all groupings")
        else:
            feedback_parts.append(f"Chronological sort partially correct ({sort_score}/20)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }