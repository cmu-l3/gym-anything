#!/usr/bin/env python3
"""Verifier for research_synthesis_wiki task.

Checks that a science journalist created a 5-tiddler quantum computing research
wiki, including a synthesis hub that links to the pre-existing 'Quantum
Entanglement Explained' tiddler.
"""

import json
import os
import tempfile


def verify_research_synthesis_wiki(traj, env_info, task_info):
    """Score the research synthesis wiki task.

    Scoring (100 pts total):
      - Each of 5 required tiddlers found: 8 pts each = 40 pts
      - Research tag (1 pt per tiddler, up to 5): 5 pts
      - QuantumComputing tag (1 pt per tiddler, up to 5): 5 pts
      - Wiki tables (2 pts per tiddler with table, up to 5): 10 pts
      - Section headings (1 pt per tiddler, up to 5): 5 pts
      - Wikilinks to other tiddlers (1 pt per tiddler, up to 5): 5 pts
      - Hub links to 'Quantum Entanglement Explained': 6 pts
      - Adequate word count ≥120 (1 pt per tiddler, up to 10): 10 pts
      - GUI save verified: 14 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env('/tmp/research_synthesis_wiki_result.json', tmp.name)
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
            "feedback": f"Insufficient new tiddlers created: {new_count}/5 required"
        }

    required_titles = [
        ("Quantum Computing - Research Hub", "quantum_computing_research_hub"),
        ("Quantum Computing - Key Concepts", "quantum_computing_key_concepts"),
        ("Quantum Computing - Current Hardware", "quantum_computing_current_hardware"),
        ("Quantum Computing - Real-World Applications", "quantum_computing_real_world_applications"),
        ("Quantum Computing - Challenges and Roadmap", "quantum_computing_challenges_and_roadmap"),
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

    # Research tag: 1 pt per tiddler, up to 5
    research_tagged = result.get('research_tagged_count', 0)
    research_score = min(5, research_tagged)
    score += research_score
    parts.append(f"Research tag: {research_tagged}/5 tiddlers (+{research_score} pts)")

    # QuantumComputing tag: 1 pt per tiddler, up to 5
    qc_tagged = result.get('qc_tagged_count', 0)
    qc_score = min(5, qc_tagged)
    score += qc_score
    parts.append(f"QuantumComputing tag: {qc_tagged}/5 tiddlers (+{qc_score} pts)")

    # Tables: 2 pts per tiddler with table
    table_count = result.get('table_count', 0)
    table_score = min(10, table_count * 2)
    score += table_score
    parts.append(f"Wiki tables: {table_count}/5 tiddlers have tables (+{table_score} pts)")

    # Headings: 1 pt per tiddler
    heading_count = result.get('heading_count', 0)
    heading_score = min(5, heading_count)
    score += heading_score
    parts.append(f"Section headings: {heading_count}/5 tiddlers (+{heading_score} pts)")

    # Wikilinks: 1 pt per tiddler
    link_count = result.get('link_count', 0)
    link_score = min(5, link_count)
    score += link_score
    parts.append(f"Wikilinks: {link_count}/5 tiddlers (+{link_score} pts)")

    # Hub links to existing Quantum Entanglement tiddler: 6 pts
    if result.get('hub_links_to_existing_tiddler', False):
        score += 6
        parts.append("Hub tiddler links to 'Quantum Entanglement Explained' (+6 pts)")
    else:
        parts.append("FAIL: Hub does not link to pre-existing 'Quantum Entanglement Explained' tiddler")

    # Adequate word count ≥120: 2 pts per tiddler, up to 5 tiddlers = 10 pts
    adequate = result.get('adequate_words_count', 0)
    word_score = min(10, adequate * 2)
    score += word_score
    parts.append(f"Word count ≥120: {adequate}/5 tiddlers (+{word_score} pts)")

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
        and research_tagged >= 3
        and score >= 60
    )

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
