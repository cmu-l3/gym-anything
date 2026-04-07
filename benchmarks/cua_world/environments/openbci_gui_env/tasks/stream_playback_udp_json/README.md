# Stream Playback Data via UDP JSON (`stream_playback_udp_json@1`)

## Overview

This task evaluates the agent's ability to configure the OpenBCI GUI to replay a pre-recorded EEG session and stream that data to an external application using the UDP protocol in JSON format. This tests the agent's competence with both the Playback interface and the Networking widget's advanced configuration options.

## Rationale

**Why this task is valuable:**
- **Integration Testing:** Tests the ability to bridge OpenBCI GUI with external software (web apps, Python scripts).
- **Format Specificity:** Requires selecting a specific data format (JSON) over the default, which is critical for web-based integrations.
- **Data Fidelity:** Uses real playback data, ensuring the agent understands how to simulate live streams from recorded files.
- **Complex Workflow:** Combines file loading, playback control, and network stream configuration.

**Real-world Context:** A software developer is building a browser-based BCI visualization dashboard. To test their JavaScript application without wearing a headset all day, they need to stream a recorded motor imagery session from the OpenBCI GUI to their local development server (localhost:12345) in a format the web app can parse (JSON).

## Task Description

**Goal:** Load the motor imagery EEG recording (`OpenBCI-EEG-S001-MotorImagery.txt`), start playback, and configure the Networking widget to stream the data as **JSON** packets to **UDP port 12345** on localhost.

**Starting State:**
- The OpenBCI GUI is launched and at the initial system control panel (Data Source selection screen).
- The recording file is located at: `~/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-MotorImagery.txt`.
- A background listener script is running on the system, waiting for data on UDP port 12345.

**Expected Actions:**
1.  Select **"PLAYBACK (file)"** from the data source dropdown.
2.  Navigate to and select the file `OpenBCI-EEG-S001-MotorImagery.txt`.
3.  Start the session to enter the main GUI interface.
4.  Open the **Networking** widget (if not already open, select "Networking" from the widget dropdown in any layout pane).
5.  Configure the Networking widget:
    *   **Protocol:** UDP
    *   **Data Type:** JSON
    *   **IP Address:** 127.0.0.1 (or localhost)
    *   **Port:** 12345
6.  Click **"Start TCP/UDP/Serial Stream"** (or the generic "Start" button in the Networking widget).
7.  Click the main **"Start Data Stream"** (Play button) in the top-left control bar to begin playback of the recording.
8.  Ensure both the playback is running (timeline moving) and the network stream is active.

**Final State:**
- The OpenBCI GUI is actively replaying the motor imagery file.
- The Networking widget is active and streaming data.
- The background listener receives valid JSON-formatted EEG data packets.

## Verification Strategy

### Primary Verification: Active UDP Stream Check
The task infrastructure runs a background Python script that binds to UDP port 12345. It logs any received packets.
- **Criteria:**
    - At least 5 packets received.
    - Packet payload must be valid JSON.
    - JSON object must contain EEG data keys (e.g., `"data"`, `"sampleNumber"`).
    - Data values must not be all zeros (proving real playback data).

### Secondary Verification: VLM Settings Check
A Vision-Language Model analyzes the final screenshot to verify:
- **Networking Widget:** Visible and active.
- **Settings:** "UDP" and "JSON" are selected.
- **Port:** "12345" is visible in the port field.
- **Playback:** The playback timeline indicates progression (not at 00:00).

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| **UDP Packets Received** | 40 | The background listener captured data on port 12345. |
| **Valid JSON Format** | 20 | The received packets were valid JSON (not binary/LSL). |
| **Real EEG Data** | 20 | The payload contained non-zero EEG data (indicates active playback). |
| **Widget Configuration** | 20 | VLM confirms UDP, JSON, and Port 12345 settings visually. |
| **Total** | **100** | |

**Pass Threshold:** 80 points (Must successfully stream JSON data).