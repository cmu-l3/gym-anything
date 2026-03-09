#!/usr/bin/env python3
"""
Verifier for custom_search_content_audit task.

Verifies:
1. CSV export exists and was created during task.
2. CSV contains Custom Search data (headers/columns).
3. CSV contains data for books.toscrape.com.
4. Report exists and contains meaningful content (counts, recommendations).
"""

import json
import tempfile
import os
import csv
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_search_content_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- CSV Verification (60 points) ---
    csv_exists = result.get('csv_found', False)
    csv_fresh = result.get('csv_created_during_task', False)
    csv_rows = result.get('csv_rows', 0)
    
    if csv_exists and csv_fresh:
        score += 10
        feedback_parts.append("CSV exported (10/10)")
        
        # Analyze Content
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/verify_custom_search.csv", temp_csv.name)
            
            with open(temp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                
            # Check Headers for Rule Names
            # Rules: "Buy Button", "Availability", "Price Format"
            # SF exports usually name columns like "Contains 'Buy Button'" or similar
            headers_valid = False
            rule_matches = 0
            if re.search(r"Buy Button|Add to basket", content, re.IGNORECASE): rule_matches += 1
            if re.search(r"Availability|In stock", content, re.IGNORECASE): rule_matches += 1
            if re.search(r"Price Format", content, re.IGNORECASE): rule_matches += 1
            
            if rule_matches >= 2:
                score += 20
                feedback_parts.append(f"CSV contains custom search columns ({rule_matches}/3 rules found) (20/20)")
                headers_valid = True
            elif rule_matches == 1:
                score += 10
                feedback_parts.append("CSV contains partial search data (10/20)")
            else:
                feedback_parts.append("CSV headers do not match expected Custom Search rules (0/20)")

            # Check for Target Domain data
            if "books.toscrape.com" in content:
                score += 10
                feedback_parts.append("Domain verified (10/10)")
            else:
                feedback_parts.append("Wrong domain in export (0/10)")

            # Check Row Count and Data presence
            # We want to see actual matches (e.g. '1', 'True', 'Contains', depending on export format)
            # Just checking row count is decent proxy if domain is right
            if csv_rows >= 20:
                score += 10
                feedback_parts.append(f"Row count sufficient ({csv_rows}) (10/10)")
            elif csv_rows > 0:
                score += 5
                feedback_parts.append(f"Row count low ({csv_rows}) (5/10)")
                
            # Check if matching data exists (not just empty columns)
            # Custom search exports usually have counts (integers) or text
            # We look for non-header content that looks like search hits
            if headers_valid and len(content) > 500:
                score += 10
                feedback_parts.append("Data content looks valid (10/10)")
            
        except Exception as e:
            feedback_parts.append(f"Failed to analyze CSV content: {str(e)}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("CSV file not created/modified (0/60)")

    # --- Report Verification (30 points) ---
    rpt_exists = result.get('report_found', False)
    rpt_fresh = result.get('report_created_during_task', False)
    rpt_size = result.get('report_size', 0)

    if rpt_exists and rpt_fresh:
        score += 5
        feedback_parts.append("Report created (5/5)")
        
        if rpt_size >= 200:
            score += 5
            feedback_parts.append("Report length OK (5/5)")
            
            # Analyze Report Content
            temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            try:
                copy_from_env("/tmp/verify_report.txt", temp_rpt.name)
                with open(temp_rpt.name, 'r', encoding='utf-8', errors='ignore') as f:
                    rpt_content = f.read().lower()
                
                # Check for numbers (quantification)
                if re.search(r'[0-9]', rpt_content):
                    score += 10
                    feedback_parts.append("Report includes counts (10/10)")
                else:
                    feedback_parts.append("Report missing numeric counts (0/10)")

                # Check for recommendations keywords
                if any(w in rpt_content for w in ['recommend', 'fix', 'ensure', 'update', 'should', 'missing']):
                    score += 10
                    feedback_parts.append("Report includes recommendations (10/10)")
                else:
                    feedback_parts.append("Report missing actionable recommendations (0/10)")
                    
            except Exception:
                pass
            finally:
                if os.path.exists(temp_rpt.name):
                    os.unlink(temp_rpt.name)
        else:
            feedback_parts.append("Report too short (0/25)")
    else:
        feedback_parts.append("Report not found (0/30)")

    # --- App State (10 points) ---
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("App running (10/10)")
    elif csv_exists: 
        # Accepted if they closed it after export
        score += 10
        feedback_parts.append("App usage inferred (10/10)")

    # Final logic
    # Must have CSV with custom columns to pass
    passed = (score >= 60) and (csv_exists and csv_fresh)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }