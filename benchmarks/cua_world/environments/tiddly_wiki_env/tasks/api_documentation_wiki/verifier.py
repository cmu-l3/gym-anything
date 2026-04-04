#!/usr/bin/env python3
"""Verifier for api_documentation_wiki task.

Checks that a technical writer created a 5-tiddler REST API documentation
wiki for a library management system, including endpoints reference with 8+
endpoints, error codes table, and version changelog.
"""

import json
import os
import tempfile


def verify_api_documentation_wiki(traj, env_info, task_info):
    """Score the API documentation wiki task.

    Scoring (100 pts total):
      - Each of 5 required tiddlers found: 7 pts each = 35 pts
      - API-Documentation tag (1 pt per tiddler, up to 5): 5 pts
      - LibrarySystem tag (1 pt per tiddler, up to 5): 5 pts
      - Wiki tables (2 pts per tiddler with table, up to 5): 10 pts
      - Endpoints table has 8+ rows: 8 pts (partial for 4+)
      - Error codes table has 8+ rows: 6 pts (partial for 4+)
      - Changelog table has 4+ versions: 4 pts (partial for 2+)
      - Auth guide has code example (backtick monospace): 4 pts
      - Wikilinks between tiddlers (1 pt per tiddler, up to 4): 4 pts
      - Adequate word count ≥120 (1 pt per tiddler, up to 5 pts): 5 pts
      - GUI save verified: 14 pts
      (Max without capping = 100)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env('/tmp/api_documentation_wiki_result.json', tmp.name)
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
        ("Library API - Overview", "library_api_overview"),
        ("Library API - Authentication Guide", "library_api_authentication_guide"),
        ("Library API - Endpoints Reference", "library_api_endpoints_reference"),
        ("Library API - Error Codes Reference", "library_api_error_codes_reference"),
        ("Library API - Changelog", "library_api_changelog"),
    ]

    tiddlers = result.get('tiddlers', {})
    found_count = 0

    for title, key in required_titles:
        info = tiddlers.get(key, {})
        if info.get('found'):
            score += 7
            found_count += 1
            parts.append(f"Found: '{title}'")
        else:
            parts.append(f"MISSING: '{title}'")

    # API-Documentation tag: 1 pt per tiddler, up to 5
    api_tagged = result.get('api_doc_tagged_count', 0)
    api_score = min(5, api_tagged)
    score += api_score
    parts.append(f"API-Documentation tag: {api_tagged}/5 tiddlers (+{api_score} pts)")

    # LibrarySystem tag: 1 pt per tiddler, up to 5
    lib_tagged = result.get('library_tagged_count', 0)
    lib_score = min(5, lib_tagged)
    score += lib_score
    parts.append(f"LibrarySystem tag: {lib_tagged}/5 tiddlers (+{lib_score} pts)")

    # Tables: 2 pts per tiddler with table
    table_count = result.get('table_count', 0)
    table_score = min(10, table_count * 2)
    score += table_score
    parts.append(f"Wiki tables: {table_count}/5 tiddlers have tables (+{table_score} pts)")

    # Endpoints table has 8+ rows: 8 pts; 4+ rows: 4 pts
    endpoints_rows = result.get('endpoints_row_count', 0)
    if endpoints_rows >= 8:
        score += 8
        parts.append(f"Endpoints table: {endpoints_rows} rows (≥8 required) (+8 pts)")
    elif endpoints_rows >= 4:
        score += 4
        parts.append(f"Endpoints table: {endpoints_rows} rows (partial; need 8) (+4 pts)")
    else:
        parts.append(f"Endpoints table: {endpoints_rows} rows (need 8)")

    # Error codes table has 8+ rows: 6 pts; 4+ rows: 3 pts
    error_rows = result.get('error_codes_row_count', 0)
    if error_rows >= 8:
        score += 6
        parts.append(f"Error codes table: {error_rows} rows (≥8 required) (+6 pts)")
    elif error_rows >= 4:
        score += 3
        parts.append(f"Error codes table: {error_rows} rows (partial; need 8) (+3 pts)")
    else:
        parts.append(f"Error codes table: {error_rows} rows (need 8)")

    # Changelog table has 4+ version rows: 4 pts; 2+ rows: 2 pts
    changelog_rows = result.get('changelog_row_count', 0)
    if changelog_rows >= 4:
        score += 4
        parts.append(f"Changelog: {changelog_rows} versions (≥4 required) (+4 pts)")
    elif changelog_rows >= 2:
        score += 2
        parts.append(f"Changelog: {changelog_rows} versions (partial; need 4) (+2 pts)")
    else:
        parts.append(f"Changelog: {changelog_rows} versions (need 4)")

    # Auth guide has code example: 4 pts
    if result.get('has_code_example_in_auth', False):
        score += 4
        parts.append("Auth guide has code example (+4 pts)")
    else:
        parts.append("Auth guide missing code example (backtick monospace)")

    # Wikilinks: 1 pt per tiddler, up to 4
    link_count = result.get('link_count', 0)
    link_score = min(4, link_count)
    score += link_score
    parts.append(f"Wikilinks: {link_count}/5 tiddlers have [[links]] (+{link_score} pts)")

    # Adequate word count ≥120: 1 pt per tiddler, up to 5
    adequate = result.get('adequate_words_count', 0)
    word_score = min(5, adequate)
    score += word_score
    parts.append(f"Word count ≥120: {adequate}/5 tiddlers (+{word_score} pts)")

    # GUI save: 14 pts (score capped at 100)
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
        and api_tagged >= 4
        and score >= 60
    )

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
