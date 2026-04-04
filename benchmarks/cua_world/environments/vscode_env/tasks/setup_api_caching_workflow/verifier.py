#!/usr/bin/env python3
"""
Verifier for API Caching Workflow Setup task
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    get_installed_extensions,
    check_extension_installed,
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_api_caching_setup(traj, env_info, task_info):
    """
    Verify that API caching workflow was set up correctly.
    
    Checks (7 total, need 5+ to pass):
    1. REST client extension installed
    2. Request files created (.http, .rest, or equivalent)
    3. Cache directory structure exists
    4. Multiple cached responses (5+ JSON files)
    5. Configuration setup (.env or config with cache settings)
    6. Workflow documented (README or comments)
    7. Response diversity (success and error responses)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='api_cache_verify_')
    
    try:
        criteria_passed = 0
        feedback_parts = []
        
        # ========================================
        # Criterion 1: REST Client Extension Installed
        # ========================================
        extensions_ids_path = os.path.join(temp_dir, "extensions_ids.txt")
        try:
            copy_from_env("/tmp/extensions_ids.txt", extensions_ids_path)
            
            rest_client_found = False
            if os.path.exists(extensions_ids_path) and os.path.getsize(extensions_ids_path) > 0:
                with open(extensions_ids_path, 'r') as f:
                    content = f.read().lower()
                    rest_clients = [
                        'rest-client',
                        'humao.rest-client',
                        'thunder-client',
                        'rangav.vscode-thunder-client',
                        'postman',
                        'postman.postman-for-vscode',
                        'httpyac'
                    ]
                    for client in rest_clients:
                        if client in content:
                            rest_client_found = True
                            feedback_parts.append(f"✅ REST client extension found: {client}")
                            break
            
            if rest_client_found:
                criteria_passed += 1
            else:
                feedback_parts.append("❌ No REST client extension installed")
        except Exception as e:
            logger.warning(f"Failed to check extensions: {e}")
            feedback_parts.append("❌ Could not verify REST client extension")
        
        # ========================================
        # Criterion 2: Request Files Created
        # ========================================
        request_files_path = os.path.join(temp_dir, "request_files_list.txt")
        request_files_found = False
        try:
            copy_from_env("/tmp/request_files_list.txt", request_files_path)
            
            if os.path.exists(request_files_path):
                with open(request_files_path, 'r') as f:
                    content = f.read().strip()
                    if content:
                        request_files = [line for line in content.split('\n') if line.strip()]
                        if request_files:
                            request_files_found = True
                            criteria_passed += 1
                            feedback_parts.append(f"✅ Request files found: {len(request_files)} file(s)")
        except Exception as e:
            logger.warning(f"Failed to check request files: {e}")
        
        if not request_files_found:
            feedback_parts.append("❌ No .http or .rest request files found")
        
        # ========================================
        # Criterion 3: Cache Directory Structure
        # ========================================
        cache_dirs_path = os.path.join(temp_dir, "cache_dirs_found.txt")
        cache_dir_found = False
        try:
            copy_from_env("/tmp/cache_dirs_found.txt", cache_dirs_path)
            
            if os.path.exists(cache_dirs_path):
                with open(cache_dirs_path, 'r') as f:
                    content = f.read().strip()
                    if content and "Found cache directory:" in content:
                        cache_dir_found = True
                        criteria_passed += 1
                        # Extract directory name
                        for line in content.split('\n'):
                            if "Found cache directory:" in line:
                                dir_name = line.split(':')[-1].strip()
                                feedback_parts.append(f"✅ Cache directory found: {dir_name}/")
                                break
        except Exception as e:
            logger.warning(f"Failed to check cache directory: {e}")
        
        if not cache_dir_found:
            feedback_parts.append("❌ No cache directory (responses/mocks/cache) found")
        
        # ========================================
        # Criterion 4: Multiple Cached Responses (5+ JSON files)
        # ========================================
        json_files_path = os.path.join(temp_dir, "json_files_list.txt")
        cached_responses_count = 0
        json_files = []
        try:
            copy_from_env("/tmp/json_files_list.txt", json_files_path)
            
            if os.path.exists(json_files_path):
                with open(json_files_path, 'r') as f:
                    content = f.read().strip()
                    if content:
                        all_json_files = [line.strip() for line in content.split('\n') if line.strip()]
                        
                        # Filter to only cache directory JSON files
                        cache_keywords = ['responses', 'mocks', 'cache', 'api_cache']
                        for filepath in all_json_files:
                            # Exclude known config files
                            filename = os.path.basename(filepath).lower()
                            if filename in ['api_config.json', 'sample_response_format.json', 'package.json', 'package-lock.json', 'tsconfig.json']:
                                continue
                            
                            # Check if file is in a cache directory
                            filepath_lower = filepath.lower()
                            if any(keyword in filepath_lower for keyword in cache_keywords):
                                json_files.append(filepath)
                        
                        cached_responses_count = len(json_files)
            
            if cached_responses_count >= 5:
                criteria_passed += 1
                feedback_parts.append(f"✅ Sufficient cached responses: {cached_responses_count} JSON files")
            elif cached_responses_count > 0:
                feedback_parts.append(f"⚠️ Only {cached_responses_count} cached responses (need 5+)")
            else:
                feedback_parts.append("❌ No cached response JSON files found")
        except Exception as e:
            logger.warning(f"Failed to check JSON files: {e}")
            feedback_parts.append("❌ Could not verify cached responses")
        
        # ========================================
        # Criterion 5: Configuration Setup
        # ========================================
        env_file_path = os.path.join(temp_dir, "env_file_export.txt")
        config_found = False
        try:
            copy_from_env("/tmp/env_file_export.txt", env_file_path)
            
            if os.path.exists(env_file_path):
                with open(env_file_path, 'r') as f:
                    content = f.read().strip()
                    if content and content != "No .env file":
                        # Check for cache-related configuration
                        content_lower = content.lower()
                        has_cache_config = (
                            'cache' in content_lower or
                            'use_cache' in content_lower or
                            'cache_dir' in content_lower or
                            'cache_mode' in content_lower
                        )
                        
                        if has_cache_config:
                            config_found = True
                            criteria_passed += 1
                            feedback_parts.append("✅ Configuration file with cache settings found (.env)")
        except Exception as e:
            logger.warning(f"Failed to check .env file: {e}")
        
        # Check api_config.json as alternative
        if not config_found:
            try:
                api_config_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
                copy_from_env("/home/ga/workspace/weather_app/api_config.json", api_config_temp.name)
                
                if os.path.exists(api_config_temp.name):
                    with open(api_config_temp.name, 'r') as f:
                        api_config = json.load(f)
                        if 'cache' in json.dumps(api_config).lower():
                            config_found = True
                            criteria_passed += 1
                            feedback_parts.append("✅ Configuration with cache settings found (api_config.json)")
                
                os.unlink(api_config_temp.name)
            except:
                pass
        
        if not config_found:
            feedback_parts.append("❌ No configuration file with cache settings (.env or config)")
        
        # ========================================
        # Criterion 6: Workflow Documented
        # ========================================
        readme_files_path = os.path.join(temp_dir, "readme_files_list.txt")
        documentation_found = False
        try:
            copy_from_env("/tmp/readme_files_list.txt", readme_files_path)
            
            if os.path.exists(readme_files_path):
                with open(readme_files_path, 'r') as f:
                    content = f.read().strip()
                    if content:
                        readme_files = [line.strip() for line in content.split('\n') if line.strip()]
                        
                        # Check for cache-specific documentation
                        for readme_path in readme_files:
                            filename = os.path.basename(readme_path).lower()
                            # Look for cache-specific README or generic README/DEVELOPMENT docs
                            if 'cache' in filename or 'development' in filename or filename == 'readme.md':
                                # Copy and check content
                                try:
                                    readme_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.md')
                                    copy_from_env(readme_path, readme_temp.name)
                                    
                                    with open(readme_temp.name, 'r') as rf:
                                        readme_content = rf.read().lower()
                                        # Check if it discusses caching workflow
                                        if 'cache' in readme_content and ('workflow' in readme_content or 'toggle' in readme_content or 'response' in readme_content):
                                            documentation_found = True
                                            criteria_passed += 1
                                            feedback_parts.append(f"✅ Workflow documentation found: {os.path.basename(readme_path)}")
                                            os.unlink(readme_temp.name)
                                            break
                                    
                                    os.unlink(readme_temp.name)
                                except:
                                    pass
        except Exception as e:
            logger.warning(f"Failed to check documentation: {e}")
        
        # Check for substantial comments in .http files as alternative
        if not documentation_found and request_files_found:
            try:
                with open(request_files_path, 'r') as f:
                    request_file_paths = [line.strip() for line in f.readlines() if line.strip()]
                    
                for req_path in request_file_paths[:3]:  # Check first 3 request files
                    try:
                        req_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.http')
                        copy_from_env(req_path, req_temp.name)
                        
                        with open(req_temp.name, 'r') as rf:
                            req_content = rf.read()
                            # Count comment lines (lines starting with #)
                            comment_lines = [line for line in req_content.split('\n') if line.strip().startswith('#')]
                            
                            # If substantial comments (5+ lines) discussing cache
                            if len(comment_lines) >= 5:
                                req_content_lower = req_content.lower()
                                if 'cache' in req_content_lower:
                                    documentation_found = True
                                    criteria_passed += 1
                                    feedback_parts.append(f"✅ Workflow documented in {os.path.basename(req_path)} comments")
                                    os.unlink(req_temp.name)
                                    break
                        
                        os.unlink(req_temp.name)
                    except:
                        pass
            except:
                pass
        
        if not documentation_found:
            feedback_parts.append("❌ No workflow documentation found (cache_README.md or comments)")
        
        # ========================================
        # Criterion 7: Response Diversity (success and error responses)
        # ========================================
        response_diversity = False
        if cached_responses_count > 0 and json_files:
            try:
                has_error_response = False
                has_success_response = False
                
                # Check filenames for error indicators
                for filepath in json_files:
                    filename_lower = os.path.basename(filepath).lower()
                    
                    # Error response indicators
                    error_indicators = ['error', '404', '429', '500', 'invalid', 'rate', 'limit']
                    if any(indicator in filename_lower for indicator in error_indicators):
                        has_error_response = True
                    
                    # Success response indicators (city names or success/200)
                    success_indicators = ['london', 'tokyo', 'paris', 'new york', 'sydney', 
                                         'berlin', 'mumbai', 'success', '200', 'sunny', 'rainy', 'cloudy']
                    if any(indicator in filename_lower for indicator in success_indicators):
                        has_success_response = True
                
                # Also try to parse a few JSON files to check content
                for filepath in json_files[:5]:  # Check first 5 files
                    try:
                        json_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
                        copy_from_env(filepath, json_temp.name)
                        
                        with open(json_temp.name, 'r') as jf:
                            data = json.load(jf)
                            
                            # Check for error response indicators in content
                            if isinstance(data, dict):
                                if 'cod' in data:
                                    cod = str(data['cod'])
                                    if cod in ['404', '429', '500', '401']:
                                        has_error_response = True
                                    elif cod == '200':
                                        has_success_response = True
                                
                                if 'error' in data or 'message' in data:
                                    if 'error' in str(data.get('message', '')).lower():
                                        has_error_response = True
                        
                        os.unlink(json_temp.name)
                    except:
                        pass
                
                if has_error_response and has_success_response:
                    response_diversity = True
                    criteria_passed += 1
                    feedback_parts.append("✅ Response diversity: both success and error responses cached")
                elif has_error_response:
                    feedback_parts.append("⚠️ Only error responses found (need success responses too)")
                elif has_success_response:
                    feedback_parts.append("⚠️ Only success responses found (need error responses too)")
                else:
                    feedback_parts.append("⚠️ Could not determine response types from filenames/content")
            except Exception as e:
                logger.warning(f"Failed to check response diversity: {e}")
                feedback_parts.append("⚠️ Could not verify response diversity")
        elif cached_responses_count == 0:
            feedback_parts.append("❌ No responses to check for diversity")
        
        # ========================================
        # Calculate Score
        # ========================================
        score = int((criteria_passed / 7) * 100)
        passed = score >= 71  # Need 5/7 criteria (71%)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": f"Passed {criteria_passed}/7 criteria. {feedback}"
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
