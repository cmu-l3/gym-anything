# OpenC3 COSMOS Environment - Evidence Documentation

## Environment Overview

OpenC3 COSMOS is a cloud-native satellite ground station software suite used to operate real spacecraft. This environment runs the full COSMOS stack (8 Docker containers) inside a QEMU VM with a simulated INST satellite target generating real-time CCSDS telemetry packets.

## Verification Checklist

### Installation (pre_start hook)
- [x] Docker CE v29.2.1 installed from official Docker repository
- [x] Docker Compose v5.1.0 (plugin) installed
- [x] cosmos-project cloned from GitHub
- [x] All 8 Docker images pulled (openc3inc/openc3-*:6.10.4)
- [x] Firefox, wmctrl, xdotool, scrot installed
- **Log snippet** (from env_setup_pre_start.log):
  ```
  Docker version: Docker version 29.2.1, build a5c7197
  Docker Compose version: Docker Compose version v5.1.0
  COSMOS project cloned to: /home/ga/cosmos
  ```

### Setup (post_start hook)
- [x] All 7 runtime containers running (init container exits after seeding)
- [x] Web UI accessible at http://localhost:2900
- [x] Admin password set via UI automation
- [x] Firefox launched with COSMOS homepage
- **Container status**:
  ```
  cosmos-openc3-cosmos-cmd-tlm-api-1         Up 12 minutes
  cosmos-openc3-cosmos-script-runner-api-1   Up 12 minutes
  cosmos-openc3-minio-1                      Up 12 minutes
  cosmos-openc3-operator-1                   Up 12 minutes
  cosmos-openc3-redis-1                      Up 12 minutes
  cosmos-openc3-redis-ephemeral-1            Up 12 minutes
  cosmos-openc3-traefik-1                    Up 12 minutes
  ```

### Real Data Verification
- [x] INST target generating live CCSDS telemetry at 1Hz
- [x] INST2 target generating telemetry (38M+ packets observed)
- [x] Temperature readings (TEMP1-4) showing realistic fluctuation
- [x] Limit violations occurring naturally (YELLOW/RED states)
- [x] COLLECTS counter tracking data collection operations
- **Telemetry samples** (via API):
  ```
  INST HEALTH_STATUS TEMP1: 34.261 (varies continuously)
  INST HEALTH_STATUS TEMP2: -35.502
  INST HEALTH_STATUS TEMP3: 26.285
  INST HEALTH_STATUS TEMP4: 17.706
  INST HEALTH_STATUS COLLECTS: 6
  ```

### Tool Verification
- [x] **CmdTlmServer** - Shows connected interfaces, packet counts, real-time log messages (screenshot: 06)
- [x] **Limits Monitor** - Displays live limit violations with color-coded bars (screenshot: 01)
- [x] **Command Sender** - Target/command dropdowns, parameter fields, Send button (screenshot: 02)
- [x] **Telemetry Grapher** - Graph area with target/packet/item selectors (screenshot: 03)
- [x] **Script Runner** - Code editor, File/Edit/Script menus, Start button (screenshot: 04)
- [x] **Packet Viewer** - Key-value telemetry item list (screenshot: 05)

### Task Start State Verification
- [x] monitor_thermal_alarm: Limits Monitor open with live violations visible
- [x] execute_data_collect: Command Sender open, ready for INST COLLECT
- [x] diagnose_anomaly: Limits Monitor showing violations for investigation
- [x] run_pass_sequence: Script Runner open with editor ready

### Resource Usage
- Disk: 9.3GB used of 49GB (20%)
- Total setup time: ~5 minutes (with pre-pulled images)
- RAM requirement: 16GB allocated to VM

## Evidence Screenshots

| Screenshot | Description |
|-----------|-------------|
| 01_limits_monitor_live_telemetry.png | Live telemetry with color-coded limit violations |
| 02_command_sender.png | Command Sender tool with target/command selection |
| 03_telemetry_grapher.png | Telemetry Grapher with graph area and item selectors |
| 04_script_runner.png | Script Runner with code editor and execution controls |
| 05_packet_viewer.png | Packet Viewer showing telemetry items |
| 06_cmdtlm_server_connected.png | CmdTlmServer with connected interfaces and live logs |
| 07_initial_password_setup.png | Initial password setup page (first-run) |

## API Authentication

In open-source COSMOS, the auth token is the password itself. Use `Authorization: <password>` header for API calls:
```bash
curl -s -X POST http://localhost:2900/openc3-api/api \
  -H "Content-Type: application/json" \
  -H "Authorization: Cosmos2024!" \
  -d '{"jsonrpc":"2.0","method":"tlm","params":["INST HEALTH_STATUS TEMP1"],"id":1,"keyword_params":{"type":"FORMATTED","scope":"DEFAULT"}}'
```
