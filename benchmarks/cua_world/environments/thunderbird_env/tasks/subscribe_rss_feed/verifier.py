#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_subscribe_rss_feed(traj, env_info, task_info):
    """
    Hybrid verification combining:
    1. Thunderbird profile state inspection
    2. HTTP Local Server Traffic Logs
    3. Trajectory-based VLM verification 
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_feed_url = metadata.get('expected_feed_url', 'http://localhost:8080/market_news.xml')

    # Read the exported container data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    rss_pref = result.get('rss_pref_exists', False)
    server_gets = result.get('server_get_count', 0)
    article_dl = result.get('article_downloaded', False)

    # Criterion 1: Profile indicates RSS account creation
    if rss_pref:
        score += 20
        feedback.append("RSS account created in preferences (+20).")
    else:
        feedback.append("No RSS account found in Thunderbird preferences.")

    # Criterion 2: Server log proves the URL was fetched 
    # (Anti-gaming: you can't just create dummy folders to trick the mbox reader)
    if server_gets > 0:
        score += 30
        feedback.append(f"Local server logged {server_gets} GET request(s) for the '{expected_feed_url}' feed (+30).")
    else:
        feedback.append(f"Local server did NOT log any GET requests for the feed.")

    # Criterion 3: Article headline found in the Thunderbird profile (mbox data check)
    if article_dl:
        score += 30
        feedback.append("RSS article content found successfully downloaded inside Thunderbird mail files (+30).")
    else:
        feedback.append("RSS article content NOT found in Thunderbird mail files.")

    # Criterion 4: VLM visual verification based on execution trajectory
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = """You are analyzing a sequence of screenshots from an agent configuring an RSS feed in Mozilla Thunderbird.

For a successful RSS configuration, the agent should:
1. Open 'Account Settings' and select 'Blogs & News Feeds' to create an account.
2. Open the 'Feed Subscriptions' dialog and enter a feed URL.
3. Show the main Thunderbird window with the new 'Blogs & News Feeds' folder and downloaded articles visible.

Based on the chronological images provided:
1. DID_OPEN_SETTINGS: Did the agent open account settings or feed subscription dialogs?
2. DID_SUBSCRIBE: Is there evidence of a feed URL being entered or subscribed to?
3. ARTICLES_VISIBLE: Does the final screen show downloaded news articles or an RSS folder?

Respond in valid JSON format ONLY:
{
    "DID_OPEN_SETTINGS": true/false,
    "DID_SUBSCRIBE": true/false,
    "ARTICLES_VISIBLE": true/false
}"""
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("DID_OPEN_SETTINGS", False): vlm_score += 5
                if parsed.get("DID_SUBSCRIBE", False): vlm_score += 10
                if parsed.get("ARTICLES_VISIBLE", False): vlm_score += 5
                
                score += vlm_score
                feedback.append(f"VLM trajectory verification scored {vlm_score}/20 points.")
            else:
                feedback.append("VLM verification failed or returned no result.")
    except Exception as e:
        logger.warning(f"VLM check error: {e}")
        # If VLM is unavailable but programmatic checks pass perfectly, award full points gracefully
        if score == 80:
            score += 20
            feedback.append("VLM execution skipped/failed, but perfect programmatic score grants full points (+20).")

    # The fundamental requirement is that the article was downloaded through standard TB interactions
    passed = (score >= 80) and article_dl

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }