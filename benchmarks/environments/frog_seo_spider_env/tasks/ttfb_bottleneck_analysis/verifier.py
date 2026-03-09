#!/usr/bin/env python3
"""
Verifier for TTFB Bottleneck Analysis task.

Scoring Criteria (100 points total):
1. CSV Export Verification (50 pts):
   - Valid CSV exists and modified after task start (15 pts)
   - CSV contains 'Response Time' column (20 pts)
   - CSV contains > 20 rows of data from books.toscrape.com (15 pts)

2. Report Verification (40 pts):
   - Report file exists and modified after task start (10 pts)
   - Report length >= 400 chars (10 pts)
   - Report content analysis (keywords, numbers) (20 pts)

3. VLM / Environment Verification (10 pts):
   - Screaming Frog was used/running (5 pts)
   - Trajectory confirms analysis workflow (5 pts)

Pass Threshold: 55 points
"""

import json
import tempfile
import os
import csv
import logging
import re

logger = logging.getLogger(__name__)

def verify_ttfb_bottleneck_analysis(traj, env_info, task_info):
    """Verify TTFB bottleneck analysis task."""
    
    # 1. SETUP & DATA RETRIEVAL
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Load result JSON
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env('/tmp/task_result.json', tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    # 2. CSV EXPORT VERIFICATION (50 PTS)
    csv_path = result.get('csv_path', '')
    csv_score = 0
    
    if csv_path and result.get('csv_created_after_start', False):
        csv_score += 15
        feedback_parts.append("CSV exported (15/15)")
        
        # We need to inspect the actual CSV content for robust verification
        try:
            tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            tmp_csv.close()
            copy_from_env(csv_path, tmp_csv.name)
            
            with open(tmp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
                f.seek(0)
                reader = csv.DictReader(f)
                rows = list(reader)
                headers = reader.fieldnames if reader.fieldnames else []
            
            os.unlink(tmp_csv.name)
            
            # Check for Response Time column
            # Valid headers usually: "Response Time", "Response Time (s)", "Response Time (ms)"
            has_response_time = any(re.search(r'response.*time', h, re.IGNORECASE) for h in headers)
            
            if has_response_time:
                csv_score += 20
                feedback_parts.append("CSV has Response Time data (20/20)")
                
                # Check for numeric data in that column
                # Find the actual header name
                rt_header = next(h for h in headers if re.search(r'response.*time', h, re.IGNORECASE))
                valid_values = 0
                for row in rows:
                    val = row.get(rt_header, '').strip()
                    try:
                        if float(val) > 0:
                            valid_values += 1
                    except ValueError:
                        pass
                
                if valid_values > 0:
                     feedback_parts.append(f"Found {valid_values} rows with timing data")
                else:
                     feedback_parts.append("WARNING: Response Time column empty or non-numeric")
            else:
                feedback_parts.append("CSV missing Response Time column (0/20)")

            # Check for domain and row count
            has_domain = 'books.toscrape.com' in content
            row_count = len(rows)
            
            if has_domain and row_count >= 20:
                csv_score += 15
                feedback_parts.append(f"CSV contains {row_count} rows from target domain (15/15)")
            elif has_domain:
                csv_score += 5
                feedback_parts.append(f"CSV has target domain but low row count ({row_count}) (5/15)")
            else:
                feedback_parts.append("CSV does not contain target domain data (0/15)")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing CSV content: {str(e)}")
            
    else:
        feedback_parts.append("No valid CSV export found (0/50)")
        
    score += csv_score

    # 3. REPORT VERIFICATION (40 PTS)
    report_path = result.get('report_path', '')
    report_score = 0
    
    if result.get('report_exists', False) and result.get('report_created_after_start', False):
        report_score += 10
        feedback_parts.append("Report file created (10/10)")
        
        try:
            tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            tmp_report.close()
            copy_from_env(report_path, tmp_report.name)
            
            with open(tmp_report.name, 'r', encoding='utf-8', errors='replace') as f:
                report_content = f.read()
            
            os.unlink(tmp_report.name)
            
            # Length check
            if len(report_content) >= 400:
                report_score += 10
                feedback_parts.append(f"Report length sufficient ({len(report_content)} chars) (10/10)")
            else:
                partial = int(10 * (len(report_content) / 400))
                report_score += partial
                feedback_parts.append(f"Report too short ({len(report_content)} chars) ({partial}/10)")
            
            # Content Analysis
            content_score = 0
            lower_content = report_content.lower()
            
            # Keywords
            keywords = ['slow', 'response', 'time', 'ttfb', 'recommend', 'optimize', 'cache', 'compression', 'image']
            found_keywords = sum(1 for k in keywords if k in lower_content)
            if found_keywords >= 3:
                content_score += 10
            
            # Numeric values (digits) - implies quantitative analysis
            if re.search(r'\d+\.?\d*', report_content):
                content_score += 5
                
            # URL patterns
            if 'toscrape' in lower_content or 'catalogue' in lower_content:
                content_score += 5
                
            report_score += content_score
            feedback_parts.append(f"Report content quality ({content_score}/20)")
            
        except Exception as e:
            feedback_parts.append(f"Error analyzing report: {str(e)}")
    else:
        feedback_parts.append("No report file found (0/40)")
        
    score += report_score

    # 4. APP USAGE (10 PTS)
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog was running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not detected running (0/10)")

    # 5. FINAL SCORE
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }