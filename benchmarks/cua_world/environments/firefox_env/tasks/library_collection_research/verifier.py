#!/usr/bin/env python3
"""
Verifier for library_collection_research task.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_library_collection_research(traj, env_info, task_info):
    """
    Verifies the library research task:
    1. Firefox history contains visits to all 3 required platforms.
    2. 'Collection Development' bookmark folder exists with specific criteria.
    3. JSON report file exists, is fresh, and contains correct bibliographic data.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable."}
    
    # Load system metrics (history/bookmarks)
    metrics_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", metrics_file.name)
        with open(metrics_file.name, 'r') as f:
            metrics = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load metrics: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task metrics."}
    finally:
        if os.path.exists(metrics_file.name):
            os.unlink(metrics_file.name)

    # Load user's report file
    report_content = None
    if metrics.get("file_exists") and metrics.get("file_fresh"):
        report_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env("/tmp/bibliographic_report_export.json", report_file.name)
            with open(report_file.name, 'r') as f:
                report_content = json.load(f)
        except json.JSONDecodeError:
            report_content = "INVALID_JSON"
        except Exception as e:
            logger.warning(f"Failed to load report content: {e}")
        finally:
            if os.path.exists(report_file.name):
                os.unlink(report_file.name)

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # -- A. History Verification (25 points) --
    # Need visits to all 3 domains
    h_loc = metrics.get("history_loc_count", 0)
    h_gut = metrics.get("history_gutenberg_count", 0)
    h_open = metrics.get("history_openlib_count", 0)
    
    hist_score = 0
    if h_loc >= 2: hist_score += 10
    elif h_loc == 1: hist_score += 5
    
    if h_gut >= 2: hist_score += 8
    elif h_gut == 1: hist_score += 4
    
    if h_open >= 2: hist_score += 7
    elif h_open == 1: hist_score += 3
    
    score += hist_score
    feedback.append(f"History Check: {hist_score}/25 pts (LOC:{h_loc}, Gut:{h_gut}, OpenLib:{h_open})")

    # -- B. Bookmark Verification (20 points) --
    bm_score = 0
    if metrics.get("bookmark_folder_exists"):
        bm_score += 8
        cnt = metrics.get("bookmark_count", 0)
        spread = metrics.get("bookmark_domain_spread", 0)
        
        if cnt >= 8: bm_score += 6
        elif cnt >= 4: bm_score += 3
        
        if spread >= 2: bm_score += 6 # Need at least 2 of the 3 domains represented
        elif spread == 1: bm_score += 3
        
        feedback.append(f"Bookmarks: {bm_score}/20 pts (Folder found, {cnt} items, {spread} source domains)")
    else:
        feedback.append("Bookmarks: 0/20 pts (Folder 'Collection Development' not found)")
    score += bm_score

    # -- C. File Existence & Structure (15 points) --
    file_score = 0
    if metrics.get("file_exists") and metrics.get("file_fresh"):
        file_score += 5
        if report_content == "INVALID_JSON":
            feedback.append("File: 5/15 pts (File exists but is invalid JSON)")
        elif isinstance(report_content, dict):
            file_score += 5 # Valid JSON
            
            # Check for required keys (fuzzy match)
            required_books = ["moby", "huck", "scarlet", "walden"]
            keys_found = 0
            keys_lower = [k.lower() for k in report_content.keys()]
            for req in required_books:
                if any(req in k for k in keys_lower):
                    keys_found += 1
            
            if keys_found == 4: file_score += 5
            elif keys_found >= 2: file_score += 3
            
            feedback.append(f"File Structure: {file_score}/15 pts (Valid JSON, {keys_found}/4 works found)")
    else:
        feedback.append("File: 0/15 pts (Report file not found or not created during task)")
    score += file_score

    # -- D. Content Accuracy (40 points) --
    content_score = 0
    if isinstance(report_content, dict) and report_content != "INVALID_JSON":
        
        # Helper to find entry by fuzzy name
        def find_entry(fragment):
            for k, v in report_content.items():
                if fragment in k.lower():
                    return v
            return {}

        # 1. Moby Dick (Target: 1851, Gut: 2701)
        md = find_entry("moby")
        if md:
            # Year (allow string or int, +/- 1 year)
            y = str(md.get("year", md.get("first_published", "0")))
            if "1851" in y: content_score += 2.5
            # Gutenberg ID
            gid = str(md.get("gutenberg_id", md.get("gutenberg_ebook_id", "")))
            if "2701" in gid: content_score += 2.5
            # URL presence
            if "gutenberg.org" in md.get("gutenberg_url", ""): content_score += 2.5
            if "loc.gov" in md.get("loc_url", ""): content_score += 2.5
        
        # 2. Huck Finn (Target: 1884/1885, Gut: 76)
        hf = find_entry("huck")
        if hf:
            y = str(hf.get("year", hf.get("first_published", "0")))
            if "1884" in y or "1885" in y: content_score += 2.5
            gid = str(hf.get("gutenberg_id", hf.get("gutenberg_ebook_id", "")))
            if "76" in gid: content_score += 2.5
            if "gutenberg.org" in hf.get("gutenberg_url", ""): content_score += 2.5
            if "loc.gov" in hf.get("loc_url", ""): content_score += 2.5

        # 3. Scarlet Letter (Target: 1850, Gut: 25344 or 33)
        sl = find_entry("scarlet")
        if sl:
            y = str(sl.get("year", sl.get("first_published", "0")))
            if "1850" in y: content_score += 2.5
            gid = str(sl.get("gutenberg_id", sl.get("gutenberg_ebook_id", "")))
            if "33" in gid or "25344" in gid: content_score += 2.5
            if "gutenberg.org" in sl.get("gutenberg_url", ""): content_score += 2.5
            if "loc.gov" in sl.get("loc_url", ""): content_score += 2.5

        # 4. Walden (Target: 1854, Gut: 205)
        wd = find_entry("walden")
        if wd:
            y = str(wd.get("year", wd.get("first_published", "0")))
            if "1854" in y: content_score += 2.5
            gid = str(wd.get("gutenberg_id", wd.get("gutenberg_ebook_id", "")))
            if "205" in gid: content_score += 2.5
            if "gutenberg.org" in wd.get("gutenberg_url", ""): content_score += 2.5
            if "loc.gov" in wd.get("loc_url", ""): content_score += 2.5

        feedback.append(f"Content Accuracy: {content_score}/40 pts")
    
    score += content_score

    # Final Pass/Fail
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }