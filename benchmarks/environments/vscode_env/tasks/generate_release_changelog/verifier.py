#!/usr/bin/env python3
"""
Verifier for Generate Release Changelog task
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_changelog_generation(traj, env_info, task_info):
    """
    Verify that CHANGELOG.md was generated correctly.
    
    Checks:
    1. CHANGELOG.md exists (20 points)
    2. Has content (15 points)
    3. Contains version 2.1.0 header (15 points)
    4. Has category sections (20 points - 5 each for Features, Bug Fixes, Chores, Breaking Changes)
    5. Contains key commits (30 points - features, fixes, breaking changes)
    6. Noise filtering (bonus - not penalized)
    
    Pass threshold: 70% (0.70)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='changelog_verify_')
    
    try:
        # Path to changelog in container
        changelog_container_path = "/home/ga/workspace/sample-project/CHANGELOG.md"
        changelog_local = os.path.join(temp_dir, "CHANGELOG.md")
        
        # Try to copy the changelog
        try:
            copy_from_env(changelog_container_path, changelog_local)
        except Exception as e:
            logger.warning(f"Failed to copy CHANGELOG.md from workspace: {e}")
            # Try alternative path from /tmp
            try:
                copy_from_env("/tmp/CHANGELOG.md", changelog_local)
            except Exception as e2:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"❌ CHANGELOG.md file not found in repository root ({changelog_container_path})"
                }
        
        feedback_parts = []
        score = 0.0
        metadata = {}
        
        # Check 1: File exists (20 points)
        if not os.path.exists(changelog_local) or os.path.getsize(changelog_local) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ CHANGELOG.md file not found or is empty",
                "metadata": metadata
            }
        
        score += 0.2
        feedback_parts.append("✅ CHANGELOG.md file exists")
        
        # Read changelog content
        content = read_file_content(changelog_local)
        
        if not content.strip():
            return {
                "passed": False,
                "score": score,
                "feedback": "❌ CHANGELOG.md is empty",
                "metadata": metadata
            }
        
        score += 0.15
        feedback_parts.append("✅ CHANGELOG.md has content")
        metadata['changelog_length'] = len(content)
        
        # Check 3: Version header present (15 points)
        # Look for version 2.1.0 in various formats
        version_patterns = [
            r'\[?2\.1\.0\]?',
            r'##\s*\[?2\.1\.0\]?',
            r'Version\s+2\.1\.0',
            r'v2\.1\.0'
        ]
        
        version_found = False
        for pattern in version_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                version_found = True
                break
        
        if version_found:
            score += 0.15
            feedback_parts.append("✅ Version 2.1.0 header present")
        else:
            feedback_parts.append("⚠ Missing version 2.1.0 header")
        
        metadata['version_header_found'] = version_found
        
        # Check 4: Category sections present (20 points total - 5 each)
        categories = {
            'Features': r'###?\s*Features?',
            'Bug Fixes': r'###?\s*(Bug\s*)?Fixes?',
            'Chores': r'###?\s*(Chores?|Maintenance)',
            'Breaking Changes': r'###?\s*Breaking\s*(Changes?|Change)'
        }
        
        categories_found = 0
        category_details = {}
        
        for category_name, pattern in categories.items():
            if re.search(pattern, content, re.IGNORECASE):
                categories_found += 1
                category_details[category_name] = True
                feedback_parts.append(f"✅ {category_name} section found")
            else:
                category_details[category_name] = False
        
        score += (categories_found / 4) * 0.2
        metadata['categories_found'] = categories_found
        metadata['category_details'] = category_details
        
        if categories_found < 3:
            feedback_parts.append(f"⚠ Only {categories_found}/4 category sections found")
        
        # Check 5: Key commits mentioned (30 points total)
        # Features
        key_features = [
            (r'authentication|OAuth2|auth|oauth', 'authentication/OAuth2'),
            (r'(file\s*)?upload|progress\s*track', 'file upload with progress'),
            (r'notification|push\s*notif', 'push notifications')
        ]
        
        # Bug fixes
        key_fixes = [
            (r'memory\s*leak|WebSocket|websocket|ws\s*connection', 'memory leak/WebSocket'),
            (r'timezone|date\s*picker|date\s*handling', 'timezone/date handling')
        ]
        
        # Breaking changes
        key_breaking = [
            (r'(API|api).*v2|response.*format|schema.*v2|breaking.*api', 'API v2 schema/response format')
        ]
        
        # Chores
        key_chores = [
            (r'dependenc(y|ies)|update.*dep|dep.*update', 'dependency updates'),
            (r'refactor.*api|api.*refactor|error\s*handling', 'API refactoring')
        ]
        
        features_found = 0
        for pattern, desc in key_features:
            if re.search(pattern, content, re.IGNORECASE):
                features_found += 1
        
        fixes_found = 0
        for pattern, desc in key_fixes:
            if re.search(pattern, content, re.IGNORECASE):
                fixes_found += 1
        
        breaking_found = 0
        for pattern, desc in key_breaking:
            if re.search(pattern, content, re.IGNORECASE):
                breaking_found += 1
        
        chores_found = 0
        for pattern, desc in key_chores:
            if re.search(pattern, content, re.IGNORECASE):
                chores_found += 1
        
        # Score for content (30 points total)
        # Features: 10 points (need at least 2/3)
        if features_found >= 2:
            score += 0.10
            feedback_parts.append(f"✅ Found {features_found} key features")
        elif features_found >= 1:
            score += 0.05
            feedback_parts.append(f"⚠ Found only {features_found} key feature (expected 2+)")
        else:
            feedback_parts.append(f"❌ No key features found")
        
        # Bug fixes: 10 points (need at least 2/2)
        if fixes_found >= 2:
            score += 0.10
            feedback_parts.append(f"✅ Found {fixes_found} key bug fixes")
        elif fixes_found >= 1:
            score += 0.05
            feedback_parts.append(f"⚠ Found only {fixes_found} bug fix (expected 2)")
        else:
            feedback_parts.append(f"❌ No key bug fixes found")
        
        # Breaking changes: 5 points (need at least 1)
        if breaking_found >= 1:
            score += 0.05
            feedback_parts.append("✅ Breaking change documented")
        else:
            feedback_parts.append("⚠ Breaking change not documented")
        
        # Chores: 5 points (at least 1)
        if chores_found >= 1:
            score += 0.05
            feedback_parts.append(f"✅ Found {chores_found} chore(s)")
        else:
            feedback_parts.append("⚠ No chores/refactoring documented")
        
        metadata['features_found'] = features_found
        metadata['fixes_found'] = fixes_found
        metadata['breaking_found'] = breaking_found
        metadata['chores_found'] = chores_found
        
        # Check 6: Noise filtered (bonus - doesn't penalize)
        noise_patterns = [r'\bwip\b', r'\btypo\b', r'merge\s+branch', r'fix\s+formatting']
        noise_count = 0
        for pattern in noise_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                noise_count += 1
        
        if noise_count == 0:
            feedback_parts.append("✅ Noise commits filtered out")
        else:
            feedback_parts.append(f"⚠ Found {noise_count} noise commit(s) in changelog (not critical)")
        
        metadata['noise_found'] = noise_count
        
        # Determine success
        passed = score >= 0.70  # 70% threshold
        
        # Build feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n📊 Final Score: {score:.2f}/1.00 ({int(score * 100)}%)"
        
        if passed:
            feedback += "\n✅ Changelog successfully generated!"
        else:
            feedback += "\n❌ Changelog incomplete or missing key elements"
            feedback += f"\n   (Need 70% to pass, got {int(score * 100)}%)"
        
        return {
            "passed": passed,
            "score": int(score * 100),
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
