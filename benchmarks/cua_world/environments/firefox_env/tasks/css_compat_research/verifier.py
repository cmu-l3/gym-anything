#!/usr/bin/env python3
"""
Verifier for css_compat_research task.
"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_css_compat_research(traj, env_info, task_info):
    """
    Verifies the CSS compatibility research task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata (DB analysis)
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
        finally:
            os.unlink(tmp.name)

    # Load agent's generated report
    agent_report = {}
    report_path = task_result.get("report", {}).get("path", "")
    report_available = False
    
    if task_result.get("report", {}).get("exists") and task_result.get("report", {}).get("fresh"):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            try:
                copy_from_env(report_path, tmp.name)
                with open(tmp.name, 'r') as f:
                    agent_report = json.load(f)
                report_available = True
            except Exception as e:
                logger.error(f"Failed to load agent report: {e}")
            finally:
                os.unlink(tmp.name)

    # --- Scoring ---
    score = 0
    feedback = []
    
    # 1. History Checks (25 pts)
    hist = task_result.get("history", {})
    if hist.get("mdn_visits", 0) >= 2:
        score += 10
        feedback.append("MDN visited (10/10)")
    elif hist.get("mdn_visits", 0) > 0:
        score += 5
        feedback.append("MDN visited once (5/10)")
        
    if hist.get("caniuse_visits", 0) >= 2:
        score += 10
        feedback.append("Can I Use visited (10/10)")
    elif hist.get("caniuse_visits", 0) > 0:
        score += 5
        feedback.append("Can I Use visited once (5/10)")

    if hist.get("w3c_visits", 0) > 0:
        score += 5
        feedback.append("W3C/Spec site visited (5/5)")

    # 2. Bookmarks (10 pts)
    bkm = task_result.get("bookmarks", {})
    if bkm.get("folder_exists"):
        score += 5
        feedback.append("Bookmark folder created (5/5)")
        if bkm.get("count", 0) >= 5:
            score += 5
            feedback.append(f"Found {bkm.get('count')} bookmarks (5/5)")
        else:
            feedback.append(f"Only found {bkm.get('count')} bookmarks, expected 5 (0/5)")
    else:
        feedback.append("Bookmark folder not found (0/10)")

    # 3. Report Structure & Content (65 pts)
    if not report_available:
        feedback.append("Report file missing, stale, or invalid JSON (0/65)")
    else:
        score += 10
        feedback.append("Report file exists and is valid JSON (10/10)")
        
        required_keys = ["container_queries", "has_selector", "subgrid", "color_mix", "css_nesting"]
        keys_present = sum(1 for k in required_keys if k in agent_report)
        
        if keys_present == 5:
            score += 15
            feedback.append("All 5 feature keys present (15/15)")
        else:
            partial = keys_present * 3
            score += partial
            feedback.append(f"{keys_present}/5 feature keys present ({partial}/15)")

        # Validate versions
        ground_truth = task_info.get("metadata", {}).get("ground_truth", {})
        tolerance = task_info.get("metadata", {}).get("version_tolerance", 10)
        
        valid_entries = 0
        total_checks = 0
        
        for feature in required_keys:
            if feature not in agent_report:
                continue
            
            entry = agent_report[feature]
            gt = ground_truth.get(feature, {})
            
            # Check fields exist
            if all(k in entry for k in ["chrome_version", "firefox_version", "safari_version", "spec_status", "recommendation"]):
                score += 2 # 2 pts per complete entry (10 max)
            
            # Check values
            for browser in ["chrome", "firefox", "safari"]:
                total_checks += 1
                key = f"{browser}_version"
                val = entry.get(key)
                expected = gt.get(browser)
                
                # Extract number from string (e.g. "105" from "Version 105")
                try:
                    # Find first float/int in string
                    match = re.search(r"(\d+(\.\d+)?)", str(val))
                    if match:
                        num_val = float(match.group(1))
                        if abs(num_val - expected) <= tolerance:
                            valid_entries += 1
                except:
                    pass

        # Score version accuracy (Max 20)
        # 15 versions total. 1 point per correct version, bonus for high accuracy
        version_score = min(20, valid_entries * 1.5) # Scale up slightly
        score += int(version_score)
        feedback.append(f"Browser version accuracy: {valid_entries}/{total_checks} values within tolerance ({int(version_score)}/20)")

        # Check qualitative fields (Max 10)
        qual_checks = 0
        for feature in required_keys:
            if feature in agent_report:
                if agent_report[feature].get("spec_status") and agent_report[feature].get("recommendation"):
                    qual_checks += 1
        
        if qual_checks == 5:
            score += 10
            feedback.append("Qualitative fields complete (10/10)")
        else:
            score += qual_checks * 2
            feedback.append(f"Qualitative fields incomplete ({qual_checks*2}/10)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback)
    }