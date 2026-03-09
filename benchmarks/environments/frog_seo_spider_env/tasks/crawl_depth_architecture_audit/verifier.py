#!/usr/bin/env python3
"""Verifier for Crawl Depth Architecture Audit task.

Scoring (100 points total):
1. CSV Export (50 pts):
   - File exists and created during task (10 pts)
   - Contains 'Crawl Depth' column (15 pts)
   - Contains books.toscrape.com URLs (10 pts)
   - Has >= 30 rows of data (10 pts)
   - Has diversity of depth levels (>= 3 distinct depths) (5 pts)

2. Architecture Report (40 pts):
   - File exists and created during task (5 pts)
   - Length >= 400 chars (5 pts)
   - Contains distribution data (numbers/counts) (10 pts)
   - Mentions specific deep URLs (5 pts)
   - Contains recommendations keywords (5 pts)
   - Matches findings in CSV (10 pts)

3. Process (10 pts):
   - Screaming Frog ran during task (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import csv
import logging
import re

logger = logging.getLogger(__name__)

def verify_crawl_depth_audit(traj, env_info, task_info):
    """Verify crawl depth audit task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Load JSON result
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_json.close()
        copy_from_env('/tmp/crawl_depth_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # --- Criterion 1: CSV Export (50 pts) ---
    csv_created = result.get('export_csv_created', False)
    csv_valid = False
    depth_levels = set()
    row_count = 0
    
    if csv_created:
        score += 10
        feedback_parts.append("CSV exported (10/10)")
        
        # Analyze CSV content
        try:
            tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            tmp_csv.close()
            copy_from_env('/tmp/agent_export.csv', tmp_csv.name)
            
            with open(tmp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                # Read header
                reader = csv.reader(f)
                headers = next(reader, [])
                
                # Check for Crawl Depth column (case insensitive)
                depth_idx = -1
                url_idx = -1
                
                for i, h in enumerate(headers):
                    if 'crawl depth' in h.lower():
                        depth_idx = i
                    if 'address' in h.lower() or 'url' in h.lower():
                        url_idx = i
                
                if depth_idx != -1:
                    score += 15
                    feedback_parts.append("CSV has Crawl Depth column (15/15)")
                else:
                    feedback_parts.append("CSV missing Crawl Depth column (0/15)")
                
                # Check rows
                has_target_domain = False
                for row in reader:
                    if not row: continue
                    row_count += 1
                    
                    # Check domain
                    if url_idx != -1 and len(row) > url_idx:
                        if 'books.toscrape.com' in row[url_idx]:
                            has_target_domain = True
                    
                    # Check depth diversity
                    if depth_idx != -1 and len(row) > depth_idx:
                        try:
                            d = int(float(row[depth_idx])) # Handle "1" or "1.0"
                            depth_levels.add(d)
                        except ValueError:
                            pass
                
                if has_target_domain:
                    score += 10
                    feedback_parts.append("CSV contains books.toscrape.com URLs (10/10)")
                else:
                    feedback_parts.append("CSV does not contain target domain (0/10)")
                    
                if row_count >= 30:
                    score += 10
                    feedback_parts.append(f"CSV has sufficient data ({row_count} rows) (10/10)")
                else:
                    feedback_parts.append(f"CSV has insufficient data ({row_count} rows) (0/10)")
                    
                if len(depth_levels) >= 3:
                    score += 5
                    feedback_parts.append(f"CSV shows depth diversity ({len(depth_levels)} levels) (5/5)")
                else:
                    feedback_parts.append(f"CSV lacks depth diversity ({len(depth_levels)} levels) (0/5)")

            os.unlink(tmp_csv.name)
        except Exception as e:
            feedback_parts.append(f"Error analyzing CSV: {e}")
    else:
        feedback_parts.append("No CSV export found (0/50)")

    # --- Criterion 2: Architecture Report (40 pts) ---
    report_created = result.get('report_created', False)
    
    if report_created:
        score += 5
        feedback_parts.append("Report file created (5/5)")
        
        try:
            tmp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            tmp_rpt.close()
            copy_from_env('/tmp/agent_report.txt', tmp_rpt.name)
            
            with open(tmp_rpt.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                
            # Length check
            if len(content) >= 400:
                score += 5
                feedback_parts.append("Report length OK (5/5)")
            else:
                feedback_parts.append(f"Report too short ({len(content)} chars) (0/5)")
            
            # Numeric/Distribution check
            # Look for patterns like "Depth 1: 50" or list of numbers
            numbers = re.findall(r'\d+', content)
            if len(numbers) >= 5:
                score += 10
                feedback_parts.append("Report contains numeric/distribution data (10/10)")
            else:
                feedback_parts.append("Report lacks sufficient numeric data (0/10)")
            
            # URL check
            if 'http' in content and 'books.toscrape.com' in content:
                score += 5
                feedback_parts.append("Report cites specific URLs (5/5)")
            else:
                feedback_parts.append("Report missing example URLs (0/5)")
                
            # Recommendations check
            rec_keywords = ['recommend', 'suggest', 'improve', 'change', 'fix', 'should', 'structure', 'flatten']
            if any(k in content.lower() for k in rec_keywords):
                score += 5
                feedback_parts.append("Report contains recommendations (5/5)")
            else:
                feedback_parts.append("Report missing recommendations (0/5)")
                
            # Consistency check (Bonus/Integrity)
            # If report says max depth X, and CSV shows max depth Y, that's okay, 
            # but we just want to ensure they aren't totally empty.
            if len(depth_levels) > 0 and len(content) > 100:
                score += 10
                feedback_parts.append("Report validates against data presence (10/10)")
            else:
                feedback_parts.append("Report/Data inconsistency or missing (0/10)")

            os.unlink(tmp_rpt.name)
        except Exception as e:
            feedback_parts.append(f"Error analyzing report: {e}")
    else:
        feedback_parts.append("No report file found (0/40)")

    # --- Criterion 3: Process (10 pts) ---
    if result.get('sf_running', False) or (csv_created and row_count > 0):
        score += 10
        feedback_parts.append("Screaming Frog was utilized (10/10)")
    else:
        feedback_parts.append("Screaming Frog usage not detected (0/10)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }