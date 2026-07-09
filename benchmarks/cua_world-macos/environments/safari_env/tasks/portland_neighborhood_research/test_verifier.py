#!/usr/bin/env python3
"""Offline tests for portland_neighborhood_research verifier."""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from verifier import verify_portland_neighborhood_research


def _make_env(result_data):
    def copy_from_env(src, dst):
        with open(dst, "w") as f:
            json.dump(result_data, f)
    return {"copy_from_env": copy_from_env}


def _base():
    return {
        "task_start": 1700000000,
        "visited_realestate_site": False,
        "visited_school_site": False,
        "note_found": False,
        "note_is_fresh": False,
        "note_title": "",
        "note_length": 0,
        "note_keyword_count": 0,
        "note_keywords_found": [],
    }


def test_do_nothing():
    r = verify_portland_neighborhood_research([], _make_env(_base()), {})
    assert not r["passed"], f"Expected failed, got: {r}"
    assert r["score"] == 0, f"Expected score 0, got: {r['score']}"


def test_partial():
    data = {**_base(),
            "note_found": True, "note_is_fresh": True, "note_length": 600,
            "note_keyword_count": 2, "visited_realestate_site": True}
    r = verify_portland_neighborhood_research([], _make_env(data), {})
    assert not r["passed"], f"Expected failed, got: {r}"
    assert 0 < r["score"] < 70, f"Expected partial score, got: {r['score']}"


def test_full():
    data = {**_base(),
            "note_found": True, "note_is_fresh": True, "note_length": 3000,
            "note_keyword_count": 6, "visited_realestate_site": True,
            "visited_school_site": True}
    r = verify_portland_neighborhood_research([], _make_env(data), {})
    assert r["passed"], f"Expected passed, got: {r}"
    assert r["score"] >= 70, f"Expected score ≥70, got: {r['score']}"


def test_note_but_no_research_is_capped():
    data = {**_base(), "note_found": True, "note_is_fresh": True, "note_length": 3000,
            "note_keyword_count": 6}
    r = verify_portland_neighborhood_research([], _make_env(data), {})
    assert not r["passed"]
    assert r["score"] <= 15


if __name__ == "__main__":
    test_do_nothing()
    test_partial()
    test_full()
    test_note_but_no_research_is_capped()
    print("All tests passed.")
