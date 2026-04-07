# Create Supreme Court Transcript Formatter (`create_scotus_transcriber@1`)

## Overview
This task requires the agent to build a stateful Talon Voice module that assists court reporters in transcribing legal proceedings. The module will fetch and parse real Supreme Court case metadata from the Oyez API, dynamically populate a Talon list of legal advocates, maintain an active "speaker state" in Python, and automatically format dictated statements with timestamps and speaker attributions.

## Rationale
**Why this task is valuable:**
- **External Data Integration:** Tests the agent's ability to fetch and parse complex JSON from a real-world API within a Talon Python module.
- **Dynamic List Generation:** Evaluates mapping external data to spoken-friendly Talon list keys (stripping punctuation, converting to lowercase).
- **State Management:** Requires managing internal Python state (the "active speaker") across multiple separate voice command invocations.
- **String Manipulation & Context:** Tests datetime integration and text formatting within Talon's `@mod.action_class` system.

**Real-world Context:** A legal transcriptionist with severe repetitive strain injury (RSI) relies entirely on Talon Voice to transcribe Supreme Court oral arguments. Manually typing out "[14:30] Mary L. Bonauto:" before every dictated paragraph is incredibly slow and physically taxing. They need a system where they can set the active speaker once, and all subsequent dictations are automatically prefixed with the correct timestamp and advocate name.

## Task Description

**Goal:** Create a complete Talon transcription module that downloads case data for *Obergefell v. Hodges*, dynamically generates a list of advocates, and provides stateful voice commands for timestamped dictation.

**Starting State:** 
- Windows 11 desktop with Talon Voice installed.
- The Talon user directory is at `C:\Users\Docker\AppData\Roaming\talon\user\`.
- PowerShell and Notepad are available.
- Internet access is enabled to fetch the API data.

**Expected Actions:**

1. **Setup Directory & Data:**
   - Create a directory at `C:\Users\Docker\AppData\Roaming\talon\user\scotus_transcriber\`.
   - Write a script or use PowerShell to download the real case metadata from the Oyez API for *Obergefell v. Hodges*:
     `Invoke-WebRequest -Uri "https://api.oyez.org/cases/2014/14-556" -OutFile "C:\Users\Docker\AppData\Roaming\talon\user\scotus_transcriber\14-556.json"`

2. **Create `transcriber.py`:**
   - Import necessary modules (`talon.Module`, `talon.actions`, `json`, `datetime`, `re`).
   - Define a Talon `Module()` and initialize a dynamic list named `user.scotus_advocates`.
   - On module load, read `14-556.json`. Parse the `"advocates"` array.
   - For each advocate, extract the `advocate.name` field.
   - Populate the `user.scotus_advocates` list where the **key** is the spoken form (lowercase, punctuation removed, e.g., `"mary l bonauto"`) and the **value** is the exact formatted string (e.g., `"Mary L. Bonauto"`).
   - Create a module-level variable to track the `active_speaker`, defaulting to `"Chief Justice"`.
   - Register the following actions via `@mod.action_class`:
     - `user.set_speaker(name: str)`: Updates the `active_speaker` variable.
     - `user.record_statement(text: str)`: 
       - Gets the current system time in 24-hour `[HH:MM]` format.
       - Capitalizes the very first letter of the dictated `text`.
       - Constructs the final string: `[HH:MM] {active_speaker}: {capitalized_text}\n`
       - Calls `actions.insert()` to type the string.
     - `user.insert_case_name()`: Parses the `"name"` field from the JSON (which should be "Obergefell v. Hodges") and inserts it via `actions.insert()`.

3. **Create `transcriber.talon`:**
   - Define a list capture for the advocates: `list: user.scotus_advocates`
   - Define the following voice commands:
     - `speaker {user.scotus_advocates}`: Calls `user.set_speaker()` passing the selected advocate.
     - `speaker chief justice`: Calls `user.set_speaker("Chief Justice")` directly.
     - `record <user.text>`: Calls `user.record_statement()` passing the dictated text.
     - `insert case name`: Calls `user.insert_case_name()`.

**Final State:**
The `scotus_transcriber` folder contains the JSON file, the `.py` file, and the `.talon` file. The Python module successfully reads the JSON, strips punctuation for spoken keys, manages state, and cleanly formats output.

## Verification Strategy

### Primary Verification: Static File & Content Analysis
A Python test script will inspect the created files to ensure strict compliance without running the Talon engine:
- Verify `14-556.json` was downloaded successfully and contains valid JSON.
- Parse `transcriber.py` using AST/Regex to confirm:
  - `json.load` or `json.loads` is used (anti-gaming: agent didn't hardcode the names).
  - `@mod.action_class` is present and state variables exist.
  - `datetime` is used for timestamp generation.
- Parse `transcriber.talon` to ensure commands correctly route to the defined actions.

### Secondary Verification: VLM Trajectory Verification
VLM samples frames from the agent's trajectory to visually confirm that a text editor was used to script the logic, guaranteeing authentic work generation.