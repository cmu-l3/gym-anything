#!/usr/bin/env python3
"""
Verifier for Code Coverage Visualization task

Checks:
1. Coverage extension is installed
2. Coverage report was generated and is valid
3. Extension is configured in settings
4. Coverage shows gaps (< 100%)
"""

import sys
import os
import logging
import tempfile
import shutil
import json
import re
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    parse_vscode_settings,
    check_extension_installed,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_coverage_xml(filepath):
    """
    Parse coverage.xml file to extract coverage percentage.
    
    Returns:
        float: Coverage percentage (0-100), or None if parsing fails
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Try to find line-rate attribute in coverage tag
        # Format: <coverage line-rate="0.6" ...>
        match = re.search(r'<coverage[^>]*line-rate="([0-9.]+)"', content)
        if match:
            line_rate = float(match.group(1))
            return line_rate * 100  # Convert to percentage
        
        # Alternative: look for lines-covered and lines-valid
        covered_match = re.search(r'lines-covered="(\d+)"', content)
        valid_match = re.search(r'lines-valid="(\d+)"', content)
        
        if covered_match and valid_match:
            covered = int(covered_match.group(1))
            valid = int(valid_match.group(1))
            if valid > 0:
                return (covered / valid) * 100
        
        return None
    except Exception as e:
        logger.error(f"Failed to parse coverage XML: {e}")
        return None


def verify_coverage_visualization(traj, env_info, task_info):
    """
    Verify that code coverage visualization was set up correctly.
    
    Scoring:
    - 25 points: Coverage extension installed
    - 35 points: Coverage report generated and valid
    - 30 points: Extension configured in settings
    - 10 points: Coverage report is recent and shows gaps
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='coverage_verify_')
    
    try:
        score = 0
        max_score = 100
        feedback_parts = []
        
        # ===== CRITERION 1: Extension Installation (25 points) =====
        extensions_file = os.path.join(temp_dir, "extensions.txt")
        extensions_dir_file = os.path.join(temp_dir, "extensions_dir.txt")
        
        try:
            copy_from_env("/tmp/coverage_extensions.txt", extensions_file)
            copy_from_env("/tmp/coverage_extensions_dir.txt", extensions_dir_file)
        except Exception as e:
            logger.warning(f"Failed to copy extensions data: {e}")
        
        extension_installed = False
        extension_name = None
        
        # Check code --list-extensions output (most reliable)
        if os.path.exists(extensions_file) and os.path.getsize(extensions_file) > 0:
            with open(extensions_file, 'r') as f:
                content = f.read()
                lines = content.strip().split('\n')
                
                coverage_extension_ids = [
                    'ryanluker.vscode-coverage-gutters',
                    'markis.code-coverage',
                    'coverageviz',
                    'coverage-gutters'
                ]
                
                for line in lines:
                    line_lower = line.strip().lower()
                    for ext_id in coverage_extension_ids:
                        if ext_id.lower() in line_lower or 'coverage' in line_lower:
                            extension_installed = True
                            extension_name = line.strip()
                            break
                    if extension_installed:
                        break
        
        # Backup: Check extensions directory
        if not extension_installed and os.path.exists(extensions_dir_file):
            with open(extensions_dir_file, 'r') as f:
                content = f.read().lower()
                if 'coverage' in content and ('gutters' in content or 'ryanluker' in content or 'markis' in content):
                    extension_installed = True
                    extension_name = "coverage extension (detected in directory)"
        
        if extension_installed:
            score += 25
            feedback_parts.append(f"✅ Coverage extension installed: {extension_name}")
        else:
            feedback_parts.append("❌ No coverage visualization extension found")
        
        # ===== CRITERION 2: Coverage Report Generated (35 points) =====
        coverage_file_found = False
        coverage_valid = False
        coverage_percentage = None
        
        # Try to find coverage.xml
        coverage_xml = os.path.join(temp_dir, "coverage.xml")
        try:
            copy_from_env("/tmp/coverage_result.xml", coverage_xml)
            if os.path.exists(coverage_xml) and os.path.getsize(coverage_xml) > 100:
                coverage_file_found = True
                score += 15  # File exists
                
                # Validate content
                coverage_percentage = parse_coverage_xml(coverage_xml)
                if coverage_percentage is not None:
                    coverage_valid = True
                    score += 20  # Valid coverage data
                    feedback_parts.append(f"✅ Coverage report generated: {coverage_percentage:.1f}% coverage")
                else:
                    score += 10  # File exists but couldn't parse
                    feedback_parts.append("⚠️ Coverage report exists but couldn't extract metrics")
        except Exception as e:
            logger.debug(f"coverage.xml not found: {e}")
        
        # Try lcov.info as alternative
        if not coverage_file_found:
            coverage_lcov = os.path.join(temp_dir, "coverage.lcov")
            try:
                copy_from_env("/tmp/coverage_result.lcov", coverage_lcov)
                if os.path.exists(coverage_lcov) and os.path.getsize(coverage_lcov) > 100:
                    coverage_file_found = True
                    score += 15  # File exists
                    
                    # Basic validation for LCOV format
                    with open(coverage_lcov, 'r') as f:
                        content = f.read()
                        if 'SF:' in content and 'LH:' in content and 'LF:' in content:
                            coverage_valid = True
                            score += 20  # Valid coverage data
                            feedback_parts.append("✅ Coverage report generated (lcov format)")
                        else:
                            score += 10
                            feedback_parts.append("⚠️ Coverage report exists but format unclear")
            except Exception as e:
                logger.debug(f"lcov.info not found: {e}")
        
        # Try .coverage as last alternative
        if not coverage_file_found:
            coverage_file = os.path.join(temp_dir, ".coverage")
            try:
                copy_from_env("/tmp/coverage_result.coverage", coverage_file)
                if os.path.exists(coverage_file) and os.path.getsize(coverage_file) > 100:
                    coverage_file_found = True
                    coverage_valid = True  # Assume valid if file exists
                    score += 25  # File exists and likely valid
                    feedback_parts.append("✅ Coverage report generated (.coverage format)")
            except Exception as e:
                logger.debug(f".coverage not found: {e}")
        
        if not coverage_file_found:
            feedback_parts.append("❌ No coverage report file found (coverage.xml, lcov.info, or .coverage)")
        
        # ===== CRITERION 3: Extension Configuration (30 points) =====
        workspace_settings_file = os.path.join(temp_dir, "workspace_settings.json")
        user_settings_file = os.path.join(temp_dir, "user_settings.json")
        
        try:
            copy_from_env("/tmp/coverage_workspace_settings.json", workspace_settings_file)
            copy_from_env("/tmp/coverage_user_settings.json", user_settings_file)
        except Exception as e:
            logger.warning(f"Failed to copy settings: {e}")
        
        config_found = False
        config_details = None
        
        # Check workspace settings first (preferred)
        if os.path.exists(workspace_settings_file):
            try:
                settings = parse_vscode_settings(workspace_settings_file)
                
                # Look for coverage-related settings
                coverage_keys = [
                    'coverage-gutters.coverageFileNames',
                    'coverage-gutters.xmlname',
                    'coverage-gutters.lcovname',
                    'coverage.coverageFilePath',
                    'coverageviewer.coverageFilePath'
                ]
                
                for key in coverage_keys:
                    if key in settings:
                        config_found = True
                        config_details = f"{key}: {settings[key]}"
                        score += 30
                        feedback_parts.append(f"✅ Extension configured in workspace settings: {key}")
                        break
                
                # Even if specific keys not found, check if any coverage-related config exists
                if not config_found:
                    for key in settings:
                        if 'coverage' in key.lower():
                            config_found = True
                            config_details = f"{key}: {settings[key]}"
                            score += 20  # Partial credit
                            feedback_parts.append(f"⚠️ Coverage-related setting found: {key}")
                            break
            except Exception as e:
                logger.warning(f"Failed to parse workspace settings: {e}")
        
        # Check user settings as fallback
        if not config_found and os.path.exists(user_settings_file):
            try:
                settings = parse_vscode_settings(user_settings_file)
                
                coverage_keys = [
                    'coverage-gutters.coverageFileNames',
                    'coverage-gutters.xmlname',
                    'coverage-gutters.lcovname',
                    'coverage.coverageFilePath'
                ]
                
                for key in coverage_keys:
                    if key in settings:
                        config_found = True
                        config_details = f"{key}: {settings[key]}"
                        score += 25  # Slightly less credit for user settings
                        feedback_parts.append(f"✅ Extension configured in user settings: {key}")
                        break
            except Exception as e:
                logger.warning(f"Failed to parse user settings: {e}")
        
        if not config_found:
            # Check if extension has default behavior (some extensions auto-detect coverage files)
            if extension_installed and coverage_file_found:
                score += 15  # Partial credit - extension may auto-detect
                feedback_parts.append("⚠️ No explicit configuration found, but extension may auto-detect coverage files")
            else:
                feedback_parts.append("❌ Extension not configured in settings.json")
        
        # ===== CRITERION 4: Coverage Shows Gaps (10 points) =====
        if coverage_percentage is not None:
            if coverage_percentage < 100:
                score += 10
                feedback_parts.append(f"✅ Coverage shows gaps: {coverage_percentage:.1f}% < 100%")
            else:
                feedback_parts.append(f"⚠️ Coverage is 100% (expected gaps)")
        elif coverage_valid and coverage_file_found:
            # If we have a valid file but couldn't parse percentage, give partial credit
            score += 5
            feedback_parts.append("⚠️ Coverage file exists but couldn't verify percentage")
        
        # Calculate final score
        percentage = (score / max_score) * 100
        passed = percentage >= 80
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": int(percentage),
            "feedback": feedback,
            "details": {
                "extension_installed": extension_installed,
                "coverage_file_found": coverage_file_found,
                "coverage_valid": coverage_valid,
                "coverage_percentage": coverage_percentage,
                "config_found": config_found
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
