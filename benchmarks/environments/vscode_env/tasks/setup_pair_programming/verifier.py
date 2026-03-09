#!/usr/bin/env python3
"""
Verifier for setup_pair_programming@1 task
"""

import sys
import os
import json
import logging
import tempfile
import shutil
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    parse_vscode_settings,
    read_file_content,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_pair_programming_setup(traj, env_info, task_info):
    """
    Verify that VSCode was properly configured for pair programming.
    
    Checks:
    1. Font size is 18 or larger
    2. Whitespace rendering is enabled (not "none")
    3. Line numbers are visible (not "off")
    4. session_notes.txt exists
    5. Session notes contain required information (date, settings, readiness)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='pair_verify_')
    
    try:
        # Define container paths
        settings_container_path = "/tmp/vscode_settings.json"
        notes_container_path = "/tmp/session_notes.txt"
        
        # Define local temp paths
        settings_local = os.path.join(temp_dir, "settings.json")
        notes_local = os.path.join(temp_dir, "session_notes.txt")
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # ===== CRITERION 1-3: VSCode Settings =====
        try:
            copy_from_env(settings_container_path, settings_local)
            
            if not os.path.exists(settings_local) or os.path.getsize(settings_local) == 0:
                feedback_parts.append("❌ VSCode settings.json not found or empty")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
            
            settings = parse_vscode_settings(settings_local)
            
            if not settings:
                feedback_parts.append("❌ Could not parse VSCode settings")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
            
        except Exception as e:
            logger.error(f"Failed to read settings: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to read VSCode settings: {str(e)}"
            }
        
        # Check Criterion 1: Font size >= 18
        font_size = settings.get("editor.fontSize", 12)
        if font_size >= 18:
            criteria_passed += 1
            feedback_parts.append(f"✅ Font size is {font_size} (≥18)")
        else:
            feedback_parts.append(f"❌ Font size is {font_size}, must be 18 or larger for screen sharing")
        
        # Check Criterion 2: Whitespace rendering enabled
        whitespace = settings.get("editor.renderWhitespace", "none")
        # Accept: "all", "boundary", "selection", "trailing" - anything except "none"
        if whitespace and whitespace != "none":
            criteria_passed += 1
            feedback_parts.append(f"✅ Whitespace rendering enabled: '{whitespace}'")
        else:
            feedback_parts.append(f"❌ Whitespace rendering is '{whitespace}' - must enable (set to 'all', 'boundary', 'selection', or 'trailing')")
        
        # Check Criterion 3: Line numbers visible
        line_numbers = settings.get("editor.lineNumbers", "on")
        # Accept: "on", "relative", "interval" - anything except "off"
        if line_numbers and line_numbers != "off":
            criteria_passed += 1
            feedback_parts.append(f"✅ Line numbers visible: '{line_numbers}'")
        else:
            feedback_parts.append(f"❌ Line numbers are '{line_numbers}' - must be visible (set to 'on', 'relative', or 'interval')")
        
        # ===== CRITERION 4: Session notes file exists =====
        try:
            copy_from_env(notes_container_path, notes_local)
            
            if not os.path.exists(notes_local) or os.path.getsize(notes_local) == 0:
                feedback_parts.append("❌ session_notes.txt not found in workspace - create documentation file")
                
                score = int((criteria_passed / total_criteria) * 100)
                return {
                    "passed": False,
                    "score": score,
                    "feedback": " | ".join(feedback_parts)
                }
            
            criteria_passed += 1
            feedback_parts.append("✅ session_notes.txt found")
            
        except Exception as e:
            logger.warning(f"Could not read session notes: {e}")
            feedback_parts.append("❌ session_notes.txt not found in workspace")
            
            score = int((criteria_passed / total_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # ===== CRITERION 5: Session notes content quality =====
        notes_content = read_file_content(notes_local)
        notes_lower = notes_content.lower()
        
        # Sub-check: Date mentioned
        today = datetime.now()
        date_found = (
            str(today.year) in notes_content or
            today.strftime("%Y-%m-%d") in notes_content or
            today.strftime("%m/%d/%Y") in notes_content or
            today.strftime("%d/%m/%Y") in notes_content or
            today.strftime("%B %d") in notes_content or  # "January 15"
            today.strftime("%b %d") in notes_content or  # "Jan 15"
            today.strftime("%m-%d") in notes_content     # "01-15"
        )
        
        # Sub-check: Settings changes mentioned
        settings_mentioned = any(keyword in notes_lower for keyword in [
            "font", "whitespace", "setting", "configured", "changed", 
            "increased", "modified", "adjusted", "size", "18"
        ])
        
        # Sub-check: Session purpose/readiness mentioned
        purpose_mentioned = any(keyword in notes_lower for keyword in [
            "ready", "pair", "debug", "session", "collaborative", 
            "prepared", "setup", "collab", "programming"
        ])
        
        # Sub-check: Some form of name/lead identification
        name_mentioned = (
            len(notes_content.strip()) > 10 and  # Has some content
            not notes_content.strip().startswith("TODO")  # Not just a placeholder
        )
        
        # Calculate sub-score for content quality
        content_quality_score = sum([date_found, settings_mentioned, purpose_mentioned, name_mentioned])
        
        # Need at least 3 out of 4 sub-checks to pass this criterion
        if content_quality_score >= 3:
            criteria_passed += 1
            feedback_parts.append("✅ Session notes contain required information")
        else:
            missing = []
            if not date_found:
                missing.append("today's date")
            if not settings_mentioned:
                missing.append("settings changes")
            if not purpose_mentioned:
                missing.append("session readiness/purpose")
            if not name_mentioned:
                missing.append("meaningful content/name")
            
            feedback_parts.append(f"❌ Session notes incomplete - missing or unclear: {', '.join(missing)}")
        
        # ===== FINAL SCORE CALCULATION =====
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 85  # Need at least 85% (4-5 criteria)
        
        if passed:
            feedback_parts.insert(0, f"✅ Pair programming setup complete ({criteria_passed}/{total_criteria} criteria passed)")
        else:
            feedback_parts.insert(0, f"⚠️ Setup incomplete ({criteria_passed}/{total_criteria} criteria passed, need {total_criteria} for full success)")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp(temp_dir)
