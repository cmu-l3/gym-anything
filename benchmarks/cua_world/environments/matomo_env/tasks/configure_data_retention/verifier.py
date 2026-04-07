#!/usr/bin/env python3
"""
Verifier for Configure Data Retention task in Matomo.

Verification Strategy:
1. PRIMARY: Database verification via exported JSON.
   Checks specific keys in `matomo_option` table (PrivacyManager.*).
2. ANTI-GAMING: Verifies that values actually changed from their initial state.
3. SCORING: 
   - 100 points total
   - Granular scoring for each setting (enable flags, duration values, checkboxes).
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_data_retention(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that data retention policies were configured correctly in Matomo.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_settings', {
        "delete_logs_enable": "1",
        "delete_logs_older_than": "180",
        "delete_reports_enable": "1",
        "delete_reports_older_than": "365",
        "delete_reports_keep_basic_metrics": "1",
        "delete_reports_keep_day_reports": "0",
        "delete_reports_keep_week_reports": "0",
        "delete_reports_keep_month_reports": "1",
        "delete_reports_keep_year_reports": "1",
        "delete_reports_keep_segment_reports": "1"
    })
    
    weights = metadata.get('scoring_weights', {
        "logs_enable": 12,
        "logs_days": 15,
        "reports_enable": 12,
        "reports_days": 15,
        "keep_basic": 8,
        "no_day": 8,
        "no_week": 8,
        "keep_month": 8,
        "keep_year": 8,
        "keep_segment": 6
    })

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        current_settings = result.get('settings', {})
        changed_keys = result.get('changed_keys', [])
        
        score = 0
        feedback_parts = []
        
        # --- Check 1: Anti-Gaming Gate ---
        # If no settings changed, the agent did nothing.
        if not changed_keys:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No settings were changed from defaults. Task incomplete."
            }

        # --- Check 2: Raw Logs Configuration ---
        # Enable logs deletion
        val = str(current_settings.get('delete_logs_enable', '0'))
        if val == expected['delete_logs_enable']:
            score += weights['logs_enable']
            feedback_parts.append("Logs deletion enabled (+12)")
        else:
            feedback_parts.append(f"Logs deletion NOT enabled (got {val})")

        # Logs retention days
        val = str(current_settings.get('delete_logs_older_than', '0'))
        if val == expected['delete_logs_older_than']:
            score += weights['logs_days']
            feedback_parts.append("Logs retention 180 days (+15)")
        else:
            feedback_parts.append(f"Logs retention incorrect (expected 180, got {val})")

        # --- Check 3: Reports Configuration ---
        # Enable reports deletion
        val = str(current_settings.get('delete_reports_enable', '0'))
        if val == expected['delete_reports_enable']:
            score += weights['reports_enable']
            feedback_parts.append("Reports deletion enabled (+12)")
        else:
            feedback_parts.append(f"Reports deletion NOT enabled (got {val})")

        # Reports retention days
        val = str(current_settings.get('delete_reports_older_than', '0'))
        if val == expected['delete_reports_older_than']:
            score += weights['reports_days']
            feedback_parts.append("Reports retention 365 days (+15)")
        else:
            feedback_parts.append(f"Reports retention incorrect (expected 365, got {val})")

        # --- Check 4: Report Granularity (Checkboxes) ---
        # Keep Basic Metrics (Yes)
        val = str(current_settings.get('delete_reports_keep_basic_metrics', '0'))
        if val == expected['delete_reports_keep_basic_metrics']:
            score += weights['keep_basic']
            feedback_parts.append("Basic metrics kept (+8)")
        else:
            feedback_parts.append("Basic metrics setting incorrect")

        # Keep Day Reports (No)
        val = str(current_settings.get('delete_reports_keep_day_reports', '1'))
        if val == expected['delete_reports_keep_day_reports']:
            score += weights['no_day']
            feedback_parts.append("Daily reports deleted (+8)")
        else:
            feedback_parts.append("Daily reports setting incorrect (should be unchecked)")

        # Keep Week Reports (No)
        val = str(current_settings.get('delete_reports_keep_week_reports', '1'))
        if val == expected['delete_reports_keep_week_reports']:
            score += weights['no_week']
            feedback_parts.append("Weekly reports deleted (+8)")
        else:
            feedback_parts.append("Weekly reports setting incorrect (should be unchecked)")

        # Keep Month Reports (Yes)
        val = str(current_settings.get('delete_reports_keep_month_reports', '0'))
        if val == expected['delete_reports_keep_month_reports']:
            score += weights['keep_month']
            feedback_parts.append("Monthly reports kept (+8)")
        else:
            feedback_parts.append("Monthly reports setting incorrect")

        # Keep Year Reports (Yes)
        val = str(current_settings.get('delete_reports_keep_year_reports', '0'))
        if val == expected['delete_reports_keep_year_reports']:
            score += weights['keep_year']
            feedback_parts.append("Yearly reports kept (+8)")
        else:
            feedback_parts.append("Yearly reports setting incorrect")
            
        # Keep Segment Reports (Yes)
        val = str(current_settings.get('delete_reports_keep_segment_reports', '0'))
        if val == expected['delete_reports_keep_segment_reports']:
            score += weights['keep_segment']
            feedback_parts.append("Segment reports kept (+6)")
        else:
            feedback_parts.append("Segment reports setting incorrect")

        # Final Evaluation
        # Threshold: 65 points (allows for minor errors but requires core tasks)
        passed = score >= 65
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed: {str(e)}"
        }