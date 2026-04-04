#!/usr/bin/env python3
"""
Verifier for event_line_listing_report task.

Scoring (100 points):
1. Report saved (Mandatory) [30 pts]
   - Checks both eventReports and eventVisualizations for items created after start.
2. Report name keywords [10 pts]
   - Contains 'Bombali', 'Child', 'Line', or 'List'.
3. Report type is LINE_LIST [15 pts]
4. Report references a programme [15 pts]
5. Export file exists in Downloads [20 pts]
6. Export file has content (>500 bytes) [10 pts]

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_event_line_listing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/event_line_listing_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # Combine reports and visualizations
        new_reports = result.get('new_event_reports', [])
        new_viz = result.get('new_event_visualizations', [])
        all_items = new_reports + new_viz

        # Criterion 1: Report Saved (Mandatory)
        if not all_items:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new Event Reports or Line Lists found in DHIS2. You must save the report as a favorite.",
                "subscores": {"report_saved": False}
            }
        
        score += 30
        subscores["report_saved"] = True
        feedback_parts.append(f"Report saved ({len(all_items)} found) (+30)")

        # Evaluate the best item found (to maximize score)
        best_item_score = 0
        best_item_feedback = []
        
        # Keywords from metadata
        metadata = task_info.get('metadata', {})
        name_keywords = metadata.get('target_name_keywords', ['Bombali', 'Child', 'Line', 'List'])
        prog_keywords = metadata.get('target_programme_keywords', ['Child'])

        for item in all_items:
            item_score = 0
            item_fb = []
            
            # Name Check
            name = item.get('displayName', '')
            name_hits = sum(1 for k in name_keywords if k.lower() in name.lower())
            if name_hits >= 2: # Require at least 2 keywords match
                item_score += 10
                item_fb.append("Name correct")
            elif name_hits == 1:
                item_score += 5
                item_fb.append("Name partial")
            
            # Type Check
            typ = item.get('type', '')
            if typ == 'LINE_LIST' or typ == 'EVENT_REPORT': # API might vary
                item_score += 15
                item_fb.append("Type LINE_LIST")
            
            # Programme Check
            prog = item.get('program', {}).get('displayName', '')
            if any(k.lower() in prog.lower() for k in prog_keywords):
                item_score += 15
                item_fb.append("Programme correct")
            
            if item_score > best_item_score:
                best_item_score = item_score
                best_item_feedback = item_fb

        score += best_item_score
        feedback_parts.extend(best_item_feedback)
        
        # Criterion 5 & 6: Export
        downloads = result.get('downloads', {})
        valid_exports = downloads.get('files', [])
        
        if valid_exports:
            score += 20
            subscores["export_exists"] = True
            feedback_parts.append("Export file found (+20)")
            
            # Check content size
            if any(f.get('size', 0) > 500 for f in valid_exports):
                score += 10
                subscores["export_content"] = True
                feedback_parts.append("Export has content (+10)")
            else:
                feedback_parts.append("Export file is empty/too small")
        else:
            subscores["export_exists"] = False
            feedback_parts.append("No export file found in Downloads")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.exception("Verifier error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}