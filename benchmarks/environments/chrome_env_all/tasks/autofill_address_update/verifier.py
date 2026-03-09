#!/usr/bin/env python3
"""
Verifier for Chrome Autofill Address Update Task (autofill_address_update@1)
Task: Remove old address and add new address to Chrome autofill

Verification Strategy:
- Copy Chrome's Web Data SQLite database from container
- Query autofill_profile_addresses table for old address (should be absent)
- Query autofill_profile_addresses table for new address (should be present)
- Verify all components: street, city, state, ZIP, and name association
- Check database integrity

Scoring:
- 100%: All 5 criteria met (perfect address update)
- 80-99%: 4/5 criteria met (good execution, minor issue)
- 60-79%: 3/5 criteria met (partial success)
- 40-59%: 2/5 criteria met (significant issues)
- 0-39%: <2 criteria met (task failed)

Pass threshold: 80% (requires at least 4 out of 5 criteria)
"""

import logging
import sys
import os
import sqlite3
import tempfile
import re
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for autofill_address_update@1.
    
    Verifies:
    1. Old address (742 Evergreen Terrace, IL 62704) is removed
    2. New street address (1428 Elm Street) is present
    3. New city/ZIP (Springfield, IL 62701) is present
    4. Name (Sarah Chen) is associated with new address
    5. Database integrity maintained
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    web_data_path = None
    try:
        # Copy Web Data database from container
        web_data_path, error_msg = copy_web_data_database(copy_from_env)
        
        if web_data_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Web Data database: {error_msg}"
            }
        
        logger.info(f"Successfully copied Web Data database to: {web_data_path}")
        
        # Verify autofill address changes
        result = verify_autofill_changes(web_data_path)
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temporary files
        if web_data_path and os.path.exists(web_data_path):
            try:
                os.unlink(web_data_path)
                logger.info("Cleaned up temporary Web Data file")
            except Exception as e:
                logger.warning(f"Could not clean up temp file: {e}")
        
        cleanup_verification_temp()


def copy_web_data_database(copy_from_env):
    """
    Copy Web Data database from container to host for analysis.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (local_path: str or None, error_message: str)
    """
    # Create temporary file for database
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
    temp_path = temp_file.name
    temp_file.close()
    
    # Try multiple possible locations
    possible_paths = [
        "/tmp/web_data_export.db",
        "/tmp/WebData",
        "/home/ga/.config/google-chrome-cdp/Default/Web Data",
        "/home/ga/.config/google-chrome/Default/Web Data",
    ]
    
    for container_path in possible_paths:
        try:
            logger.info(f"Attempting to copy Web Data from: {container_path}")
            copy_from_env(container_path, temp_path)
            
            # Verify file was copied and has content
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                logger.info(f"✓ Successfully copied Web Data from: {container_path}")
                logger.info(f"  File size: {os.path.getsize(temp_path)} bytes")
                return temp_path, ""
            else:
                logger.debug(f"File copied but empty or missing: {container_path}")
                
        except Exception as e:
            logger.debug(f"Failed to copy from {container_path}: {e}")
            continue
    
    # If we get here, none of the paths worked
    os.unlink(temp_path)
    return None, "Could not copy Web Data database from any known location"


def verify_autofill_changes(web_data_path):
    """
    Verify that autofill addresses were correctly updated.
    
    Checks:
    1. Old address removed
    2. New street address present
    3. New city/ZIP present
    4. Name associated
    5. Database integrity
    
    Args:
        web_data_path: Path to local copy of Web Data database
        
    Returns:
        Dict with verification results
    """
    criteria_results = {
        "old_removed": False,
        "new_street_present": False,
        "new_city_zip_present": False,
        "name_present": False,
        "db_valid": False
    }
    
    feedback_parts = []
    
    try:
        # Connect to database
        conn = sqlite3.connect(web_data_path)
        cursor = conn.cursor()
        
        # Check 1: Old address should be REMOVED
        logger.info("Checking if old address was removed...")
        cursor.execute("""
            SELECT COUNT(*) FROM autofill_profile_addresses
            WHERE street_address LIKE '%742 Evergreen%'
               OR (city = 'Springfield' AND zip_code = '62704')
        """)
        old_address_count = cursor.fetchone()[0]
        
        if old_address_count == 0:
            criteria_results["old_removed"] = True
            feedback_parts.append("✅ Old address successfully removed (742 Evergreen Terrace)")
            logger.info("  ✓ Old address removed")
        else:
            feedback_parts.append(f"❌ Old address still present ({old_address_count} entries found)")
            logger.info(f"  ✗ Old address still present: {old_address_count} entries")
        
        # Check 2: New street address should be present
        logger.info("Checking if new street address is present...")
        cursor.execute("""
            SELECT COUNT(*) FROM autofill_profile_addresses
            WHERE street_address LIKE '%1428 Elm%'
        """)
        new_street_count = cursor.fetchone()[0]
        
        if new_street_count > 0:
            criteria_results["new_street_present"] = True
            feedback_parts.append("✅ New street address added (1428 Elm Street)")
            logger.info("  ✓ New street address present")
            
            # Get the actual address for details
            cursor.execute("""
                SELECT street_address FROM autofill_profile_addresses
                WHERE street_address LIKE '%1428 Elm%'
                LIMIT 1
            """)
            actual_street = cursor.fetchone()[0]
            logger.info(f"    Address: {actual_street}")
        else:
            feedback_parts.append("❌ New street address not found (expected 1428 Elm Street)")
            logger.info("  ✗ New street address not found")
        
        # Check 3: New city/ZIP should be present together
        logger.info("Checking if new city/ZIP is present...")
        cursor.execute("""
            SELECT COUNT(*) FROM autofill_profile_addresses
            WHERE city = 'Springfield' AND zip_code = '62701'
        """)
        new_city_zip_count = cursor.fetchone()[0]
        
        if new_city_zip_count > 0:
            criteria_results["new_city_zip_present"] = True
            feedback_parts.append("✅ New city/ZIP correctly stored (Springfield, IL 62701)")
            logger.info("  ✓ New city/ZIP present")
        else:
            feedback_parts.append("❌ New city/ZIP combination not found (expected Springfield, 62701)")
            logger.info("  ✗ New city/ZIP not found")
        
        # Check 4: Name should be associated with new address
        logger.info("Checking if name is associated with address...")
        
        # First, try to find the GUID of the new address
        cursor.execute("""
            SELECT guid FROM autofill_profile_addresses
            WHERE street_address LIKE '%1428 Elm%'
            LIMIT 1
        """)
        new_address_guid_result = cursor.fetchone()
        
        if new_address_guid_result:
            new_address_guid = new_address_guid_result[0]
            
            # Check if name exists in autofill_profile_names
            cursor.execute("""
                SELECT full_name FROM autofill_profile_names
                WHERE guid = ?
            """, (new_address_guid,))
            name_result = cursor.fetchone()
            
            if name_result:
                full_name = name_result[0]
                if "Sarah" in full_name and "Chen" in full_name:
                    criteria_results["name_present"] = True
                    feedback_parts.append(f"✅ Name correctly associated ('{full_name}')")
                    logger.info(f"  ✓ Name associated: {full_name}")
                else:
                    feedback_parts.append(f"⚠️  Name associated but incorrect ('{full_name}', expected 'Sarah Chen')")
                    logger.info(f"  ~ Name wrong: {full_name}")
            else:
                feedback_parts.append("⚠️  Name not associated with new address (minor issue)")
                logger.info("  ~ Name not found for GUID")
        else:
            # If we couldn't find the address, check for name anyway
            cursor.execute("""
                SELECT COUNT(*) FROM autofill_profile_names
                WHERE full_name LIKE '%Sarah%Chen%' OR full_name LIKE '%Chen%Sarah%'
            """)
            name_count = cursor.fetchone()[0]
            
            if name_count > 0:
                criteria_results["name_present"] = True
                feedback_parts.append("✅ Name 'Sarah Chen' found in database")
                logger.info("  ✓ Name present (but GUID association unclear)")
            else:
                feedback_parts.append("⚠️  Name 'Sarah Chen' not found (minor issue)")
                logger.info("  ~ Name not present")
        
        # Check 5: Database integrity
        logger.info("Checking database integrity...")
        try:
            # Check that tables exist and are queryable
            cursor.execute("SELECT COUNT(*) FROM autofill_profiles")
            profile_count = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM autofill_profile_addresses")
            address_count = cursor.fetchone()[0]
            
            # Reasonable bounds check
            if 0 <= profile_count <= 100 and 0 <= address_count <= 100:
                criteria_results["db_valid"] = True
                feedback_parts.append(f"✅ Database integrity maintained ({profile_count} profiles, {address_count} addresses)")
                logger.info(f"  ✓ Database valid: {profile_count} profiles, {address_count} addresses")
            else:
                feedback_parts.append(f"⚠️  Database profile counts unusual ({profile_count} profiles, {address_count} addresses)")
                logger.info(f"  ~ Database counts unusual: {profile_count} profiles, {address_count} addresses")
        except sqlite3.Error as e:
            feedback_parts.append(f"❌ Database integrity check failed: {e}")
            logger.info(f"  ✗ Database error: {e}")
        
        conn.close()
        
    except sqlite3.Error as e:
        feedback_parts.append(f"❌ Database error: {str(e)}")
        logger.error(f"SQLite error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Database error: {str(e)}",
            "criteria": criteria_results
        }
    except Exception as e:
        feedback_parts.append(f"❌ Verification error: {str(e)}")
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "criteria": criteria_results
        }
    
    # Calculate score
    criteria_met = sum(criteria_results.values())
    score = (criteria_met / 5.0) * 100
    passed = score >= 80  # Need at least 4/5 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/5"
    feedback += f"\nFinal score: {score:.0f}%"
    feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if score >= 80 and score < 100:
        feedback += "\n\nNote: Minor issues detected but core task completed successfully."
    elif score < 80:
        feedback += "\n\nTask incomplete: Please ensure both old address is removed AND new address is added with all fields."
    
    logger.info(f"Final verification result: score={score:.0f}%, passed={passed}")
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "criteria": criteria_results,
        "details": {
            "old_address_removed": criteria_results["old_removed"],
            "new_street_present": criteria_results["new_street_present"],
            "new_city_zip_present": criteria_results["new_city_zip_present"],
            "name_associated": criteria_results["name_present"],
            "database_valid": criteria_results["db_valid"]
        }
    }
