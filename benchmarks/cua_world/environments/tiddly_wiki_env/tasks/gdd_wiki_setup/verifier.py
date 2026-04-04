#!/usr/bin/env python3
"""Verifier for gdd_wiki_setup task.

Checks that the agent created a 6-tiddler Game Design Document wiki for
'Echoes of the Void', each with proper tags, tables, headings, and wikilinks.
"""

import json
import os
import tempfile


def verify_gdd_wiki_setup(traj, env_info, task_info):
    """Score the GDD wiki creation task.

    Scoring (100 pts total):
      - Each of 6 required tiddlers found: 8 pts each = 48 pts
      - GDD tag present (1 pt per tiddler, up to 5): 5 pts
      - EchoesOfTheVoid tag present (1 pt per tiddler, up to 5): 5 pts
      - Wiki tables present (2 pts per tiddler with table, up to 6): 12 pts
      - Wikilinks present (1.5 pts per tiddler with links, up to 6): 9 pts
      - Adequate word count ≥80 (1 pt per tiddler, up to 7): 7 pts
      - GUI save verified via server log: 14 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env('/tmp/gdd_wiki_setup_result.json', tmp.name)
        with open(tmp.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    parts = []

    new_count = result.get('new_count', 0)
    if new_count < 3:
        return {
            "passed": False, "score": 0,
            "feedback": f"Insufficient new tiddlers created: {new_count}/6 required"
        }

    required_titles = [
        ("Echoes of the Void - GDD Hub", "echoes_of_the_void_gdd_hub"),
        ("Echoes of the Void - Core Mechanics", "echoes_of_the_void_core_mechanics"),
        ("Echoes of the Void - Character Roster", "echoes_of_the_void_character_roster"),
        ("Echoes of the Void - World Design", "echoes_of_the_void_world_design"),
        ("Echoes of the Void - Story and Narrative", "echoes_of_the_void_story_and_narrative"),
        ("Echoes of the Void - Technical Requirements", "echoes_of_the_void_technical_requirements"),
    ]

    tiddlers = result.get('tiddlers', {})
    found_count = 0

    for title, key in required_titles:
        info = tiddlers.get(key, {})
        if info.get('found'):
            score += 8
            found_count += 1
            parts.append(f"Found: '{title}'")
        else:
            parts.append(f"MISSING: '{title}'")

    # Tags: 5 pts for GDD + 5 pts for EchoesOfTheVoid (1 pt per tiddler, capped)
    gdd_tagged = result.get('gdd_tagged_count', 0)
    echoes_tagged = result.get('echoes_tagged_count', 0)
    gdd_score = min(5, gdd_tagged)
    echoes_score = min(5, echoes_tagged)
    score += gdd_score + echoes_score
    parts.append(f"GDD tag: {gdd_tagged}/6 tiddlers (+{gdd_score} pts)")
    parts.append(f"EchoesOfTheVoid tag: {echoes_tagged}/6 tiddlers (+{echoes_score} pts)")

    # Tables: 2 pts per tiddler with a table, up to 6 tiddlers
    table_count = result.get('table_count', 0)
    table_score = min(12, table_count * 2)
    score += table_score
    parts.append(f"Wiki tables: {table_count}/6 tiddlers have tables (+{table_score} pts)")

    # Wikilinks: 1.5 pts per tiddler with [[links]], up to 6
    link_count = result.get('link_count', 0)
    link_score = min(9, int(link_count * 1.5))
    score += link_score
    parts.append(f"Wikilinks: {link_count}/6 tiddlers have [[links]] (+{link_score} pts)")

    # Adequate word count (≥80 words): 1 pt per tiddler, up to 7
    adequate = result.get('adequate_words_count', 0)
    word_score = min(7, adequate)
    score += word_score
    parts.append(f"Word count ≥80: {adequate}/6 tiddlers (+{word_score} pts)")

    # GUI save via server log: 14 pts
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        score += 14
        parts.append("GUI save verified via TiddlyWiki server log (+14 pts)")
    else:
        parts.append("FAIL: No server-mediated save detected — direct file editing suspected")

    parts.append(f"New tiddlers created: {new_count}")

    passed = (
        found_count >= 4
        and gui_save
        and gdd_tagged >= 4
        and score >= 60
    )

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
