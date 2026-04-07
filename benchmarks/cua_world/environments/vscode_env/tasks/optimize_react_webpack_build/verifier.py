#!/usr/bin/env python3
"""
Verifier for the optimize_react_webpack_build task.

Checks whether the agent successfully implemented 5 build optimizations:
1. CSS Extraction
2. Vendor Chunking
3. Component Lazy Loading
4. Moment Locale Stripping
5. Lodash Tree-Shaking

Gatekeeper: Application tests must pass. If they fail, score is 0.
"""

import os
import json
import re
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_webpack_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/webpack_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Check gatekeepers
    test_passed = result.get('test_passed', False)
    build_passed = result.get('build_passed', False)
    
    if not build_passed:
        return {"passed": False, "score": 0, "feedback": "Build failed. Webpack configuration is invalid."}
        
    if not test_passed:
        return {"passed": False, "score": 0, "feedback": "Tests failed. Application logic was broken during optimization."}

    sources = result.get('sources', {})
    webpack_src = sources.get('webpack.config.js', '')
    app_src = sources.get('src/App.js', '')
    formatters_src = sources.get('src/utils/formatters.js', '')
    
    dist_js_count = result.get('dist_js_count', 0)
    dist_css_count = result.get('dist_css_count', 0)

    # 1. CSS Extracted (20 pts)
    has_minicss_loader = 'MiniCssExtractPlugin.loader' in webpack_src
    has_minicss_plugin = 'new MiniCssExtractPlugin' in webpack_src
    if has_minicss_loader and has_minicss_plugin and dist_css_count > 0:
        score += 20
        feedback.append("[+] CSS successfully extracted")
    else:
        feedback.append("[-] CSS extraction incomplete or missing")

    # 2. Vendor Code Split (20 pts)
    has_split_chunks = 'splitChunks' in webpack_src or 'chunks: "all"' in webpack_src or "chunks: 'all'" in webpack_src
    if has_split_chunks and dist_js_count >= 2:
        score += 20
        feedback.append("[+] Vendor code successfully split into chunks")
    else:
        feedback.append("[-] Vendor splitting incomplete or missing")

    # 3. Component Lazy Loaded (20 pts)
    has_lazy = 'React.lazy' in app_src or 'lazy(' in app_src
    has_suspense = '<Suspense' in app_src
    no_static_import = 'import InteractiveMap from' not in app_src
    if has_lazy and has_suspense and no_static_import:
        score += 20
        feedback.append("[+] InteractiveMap successfully lazy loaded")
    else:
        feedback.append("[-] Lazy loading implementation incomplete or incorrect")

    # 4. Moment Locales Stripped (20 pts)
    has_ignore_plugin = 'IgnorePlugin' in webpack_src and 'moment' in webpack_src
    has_context_plugin = 'ContextReplacementPlugin' in webpack_src and 'moment' in webpack_src
    if has_ignore_plugin or has_context_plugin:
        score += 20
        feedback.append("[+] Moment locales successfully ignored")
    else:
        feedback.append("[-] Moment locales not ignored in Webpack")

    # 5. Lodash Tree-Shaken (20 pts)
    has_full_import = re.search(r"import\s+_\s+from\s+['\"]lodash['\"]", formatters_src)
    has_specific_import = re.search(r"import\s+(?:\{\s*debounce\s*\}|debounce)\s+from\s+['\"]lodash(?:/debounce)?['\"]", formatters_src)
    
    if not has_full_import and has_specific_import:
        score += 20
        feedback.append("[+] Lodash import successfully tree-shaken")
    else:
        feedback.append("[-] Lodash full import still present or debounce not properly imported")

    # VLM Verification
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_prompt = "Looking at this sequence of screenshots from a VS Code session, does it show the user editing webpack.config.js or React source files to optimize performance?"
            vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
            if vlm_res and "yes" in vlm_res.get('text', '').lower():
                feedback.append("[+] VLM verified trajectory matches task intent")
            else:
                feedback.append("[-] VLM could not confirm proper VS Code usage")

    threshold = task_info.get('metadata', {}).get('pass_threshold', 60)
    passed = score >= threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }