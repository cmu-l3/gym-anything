#!/usr/bin/env python3
"""Verifier for fiction_worldbuilding_wiki task.

Checks that a creative writer built a 6-tiddler world-building wiki for
the fantasy series 'Shards of the Celestial War' with characters, factions,
magic system, timeline, and glossary.
"""

import json
import os
import tempfile


def verify_fiction_worldbuilding_wiki(traj, env_info, task_info):
    """Score the fiction world-building wiki task.

    Scoring (100 pts total):
      - Each of 6 required tiddlers found: 8 pts each = 48 pts
      - Fiction tag (1 pt per tiddler, up to 5): 5 pts
      - CelestialWar tag (1 pt per tiddler, up to 5): 5 pts
      - Wiki tables (2 pts per tiddler with table, up to 5): 10 pts
      - Cross-linking between tiddlers (1 pt per tiddler, up to 6): 6 pts
      - Characters tiddler has 5+ characters in table: 8 pts (partial for 3+)
      - Adequate word count ≥100 (1 pt per tiddler, up to 4): 4 pts
      - GUI save verified: 14 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env('/tmp/fiction_worldbuilding_wiki_result.json', tmp.name)
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
        ("Celestial War - World Overview", "celestial_war_world_overview"),
        ("Celestial War - Factions and Politics", "celestial_war_factions_and_politics"),
        ("Celestial War - Characters", "celestial_war_characters"),
        ("Celestial War - Magic System", "celestial_war_magic_system"),
        ("Celestial War - Timeline", "celestial_war_timeline"),
        ("Celestial War - Glossary", "celestial_war_glossary"),
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

    # Fiction tag: 1 pt per tiddler, up to 5
    fiction_tagged = result.get('fiction_tagged_count', 0)
    fiction_score = min(5, fiction_tagged)
    score += fiction_score
    parts.append(f"Fiction tag: {fiction_tagged}/6 tiddlers (+{fiction_score} pts)")

    # CelestialWar tag: 1 pt per tiddler, up to 5
    cw_tagged = result.get('cw_tagged_count', 0)
    cw_score = min(5, cw_tagged)
    score += cw_score
    parts.append(f"CelestialWar tag: {cw_tagged}/6 tiddlers (+{cw_score} pts)")

    # Tables: 2 pts per tiddler with table, up to 5 tiddlers
    table_count = result.get('table_count', 0)
    table_score = min(10, table_count * 2)
    score += table_score
    parts.append(f"Wiki tables: {table_count}/6 tiddlers have tables (+{table_score} pts)")

    # Wikilinks: 1 pt per tiddler with [[links]]
    link_count = result.get('link_count', 0)
    link_score = min(6, link_count)
    score += link_score
    parts.append(f"Wikilinks: {link_count}/6 tiddlers have [[links]] (+{link_score} pts)")

    # Characters tiddler: 5+ rows = 8 pts, 3+ rows = 4 pts
    char_rows = result.get('characters_table_rows', 0)
    char_score = 0
    if char_rows >= 5:
        char_score = 8
        parts.append(f"Characters table: {char_rows} characters (≥5 required) (+8 pts)")
    elif char_rows >= 3:
        char_score = 4
        parts.append(f"Characters table: {char_rows} characters (partial; need 5) (+4 pts)")
    else:
        parts.append(f"Characters table: {char_rows} characters (need 5, got {char_rows})")
    score += char_score

    # Adequate word count ≥100: 1 pt per tiddler, up to 4
    adequate = result.get('adequate_words_count', 0)
    word_score = min(4, adequate)
    score += word_score
    parts.append(f"Word count ≥100: {adequate}/6 tiddlers (+{word_score} pts)")

    # GUI save: 14 pts
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
        and fiction_tagged >= 4
        and score >= 60
    )

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
