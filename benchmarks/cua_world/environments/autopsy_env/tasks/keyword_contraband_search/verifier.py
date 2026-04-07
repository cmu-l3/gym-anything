#!/usr/bin/env python3
"""
Verifier for keyword_contraband_search task.

Scoring (100 pts total, pass threshold = 60):
  15 pts  — Autopsy case created and DB found
  15 pts  — Disk image data source added
  10 pts  — Ingest completed (files indexed)
  20 pts  — Keyword hits found in Autopsy DB (artifacts populated)
  20 pts  — Hits report file exists, is recent, has pipe-delimited entries
  20 pts  — Report keywords match GT-identified keywords and summary is correct
"""

import json
import os
import re
import tempfile


_TARGET_KEYWORDS = {"secret", "password", "evidence", "deleted"}


def verify_keyword_contraband_search(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/keyword_contraband_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/keyword_contraband_gt.json")

    # ── Pull result ───────────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — task was not attempted."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Pull GT ───────────────────────────────────────────────────────────────
    gt = {"keywords_with_hits": [], "keyword_hits": {}}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_keywords_with_hits = set(gt.get("keywords_with_hits", []))
    gt_keyword_hits = gt.get("keyword_hits", {})

    # ── Criterion 1: Case DB found (15 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 15
        feedback_parts.append("PASS Case DB found for Keyword_Search_2024 (+15)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data source added (15 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Data source added (+15)")
    else:
        feedback_parts.append("FAIL Data source not found in DB")

    # ── Criterion 3: Ingest completed (10 pts) ────────────────────────────────
    if result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS Ingest completed (+10)")
    else:
        feedback_parts.append("FAIL Ingest did not complete")

    # ── Criterion 4: Keyword hits in DB (20 pts) ──────────────────────────────
    db_hit_count = result.get("db_keyword_hit_count", 0)
    db_keywords_found = set(kw.lower() for kw in result.get("db_keywords_found", []))

    if db_hit_count > 0:
        score += 20
        feedback_parts.append(
            f"PASS {db_hit_count} keyword hit artifact(s) in DB, "
            f"keywords: {sorted(db_keywords_found)} (+20)"
        )
    elif result.get("ingest_completed"):
        # Ingest ran but no keyword hits — maybe keyword search was not enabled
        # OR the image truly has no hits for these keywords
        # Give partial credit if GT also shows no hits
        if not gt_keywords_with_hits:
            score += 15
            feedback_parts.append(
                "PASS No keyword hits in DB, consistent with GT showing no hits (+15)"
            )
        else:
            feedback_parts.append(
                f"FAIL No keyword hit artifacts in DB despite GT showing "
                f"hits for: {sorted(gt_keywords_with_hits)}"
            )
    else:
        feedback_parts.append("FAIL No keyword hit artifacts found — ingest may not have included Keyword Search")

    # ── Criterion 5: Hits report file (20 pts) ────────────────────────────────
    start_time = result.get("start_time", 0)
    hits_mtime = result.get("hits_file_mtime", 0)
    hits_content = result.get("hits_file_content", "").replace("\\n", "\n").replace("\\t", "\t")

    if result.get("hits_file_exists"):
        is_recent = (start_time == 0 or hits_mtime >= start_time)
        lines = [l.strip() for l in hits_content.splitlines() if l.strip()]
        pipe_lines = [l for l in lines if "|" in l]

        if is_recent and len(pipe_lines) >= 1:
            score += 20
            feedback_parts.append(
                f"PASS Hits report has {len(pipe_lines)} pipe-delimited entries (+20)"
            )
        elif is_recent and not hits_content.strip():
            # Empty file is valid if no hits were found
            if not gt_keywords_with_hits:
                score += 15
                feedback_parts.append(
                    "PASS Hits report is empty — consistent with no keyword hits found (+15)"
                )
            else:
                score += 5
                feedback_parts.append(
                    "PARTIAL Hits report exists but is empty despite expected keyword hits (+5)"
                )
        elif not is_recent:
            score += 3
            feedback_parts.append("PARTIAL Hits report exists but pre-dates task start (+3)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Hits report exists but has no pipe-delimited lines (+5)")
    else:
        feedback_parts.append("FAIL Hits report not written to /home/ga/Reports/keyword_hits.txt")

    # ── Criterion 6: Report keywords match GT + summary correct (20 pts) ──────
    hits_content_lower = hits_content.lower()
    summary_content = result.get("summary_content", "").replace("\\n", "\n").lower()
    all_content = (hits_content_lower + " " + summary_content)

    pts_kw = 0
    # Check all 4 target keywords appear somewhere in the reports
    for kw in _TARGET_KEYWORDS:
        if kw in all_content:
            pts_kw += 5  # 5 pts per keyword referenced
    pts_kw = min(pts_kw, 20)

    # Check summary format
    has_total_line = "total_keywords_searched" in summary_content or "total keywords" in summary_content
    has_keywords_with_hits = "keywords_with_hits" in summary_content or "keywords with hits" in summary_content

    if has_total_line and has_keywords_with_hits:
        pts_kw = min(pts_kw + 5, 20)

    if pts_kw > 0:
        score += pts_kw
        feedback_parts.append(
            f"{'PASS' if pts_kw >= 16 else 'PARTIAL'} Keyword coverage in reports: +{pts_kw}"
        )
    else:
        feedback_parts.append("FAIL Reports do not reference any of the 4 target keywords")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
