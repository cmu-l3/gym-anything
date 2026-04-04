#!/usr/bin/env python3
"""
Verifier for Locate Safe Edit Zones task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_safe_edit_guide(traj, env_info, task_info):
    """
    Verify that the agent correctly identified safe edit zones.
    
    Checks:
    1. SAFE_EDIT_GUIDE.md exists
    2. Document identifies base.ts as DO NOT EDIT
    3. Document identifies api-client-wrapper.ts as SAFE TO EDIT
    4. Document references configuration (codegen.yml)
    5. Document includes evidence (quotes/line numbers)
    6. Document suggests correct fix location
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_safe_edit_')
    
    try:
        # Copy the guide file
        guide_container_path = "/home/ga/workspace/api-client-project/SAFE_EDIT_GUIDE.md"
        guide_temp_path = os.path.join(temp_dir, "SAFE_EDIT_GUIDE.md")
        
        # Also try /tmp location (from export script)
        guide_tmp_path = "/tmp/SAFE_EDIT_GUIDE.md"
        
        guide_found = False
        guide_content = ""
        
        # Try workspace location first
        try:
            copy_from_env(guide_container_path, guide_temp_path)
            if os.path.exists(guide_temp_path) and os.path.getsize(guide_temp_path) > 0:
                guide_content = read_file_content(guide_temp_path)
                guide_found = True
                logger.info("Found guide in workspace")
        except Exception as e:
            logger.warning(f"Could not copy from workspace: {e}")
        
        # Try /tmp location as fallback
        if not guide_found:
            try:
                guide_temp_path2 = os.path.join(temp_dir, "SAFE_EDIT_GUIDE_tmp.md")
                copy_from_env(guide_tmp_path, guide_temp_path2)
                if os.path.exists(guide_temp_path2) and os.path.getsize(guide_temp_path2) > 0:
                    guide_content = read_file_content(guide_temp_path2)
                    guide_found = True
                    logger.info("Found guide in /tmp")
            except Exception as e:
                logger.warning(f"Could not copy from /tmp: {e}")
        
        if not guide_found or not guide_content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ SAFE_EDIT_GUIDE.md not found or empty. Expected at: /home/ga/workspace/api-client-project/SAFE_EDIT_GUIDE.md"
            }
        
        # Convert to lowercase for case-insensitive matching
        content_lower = guide_content.lower()
        
        score = 0.0
        max_score = 5.0
        feedback_parts = []
        
        # Criterion 1: Identifies base.ts as generated/unsafe (1.0 point)
        mentions_base = 'base.ts' in content_lower
        mentions_unsafe = any(term in content_lower for term in [
            'do not edit', 'generated', 'auto-generated', 'unsafe', 
            'do not modify', 'will be overwritten', 'overwritten'
        ])
        
        if mentions_base and mentions_unsafe:
            score += 1.0
            feedback_parts.append("✅ Correctly identified base.ts as generated/unsafe to edit")
        elif mentions_base:
            score += 0.5
            feedback_parts.append("⚠️ Mentioned base.ts but didn't clearly mark as unsafe")
        else:
            feedback_parts.append("❌ Did not identify base.ts as unsafe to edit")
        
        # Criterion 2: Identifies wrapper as safe (1.0 point)
        mentions_wrapper = 'api-client-wrapper' in content_lower or 'wrapper' in content_lower
        mentions_safe = any(term in content_lower for term in [
            'safe to edit', 'safe', 'custom', 'extension point', 
            'can edit', 'should edit', 'add code here'
        ])
        
        if mentions_wrapper and mentions_safe:
            score += 1.0
            feedback_parts.append("✅ Correctly identified api-client-wrapper.ts as safe to edit")
        elif mentions_wrapper or mentions_safe:
            score += 0.5
            feedback_parts.append("⚠️ Partially identified safe edit zones")
        else:
            feedback_parts.append("❌ Did not identify wrapper as safe edit zone")
        
        # Criterion 3: References configuration (0.75 points)
        mentions_config = any(term in content_lower for term in [
            'codegen.yml', 'codegen', 'openapi-generator', 
            'generator', 'configuration', 'config'
        ])
        
        if mentions_config:
            score += 0.75
            feedback_parts.append("✅ Referenced code generation configuration")
        else:
            feedback_parts.append("❌ No mention of generation configuration")
        
        # Criterion 4: Includes evidence (1.0 point)
        # Look for quotes, line numbers, or copied text
        has_quotes = bool(re.search(r'(["\'].*?["\']|`.*?`)', guide_content))
        has_line_refs = bool(re.search(r'line\s+\d+', content_lower))
        has_evidence_keyword = bool(re.search(r'evidence:', content_lower))
        if has_quotes or has_line_refs or has_evidence_keyword:
            score += 1.0
            feedback_parts.append("✅ Guide includes concrete evidence")
        else:
            feedback_parts.append("❌ Guide lacks evidence such as quotes or line references")

        # Criterion 5: Suggests the correct fix location (0.75 points)
        mentions_fix_location = any(term in content_lower for term in [
            'api-client-wrapper.ts',
            'wrapper',
            'fix should go',
            'change here',
            'edit this file'
        ])
        if mentions_fix_location:
            score += 0.75
            feedback_parts.append("✅ Guide identifies the correct edit location")
        else:
            feedback_parts.append("❌ Guide does not clearly point to the correct edit location")

        # Criterion 6: Overall quality threshold (0.5 points)
        if len(guide_content.strip()) >= 250:
            score += 0.5
            feedback_parts.append("✅ Guide has sufficient detail")
        else:
            feedback_parts.append("❌ Guide is too short to be reliable")

        passed = score >= 3.5 and mentions_base and mentions_wrapper
        return {
            "passed": passed,
            "score": int((score / max_score) * 100),
            "feedback": " | ".join(feedback_parts),
        }
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
