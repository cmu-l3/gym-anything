#!/usr/bin/env python3
"""
Verifier for Prepare Release Notes task
"""

import sys
import os
import re
import logging
import tempfile
import shutil
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_release_notes(traj, env_info, task_info):
    """
    Verify that CHANGELOG.md was created with appropriate release notes.
    
    Checks:
    1. File exists at correct path
    2. Contains version 2.0.0 header
    3. Features section with at least 3 items
    4. Bug Fixes section with at least 2 items
    5. Breaking Changes section with API change mention
    6. Does NOT contain internal changes (refactors, tests, chores)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_changelog_')
    
    try:
        # Copy CHANGELOG.md exported by export_result.sh
        changelog_container_path = "/tmp/CHANGELOG.md"
        changelog_local = os.path.join(temp_dir, "CHANGELOG.md")
        
        try:
            copy_from_env(changelog_container_path, changelog_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy CHANGELOG.md: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(changelog_local) or os.path.getsize(changelog_local) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ CHANGELOG.md file not found or is empty"
            }
        
        # Read content
        content = read_file_content(changelog_local)
        
        if not content or len(content.strip()) < 50:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ CHANGELOG.md exists but has insufficient content"
            }
        
        feedback_parts = []
        metadata = {}
        reward = 0.0
        
        # Check 1: File exists (already confirmed)
        feedback_parts.append("✅ CHANGELOG.md file exists")
        reward += 0.15
        
        metadata["changelog_length"] = len(content)
        
        # Check 2: Has version header (2.0.0)
        version_pattern = r'##?\s*\[?2\.0\.0\]?'
        if re.search(version_pattern, content, re.IGNORECASE):
            feedback_parts.append("✅ Version 2.0.0 header present")
            reward += 0.10
        else:
            feedback_parts.append("⚠️ Missing version 2.0.0 header")
        
        # Check 3: Has Features section with content
        features_section = re.search(
            r'###?\s*Features?(.*?)(?=###?|\Z)',
            content,
            re.DOTALL | re.IGNORECASE
        )
        
        if not features_section:
            feedback_parts.append("❌ Missing 'Features' section")
        else:
            features_content = features_section.group(1)
            # Count bullet points
            feature_items = re.findall(r'[-*]\s+(.+)', features_content)
            metadata["features_count"] = len(feature_items)
            
            if len(feature_items) < 3:
                feedback_parts.append(
                    f"⚠️ Only {len(feature_items)} features listed (expected at least 3)"
                )
                reward += 0.05
            else:
                feedback_parts.append(
                    f"✅ Features section with {len(feature_items)} items"
                )
                reward += 0.20
                
                # Check for expected features
                expected_keywords = ["dark mode", "export", "csv", "batch", "keyboard", "shortcut"]
                found_features = []
                features_lower = features_content.lower()
                
                for keyword in expected_keywords:
                    if keyword in features_lower:
                        found_features.append(keyword)
                
                if len(found_features) >= 3:
                    feedback_parts.append(
                        f"✅ Found expected feature keywords: {', '.join(found_features[:4])}"
                    )
                    reward += 0.10
        
        # Check 4: Has Bug Fixes section with content
        bugfix_section = re.search(
            r'###?\s*Bug\s*Fixes?(.*?)(?=###?|\Z)',
            content,
            re.DOTALL | re.IGNORECASE
        )
        
        if not bugfix_section:
            feedback_parts.append("❌ Missing 'Bug Fixes' section")
        else:
            bugfix_content = bugfix_section.group(1)
            bugfix_items = re.findall(r'[-*]\s+(.+)', bugfix_content)
            metadata["bugfix_count"] = len(bugfix_items)
            
            if len(bugfix_items) < 2:
                feedback_parts.append(
                    f"⚠️ Only {len(bugfix_items)} bug fixes listed (expected at least 2)"
                )
                reward += 0.05
            else:
                feedback_parts.append(
                    f"✅ Bug Fixes section with {len(bugfix_items)} items"
                )
                reward += 0.15
                
                # Check for expected fixes
                expected_keywords = ["username", "null", "crash", "empty", "csv", "memory", "leak", "cache"]
                found_fixes = []
                bugfix_lower = bugfix_content.lower()
                
                for keyword in expected_keywords:
                    if keyword in bugfix_lower:
                        found_fixes.append(keyword)
                
                if len(found_fixes) >= 2:
                    feedback_parts.append(
                        f"✅ Found expected bug fix keywords: {', '.join(found_fixes[:3])}"
                    )
                    reward += 0.05
        
        # Check 5: Has Breaking Changes section
        breaking_section = re.search(
            r'###?\s*Breaking\s*Changes?(.*?)(?=###?|\Z)',
            content,
            re.DOTALL | re.IGNORECASE
        )
        
        if not breaking_section:
            feedback_parts.append("⚠️ Missing 'Breaking Changes' section")
        else:
            breaking_content = breaking_section.group(1)
            breaking_items = re.findall(r'[-*]\s+(.+)', breaking_content)
            metadata["breaking_count"] = len(breaking_items)
            
            # Check for API change mention
            api_keywords = ["api", "fetchdata", "options", "parameter", "signature"]
            has_api_mention = any(kw in breaking_content.lower() for kw in api_keywords)
            
            if has_api_mention:
                feedback_parts.append("✅ Breaking Changes section mentions API change")
                reward += 0.15
            else:
                feedback_parts.append("⚠️ Breaking Changes section exists but missing API details")
                reward += 0.05
        
        # Check 6: Should NOT mention internal items (negative check)
        noise_keywords = ["refactor", "test:", "chore:", "bump version", "dependency", "internal"]
        found_noise = []
        content_lower = content.lower()
        
        for keyword in noise_keywords:
            if keyword in content_lower:
                found_noise.append(keyword)
        
        if found_noise:
            feedback_parts.append(
                f"⚠️ Contains internal changes that should be filtered: {', '.join(found_noise)}"
            )
            reward -= 0.10
        else:
            feedback_parts.append("✅ No internal/test changes mentioned (good filtering)")
            reward += 0.10
        
        # Clamp reward to [0, 1]
        reward = max(0.0, min(1.0, reward))
        
        # Success threshold is 0.7
        passed = reward >= 0.7
        
        feedback = " | ".join(feedback_parts)
        
        if passed:
            feedback += "\n\n🎉 Release notes successfully compiled!"
        else:
            feedback += "\n\n❌ Release notes incomplete or missing key sections."
        
        score = int(reward * 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "metadata": metadata
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
