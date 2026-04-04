#!/usr/bin/env python3
"""
Verifier for wayback_web_history_research task.

Verifies:
1. Browser History: Evidence of using Wayback Machine.
2. Bookmarks: "Web Archive Research" folder with bookmarks.
3. Report: JSON file validity, content, and accuracy of dates.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_date(date_str):
    """Attempt to parse date string in YYYY-MM-DD format."""
    try:
        return datetime.strptime(date_str.strip(), "%Y-%m-%d")
    except (ValueError, AttributeError):
        return None

def verify_wayback_web_history_research(traj, env_info, task_info):
    """
    Verification entry point.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env unavailable"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    target_sites = metadata.get('target_sites', [])
    date_ranges = metadata.get('date_ranges', {})

    # Retrieve Exported Task Result
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task_result.json: {e}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # Retrieve User Report
    user_report = {}
    report_content_valid = False
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        try:
            # We know the path from metadata or task_result
            report_path = task_result.get("report_file_path", "/home/ga/Documents/web_history_report.json")
            if task_result.get("report_file_exists"):
                copy_from_env(report_path, tmp.name)
                with open(tmp.name, 'r') as f:
                    user_report = json.load(f)
                    report_content_valid = True
        except json.JSONDecodeError:
            logger.error("User report is not valid JSON")
        except Exception as e:
            logger.error(f"Failed to load user report: {e}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # --- Criterion 1: History Evidence (20 pts) ---
    visits = task_result.get("wayback_history_visits", 0)
    if visits >= 5:
        score += 20
        feedback.append(f"History Check: Excellent usage of Wayback Machine ({visits} pages visited). (+20)")
    elif visits >= 1:
        score += 10
        feedback.append(f"History Check: Some usage of Wayback Machine detected ({visits} pages), but low. (+10)")
    else:
        feedback.append("History Check: No evidence of visiting web.archive.org/web/. (+0)")

    # --- Criterion 2: Bookmarks (15 pts) ---
    folder_exists = task_result.get("bookmark_folder_exists", False)
    bm_count = task_result.get("wayback_bookmarks_count", 0)
    
    if folder_exists:
        if bm_count >= 5:
            score += 15
            feedback.append(f"Bookmark Check: Folder exists with {bm_count} Wayback bookmarks. (+15)")
        elif bm_count >= 1:
            score += 8
            feedback.append(f"Bookmark Check: Folder exists but only contains {bm_count} Wayback bookmarks (expected 5). (+8)")
        else:
            score += 5
            feedback.append("Bookmark Check: Folder exists but contains no Wayback bookmarks. (+5)")
    else:
        feedback.append("Bookmark Check: 'Web Archive Research' folder not found. (+0)")

    # --- Criterion 3: Report Structure & Freshness (25 pts) ---
    if task_result.get("report_file_exists"):
        if task_result.get("report_file_fresh"):
            score += 10
            feedback.append("Report Check: File exists and is new. (+10)")
        else:
            feedback.append("Report Check: File exists but is old (pre-task). (+0)")
            
        if report_content_valid:
            score += 5
            feedback.append("Report Check: Valid JSON format. (+5)")
            
            # Check for all keys
            sites_found = [site for site in target_sites if site in user_report]
            if len(sites_found) == len(target_sites):
                score += 10
                feedback.append("Report Check: All target websites present. (+10)")
            else:
                score += (2 * len(sites_found))
                feedback.append(f"Report Check: Found {len(sites_found)}/{len(target_sites)} websites. (+{2 * len(sites_found)})")
        else:
            feedback.append("Report Check: File is not valid JSON. (+0)")
    else:
        feedback.append("Report Check: Report file not found. (+0)")

    # --- Criterion 4: Data Accuracy (40 pts) ---
    # Only evaluate if report is valid
    if report_content_valid:
        data_score = 0
        max_data_score = 40
        per_site_score = max_data_score / len(target_sites) # 8 pts per site
        
        for site in target_sites:
            site_data = user_report.get(site)
            site_feedback = []
            
            if not site_data or not isinstance(site_data, dict):
                continue
                
            # Check 1: URL (2 pts)
            url = site_data.get("wayback_url", "")
            if "web.archive.org/web/" in url:
                data_score += 2
            else:
                site_feedback.append("Invalid URL")

            # Check 2: Description (2 pts)
            desc = site_data.get("description", "")
            if desc and len(str(desc)) > 10:
                data_score += 2
            else:
                site_feedback.append("Poor/missing description")

            # Check 3: Date (4 pts)
            date_str = site_data.get("earliest_capture_date", "")
            date_obj = parse_date(date_str)
            
            expected_range = date_ranges.get(site)
            if date_obj and expected_range:
                start_dt = parse_date(expected_range["start"])
                end_dt = parse_date(expected_range["end"])
                
                if start_dt <= date_obj <= end_dt:
                    data_score += 4
                else:
                    site_feedback.append(f"Date {date_str} out of range ({expected_range['start']} to {expected_range['end']})")
            else:
                site_feedback.append("Invalid date format")

            if site_feedback:
                feedback.append(f"  - {site}: {', '.join(site_feedback)}")

        score += data_score
        feedback.append(f"Data Accuracy: {data_score}/{max_data_score} points based on URL, description, and date checks.")

    # Final Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }