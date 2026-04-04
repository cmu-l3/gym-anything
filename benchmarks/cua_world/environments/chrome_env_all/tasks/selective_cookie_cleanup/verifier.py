#!/usr/bin/env python3
"""
Verifier for Chrome Selective Cookie Cleanup Task (selective_cookie_cleanup@1)
Task: Delete cookies from untrusted domains while preserving trusted site logins

Verification Strategy:
- Copy Cookies SQLite database from container
- Parse using sqlite3
- Compare initial state (from setup) with final state
- Verify 4 criteria:
  1. Trusted domains preserved (all 3 domains)
  2. Untrusted domains deleted (≥80% removed)
  3. Volume reduction (≥70% total cookies deleted)
  4. No collateral damage to trusted cookies (±2 tolerance)

Scoring: 100% for 4/4, 75% for 3/4, 50% for 2/4, 0% for <2/4
Pass threshold: 75% (requires at least 3 out of 4 criteria)
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for selective_cookie_cleanup@1 task.
    
    Args:
        traj: Trajectory data (unused for this task)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get initial state metadata
        initial_state = get_initial_state(copy_from_env)
        if initial_state is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve initial cookie state metadata"
            }

        # Get final cookies from database
        final_cookies = get_final_cookies(copy_from_env)
        if final_cookies is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve final cookie database"
            }

        # Perform multi-criteria verification
        verification_result = verify_selective_cookie_cleanup(
            initial_state,
            final_cookies
        )
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return verification_result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_initial_state(copy_from_env) -> Dict[str, Any]:
    """
    Retrieve initial cookie state metadata from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Dictionary with initial state or None if failed
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/initial_cookie_state_export.json",
            "/tmp/initial_cookie_state.json"
        ]
        
        for container_path in possible_paths:
            try:
                copy_from_env(container_path, temp_path)
                
                with open(temp_path, 'r') as f:
                    initial_state = json.load(f)
                
                os.unlink(temp_path)
                logger.info(f"Successfully retrieved initial state from {container_path}")
                return initial_state
                
            except Exception as e:
                logger.debug(f"Failed to get initial state from {container_path}: {e}")
                continue
        
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        
        logger.error("Could not retrieve initial state from any location")
        return None
        
    except Exception as e:
        logger.error(f"Error getting initial state: {e}")
        return None


def get_final_cookies(copy_from_env) -> List[Tuple[str, str]]:
    """
    Retrieve and parse final cookie database from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        List of (cookie_name, host_key) tuples or None if failed
    """
    temp_db = None
    try:
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db_path = temp_db.name
        temp_db.close()
        
        # Try to copy cookies database
        possible_paths = [
            "/tmp/cookies_export.db",
            "/home/ga/.config/google-chrome-cdp/Default/Cookies",
            "/home/ga/.config/google-chrome/Default/Cookies"
        ]
        
        for container_path in possible_paths:
            try:
                copy_from_env(container_path, temp_db_path)
                
                # Check if file has content
                if Path(temp_db_path).stat().st_size > 0:
                    logger.info(f"Successfully copied cookies database from {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # Parse the SQLite database
        conn = sqlite3.connect(temp_db_path)
        cursor = conn.cursor()
        
        # Query all cookies
        cursor.execute("SELECT name, host_key FROM cookies")
        cookies = cursor.fetchall()
        
        conn.close()
        
        logger.info(f"Successfully parsed {len(cookies)} cookies from database")
        
        # Clean up
        os.unlink(temp_db_path)
        
        return cookies
        
    except Exception as e:
        logger.error(f"Error getting final cookies: {e}")
        if temp_db and os.path.exists(temp_db_path):
            try:
                os.unlink(temp_db_path)
            except:
                pass
        return None


def verify_selective_cookie_cleanup(
    initial_state: Dict[str, Any],
    final_cookies: List[Tuple[str, str]]
) -> Dict[str, Any]:
    """
    Verify that selective cookie cleanup was performed correctly.
    
    Checks:
    1. Trusted domains preserved (all 3 domains have cookies)
    2. Untrusted domains deleted (≥80% removed)
    3. Volume reduction (≥70% total cookies deleted)
    4. No collateral damage (trusted cookie counts within ±2 of original)
    
    Args:
        initial_state: Initial cookie state metadata
        final_cookies: List of (name, host_key) tuples from final database
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Extract initial state data
    initial_total = initial_state.get('total_count', 46)
    initial_trusted = initial_state.get('trusted_counts', {})
    untrusted_domains = initial_state.get('untrusted_domains', [])
    trusted_domains = initial_state.get('trusted_domains', [])
    
    logger.info(f"Initial state: {initial_total} total cookies")
    logger.info(f"Trusted domains: {trusted_domains}")
    logger.info(f"Untrusted domains: {len(untrusted_domains)} domains")
    
    # Analyze final cookies
    final_total = len(final_cookies)
    logger.info(f"Final state: {final_total} total cookies")
    
    # Count cookies by domain
    final_trusted_counts = {}
    for trusted_domain in trusted_domains:
        count = sum(1 for name, host in final_cookies if trusted_domain in host)
        final_trusted_counts[trusted_domain] = count
        logger.info(f"  {trusted_domain}: {count} cookies")
    
    final_untrusted_count = 0
    remaining_untrusted = []
    for untrusted_domain in untrusted_domains:
        has_cookies = any(untrusted_domain in host for name, host in final_cookies)
        if has_cookies:
            count = sum(1 for name, host in final_cookies if untrusted_domain in host)
            final_untrusted_count += count
            remaining_untrusted.append(untrusted_domain)
    
    logger.info(f"  Remaining untrusted domains: {len(remaining_untrusted)}/{len(untrusted_domains)}")
    
    # Criterion 1: Trusted domains preserved
    trusted_preserved_count = sum(1 for domain in trusted_domains 
                                   if final_trusted_counts.get(domain, 0) > 0)
    preservation_success = (trusted_preserved_count == len(trusted_domains))
    
    logger.info(f"✓ Criterion 1 - Trusted domains preserved: {trusted_preserved_count}/{len(trusted_domains)} - {'PASS' if preservation_success else 'FAIL'}")
    
    # Criterion 2: Untrusted domains deleted (≥80%)
    deletion_rate = (len(untrusted_domains) - len(remaining_untrusted)) / len(untrusted_domains)
    deletion_success = deletion_rate >= 0.80
    
    logger.info(f"✓ Criterion 2 - Untrusted domains deleted: {deletion_rate*100:.1f}% ({len(untrusted_domains)-len(remaining_untrusted)}/{len(untrusted_domains)}) - {'PASS' if deletion_success else 'FAIL'}")
    
    # Criterion 3: Volume reduction (≥70%)
    if initial_total > 0:
        reduction_rate = (initial_total - final_total) / initial_total
    else:
        reduction_rate = 0
    volume_success = reduction_rate >= 0.70
    
    logger.info(f"✓ Criterion 3 - Volume reduction: {reduction_rate*100:.1f}% ({initial_total} → {final_total}) - {'PASS' if volume_success else 'FAIL'}")
    
    # Criterion 4: No collateral damage to trusted cookies (±2 tolerance)
    no_collateral_damage = True
    damage_details = []
    for trusted_domain in trusted_domains:
        initial_count = initial_trusted.get(trusted_domain, 0)
        final_count = final_trusted_counts.get(trusted_domain, 0)
        difference = abs(final_count - initial_count)
        
        if difference > 2:
            no_collateral_damage = False
            damage_details.append(f"{trusted_domain}: {initial_count} → {final_count} (±{difference})")
        
    logger.info(f"✓ Criterion 4 - No collateral damage: {'PASS' if no_collateral_damage else 'FAIL'}")
    if damage_details:
        logger.info(f"  Collateral damage detected: {', '.join(damage_details)}")
    
    # Calculate score based on criteria met
    criteria_results = [
        preservation_success,
        deletion_success,
        volume_success,
        no_collateral_damage
    ]
    
    criteria_met = sum(criteria_results)
    score = (criteria_met / 4) * 100
    passed = score >= 75  # Need at least 3/4 criteria (75%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Selective Cookie Cleanup Verification: {criteria_met}/4 criteria met")
    feedback_parts.append("")
    
    # Criterion 1 feedback
    if preservation_success:
        feedback_parts.append(f"✓ Trusted domains preserved: {trusted_preserved_count}/{len(trusted_domains)} domains")
        for domain in trusted_domains:
            count = final_trusted_counts.get(domain, 0)
            feedback_parts.append(f"    • {domain}: {count} cookies ✓")
    else:
        feedback_parts.append(f"✗ Trusted domains NOT fully preserved: {trusted_preserved_count}/{len(trusted_domains)}")
        for domain in trusted_domains:
            count = final_trusted_counts.get(domain, 0)
            status = "✓" if count > 0 else "✗ MISSING"
            feedback_parts.append(f"    • {domain}: {count} cookies {status}")
    
    # Criterion 2 feedback
    if deletion_success:
        feedback_parts.append(f"✓ Untrusted domains deleted: {deletion_rate*100:.1f}% ({len(untrusted_domains)-len(remaining_untrusted)}/{len(untrusted_domains)})")
    else:
        feedback_parts.append(f"✗ Insufficient untrusted domain deletion: {deletion_rate*100:.1f}% (need ≥80%)")
        if remaining_untrusted:
            feedback_parts.append(f"    Remaining untrusted: {', '.join(remaining_untrusted[:5])}")
            if len(remaining_untrusted) > 5:
                feedback_parts.append(f"    ... and {len(remaining_untrusted)-5} more")
    
    # Criterion 3 feedback
    if volume_success:
        feedback_parts.append(f"✓ Total cookies reduced: {reduction_rate*100:.1f}% ({initial_total} → {final_total})")
    else:
        feedback_parts.append(f"✗ Insufficient volume reduction: {reduction_rate*100:.1f}% (need ≥70%)")
    
    # Criterion 4 feedback
    if no_collateral_damage:
        feedback_parts.append(f"✓ No collateral damage to trusted cookies")
    else:
        feedback_parts.append(f"✗ Collateral damage detected:")
        for detail in damage_details:
            feedback_parts.append(f"    • {detail}")
    
    feedback_parts.append("")
    
    if passed:
        feedback_parts.append("✅ Task completed successfully!")
        feedback_parts.append("Privacy improved: tracking cookies removed while staying logged into important sites.")
    else:
        feedback_parts.append("❌ Task incomplete - missing required criteria")
        if not preservation_success:
            feedback_parts.append("  ⚠ Some trusted domain cookies were deleted (logout risk)")
        if not deletion_success:
            feedback_parts.append("  ⚠ Too many tracking cookies remain (privacy concern)")
        if not volume_success:
            feedback_parts.append("  ⚠ Insufficient overall cleanup (performance concern)")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "initial_total": initial_total,
            "final_total": final_total,
            "reduction_percentage": reduction_rate * 100,
            "criteria_met": criteria_met,
            "preservation": preservation_success,
            "deletion": deletion_success,
            "volume_reduction": volume_success,
            "no_collateral_damage": no_collateral_damage,
            "trusted_preserved": trusted_preserved_count,
            "untrusted_deleted": len(untrusted_domains) - len(remaining_untrusted),
            "remaining_untrusted": remaining_untrusted,
            "final_trusted_counts": final_trusted_counts
        }
    }
