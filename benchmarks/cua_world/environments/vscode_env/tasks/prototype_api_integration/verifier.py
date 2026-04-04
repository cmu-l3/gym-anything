#!/usr/bin/env python3
"""
Verifier for Prototype API Integration task
Checks that student successfully prototyped OpenWeatherMap API integration
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_api_prototype(traj, env_info, task_info):
    """
    Verify API integration prototype task.
    
    Checks:
    1. HTTP file exists and has substantial content (2 points)
    2. API key configured (not placeholder) (1 point)
    3. Multiple endpoints tested (3 points - 1 per endpoint)
    4. Different query patterns (1.5 points)
    5. Documentation via comments (1.5 points)
    6. Multiple requests defined (1 point)
    
    Bonuses:
    - Error handling documented (+0.5)
    - Response examples saved (+0.5)
    
    Total: 10 base points + 1 bonus = 11 max
    Pass threshold: 70% of base (7/10)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/tmp/weather_api.http"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.http', mode='w+')
    temp_dir = tempfile.mkdtemp(prefix='api_verify_')
    
    try:
        # Copy the HTTP file
        try:
            copy_from_env(container_path, temp_file.name)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"❌ Failed to copy weather_api.http: {str(e)}"
            }
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ HTTP request file not found or empty"
            }
        
        content = read_file_content(temp_file.name)
        
        if not content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ HTTP request file is empty"
            }
        
        score = 0.0
        max_score = 10.0
        feedback_parts = []
        metadata = {}
        
        # Check 1: File has substantial content (not just template) (2 points)
        if "TODO: Complete this request" in content or "TODO: Test current weather" in content:
            feedback_parts.append("❌ HTTP file appears incomplete (still has TODOs)")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        if len(content) < 300:
            feedback_parts.append(f"❌ HTTP file too short ({len(content)} chars, expected 300+)")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        feedback_parts.append(f"✅ HTTP request file created ({len(content)} chars)")
        score += 2.0
        
        # Check 2: API key configured (not placeholder) (1 point)
        has_placeholder = "YOUR_API_KEY" in content
        has_real_key = bool(re.search(r'(@apiKey\s*=\s*[a-f0-9]{32}|appid=[a-f0-9]{32})', content, re.IGNORECASE))
        
        if has_placeholder and not has_real_key:
            feedback_parts.append("⚠️ API key not replaced (still has YOUR_API_KEY placeholder)")
        elif has_real_key:
            feedback_parts.append("✅ API key configured")
            score += 1.0
        else:
            # Check if key is in variable or directly in URL
            if re.search(r'appid\s*=\s*\w{32}', content) or re.search(r'@apiKey\s*=\s*\w+', content):
                feedback_parts.append("✅ API key present")
                score += 1.0
            else:
                feedback_parts.append("⚠️ API key format unclear (0.5 points)")
                score += 0.5
        
        # Check 3: Multiple endpoints tested (3 points - 1 per endpoint)
        endpoints_found = []
        
        # Current weather endpoint
        if re.search(r'(GET|POST)\s+[^\n]*/(weather|current)(\?|$|\s)', content, re.IGNORECASE | re.MULTILINE):
            endpoints_found.append("current weather")
            score += 1.0
        
        # Forecast endpoint
        if re.search(r'(GET|POST)\s+[^\n]*/forecast(\?|$|\s)', content, re.IGNORECASE | re.MULTILINE):
            endpoints_found.append("forecast")
            score += 1.0
        
        # Geocoding endpoint
        if re.search(r'(GET|POST)\s+[^\n]*/(geo|geocoding)', content, re.IGNORECASE | re.MULTILINE):
            endpoints_found.append("geocoding")
            score += 1.0
        
        if endpoints_found:
            feedback_parts.append(f"✅ Tested {len(endpoints_found)} endpoint(s): {', '.join(endpoints_found)}")
            metadata['endpoints_tested'] = endpoints_found
        else:
            feedback_parts.append("❌ No recognizable API endpoints found")
        
        # Check 4: Different query patterns used (1.5 points)
        has_city_query = bool(re.search(r'[?&]q=', content))
        has_coord_query = bool(re.search(r'[?&](lat|lon)=', content))
        has_units = bool(re.search(r'[?&]units=', content))
        
        query_patterns = []
        pattern_score = 0.0
        
        if has_city_query:
            query_patterns.append("city name")
            pattern_score += 0.5
        if has_coord_query:
            query_patterns.append("coordinates")
            pattern_score += 0.5
        if has_units:
            query_patterns.append("units parameter")
            pattern_score += 0.5
        
        score += pattern_score
        
        if query_patterns:
            feedback_parts.append(f"✅ Used query patterns: {', '.join(query_patterns)} (+{pattern_score:.1f})")
        else:
            feedback_parts.append("⚠️ Limited query pattern variety")
        
        # Check 5: Documentation via comments (1.5 points)
        comment_lines = [line for line in content.split('\n') if line.strip().startswith('#')]
        
        doc_score = 0.0
        if len(comment_lines) >= 5:
            feedback_parts.append(f"✅ Well documented ({len(comment_lines)} comment lines)")
            doc_score = 1.5
        elif len(comment_lines) >= 3:
            feedback_parts.append(f"⚠️ Some documentation ({len(comment_lines)} comment lines)")
            doc_score = 0.75
        elif len(comment_lines) >= 1:
            feedback_parts.append(f"⚠️ Minimal documentation ({len(comment_lines)} comment lines)")
            doc_score = 0.3
        else:
            feedback_parts.append("❌ No documentation comments found")
        
        score += doc_score
        
        # Check 6: Multiple requests defined (1 point)
        # REST Client uses ### as request separator
        request_count = content.count('###')
        
        if request_count >= 3:
            feedback_parts.append(f"✅ Multiple requests defined ({request_count} sections)")
            score += 1.0
            metadata['request_count'] = request_count
        elif request_count >= 2:
            feedback_parts.append(f"⚠️ Only {request_count} request sections (+0.5)")
            score += 0.5
        elif request_count >= 1:
            feedback_parts.append(f"⚠️ Only {request_count} request section (+0.25)")
            score += 0.25
        else:
            feedback_parts.append("❌ No request separators (###) found")
        
        # Bonus: Check if error handling discussed
        has_error_handling = bool(re.search(r'(error|401|404|429|invalid|missing)', content, re.IGNORECASE))
        if has_error_handling:
            feedback_parts.append("🌟 Bonus: Error cases documented (+0.5)")
            score += 0.5
            max_score += 0.5
        
        # Bonus: Check for substantial request bodies or multiple methods
        has_multiple_methods = bool(re.search(r'(GET|POST|PUT|DELETE|PATCH)', content, re.IGNORECASE))
        method_count = len(re.findall(r'^(GET|POST|PUT|DELETE|PATCH)\s+', content, re.IGNORECASE | re.MULTILINE))
        if method_count >= 3:
            feedback_parts.append(f"🌟 Bonus: Multiple HTTP requests ({method_count} methods) (+0.5)")
            score += 0.5
            max_score += 0.5
        
        # Normalize score
        normalized_score = min(score / max_score, 1.0)
        success = score >= 7.0  # 70% of base 10 points
        
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\n📊 Score: {score:.1f}/{max_score:.1f} ({normalized_score*100:.0f}%)"
        
        if success:
            feedback += "\n\n✅ Task completed successfully! API integration prototype is ready for team review."
        else:
            feedback += "\n\n❌ Task incomplete. The prototype needs more comprehensive endpoint testing and documentation."
            feedback += "\n\nRequired improvements:"
            if len(endpoints_found) < 3:
                feedback += f"\n  - Test all 3 required endpoints (current: {len(endpoints_found)})"
            if pattern_score < 1.0:
                feedback += "\n  - Use more query patterns (city name, coordinates, units)"
            if doc_score < 1.0:
                feedback += "\n  - Add more documentation comments"
            if request_count < 3:
                feedback += "\n  - Separate requests with ### markers"
        
        return {
            "passed": success,
            "score": int(normalized_score * 100),
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
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
