#!/usr/bin/env python3
import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_daily_minmax(traj, env_info, task_info):
    """
    Verifies that the Emoncms input processing pipeline is correctly configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define standard Emoncms process IDs
    PROC_LOG_TO_FEED = 1
    PROC_MAX_DAILY = 22
    PROC_MIN_DAILY = 23
    PROC_RESET_ORIGINAL = 24
    
    # Expected settings
    EXPECTED_FEEDS = {
        'greenhouse_temp_raw': {'required_process': PROC_LOG_TO_FEED},
        'greenhouse_temp_max': {'required_process': PROC_MAX_DAILY},
        'greenhouse_temp_min': {'required_process': PROC_MIN_DAILY}
    }

    try:
        # Load result from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
        
        score = 0
        feedback = []
        
        # 1. Check Input Existence
        if result.get('input_found') is False:
            return {"passed": False, "score": 0, "feedback": "Input 'greenhouse_temp' not found in database."}

        # 2. Parse Feeds
        feeds = {f['name']: f for f in result.get('feeds', [])}
        feed_ids = {str(f['id']): f['name'] for f in result.get('feeds', [])}
        
        # Check if all required feeds exist
        feeds_score = 0
        missing_feeds = []
        for fname in EXPECTED_FEEDS:
            if fname in feeds:
                f = feeds[fname]
                # Check Engine and Interval
                if f['engine'] == 5 and f['interval'] == 10:
                    feeds_score += 20 # Full points for correct feed
                else:
                    feeds_score += 10 # Partial points for wrong settings
                    feedback.append(f"Feed '{fname}' exists but has wrong settings (expected PHPFina/10s).")
            else:
                missing_feeds.append(fname)
        
        if missing_feeds:
            feedback.append(f"Missing feeds: {', '.join(missing_feeds)}")
        else:
            feedback.append("All required feeds created.")
            
        score += feeds_score

        # 3. Parse Pipeline Logic
        # processList string format: "pid:arg,pid:arg,..."
        raw_plist = result.get('process_list_str', "")
        pipeline = []
        
        if raw_plist:
            steps = raw_plist.split(',')
            for step in steps:
                if ':' in step:
                    pid, arg = step.split(':', 1)
                    try:
                        pipeline.append({'pid': int(pid), 'arg': arg})
                    except ValueError:
                        pass
        
        # Verify processes are linked to correct feeds
        pipeline_score = 0
        linked_feeds = set()
        
        # We need to map feed arguments in pipeline back to feed names to verify logic
        pipeline_names = []
        
        for step in pipeline:
            pid = step['pid']
            arg = str(step['arg'])
            fname = feed_ids.get(arg, "unknown_feed")
            
            step_desc = ""
            if pid == PROC_LOG_TO_FEED:
                step_desc = "Log"
                if fname == 'greenhouse_temp_raw':
                    pipeline_score += 5
                    linked_feeds.add(fname)
            elif pid == PROC_MAX_DAILY:
                step_desc = "Max"
                if fname == 'greenhouse_temp_max':
                    pipeline_score += 5
                    linked_feeds.add(fname)
            elif pid == PROC_MIN_DAILY:
                step_desc = "Min"
                if fname == 'greenhouse_temp_min':
                    pipeline_score += 5
                    linked_feeds.add(fname)
            elif pid == PROC_RESET_ORIGINAL:
                step_desc = "Reset"
            
            pipeline_names.append(step_desc)

        # 4. Check Logical Order (The Core Challenge)
        # We need to ensure that Raw Value is passed to Min, not the output of Max.
        # Valid sequences:
        # A) ... -> Max -> Reset -> Min ...
        # B) ... -> Min -> Reset -> Max ...
        # C) ... -> Log(Raw) -> ... (Log passes value through, so order of Log relative to others matters less for value corruption, but Max/Min modify chain)
        
        # Specifically: Max and Min processes in Emoncms MODIFY the value in the chain to the new Max/Min.
        # So if we have Max -> Min, Min receives the Max value.
        
        # Locate indices
        indices_max = [i for i, x in enumerate(pipeline) if x['pid'] == PROC_MAX_DAILY]
        indices_min = [i for i, x in enumerate(pipeline) if x['pid'] == PROC_MIN_DAILY]
        indices_reset = [i for i, x in enumerate(pipeline) if x['pid'] == PROC_RESET_ORIGINAL]
        
        logic_valid = False
        
        if indices_max and indices_min:
            idx_max = indices_max[0]
            idx_min = indices_min[0]
            
            if idx_max < idx_min:
                # Max is calculated first. Is there a reset between them?
                has_reset = any(r > idx_max and r < idx_min for r in indices_reset)
                if has_reset:
                    logic_valid = True
                    feedback.append("Logic correct: Reset used between Max and Min.")
                else:
                    feedback.append("Logic error: Daily Minimum is calculated from Daily Maximum value (missing Reset).")
            else:
                # Min is calculated first. Is there a reset?
                has_reset = any(r > idx_min and r < idx_max for r in indices_reset)
                if has_reset:
                    logic_valid = True
                    feedback.append("Logic correct: Reset used between Min and Max.")
                else:
                    feedback.append("Logic error: Daily Maximum is calculated from Daily Minimum value (missing Reset).")
        
        elif not indices_max and not indices_min:
             feedback.append("Pipeline incomplete: Missing Max/Min processes.")
        else:
             feedback.append("Pipeline incomplete: Missing either Max or Min process.")

        if logic_valid:
            score += 25  # Logic points
        
        # Check if raw logging happened BEFORE modification (or if reset was used effectively)
        # Usually Log to Feed (Raw) should be first or after a reset
        indices_log = [i for i, x in enumerate(pipeline) if x['pid'] == PROC_LOG_TO_FEED and feed_ids.get(str(x['arg'])) == 'greenhouse_temp_raw']
        if indices_log:
            idx_log = indices_log[0]
            # It's valid if it's before any Max/Min OR immediately after a Reset
            # Simplified check: Just ensure it's usually step 0 or 1
            if idx_log == 0:
                score += 0 # Already counted in feed linking
            elif any(r == idx_log - 1 for r in indices_reset):
                score += 0
            else:
                # If it comes after Max/Min without reset, it logs the wrong value
                # Check for bad upstream modifiers
                bad_upstream = False
                for i in range(idx_log):
                    if pipeline[i]['pid'] in [PROC_MAX_DAILY, PROC_MIN_DAILY]:
                         # check if a reset intervened
                         if not any(r > i and r < idx_log for r in indices_reset):
                             bad_upstream = True
                
                if bad_upstream:
                    score -= 10
                    feedback.append("Logic error: Raw feed logs modified value (Max/Min applied before logging).")

        # 5. Final Score Calculation
        # Max score: 60 (Feeds) + 15 (Pipeline links) + 25 (Logic) = 100
        
        passed = (score >= 70) and logic_valid
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}