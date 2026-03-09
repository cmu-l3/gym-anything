#!/usr/bin/env python3
"""Verifier for it_knowledge_base task.

Checks that an IT support knowledge base was created with 6 tiddlers covering
network, performance, printer, email, and a quick reference commands sheet.
"""

import json
import os
import tempfile


def verify_it_knowledge_base(traj, env_info, task_info):
    """Score the IT knowledge base creation task.

    Scoring (100 pts total):
      - Each of 6 required tiddlers found: 8 pts each = 48 pts
      - IT-Support tag (1 pt per tiddler, up to 6): 6 pts
      - Wiki tables (2 pts per tiddler with table, up to 6): 12 pts
      - Headings (1 pt per tiddler with !! headings, up to 6): 6 pts
      - Structured symptoms/solutions content (1 pt per tiddler, up to 4): 4 pts
      - Wikilinks (1 pt per tiddler with links, up to 6): 6 pts
      - Adequate word count ≥100 (1 pt per tiddler, up to 4): 4 pts
      - GUI save verified via server log: 14 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env('/tmp/it_knowledge_base_result.json', tmp.name)
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
        ("IT Support - Master Index", "it_support_master_index"),
        ("IT Support - Network Connectivity", "it_support_network_connectivity"),
        ("IT Support - Slow Performance", "it_support_slow_performance"),
        ("IT Support - Printer Problems", "it_support_printer_problems"),
        ("IT Support - Email Configuration", "it_support_email_configuration"),
        ("IT Support - Quick Reference Commands", "it_support_quick_reference_commands"),
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

    # IT-Support tag: 1 pt per tiddler, up to 6
    it_tagged = result.get('it_support_tagged_count', 0)
    tag_score = min(6, it_tagged)
    score += tag_score
    parts.append(f"IT-Support tag: {it_tagged}/6 tiddlers (+{tag_score} pts)")

    # Tables: 2 pts per tiddler with table
    table_count = result.get('table_count', 0)
    table_score = min(12, table_count * 2)
    score += table_score
    parts.append(f"Wiki tables: {table_count}/6 tiddlers have tables (+{table_score} pts)")

    # Headings: 1 pt per tiddler with !! headings
    heading_count = result.get('heading_count', 0)
    heading_score = min(6, heading_count)
    score += heading_score
    parts.append(f"Section headings: {heading_count}/6 tiddlers (+{heading_score} pts)")

    # Structured content (symptoms/solutions keywords): 1 pt per guide, up to 4
    symptoms = result.get('symptoms_sections_count', 0)
    solutions = result.get('solutions_sections_count', 0)
    structure_score = min(4, min(symptoms, solutions))
    score += structure_score
    parts.append(f"Structured guides (symptoms+solutions): {min(symptoms, solutions)}/5 (+{structure_score} pts)")

    # Wikilinks: 1 pt per tiddler with [[links]]
    link_count = result.get('link_count', 0)
    link_score = min(6, link_count)
    score += link_score
    parts.append(f"Wikilinks: {link_count}/6 tiddlers have [[links]] (+{link_score} pts)")

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
        and it_tagged >= 4
        and score >= 60
    )

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
