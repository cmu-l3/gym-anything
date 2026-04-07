#!/usr/bin/env python3
"""
Verifier for web_browser_artifact_triage task.

Scoring (100 pts total, pass threshold = 60):
  15 pts  — Autopsy case created and logical data source added
  20 pts  — 'Recent Activity' run successfully (Autopsy DB contains TSK_WEB_SEARCH & TSK_WEB_DOWNLOAD artifacts)
  15 pts  — Report files exist and were written during the task timeframe
  25 pts  — Searches report content matches ground-truth search terms correctly
  15 pts  — Downloads report content matches ground-truth downloaded filenames
  10 pts  — Summary file accurately calculates totals
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_web_browser_artifact_triage(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/web_browser_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/web_browser_gt.json")

    # ── Pull Result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
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

    # ── Pull Ground Truth JSON ────────────────────────────────────────────────
    gt = {"searches": [], "downloads": [], "total_searches": 0, "total_downloads": 0}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception as e:
        logger.warning(f"Could not load GT file, relying on fallback: {e}")

    # ── Anti-gaming / Timing check ────────────────────────────────────────────
    start_time = result.get("start_time", 0)

    # ── Criterion 1: Case & Data Source (15 pts) ──────────────────────────────
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Case DB and Logical Data Source found (+15)")
    else:
        feedback_parts.append("FAIL Case DB or Data Source not found")

    # ── Criterion 2: Recent Activity Artifacts (20 pts) ───────────────────────
    db_searches = result.get("db_search_count", 0)
    db_downloads = result.get("db_download_count", 0)
    if result.get("recent_activity_run"):
        score += 20
        feedback_parts.append(f"PASS Recent Activity run: {db_searches} searches, {db_downloads} downloads in DB (+20)")
    else:
        feedback_parts.append("FAIL No Web artifacts found in Autopsy DB (Recent Activity not run)")

    # ── Criterion 3: File Exists & Recency (15 pts) ───────────────────────────
    searches_exist = result.get("searches_file_exists", False)
    downloads_exist = result.get("downloads_file_exists", False)
    
    searches_recent = start_time == 0 or result.get("searches_mtime", 0) >= start_time
    downloads_recent = start_time == 0 or result.get("downloads_mtime", 0) >= start_time

    if searches_exist and downloads_exist and searches_recent and downloads_recent:
        score += 15
        feedback_parts.append("PASS Report files exist and were modified during task (+15)")
    elif searches_exist or downloads_exist:
        score += 7
        feedback_parts.append("PARTIAL Only some report files exist or files are stale (+7)")
    else:
        feedback_parts.append("FAIL Report files not found")

    # ── Criterion 4: Searches Content Accuracy (25 pts) ───────────────────────
    s_content = result.get("searches_content", "").lower()
    gt_searches = [s.lower() for s in gt.get("searches", [])]
    
    if searches_exist and gt_searches:
        found_searches = sum(1 for term in gt_searches if term in s_content)
        s_coverage = found_searches / len(gt_searches)
        
        # Verify header
        if "SEARCH_TERM|DATE_ACCESSED|DOMAIN".lower() in s_content:
            score += 5
            feedback_parts.append("PASS Searches report header correct (+5)")
        else:
            feedback_parts.append("FAIL Searches report missing correct header")

        if s_coverage >= 0.8:
            score += 20
            feedback_parts.append(f"PASS High search term coverage ({found_searches}/{len(gt_searches)}) (+20)")
        elif s_coverage >= 0.4:
            score += 10
            feedback_parts.append(f"PARTIAL Medium search term coverage ({found_searches}/{len(gt_searches)}) (+10)")
        else:
            feedback_parts.append(f"FAIL Low search term coverage ({found_searches}/{len(gt_searches)})")
    else:
        feedback_parts.append("FAIL Search content validation failed")

    # ── Criterion 5: Downloads Content Accuracy (15 pts) ──────────────────────
    d_content = result.get("downloads_content", "").lower()
    gt_downloads = [d.lower() for d in gt.get("downloads", [])]

    if downloads_exist and gt_downloads:
        found_downloads = sum(1 for fname in gt_downloads if fname in d_content)
        d_coverage = found_downloads / len(gt_downloads)

        # Verify header
        if "FILENAME|URL|DATE_DOWNLOADED".lower() in d_content:
            score += 5
            feedback_parts.append("PASS Downloads report header correct (+5)")
        else:
            feedback_parts.append("FAIL Downloads report missing correct header")

        if d_coverage >= 0.8:
            score += 10
            feedback_parts.append(f"PASS High downloads coverage ({found_downloads}/{len(gt_downloads)}) (+10)")
        elif d_coverage >= 0.4:
            score += 5
            feedback_parts.append(f"PARTIAL Medium downloads coverage ({found_downloads}/{len(gt_downloads)}) (+5)")
        else:
            feedback_parts.append(f"FAIL Low downloads coverage ({found_downloads}/{len(gt_downloads)})")
    else:
        feedback_parts.append("FAIL Downloads content validation failed")

    # ── Criterion 6: Summary File (10 pts) ────────────────────────────────────
    summary_content = result.get("summary_content", "")
    if result.get("summary_file_exists"):
        has_total_s = "TOTAL_SEARCHES" in summary_content.upper()
        has_total_d = "TOTAL_DOWNLOADS" in summary_content.upper()
        
        if has_total_s and has_total_d:
            score += 10
            feedback_parts.append("PASS Summary file contains correct sections (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Summary file exists but missing required fields (+5)")
    else:
        feedback_parts.append("FAIL Summary file not found")

    # ── Optional VLM Trajectory Verification ──────────────────────────────────
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots from a digital forensics agent using Autopsy. "
            "Did the agent successfully navigate to the 'Data Artifacts' view and interact with 'Web Searches' or 'Web Downloads'? "
            "Reply strictly with a JSON: {\"is_data_artifacts_viewed\": true/false}"
        )
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("is_data_artifacts_viewed"):
                feedback_parts.append("VLM confirms agent navigated to Data Artifacts view.")
            else:
                feedback_parts.append("VLM did not detect agent in Data Artifacts view.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Determine passing threshold
    key_criteria_met = result.get("recent_activity_run") and searches_exist and downloads_exist
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }