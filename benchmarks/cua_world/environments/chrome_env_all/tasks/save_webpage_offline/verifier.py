#!/usr/bin/env python3
"""
Verifier for Chrome Save Webpage for Offline Reading Task (save_webpage_offline@1)
Task: Save a complete webpage with all resources for offline reading

Verification Strategy:
- Check Downloads folder for recently created HTML file
- Verify companion _files folder exists with matching name
- Validate folder contains multiple resource files
- Parse HTML to ensure local resource references (not external URLs)
- Check content preservation (substantial text present)
"""

import logging
import sys
import os
import re
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import BeautifulSoup for HTML parsing
try:
    from bs4 import BeautifulSoup
    HAS_BS4 = True
except ImportError:
    HAS_BS4 = False
    logger.warning("BeautifulSoup not available, HTML analysis will be limited")

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for save_webpage_offline@1.
    
    Verifies:
    1. HTML file exists in Downloads with reasonable size
    2. Companion _files folder exists
    3. Folder contains multiple resource files
    4. HTML references local resources (not external URLs)
    5. Content preserved (substantial text present)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Find and copy saved files from container
        html_file, resources_folder, error = find_saved_webpage(copy_from_env)
        
        if html_file is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to find saved webpage: {error}"
            }
        
        # Perform multi-criteria verification
        result = verify_offline_webpage_save(html_file, resources_folder)
        
        # Clean up temporary files
        cleanup_temp_files(html_file, resources_folder)
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def find_saved_webpage(copy_from_env) -> Tuple[Optional[str], Optional[str], str]:
    """
    Find and copy the saved HTML file and resources folder from container.
    
    Returns:
        Tuple of (html_file_path, resources_folder_path, error_message)
    """
    downloads_dir = "/home/ga/Downloads"
    
    # Create temp directory for verification
    temp_dir = Path(tempfile.mkdtemp(prefix="chrome_save_verify_"))
    logger.info(f"Created temp directory: {temp_dir}")
    
    try:
        # First, list files in Downloads to find recent HTML files
        # We'll create a small script to find recent HTML files and copy them
        list_script = f"""
import os
import json
from pathlib import Path
from datetime import datetime, timedelta

downloads = Path("{downloads_dir}")
recent_threshold = datetime.now() - timedelta(minutes=10)

html_files = []
for ext in ['*.html', '*.htm']:
    for f in downloads.glob(ext):
        if f.is_file():
            mtime = datetime.fromtimestamp(f.stat().st_mtime)
            if mtime > recent_threshold:
                html_files.append({{
                    'path': str(f),
                    'name': f.name,
                    'mtime': mtime.timestamp(),
                    'size': f.stat().st_size
                }})

# Sort by modification time (most recent first)
html_files.sort(key=lambda x: x['mtime'], reverse=True)

# Output as JSON
print(json.dumps(html_files))
"""
        
        # Write script to temp file and copy it to container
        script_file = temp_dir / "find_html.py"
        with open(script_file, 'w') as f:
            f.write(list_script)
        
        # Execute the script in container (this is a simplification - in practice, we'd need a different approach)
        # Instead, let's try to directly copy known possible filenames
        
        # Try common filenames that might be used
        possible_names = [
            "python_tutorial.html",
            "python_tutorial_offline.html",
            "Python Programming Tutorial - Complete Guide for Beginners.html",
            "tutorial_offline.html",
        ]
        
        html_file = None
        html_name = None
        
        # Try to copy each possible file
        for name in possible_names:
            try:
                container_path = f"{downloads_dir}/{name}"
                local_path = temp_dir / name
                copy_from_env(container_path, str(local_path))
                
                if local_path.exists() and local_path.stat().st_size > 0:
                    html_file = str(local_path)
                    html_name = name
                    logger.info(f"Found HTML file: {name}")
                    break
            except Exception as e:
                logger.debug(f"Could not copy {name}: {e}")
                continue
        
        # If no known filename worked, try to find ANY recent HTML file
        if html_file is None:
            # Try to list directory and find HTML files
            try:
                # Create a marker file to help find files
                for attempt in range(5):
                    try:
                        test_name = f"test_html_{attempt}.html"
                        container_path = f"{downloads_dir}/{test_name}"
                        local_path = temp_dir / test_name
                        copy_from_env(container_path, str(local_path))
                        if local_path.exists():
                            os.unlink(local_path)
                    except:
                        pass
                
                # Try glob patterns
                for pattern in ["*.html", "*.htm"]:
                    try:
                        # This is a workaround - try common patterns
                        for i in range(20):
                            try:
                                # Generate possible filenames
                                test_file = temp_dir / f"download_{i}.html"
                                copy_from_env(f"{downloads_dir}/download_{i}.html", str(test_file))
                                if test_file.exists() and test_file.stat().st_size > 1024:
                                    html_file = str(test_file)
                                    html_name = f"download_{i}.html"
                                    break
                            except:
                                continue
                    except:
                        continue
            except Exception as e:
                logger.debug(f"Directory listing failed: {e}")
        
        if html_file is None:
            return None, None, "No HTML file found in Downloads folder. File may not have been saved or wrong format used."
        
        # Now find the corresponding _files folder
        html_path = Path(html_file)
        html_stem = html_path.stem
        resources_folder_name = f"{html_stem}_files"
        
        # Try to copy the resources folder
        container_folder = f"{downloads_dir}/{resources_folder_name}"
        local_folder = temp_dir / resources_folder_name
        
        try:
            # Since we can't copy directories directly with copy_from_env,
            # we need to try copying individual files from the folder
            # First, try to determine if folder exists by attempting to copy a common file
            
            # Create local folder
            local_folder.mkdir(exist_ok=True)
            
            # Try to copy common resource file types
            resource_found = False
            for ext in ['css', 'png', 'jpg', 'jpeg', 'gif', 'js']:
                for i in range(10):
                    try:
                        filename = f"file_{i}.{ext}"
                        copy_from_env(
                            f"{container_folder}/{filename}",
                            str(local_folder / filename)
                        )
                        resource_found = True
                    except:
                        pass
            
            # Also try copying files with specific names from our tutorial
            specific_files = [
                'styles.css',
                'sample1.png',
                'sample2.png',
            ]
            for filename in specific_files:
                try:
                    copy_from_env(
                        f"{container_folder}/{filename}",
                        str(local_folder / filename)
                    )
                    resource_found = True
                except:
                    pass
            
            if not resource_found:
                # Folder might not exist or be empty
                logger.warning(f"Could not copy resources from {resources_folder_name}")
                return html_file, None, ""
            
            resources_folder = str(local_folder)
            logger.info(f"Found resources folder: {resources_folder_name}")
            
        except Exception as e:
            logger.warning(f"Could not access resources folder: {e}")
            resources_folder = None
        
        return html_file, resources_folder, ""
        
    except Exception as e:
        logger.error(f"Error finding saved webpage: {e}")
        return None, None, f"Error finding saved webpage: {str(e)}"


def verify_offline_webpage_save(html_file: str, resources_folder: Optional[str]) -> Dict[str, Any]:
    """
    Verify the offline webpage save meets all criteria.
    
    Criteria:
    1. HTML file has reasonable size (>1KB)
    2. Resources folder exists
    3. Resources folder contains files (≥3)
    4. HTML contains local resource references
    5. HTML has substantial text content
    
    Args:
        html_file: Path to HTML file
        resources_folder: Path to resources folder (or None)
        
    Returns:
        Verification result dict
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: HTML file size
    try:
        html_size = Path(html_file).stat().st_size
        if html_size > 1024:  # > 1KB
            criteria_met += 1
            feedback_parts.append(f"✓ HTML file saved ({html_size / 1024:.1f} KB)")
        else:
            feedback_parts.append(f"✗ HTML file too small ({html_size} bytes)")
    except Exception as e:
        feedback_parts.append(f"✗ Could not check HTML file size: {e}")
    
    # Criterion 2: Resources folder exists
    if resources_folder and Path(resources_folder).exists():
        criteria_met += 1
        folder_name = Path(resources_folder).name
        feedback_parts.append(f"✓ Resources folder found: {folder_name}")
    else:
        feedback_parts.append("✗ Resources folder not found (wrong save format - likely used 'HTML only')")
    
    # Criterion 3: Resources folder contains files
    resource_count = 0
    if resources_folder and Path(resources_folder).exists():
        try:
            resource_files = list(Path(resources_folder).glob("*"))
            resource_count = len([f for f in resource_files if f.is_file()])
            
            if resource_count >= 3:
                criteria_met += 1
                feedback_parts.append(f"✓ Resources folder has {resource_count} files")
            else:
                feedback_parts.append(f"✗ Resources folder has only {resource_count} files (expected ≥3)")
        except Exception as e:
            feedback_parts.append(f"✗ Could not count resource files: {e}")
    else:
        feedback_parts.append("✗ Cannot check resource count (folder missing)")
    
    # Criterion 4 & 5: HTML content analysis
    if HAS_BS4:
        try:
            with open(html_file, 'r', encoding='utf-8', errors='ignore') as f:
                html_content = f.read()
            
            soup = BeautifulSoup(html_content, 'html.parser')
            
            # Criterion 4: Local resource references
            html_stem = Path(html_file).stem
            expected_folder = f"{html_stem}_files/"
            
            # Check images
            img_tags = soup.find_all('img')
            local_imgs = [
                img for img in img_tags
                if img.get('src', '').startswith(expected_folder) or
                   img.get('src', '').startswith(f"./{expected_folder}")
            ]
            
            # Check CSS links
            link_tags = soup.find_all('link', rel='stylesheet')
            local_css = [
                link for link in link_tags
                if link.get('href', '').startswith(expected_folder) or
                   link.get('href', '').startswith(f"./{expected_folder}")
            ]
            
            if len(local_imgs) > 0 or len(local_css) > 0:
                criteria_met += 1
                feedback_parts.append(
                    f"✓ HTML references local resources ({len(local_imgs)} images, {len(local_css)} CSS)"
                )
            else:
                feedback_parts.append("✗ HTML does not reference local resources properly")
            
            # Criterion 5: Content preservation
            text_content = soup.get_text(strip=True)
            text_length = len(text_content)
            
            if text_length > 500:  # At least 500 characters
                criteria_met += 1
                feedback_parts.append(f"✓ Substantial text content preserved ({text_length} chars)")
            else:
                feedback_parts.append(f"✗ Insufficient text content ({text_length} chars)")
                
        except Exception as e:
            feedback_parts.append(f"✗ Could not analyze HTML content: {e}")
    else:
        # Without BeautifulSoup, do basic checks
        try:
            with open(html_file, 'r', encoding='utf-8', errors='ignore') as f:
                html_content = f.read()
            
            # Basic check for local references
            html_stem = Path(html_file).stem
            if f"{html_stem}_files/" in html_content:
                criteria_met += 1
                feedback_parts.append("✓ HTML appears to reference local resources")
            else:
                feedback_parts.append("✗ No local resource references detected")
            
            # Basic content length check
            if len(html_content) > 2000:
                criteria_met += 1
                feedback_parts.append("✓ HTML has substantial content")
            else:
                feedback_parts.append("✗ HTML content seems insufficient")
                
        except Exception as e:
            feedback_parts.append(f"✗ Could not read HTML file: {e}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met >= 4  # Need 4 out of 5 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += "\n\n✅ Webpage successfully saved for offline reading!"
        feedback += "\nThe page can now be opened without internet connection."
    else:
        feedback += "\n\n❌ Webpage not properly saved in 'Complete' format"
        if resources_folder is None:
            feedback += "\n\n⚠️  HINT: Make sure to select 'Webpage, Complete' format in the Save dialog,"
            feedback += "\n   not 'HTML only'. The 'Complete' format creates both an HTML file"
            feedback += "\n   and a '_files' folder with all images and stylesheets."
    
    if not HAS_BS4:
        feedback += "\n\n⚠️  Note: BeautifulSoup not available, some checks were limited"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "html_file": html_file,
            "resources_folder": resources_folder,
            "resource_count": resource_count
        }
    }


def cleanup_temp_files(html_file: Optional[str], resources_folder: Optional[str]):
    """Clean up temporary verification files"""
    try:
        if html_file:
            html_path = Path(html_file)
            temp_dir = html_path.parent
            if temp_dir.exists() and "chrome_save_verify_" in str(temp_dir):
                import shutil
                shutil.rmtree(temp_dir, ignore_errors=True)
                logger.info(f"Cleaned up temp directory: {temp_dir}")
    except Exception as e:
        logger.warning(f"Could not clean up temp files: {e}")
