#!/usr/bin/env python3
import json
import os
import tempfile
from bs4 import BeautifulSoup
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_live_channel_stats_dashboard(traj, env_info, task_info):
    """
    Verifies that the agent created a dashboard that updates dynamically.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/export_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Channel Status (10 pts)
    status = result.get('agent_channel_status', 'UNKNOWN')
    if status in ['STARTED', 'DEPLOYED', 'POLLING']:
        score += 10
        feedback.append(f"Agent channel is running ({status}).")
    else:
        feedback.append(f"Agent channel status is {status} (Expected STARTED).")

    # 2. Output File Existence (10 pts)
    if result.get('output_exists'):
        score += 10
        feedback.append("Output file exists.")
    else:
        feedback.append("Output file /var/www/html/dashboard.html missing.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # Parse HTML snapshots
    html1 = result.get('html_snapshot_1', '')
    html2 = result.get('html_snapshot_2', '')
    
    soup1 = BeautifulSoup(html1, 'lxml')
    soup2 = BeautifulSoup(html2, 'lxml')

    # 3. HTML Structure (20 pts)
    table1 = soup1.find('table')
    if table1:
        score += 10
        feedback.append("HTML contains a table.")
        
        headers = [th.get_text().lower() for th in table1.find_all('th')]
        header_text = " ".join(headers)
        if "name" in header_text and "received" in header_text and "error" in header_text:
            score += 10
            feedback.append("Table has correct headers.")
        else:
            feedback.append(f"Table headers missing required columns. Found: {headers}")
    else:
        feedback.append("No <table> found in HTML.")

    # 4. Data Validation (Stats 1) (20 pts)
    # Parse API stats
    try:
        stats1_data = json.loads(result.get('api_stats_1', '{}'))
        channels1 = stats1_data.get('channelStatistics', [])
        # If single channel, it returns dict, if multiple, list. NextGen API usually list.
        if isinstance(channels1, dict): channels1 = [channels1]
        
        # Helper to find stats in HTML
        def check_stats_in_html(soup, channel_name, expected_received):
            rows = soup.find_all('tr')
            for row in rows:
                if channel_name in row.get_text():
                    # Check if the number appears in the row
                    if str(expected_received) in row.get_text():
                        return True
            return False

        # Find Sim_ADT_Inbound stats
        adt_stats = next((c for c in channels1 if c.get('channelName') == 'Sim_ADT_Inbound'), {})
        adt_received = adt_stats.get('received', -1)
        
        if adt_received != -1 and check_stats_in_html(soup1, 'Sim_ADT_Inbound', adt_received):
            score += 20
            feedback.append(f"Snapshot 1: Correctly shows {adt_received} received for Sim_ADT_Inbound.")
        else:
            feedback.append(f"Snapshot 1: Failed to find count {adt_received} for Sim_ADT_Inbound.")
            
    except Exception as e:
        feedback.append(f"Error validating snapshot 1: {str(e)}")

    # 5. Dynamic Update (Stats 2) (40 pts)
    # Check if HTML updated after we sent messages
    if html1 == html2:
        feedback.append("Dashboard did not update after traffic injection (HTML content identical).")
    else:
        try:
            stats2_data = json.loads(result.get('api_stats_2', '{}'))
            channels2 = stats2_data.get('channelStatistics', [])
            if isinstance(channels2, dict): channels2 = [channels2]
            
            adt_stats_2 = next((c for c in channels2 if c.get('channelName') == 'Sim_ADT_Inbound'), {})
            adt_received_2 = adt_stats_2.get('received', -1)
            
            # Check if this new number is in the second HTML snapshot
            if adt_received_2 != -1 and check_stats_in_html(soup2, 'Sim_ADT_Inbound', adt_received_2):
                score += 40
                feedback.append(f"Snapshot 2: Dashboard updated! Shows new count {adt_received_2}.")
            else:
                feedback.append(f"Snapshot 2: HTML changed, but didn't match expected count {adt_received_2}.")
                
        except Exception as e:
            feedback.append(f"Error validating snapshot 2: {str(e)}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }