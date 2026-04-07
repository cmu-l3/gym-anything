#!/usr/bin/env python3
"""
Verifier for tcp_sender_queue_config task.
Verifies channel configuration (XML) and runtime statistics.
"""

import json
import xml.etree.ElementTree as ET
import os
import sys

def verify_tcp_sender_queue_config(traj, env_info, task_info):
    """
    Verify the agent configured the TCP Sender channel with correct queue settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    try:
        # Copy files to temp location
        import tempfile
        temp_dir = tempfile.mkdtemp()
        result_file = os.path.join(temp_dir, "task_result.json")
        xml_file = os.path.join(temp_dir, "channel_config.xml")
        
        copy_from_env("/tmp/task_result.json", result_file)
        
        with open(result_file, 'r') as f:
            result = json.load(f)
            
        # Copy XML if it exists
        xml_content = None
        if result.get('channel_found', False):
            copy_from_env("/tmp/channel_config.xml", xml_file)
            if os.path.exists(xml_file):
                with open(xml_file, 'r') as f:
                    xml_content = f.read()

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Channel Existence (10 pts)
    if not result.get('channel_found', False):
        return {"passed": False, "score": 0, "feedback": "Channel 'ADT_Message_Relay' not found."}
    
    score += 10
    feedback_parts.append("Channel 'ADT_Message_Relay' exists.")

    # Parse XML configuration
    try:
        root = ET.fromstring(xml_content)
        
        # 2. Check Source Connector (TCP Listener 6661) (10 pts)
        source_conn = root.find(".//sourceConnector")
        source_transport = source_conn.find("transportName").text
        source_props = source_conn.find(".//properties")
        listener_props = source_props.find("listenerConnectorProperties")
        source_port = listener_props.find("port").text
        
        if source_transport == "TCP Listener" and source_port == "6661":
            score += 10
            feedback_parts.append("Source configured correctly (TCP Listener on 6661).")
        else:
            feedback_parts.append(f"Source config mismatch: Found {source_transport} on {source_port}.")

        # 3. Check Destination Connector (TCP Sender localhost:6665) (15 pts)
        # Note: Channels can have multiple destinations, look for the TCP Sender one
        dest_connectors = root.findall(".//destinationConnectors/connector")
        target_dest = None
        
        for dest in dest_connectors:
            transport = dest.find("transportName").text
            if transport == "TCP Sender":
                target_dest = dest
                break
        
        if target_dest:
            dest_props = target_dest.find(".//properties")
            
            # TCP Sender props usually in tcpDispatcherProperties or similar depending on version, 
            # but XML often wraps them in 'properties' with class attribute.
            # Mirth/NextGen XML structure: <properties class="com.mirth.connect.connectors.tcp.TcpDispatcherProperties">
            #   <remoteAddress>localhost</remoteAddress>
            #   <remotePort>6665</remotePort>
            
            remote_addr = dest_props.find("remoteAddress").text
            remote_port = dest_props.find("remotePort").text
            
            if remote_addr in ["localhost", "127.0.0.1", "0.0.0.0"] and remote_port == "6665":
                score += 10
                feedback_parts.append("Destination connector target correct (localhost:6665).")
            else:
                feedback_parts.append(f"Destination target mismatch: {remote_addr}:{remote_port}.")
                
            dest_name = target_dest.find("name").text
            if dest_name == "Forward_to_ADT_System":
                score += 5
                feedback_parts.append("Destination name correct.")
            else:
                feedback_parts.append(f"Destination name incorrect: {dest_name}")

            # 4. Check Queue Settings (45 pts total)
            # Queue settings are in destinationConnectorProperties inside the main properties block
            dest_conn_props = dest_props.find("destinationConnectorProperties")
            
            # Queue Enabled (Always) -> queueEnabled=true, sendFirst=false
            q_enabled = dest_conn_props.find("queueEnabled").text
            send_first = dest_conn_props.find("sendFirst").text
            
            if q_enabled == "true" and send_first == "false":
                score += 15
                feedback_parts.append("Queue configured to 'Always' (queueEnabled=true, sendFirst=false).")
            elif q_enabled == "true":
                 feedback_parts.append("Queue enabled but 'sendFirst' is true (On Failure). Expected 'Always'.")
                 score += 5
            else:
                feedback_parts.append("Queueing is disabled.")

            # Retry Interval
            interval = dest_conn_props.find("retryIntervalMillis").text
            if interval == "10000":
                score += 10
                feedback_parts.append("Retry interval correct (10000ms).")
            else:
                feedback_parts.append(f"Retry interval incorrect: {interval}ms.")

            # Max Retries
            retries = dest_conn_props.find("retryCount").text
            if retries == "5":
                score += 10
                feedback_parts.append("Retry count correct (5).")
            else:
                feedback_parts.append(f"Retry count incorrect: {retries}.")
                
            # Rotate Queue
            rotate = dest_conn_props.find("rotate").text
            if rotate == "true":
                score += 10
                feedback_parts.append("Rotate queue enabled.")
            else:
                feedback_parts.append("Rotate queue disabled.")

        else:
            feedback_parts.append("No TCP Sender destination found.")

    except Exception as e:
        feedback_parts.append(f"Error parsing channel XML: {str(e)}")

    # 5. Check Deployment and Runtime (20 pts)
    status = result.get('channel_status', 'UNKNOWN')
    if status in ['STARTED', 'DEPLOYED', 'RUNNING']:
        score += 10
        feedback_parts.append("Channel is deployed/started.")
    else:
        feedback_parts.append(f"Channel status: {status}")

    # Check messages processed
    # We want to see > 0 received on our channel AND > 0 received on downstream
    # This proves the TCP connection worked
    relay_received = result.get('received_count', 0)
    downstream_received = result.get('downstream_received_count', 0)
    
    if relay_received > 0 and downstream_received > 0:
        score += 10
        feedback_parts.append(f"Message successfully relayed (Source: {relay_received}, Dest: {downstream_received}).")
    elif relay_received > 0:
        score += 5
        feedback_parts.append("Message received by relay but NOT by downstream (forwarding failed).")
    else:
        feedback_parts.append("No messages processed.")

    passed = score >= 60 and result.get('channel_found', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }