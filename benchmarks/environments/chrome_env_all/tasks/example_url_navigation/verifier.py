#!/usr/bin/env python3
import logging
import sys
import os
import re
from pathlib import Path

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)


def check_url_navigation(traj, env_info, task_info):
    """
    Verify that the agent navigated to the correct URL containing the baggage fee calculator.
    This follows the OSWorld pattern for URL pattern matching.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in env_info"}

    temp_dir = None
    try:
        # Create temp directory for verification
        temp_dir = Path(os.path.join(os.getcwd(), "temp_chrome_url_check"))
        temp_dir.mkdir(exist_ok=True)
        
        # Copy the final URL file from container
        container_url_file = "/tmp/final_url.txt"
        host_url_file = temp_dir / "final_url.txt"
        
        try:
            success, error = copy_from_env(container_url_file, str(host_url_file))
        except RuntimeError as e:
            logger.warning(f"Failed to copy URL file: {e}")
            return {"passed": False, "score": 0, "feedback": f"Failed to get final URL: {e}"}
        except TypeError as e:
            logger.warning(f"Failed to copy URL file: {e}")
            return {"passed": False, "score": 0, "feedback": f"Failed to get final URL: {e}"}
        if not success:
            logger.warning(f"Failed to copy URL file: {error}")
            return {"passed": False, "score": 0, "feedback": f"Failed to get final URL: {error}"}
        
        # Read the URL
        if not host_url_file.exists():
            return {"passed": False, "score": 0, "feedback": "URL file not found"}
        
        with open(host_url_file, 'r') as f:
            final_url = f.read().strip()
        
        logger.info(f"Final URL: {final_url}")
        
        # Check if URL is empty
        if not final_url:
            return {"passed": False, "score": 0, "feedback": "No URL captured"}
        
        # Expected URL pattern (from OSWorld example)
        # The URL should contain "united.com/en/us/checked-bag-fee-calculator"
        expected_pattern = r"united\.com/en/us/checked-bag-fee-calculator"
        
        # Check if pattern matches
        match = re.search(expected_pattern, final_url)
        
        if match:
            logger.info("URL pattern matched successfully")
            return {
                "passed": True,
                "score": 100,
                "feedback": f"Successfully navigated to baggage fee calculator: {final_url}"
            }
        else:
            logger.info(f"URL pattern did not match. Expected pattern: {expected_pattern}, Got: {final_url}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"URL does not match expected pattern. Got: {final_url}"
            }
    
    except Exception as e:
        logger.error(f"Error in URL verification: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        # Cleanup temp directory
        if temp_dir and temp_dir.exists():
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
