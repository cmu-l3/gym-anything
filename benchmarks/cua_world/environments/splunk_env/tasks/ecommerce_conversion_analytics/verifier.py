#!/usr/bin/env python3
"""
Verifier for ecommerce_conversion_analytics task.

Scoring System (Total 100 points, Pass Threshold: 60):
1. Report Exists (20 pts) - Saved search exactly named 'Category_Conversion_Rate'
2. Correct Grouping (20 pts) - SPL queries index=tutorial and by categoryId
3. Metric Calculation (20 pts) - SPL isolates 'addtocart' and 'purchase' and calculates a ratio (/)
4. Dashboard Exists (20 pts) - Dashboard exactly named 'Business_KPI_Dashboard'
5. Dashboard Configured (20 pts) - Dashboard contains a panel that references the metric/report
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ecommerce_conversion_analytics(traj, env_info, task_info):
    """Verify that the business KPI report and dashboard were created correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ecommerce_conversion_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    report = analysis.get('report')
    dashboard = analysis.get('dashboard')

    score = 0
    feedback_parts = []
    subscores = {
        "report_exists": False,
        "correct_grouping": False,
        "metric_calculation": False,
        "dashboard_exists": False,
        "dashboard_configured": False
    }

    # Criterion 1: Report Exists (20 pts)
    if report:
        score += 20
        feedback_parts.append("Report 'Category_Conversion_Rate' exists")
        subscores["report_exists"] = True
        
        search_spl = report.get('search', '').lower()
        
        # Criterion 2: Correct Grouping (20 pts)
        has_index = 'tutorial' in search_spl
        has_category = 'categoryid' in search_spl
        
        if has_index and has_category:
            score += 20
            feedback_parts.append("Report queries tutorial index and groups by categoryId")
            subscores["correct_grouping"] = True
        else:
            feedback_parts.append("FAIL: Report SPL must include 'tutorial' and 'categoryId'")
            
        # Criterion 3: Metric Calculation (20 pts)
        has_actions = 'addtocart' in search_spl and 'purchase' in search_spl
        has_math = '/' in search_spl or 'eval' in search_spl
        
        if has_actions and has_math:
            score += 20
            feedback_parts.append("Report calculates a ratio using addtocart and purchase actions")
            subscores["metric_calculation"] = True
        else:
            feedback_parts.append("FAIL: Report SPL must compute conversion using 'addtocart', 'purchase', and math (eval or /)")
    else:
        feedback_parts.append("FAIL: Report 'Category_Conversion_Rate' not found")

    # Criterion 4: Dashboard Exists (20 pts)
    if dashboard:
        score += 20
        feedback_parts.append("Dashboard 'Business_KPI_Dashboard' exists")
        subscores["dashboard_exists"] = True
        
        # Criterion 5: Dashboard Configured (20 pts)
        panel_count = dashboard.get('panel_count', 0)
        xml = dashboard.get('xml', '').lower()
        
        # The dashboard should contain panels AND reference either the saved search or the underlying logic
        refs_report = 'category_conversion_rate' in xml
        refs_logic = 'categoryid' in xml and 'tutorial' in xml
        
        if panel_count > 0 and (refs_report or refs_logic):
            score += 20
            feedback_parts.append("Dashboard contains >= 1 panel displaying the conversion data")
            subscores["dashboard_configured"] = True
        else:
            feedback_parts.append("FAIL: Dashboard must have a panel referencing the report or equivalent SPL")
    else:
        feedback_parts.append("FAIL: Dashboard 'Business_KPI_Dashboard' not found")

    # Final Evaluation
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "report_spl": report.get('search', '') if report else None,
            "dashboard_xml": dashboard.get('xml', '') if dashboard else None,
            "panel_count": dashboard.get('panel_count', 0) if dashboard else 0
        }
    }