#!/usr/bin/env python3
"""
Verifier for thin_content_word_count_audit task.

Verifies:
1. Valid CSV export with Word Count column and target domain URLs.
2. Text report analyzing the data (counts, specific URLs, remediation).
3. VLM trajectory check for UI interaction.
"""

import json
import tempfile
import os
import csv
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_thin_content_audit(traj, env_info, task_info):
    """
    Verify the thin content audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_domain = metadata.get('target_domain', 'books.toscrape.com')

    score = 0
    feedback_parts = []
    
    # Load JSON Result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- Criterion 1: CSV Export Verification (45 points) ---
    csv_valid = False
    if result.get('csv_found') and result.get('csv_created_during_task'):
        # Check logic from export script
        if result.get('csv_has_word_count'):
            score += 15
            feedback_parts.append("Export has Word Count column (15/15)")
            
            if result.get('csv_has_target_domain'):
                score += 10
                feedback_parts.append("Export contains target domain (10/10)")
                
                rows = result.get('csv_row_count', 0)
                if rows >= 20:
                    score += 10
                    feedback_parts.append(f"Export has sufficient data ({rows} rows) (10/10)")
                    csv_valid = True
                else:
                    feedback_parts.append(f"Export has too few rows ({rows}) (0/10)")
            else:
                feedback_parts.append("Export missing target domain URLs (0/10)")
        else:
            feedback_parts.append("Export missing 'Word Count' column - wrong tab exported? (0/45)")
            
        # Check for non-empty word count values
        # We need to inspect the file content itself to be sure
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/audit_export.csv", temp_csv.name)
            with open(temp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                reader = csv.DictReader(f)
                valid_wc_rows = 0
                for row in reader:
                    # Find the word count column (handle case sensitivity)
                    wc_key = next((k for k in row.keys() if k and 'word count' in k.lower()), None)
                    if wc_key and row[wc_key] and row[wc_key].strip().isdigit():
                        valid_wc_rows += 1
                        
                if valid_wc_rows >= 15:
                    score += 10
                    feedback_parts.append("Word Count data is populated (10/10)")
                else:
                    feedback_parts.append(f"Word Count data missing or sparse ({valid_wc_rows} valid rows) (0/10)")
        except Exception:
            feedback_parts.append("Failed to verify CSV content (0/10)")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("No valid CSV created during task (0/45)")

    # --- Criterion 2: Report Verification (50 points) ---
    if result.get('report_exists') and result.get('report_created_during_task'):
        report_size = result.get('report_size', 0)
        
        if report_size >= 400:
            score += 10
            feedback_parts.append("Report exists and is non-trivial (10/10)")
            
            # Analyze report content
            temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            try:
                copy_from_env("/tmp/audit_report.txt", temp_report.name)
                with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read().lower()
                    
                    # Check for numbers (counts)
                    numbers = re.findall(r'\d+', content)
                    if len(numbers) >= 3:
                        score += 10
                        feedback_parts.append("Report contains numeric counts (10/10)")
                    else:
                        feedback_parts.append("Report missing numeric data (0/10)")

                    # Check for URL references
                    if target_domain in content or 'http' in content:
                        score += 10
                        feedback_parts.append("Report references URLs (10/10)")
                    else:
                        feedback_parts.append("Report missing URL references (0/10)")

                    # Check for thresholds/brackets
                    if '100' in content or '300' in content:
                        score += 10
                        feedback_parts.append("Report references content brackets (10/10)")
                    else:
                        feedback_parts.append("Report missing bracket thresholds (0/10)")

                    # Check for remediation keywords
                    keywords = ['recommend', 'fix', 'improve', 'action', 'add content', 'rewrite', 'consolidate']
                    if any(k in content for k in keywords):
                        score += 10
                        feedback_parts.append("Report includes recommendations (10/10)")
                    else:
                        feedback_parts.append("Report missing recommendations (0/10)")
            except Exception:
                feedback_parts.append("Failed to verify report content")
            finally:
                if os.path.exists(temp_report.name):
                    os.unlink(temp_report.name)
        else:
            feedback_parts.append(f"Report exists but is too short ({report_size} bytes) (0/50)")
    else:
        feedback_parts.append("No report created during task (0/50)")

    # --- Criterion 3: Trajectory/VLM (5 points) ---
    # Minimal check: Screaming Frog running
    if result.get('sf_running'):
        score += 5
        feedback_parts.append("App verified running (5/5)")
    else:
        feedback_parts.append("App not running at end (0/5)")

    # VLM Trajectory Check (Bonus/Verification)
    # Using the framework's VLM utility if available
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    if csv_valid and query_vlm and get_final_screenshot:
        # Only run VLM if we have a valid CSV, to confirm UI interaction matches
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            prompt = """
            Analyze this screenshot of Screaming Frog SEO Spider.
            1. Is the 'Internal' tab visible or selected?
            2. Is there a table with data visible?
            3. Is the domain books.toscrape.com visible in the URL bar or data?
            Reply YES if this looks like a valid SEO crawl session, else NO.
            """
            try:
                vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
                if vlm_res.get('success') and 'YES' in str(vlm_res.get('response', '')).upper():
                    feedback_parts.append("[VLM confirmed UI state]")
            except Exception:
                pass

    passed = score >= 60 and csv_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }