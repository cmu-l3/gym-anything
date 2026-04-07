#!/usr/bin/env python3
"""Verifier for Clickstream Funnel Analysis task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used."""
    if not gui_evidence:
        return False, 0.0, "No GUI evidence"
    signals = 0
    details = []
    if gui_evidence.get('mru_connection_count', 0) > 0:
        signals += 1
        details.append(f"MRU:{gui_evidence['mru_connection_count']}")
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:
        signals += 1
        details.append(f"sessions:{gui_evidence['sqldev_oracle_sessions']}")
    if gui_evidence.get('sql_history_count', 0) > 0:
        signals += 1
        details.append(f"history:{gui_evidence['sql_history_count']}")
    gui_used = signals >= 2
    return gui_used, min(signals / 3, 1.0), "; ".join(details) or "No signals"


def verify_clickstream_funnel_analysis(traj, env_info, task_info):
    """
    Verify Clickstream Funnel Analysis task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/clickstream_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Extract variables
        user_sessions_exists = result.get('user_sessions_exists', False)
        user_sessions_rows = result.get('user_sessions_rows', 0)
        funnel_patterns_exists = result.get('funnel_patterns_exists', False)
        funnel_patterns_rows = result.get('funnel_patterns_rows', 0)
        pattern_types_count = result.get('pattern_types_count', 0)
        user_segments_exists = result.get('user_segments_exists', False)
        user_segments_rows = result.get('user_segments_rows', 0)
        conversion_vw_exists = result.get('conversion_vw_exists', False)
        engagement_mv_exists = result.get('engagement_mv_exists', False)
        window_func_used = result.get('window_func_used', False)
        pattern_match_used = result.get('pattern_match_used', False)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        gui_evidence = result.get('gui_evidence', {})

        # 1. User Sessions (20 pts)
        if user_sessions_exists and user_sessions_rows > 100:
            score += 20
            feedback_parts.append(f"USER_SESSIONS populated with {user_sessions_rows} rows (20/20)")
        elif user_sessions_exists:
            score += 10
            feedback_parts.append(f"USER_SESSIONS exists but empty or low row count (10/20)")
        else:
            feedback_parts.append("USER_SESSIONS table missing (0/20)")

        # 2. Funnel Patterns (20 pts)
        if funnel_patterns_exists and funnel_patterns_rows > 10 and pattern_types_count >= 2:
            score += 20
            feedback_parts.append(f"FUNNEL_PATTERNS populated with {pattern_types_count} pattern types (20/20)")
        elif funnel_patterns_exists and funnel_patterns_rows > 0:
            score += 10
            feedback_parts.append("FUNNEL_PATTERNS exists but lacks diverse pattern types (10/20)")
        else:
            feedback_parts.append("FUNNEL_PATTERNS table missing or empty (0/20)")

        # 3. User Segments (10 pts)
        if user_segments_exists and user_segments_rows >= 500:
            score += 10
            feedback_parts.append(f"USER_SEGMENTS populated with {user_segments_rows} rows (10/10)")
        elif user_segments_exists:
            score += 5
            feedback_parts.append("USER_SEGMENTS exists but low row count (5/10)")
        else:
            feedback_parts.append("USER_SEGMENTS table missing (0/10)")

        # 4. Conversion View (10 pts)
        if conversion_vw_exists:
            score += 10
            feedback_parts.append("CONVERSION_FUNNEL_VW exists (10/10)")
        else:
            feedback_parts.append("CONVERSION_FUNNEL_VW missing (0/10)")

        # 5. Dashboard MV & Window functions (15 pts)
        if engagement_mv_exists and window_func_used:
            score += 15
            feedback_parts.append("ENGAGEMENT_DASHBOARD_MV exists with window functions (15/15)")
        elif engagement_mv_exists:
            score += 8
            feedback_parts.append("ENGAGEMENT_DASHBOARD_MV exists but no window functions detected (8/15)")
        else:
            feedback_parts.append("ENGAGEMENT_DASHBOARD_MV missing (0/15)")

        # 6. Advanced SQL (10 pts)
        if pattern_match_used:
            score += 10
            feedback_parts.append("Advanced gap detection (MATCH_RECOGNIZE/LAG/LEAD) used (10/10)")
        else:
            feedback_parts.append("No advanced pattern matching detected (0/10)")

        # 7. CSV Export (5 pts)
        if csv_exists and csv_size > 50:
            score += 5
            feedback_parts.append("funnel_report.csv exported successfully (5/5)")
        else:
            feedback_parts.append("funnel_report.csv missing or too small (0/5)")

        # 8. GUI Usage (10 pts)
        gui_used, gui_score_mult, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(10 * gui_score_mult)
        score += gui_pts
        if gui_used:
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] ({gui_pts}/10)")
        else:
            feedback_parts.append(f"Limited/No GUI usage [{gui_details}] ({gui_pts}/10)")

        # Optional: VLM Verification using trajectory frames
        if query_vlm:
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=3) if isinstance(traj, list) else []
                final = get_final_screenshot(traj) if isinstance(traj, list) else None
                images = frames + ([final] if final else [])
                
                if images:
                    prompt = """Examine these screenshots of an agent using Oracle SQL Developer.
                    Did the agent successfully write and execute SQL queries relating to funnels, clickstreams, or sessions, AND view the results in the grid?
                    Respond in JSON format: {"sql_executed": true/false, "results_viewed": true/false}"""
                    
                    vlm_res = query_vlm(images=images, prompt=prompt)
                    if vlm_res.get("success") and vlm_res.get("parsed"):
                        parsed = vlm_res["parsed"]
                        if parsed.get("sql_executed") and parsed.get("results_viewed"):
                            feedback_parts.append("VLM confirmed SQL execution and result viewing.")
            except ImportError:
                logger.warning("VLM framework helpers unavailable. Skipping VLM check.")
            except Exception as e:
                logger.warning(f"VLM verification error: {e}")

        # Final Evaluation
        # Must score at least 60 AND core table (USER_SESSIONS) must exist
        passed = score >= 60 and user_sessions_exists and user_sessions_rows > 100

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {str(e)}"}