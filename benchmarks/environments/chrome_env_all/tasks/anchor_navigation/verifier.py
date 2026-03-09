#!/usr/bin/env python3
"""
Verifier for Chrome Anchor Navigation Task (anchor_navigation@1)
Task: Navigate within documentation page using anchor links to jump to sections

Verification Strategy:
- Copy Chrome History database from container
- Parse History to find URLs with fragment identifiers (#section)
- Validate that required anchor sections were visited
- Check navigation sequence and timing
- Verify final URL contains fragment identifier
"""

import logging
import sys
import os
import sqlite3
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        copy_chrome_file,
        parse_history,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def cleanup_verification_temp():
        pass


# Expected fragments that should be visited
REQUIRED_FRAGMENTS = ["getting-started", "api-reference", "examples"]
BASE_URL_PATTERN = "api_documentation.html"


def extract_fragment_from_url(url: str) -> str:
    """Extract fragment identifier from URL (part after #)."""
    if '#' in url:
        # Handle possible query parameters after fragment
        fragment = url.split('#')[1].split('?')[0]
        return fragment.lower()
    return ""


def normalize_url(url: str) -> str:
    """Normalize URL for comparison."""
    # Remove trailing slashes and query parameters for base comparison
    url = url.split('?')[0].rstrip('/')
    return url.lower()


def analyze_fragment_history(history_path: str, base_url_pattern: str) -> Dict[str, Any]:
    """
    Analyze History database for fragment navigations.
    
    Args:
        history_path: Path to History SQLite database
        base_url_pattern: Pattern to match base URL
        
    Returns:
        Dict with analysis results including fragments visited
    """
    try:
        # Connect to History database
        conn = sqlite3.connect(history_path)
        cursor = conn.cursor()
        
        # Query URLs containing fragments, ordered by visit time
        # Chrome timestamps are microseconds since 1601-01-01
        query = """
            SELECT url, title, last_visit_time 
            FROM urls 
            WHERE url LIKE '%#%'
            ORDER BY last_visit_time DESC
            LIMIT 50
        """
        
        cursor.execute(query)
        results = cursor.fetchall()
        conn.close()
        
        # Filter for our documentation page
        fragment_visits = []
        for url, title, timestamp in results:
            if base_url_pattern.lower() in url.lower() and '#' in url:
                fragment = extract_fragment_from_url(url)
                if fragment:
                    fragment_visits.append({
                        'url': url,
                        'fragment': fragment,
                        'title': title,
                        'timestamp': timestamp
                    })
        
        # Most recent first, so reverse for chronological order
        fragment_visits.reverse()
        
        # Get unique fragments
        unique_fragments = list(set(v['fragment'] for v in fragment_visits))
        
        logger.info(f"Found {len(fragment_visits)} fragment navigations, {len(unique_fragments)} unique")
        
        return {
            'total_fragments': len(fragment_visits),
            'unique_fragments': len(unique_fragments),
            'fragments': [v['fragment'] for v in fragment_visits],
            'visits': fragment_visits
        }
        
    except Exception as e:
        logger.error(f"Error analyzing fragment history: {e}", exc_info=True)
        return {
            'total_fragments': 0,
            'unique_fragments': 0,
            'fragments': [],
            'visits': []
        }


def verify_required_fragments(visited_fragments: List[str], required: List[str]) -> Tuple[bool, List[str]]:
    """
    Check if all required fragments were visited.
    
    Args:
        visited_fragments: List of fragment identifiers that were visited
        required: List of required fragment identifiers
        
    Returns:
        Tuple of (all_present: bool, missing: List[str])
    """
    visited_set = set(f.lower() for f in visited_fragments)
    required_set = set(f.lower() for f in required)
    
    missing = list(required_set - visited_set)
    all_present = len(missing) == 0
    
    return all_present, missing


def get_final_url_fragment(copy_from_env) -> Optional[str]:
    """
    Get the fragment from the final URL captured via CDP.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Fragment identifier or None
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        # Try to get final fragment that was captured
        try:
            copy_from_env("/tmp/final_fragment.txt", temp_file.name)
            
            with open(temp_file.name, 'r') as f:
                fragment = f.read().strip()
            
            os.unlink(temp_file.name)
            
            if fragment:
                logger.info(f"Final URL fragment: #{fragment}")
                return fragment
            else:
                logger.warning("No fragment in final URL")
                return None
                
        except Exception as e:
            logger.warning(f"Could not get final fragment: {e}")
            os.unlink(temp_file.name)
            return None
            
    except Exception as e:
        logger.error(f"Error getting final URL fragment: {e}")
        return None


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for anchor_navigation@1 task.
    
    Verifies:
    1. History contains multiple fragment URLs (at least 3)
    2. All navigations stayed on the documentation page
    3. All required fragments were visited (getting-started, api-reference, examples)
    4. At least 3 unique fragments were navigated
    5. Final URL contains a valid fragment identifier
    
    Scoring:
    - 100%: All 5 criteria met
    - 80%: 4/5 criteria met (passing threshold)
    - 60%: 3/5 criteria met
    - 40%: 2/5 criteria met
    - 0-20%: 0-1 criteria met
    
    Pass threshold: 80% (requires at least 4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Error: copy_from_env function not available in environment"
        }
    
    try:
        # Copy History database from container
        logger.info("Copying History database from container...")
        history_path = None
        
        # Try multiple possible locations
        history_locations = [
            "/tmp/anchor_navigation_export/History",
            "/tmp/History",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        for container_path in history_locations:
            try:
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='_History')
                temp_file.close()
                
                logger.info(f"Trying to copy History from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file has content
                if Path(temp_file.name).stat().st_size > 0:
                    history_path = temp_file.name
                    logger.info(f"✓ Successfully copied History from: {container_path}")
                    break
                else:
                    os.unlink(temp_file.name)
                    
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                if 'temp_file' in locals() and os.path.exists(temp_file.name):
                    os.unlink(temp_file.name)
                continue
        
        if not history_path:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access Chrome History database from any location"
            }
        
        # Analyze fragment navigation history
        logger.info("Analyzing fragment navigation history...")
        analysis = analyze_fragment_history(history_path, BASE_URL_PATTERN)
        
        # Clean up History file
        try:
            os.unlink(history_path)
        except:
            pass
        
        # Verification criteria
        criteria_met = 0
        total_criteria = 5
        feedback_parts = []
        
        # Criterion 1: At least 3 fragment navigations recorded
        min_navigations = 3
        if analysis['total_fragments'] >= min_navigations:
            criteria_met += 1
            feedback_parts.append(f"✓ Found {analysis['total_fragments']} fragment navigations (need ≥{min_navigations})")
        else:
            feedback_parts.append(f"✗ Only {analysis['total_fragments']} fragment navigations (need ≥{min_navigations})")
        
        # Criterion 2: All navigations stayed on correct documentation page
        all_correct_base = True
        if analysis['visits']:
            for visit in analysis['visits']:
                if BASE_URL_PATTERN.lower() not in visit['url'].lower():
                    all_correct_base = False
                    break
        else:
            all_correct_base = False
        
        if all_correct_base and analysis['visits']:
            criteria_met += 1
            feedback_parts.append(f"✓ All navigations stayed on documentation page")
        else:
            feedback_parts.append(f"✗ Navigations left the documentation page or no visits recorded")
        
        # Criterion 3: Required fragments visited
        all_required, missing = verify_required_fragments(
            analysis['fragments'], 
            REQUIRED_FRAGMENTS
        )
        if all_required:
            criteria_met += 1
            feedback_parts.append(f"✓ All required sections visited: {REQUIRED_FRAGMENTS}")
        else:
            feedback_parts.append(f"✗ Missing required sections: {missing}")
        
        # Criterion 4: At least 3 unique fragments
        min_unique = 3
        if analysis['unique_fragments'] >= min_unique:
            criteria_met += 1
            feedback_parts.append(f"✓ Visited {analysis['unique_fragments']} unique sections (need ≥{min_unique})")
        else:
            feedback_parts.append(f"✗ Only {analysis['unique_fragments']} unique sections (need ≥{min_unique})")
        
        # Criterion 5: Final URL contains fragment
        final_fragment = get_final_url_fragment(copy_from_env)
        has_final_fragment = final_fragment is not None and final_fragment != ""
        
        if has_final_fragment:
            criteria_met += 1
            feedback_parts.append(f"✓ Final URL contains fragment: #{final_fragment}")
        else:
            feedback_parts.append(f"✗ Final URL missing fragment identifier")
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = criteria_met >= 4  # 80% threshold
        
        # Build feedback
        feedback = f"Anchor Navigation Verification Results\n{'='*50}\n"
        feedback += f"Criteria met: {criteria_met}/{total_criteria} ({score}%)\n\n"
        feedback += "\n".join(feedback_parts)
        
        # Add navigation sequence details if available
        if analysis['visits']:
            feedback += f"\n\nNavigation sequence (last 5):"
            for i, visit in enumerate(analysis['visits'][-5:], 1):
                feedback += f"\n  {i}. #{visit['fragment']}"
        
        # Add result summary
        if passed:
            feedback += "\n\n✅ Task completed successfully!"
        else:
            feedback += f"\n\n❌ Task incomplete - need at least {4}/{total_criteria} criteria"
        
        # Clean up
        cleanup_verification_temp()
        
        logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria_met": criteria_met,
                "total_criteria": total_criteria,
                "total_fragments": analysis['total_fragments'],
                "unique_fragments": analysis['unique_fragments'],
                "fragments_visited": analysis['fragments'],
                "required_fragments": REQUIRED_FRAGMENTS,
                "missing_fragments": missing if not all_required else [],
                "final_fragment": final_fragment
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}\n\nPlease check that anchor links were clicked in the table of contents."
        }
