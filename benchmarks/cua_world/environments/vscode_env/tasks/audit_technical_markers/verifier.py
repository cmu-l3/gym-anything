#!/usr/bin/env python3
"""
Verifier for Audit Technical Markers task
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


def verify_task(traj, env_info, task_info):
    """
    Verify that technical debt markers were properly audited and addressed.
    
    Checks:
    1. TECHNICAL_DEBT.md exists and contains structured audit (25 points)
    2. Critical database.py bug fixed (params handling) (30 points)
    3. Critical api.py bug fixed (404 status) (30 points)
    4. Audit document quality (references, categorization, status) (15 points)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='audit_verify_')

    try:
        # Copy exported files
        local_paths = {}
        files_to_copy = [
            ("TECHNICAL_DEBT.md", "/tmp/TECHNICAL_DEBT.md"),
            ("database.py", "/tmp/database.py"),
            ("api.py", "/tmp/api.py"),
            ("validation.py", "/tmp/validation.py"),
            ("utils.py", "/tmp/utils.py")
        ]

        for local_name, container_path in files_to_copy:
            local_path = os.path.join(temp_dir, local_name)
            try:
                copy_from_env(container_path, local_path)
                local_paths[local_name] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {container_path}: {e}")
                local_paths[local_name] = None

        feedback = []
        score = 0
        max_score = 100

        # Check 1: TECHNICAL_DEBT.md exists and is structured (25 points)
        debt_path = local_paths.get("TECHNICAL_DEBT.md")
        if not debt_path or not os.path.exists(debt_path) or os.path.getsize(debt_path) == 0:
            feedback.append("❌ TECHNICAL_DEBT.md not found or empty (0/25 pts)")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback)
            }

        with open(debt_path, 'r', encoding='utf-8', errors='ignore') as f:
            debt_content = f.read()

        debt_score = 0

        # Check for file references (should mention multiple source files)
        file_refs = set()
        for pattern in [r'database\.py', r'api\.py', r'validation\.py', r'utils\.py', r'test_validation\.py']:
            if re.search(pattern, debt_content):
                file_refs.add(pattern)

        if len(file_refs) >= 3:
            debt_score += 15
            feedback.append(f"✅ Audit references {len(file_refs)} files (+15 pts)")
        elif len(file_refs) >= 2:
            debt_score += 8
            feedback.append(f"⚠️ Audit references only {len(file_refs)} files (+8 pts, expected 3+)")
        else:
            feedback.append(f"❌ Audit references only {len(file_refs)} files (0 pts, expected 3+)")

        # Check for categorization/severity mentions
        has_categorization = any(
            keyword in debt_content.lower()
            for keyword in ['critical', 'severity', 'priority', 'normal', 'deferred', 'blocker', 'high', 'low']
        )
        if has_categorization:
            debt_score += 10
            feedback.append("✅ Markers categorized by severity (+10 pts)")
        else:
            feedback.append("❌ No severity categorization found (0/10 pts)")

        score += debt_score

        # Check 2: Critical bug in database.py fixed (30 points)
        db_path = local_paths.get("database.py")
        db_score = 0

        if db_path and os.path.exists(db_path):
            with open(db_path, 'r', encoding='utf-8', errors='ignore') as f:
                db_content = f.read()

            # The bug: cursor.execute(query, params) without checking if params is None
            # Proper fixes include:
            # - if params is not None: cursor.execute(query, params)
            # - cursor.execute(query, params if params else ())
            # - cursor.execute(query, params or ())
            # - checking params before execute

            has_params_check = False
            patterns = [
                r'if\s+params\s+is\s+not\s+None',
                r'if\s+params\s*:',
                r'params\s+if\s+params\s+else',
                r'params\s+or\s+\(\)',
                r'if\s+params\s+is\s+None',
            ]
            for pattern in patterns:
                if re.search(pattern, db_content, re.IGNORECASE):
                    has_params_check = True
                    break

            # Also look for alternative patterns like execute with conditional
            if 'execute(query' in db_content:
                # Check if the execute call is now conditional or has proper handling
                execute_lines = [line for line in db_content.split('\n') if 'execute(query' in line.lower()]
                for line in execute_lines:
                    if 'if' in line or 'else' in line or 'or' in line:
                        has_params_check = True
                        break

            # Check if FIXME comment was removed or marked as fixed
            fixme_removed = 'FIXME' not in db_content or 'fixed' in db_content.lower()

            if has_params_check and fixme_removed:
                db_score = 30
                feedback.append("✅ database.py bug fixed correctly (+30 pts)")
            elif has_params_check:
                db_score = 25
                feedback.append("⚠️ database.py bug fixed but FIXME remains (+25 pts)")
            elif fixme_removed and 'execute_query' in db_content:
                db_score = 10
                feedback.append("⚠️ FIXME removed but bug not properly fixed (+10 pts)")
            else:
                feedback.append("❌ database.py bug not fixed (0/30 pts)")
        else:
            feedback.append("❌ database.py not found (0/30 pts)")

        score += db_score

        # Check 3: Critical bug in api.py fixed (30 points)
        api_path = local_paths.get("api.py")
        api_score = 0

        if api_path and os.path.exists(api_path):
            with open(api_path, 'r', encoding='utf-8', errors='ignore') as f:
                api_content = f.read()

            # The bug: returning 200 with empty body instead of 404
            # Proper fix: return jsonify(...), 404 or similar

            # Look for 404 status in get_item function
            has_404_fix = False
            if '404' in api_content:
                # Check if it's in the context of get_item function
                get_item_match = re.search(
                    r'def get_item\([^)]*\):.*?(?=\ndef|\Z)',
                    api_content,
                    re.DOTALL
                )
                if get_item_match:
                    get_item_body = get_item_match.group(0)
                    if '404' in get_item_body:
                        has_404_fix = True

            # Check if FIXME was removed or marked as fixed
            # Look specifically in get_item function context
            fixme_removed_api = True
            if 'FIXME' in api_content:
                get_item_match = re.search(
                    r'def get_item\([^)]*\):.*?(?=\ndef|\Z)',
                    api_content,
                    re.DOTALL
                )
                if get_item_match and 'FIXME' in get_item_match.group(0):
                    if 'should return 404' in get_item_match.group(0).lower() or 'critical' in get_item_match.group(0).lower():
                        fixme_removed_api = False

            if has_404_fix and fixme_removed_api:
                api_score = 30
                feedback.append("✅ api.py bug fixed correctly (+30 pts)")
            elif has_404_fix:
                api_score = 25
                feedback.append("⚠️ api.py bug fixed but FIXME remains (+25 pts)")
            elif fixme_removed_api and 'get_item' in api_content:
                api_score = 10
                feedback.append("⚠️ FIXME removed but 404 not implemented (+10 pts)")
            else:
                feedback.append("❌ api.py bug not fixed (0/30 pts)")
        else:
            feedback.append("❌ api.py not found (0/30 pts)")

        score += api_score

        # Check 4: Audit document quality (15 points)
        quality_score = 0

        # Should have reasonable length (detailed, not just a list)
        if len(debt_content) > 300:
            quality_score += 5
            feedback.append("✅ Audit is detailed (+5 pts)")
        else:
            feedback.append("⚠️ Audit seems too brief (0/5 pts)")

        # Should reference line numbers or specific locations
        if re.search(r'(line\s+\d+|:\d+|L\d+|\d+:)', debt_content):
            quality_score += 5
            feedback.append("✅ Audit includes line references (+5 pts)")
        else:
            feedback.append("⚠️ No line references found (0/5 pts)")

        # Should mention status of items (fixed/tracked/deferred/documented)
        status_keywords = ['fixed', 'tracked', 'defer', 'completed', 'resolved', 'documented', 'addressed']
        status_count = sum(1 for keyword in status_keywords if keyword in debt_content.lower())

        if status_count >= 2:
            quality_score += 5
            feedback.append("✅ Audit tracks item status (+5 pts)")
        else:
            feedback.append("⚠️ Limited status tracking (0/5 pts)")

        score += quality_score

        # Calculate final result
        normalized_score = score / max_score
        passed = score >= 70  # 70 point threshold

        feedback_str = " | ".join(feedback)
        final_feedback = f"Score: {score}/{max_score} pts | {feedback_str}"

        return {
            "passed": passed,
            "score": int(normalized_score * 100),
            "feedback": final_feedback
        }

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
