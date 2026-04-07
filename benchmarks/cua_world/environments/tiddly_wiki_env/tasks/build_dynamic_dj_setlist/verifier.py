#!/usr/bin/env python3
"""Verifier for build_dynamic_dj_setlist task."""

import json
import tempfile
import os
import re

def verify_dj_setlist(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dj_setlist_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    if not result.get('tiddler_exists'):
        return {"passed": False, "score": 0, "feedback": "Tiddler 'Smith Wedding Setlist' not found."}

    score += 5
    feedback_parts.append("Tiddler exists")

    text = result.get('tiddler_text', '')
    html = result.get('rendered_html', '')

    # Check Headings
    if '! Cocktail Hour' in text and '! Dinner' in text and '! Dance Floor' in text:
        score += 5
        feedback_parts.append("All headings found")
    else:
        feedback_parts.append("Missing one or more required headings")

    # Anti-gaming: dynamic generation check
    list_widgets = len(re.findall(r'<\$list', text))
    if list_widgets >= 3:
        score += 10
        feedback_parts.append(f"Found {list_widgets} list widgets")
    else:
        feedback_parts.append("List widgets missing or insufficient")

    # Check DoNotPlay logic
    if 'DoNotPlay' in text and ('!tag[' in text or '-[tag[' in text):
        score += 5
        feedback_parts.append("DoNotPlay negation syntax found")
    else:
        feedback_parts.append("DoNotPlay explicit exclusion syntax not found")
        
    # Check for artist transclusion
    if '!!artist' in text or 'field="artist"' in text or 'get[artist]' in text:
        score += 10
        feedback_parts.append("Artist transclusion found")
    else:
        feedback_parts.append("Artist transclusion missing")

    # Check for hardcoded artists to prevent cheating
    hardcoded = False
    for artist in ["Frank Sinatra", "Al Green", "Mark Ronson"]:
        if artist in text:
            hardcoded = True
    if hardcoded:
        return {"passed": False, "score": 0, "feedback": "FAIL: Hardcoded artist names found in source tiddler."}

    def check_sequence(titles, name):
        nonlocal score
        indices = [html.find(title) for title in titles]
        if all(idx != -1 for idx in indices):
            if indices == sorted(indices):
                score += 15
                feedback_parts.append(f"{name} correctly filtered and sorted")
            else:
                score += 10
                feedback_parts.append(f"{name} filtered but incorrectly sorted")
        else:
            missing = [t for i, t in enumerate(titles) if indices[i] == -1]
            feedback_parts.append(f"{name} missing expected songs: {missing}")

    # Verify Logic and Sorting 
    cocktail_titles = ["Banana Pancakes", "Blackbird", "Come Away With Me", "Fly Me to the Moon", "So What", "Take Five"]
    check_sequence(cocktail_titles, "Cocktail Hour")

    dinner_titles = ["Let's Stay Together", "Perfect", "Thinking Out Loud", "Wonderful Tonight", "At Last", "All of Me"]
    check_sequence(dinner_titles, "Dinner")

    dance_titles = ["Billie Jean", "Crazy in Love", "Don't Stop Believin'", "I Gotta Feeling", "Levitating", "September", "Superstition", "Uptown Funk"]
    check_sequence(dance_titles, "Dance Floor")

    # Verify exclusions (Should exclude based on DoNotPlay tag, or unmatched tempo criteria)
    excluded_songs = ["Tears in Heaven", "A Thousand Years", "Mr. Brightside", "I Will Always Love You", "Shape of You"]
    found_excluded = [song for song in excluded_songs if song in html]
    if found_excluded:
        feedback_parts.append(f"FAIL: Excluded/Unmatched songs found in output: {found_excluded}")
    else:
        score += 20
        feedback_parts.append("Excluded and unmatched songs successfully omitted")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}