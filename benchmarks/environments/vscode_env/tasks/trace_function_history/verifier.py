#!/usr/bin/env python3
"""
Verifier for Code Archaeology task (trace_function_history)
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_code_archaeology(traj, env_info, task_info):
    """
    Verify that the agent successfully investigated the function history
    and documented findings.

    Checks:
    1. FINDINGS.md file exists
    2. Contains a valid commit hash
    3. The commit hash corresponds to the problematic commit
    4. Contains author information
    5. Describes the change (mentions strip/upper/modification)
    6. Explains the problem/impact
    7. Has reasonable structure and length
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_archaeology_verify_')

    try:
        # Copy FINDINGS.md from container
        findings_local = os.path.join(temp_dir, "FINDINGS.md")
        expected_commit_local = os.path.join(temp_dir, "expected_commit.txt")
        git_log_local = os.path.join(temp_dir, "git_log.txt")

        # Copy the findings file
        try:
            copy_from_env("/tmp/FINDINGS.md", findings_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"FINDINGS.md file not found or could not be copied: {str(e)}"
            }

        # Copy expected commit hash and git log for reference
        try:
            copy_from_env("/tmp/expected_commit_hash.txt", expected_commit_local)
        except Exception as e:
            logger.warning(f"Could not copy expected commit hash: {e}")

        try:
            copy_from_env("/tmp/git_log_archaeology.txt", git_log_local)
        except Exception as e:
            logger.warning(f"Could not copy git log: {e}")

        # Check if file exists and has content
        if not os.path.exists(findings_local):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ FINDINGS.md file does not exist in /home/ga/workspace/email_validator/"
            }

        if os.path.getsize(findings_local) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ FINDINGS.md file is empty"
            }

        # Read the findings content
        with open(findings_local, 'r', encoding='utf-8') as f:
            content = f.read()

        # Read expected commit hash
        expected_commit = None
        if os.path.exists(expected_commit_local):
            with open(expected_commit_local, 'r') as f:
                expected_commit = f.read().strip()

        logger.info(f"Expected problematic commit: {expected_commit}")
        logger.info(f"FINDINGS.md content length: {len(content)} characters")

        score = 0
        feedback_parts = []

        # Criterion 1: File exists and has content (already checked)
        score += 15
        feedback_parts.append("✅ FINDINGS.md file exists")

        # Criterion 2: Check for commit hash pattern (7-40 hex characters)
        commit_pattern = r'\b[0-9a-f]{7,40}\b'
        commit_matches = re.findall(commit_pattern, content, re.IGNORECASE)

        if commit_matches:
            score += 15
            feedback_parts.append(f"✅ Found commit hash(es): {', '.join(commit_matches[:2])}")

            # Criterion 3: Check if the correct commit is identified
            if expected_commit:
                # Check both full hash and first 7 characters
                expected_short = expected_commit[:7] if len(expected_commit) > 7 else expected_commit
                correct_commit_found = False

                for candidate in commit_matches:
                    # Match if candidate is prefix of expected or vice versa
                    if (expected_commit.startswith(candidate.lower()) or 
                        candidate.lower().startswith(expected_short.lower())):
                        correct_commit_found = True
                        break

                if correct_commit_found:
                    score += 25
                    feedback_parts.append(f"✅ Correct problematic commit identified")
                else:
                    feedback_parts.append(f"❌ Incorrect commit identified (expected commit starting with {expected_short})")
            else:
                # If we can't verify the exact commit, give partial credit
                score += 15
                feedback_parts.append("⚠️ Commit hash present but cannot verify correctness")
        else:
            feedback_parts.append("❌ No commit hash found in documentation")

        # Criterion 4: Check for author/developer mention
        author_keywords = ['author', 'developer', 'by', 'committed', 'changed by', 'charlie', 'davis']
        content_lower = content.lower()
        has_author = any(keyword in content_lower for keyword in author_keywords)

        if has_author:
            score += 10
            feedback_parts.append("✅ Author/developer information included")
        else:
            feedback_parts.append("❌ Missing author information")

        # Criterion 5: Check for change description
        change_keywords = ['strip', 'upper', 'changed', 'modified', 'added', 'introduced', 
                          'case', 'sensitivity', 'domain']
        has_change_desc = sum(1 for keyword in change_keywords if keyword in content_lower)

        if has_change_desc >= 2:
            score += 15
            feedback_parts.append(f"✅ Change description present (found {has_change_desc} relevant keywords)")
        else:
            feedback_parts.append("❌ Missing or incomplete description of what changed")

        # Criterion 6: Check for impact/problem explanation
        impact_keywords = ['bug', 'problem', 'issue', 'breaks', 'broken', 'incorrect', 
                          'fails', 'international', 'unicode', 'edge case', 'problematic']
        has_impact = sum(1 for keyword in impact_keywords if keyword in content_lower)

        if has_impact >= 1:
            score += 10
            feedback_parts.append("✅ Impact/problem explanation included")
        else:
            feedback_parts.append("❌ Missing explanation of why the change is problematic")

        # Criterion 7: Check for markdown structure
        has_structure = bool(re.search(r'#+\s+\w+', content)) or bool(re.search(r'^\*\*\w+', content, re.MULTILINE))
        if has_structure:
            score += 10
            feedback_parts.append("✅ Well-structured with markdown formatting")
        else:
            feedback_parts.append("⚠️ Documentation lacks clear structure (consider using markdown headers)")

        # Bonus: Check minimum substantive content
        if len(content.strip()) >= 150:
            # Good length indicates thorough investigation
            pass
        elif len(content.strip()) < 50:
            score -= 10
            feedback_parts.append("⚠️ Documentation is very brief (may lack detail)")

        # Ensure score is within bounds
        score = max(0, min(100, score))

        # Pass threshold is 70%
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        result = {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

        logger.info(f"Verification result: {result}")
        return result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
