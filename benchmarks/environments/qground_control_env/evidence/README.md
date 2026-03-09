# QGroundControl Environment - Evidence Documentation

## Environment Setup Evidence

### 1. Installation Verification (pre_start)
**Status: PASS**

Install log output (from `/home/ga/env_setup_pre_start.log`):
```
ArduCopter SITL binary built successfully
-rwxrwxr-x 1 ga ga 5618184 Mar  1 17:17 /opt/ardupilot/build/sitl/bin/arducopter
QGC: /opt/QGroundControl-x86_64.AppImage (180816376 bytes)
```

- QGC AppImage: 180MB, downloaded from GitHub releases v5.0.8
- ArduPilot SITL: Built successfully via `waf copter` (ArduCopter 4.7.0dev)
- All dependencies installed via apt-get (including NetworkManager)

### 2. Service Startup Verification (post_start)
**Status: PASS**

Post-start log output (from `/home/ga/env_setup_post_start.log`):
```
ArduPilot SITL is running (after 6s)
SITL should now be sending MAVLink on UDP 14550
QGroundControl window detected (after 3s)
NetworkManager state: connected
```

- ArduPilot SITL process running: `arducopter --model + --speedup 1 --serial0=udpclient:127.0.0.1:14550`
- QGroundControl process running: `/opt/QGroundControl-x86_64.AppImage --appimage-extract-and-run`
- QGC window visible and maximized at 1920x1080 (position 0,0)
- NetworkManager state: "connected full" (required for map tile loading)
- Netplan renderer switched from systemd-networkd to NetworkManager

### 3. Drone Connection Verification
**Status: PASS**

Screenshot evidence: `fly_view_clean_connected.png`

Visible indicators:
- "Ready To Fly" status (green) in top toolbar
- "Stabilize" flight mode displayed
- Battery level: 100%
- Drone icon (red/green triangle) visible on satellite map
- Compass widget in bottom-right
- ArduPilot branding in top-right
- Telemetry: altitude, speed, heading all showing
- **Satellite map tiles loading correctly** (terrain, roads, buildings visible)

### 4. Active Flight Verification (Drone Flying Mission)
**Status: PASS**

Screenshot evidence: `fly_view_active_flight.png`

A mission was uploaded via pymavlink (TCP port 5762) and executed:
- **6 waypoints** uploaded: Home, Takeoff (50m), 3 triangle waypoints (~111m per side), RTL
- Drone force-armed in GUIDED mode, took off to 50m, switched to AUTO
- **"Flying Auto"** mode displayed (green) in top toolbar
- **Red triangle mission path** drawn on satellite map showing the planned route
- Drone icon (red arrow) actively moving along mission path
- Telemetry HUD showing:
  - Altitude: 164.1 ft (50m)
  - Speed: 22.2 mph (~10 m/s)
  - Distance traveled: 2651.5 ft
  - Timer: 00:03:04
  - Compass heading updating in real-time
- Battery: 56% (draining during flight)

### 5. Plan View with Altitude Profile During Flight
**Status: PASS**

Screenshot evidence: `plan_view_altitude_profile.png`

Navigated to Plan View while drone was actively flying:
- **Satellite map** with waypoint markers and home position (green dot)
- **Altitude profile graph** visible at bottom of screen (dark strip showing elevation)
- **Mission summary bar** at top: waypoint altitude, azimuth, distance per WP, total distance
- Mission/Fence/Rally tabs in right panel
- Mixed Ascent and Vehicle Info sections

### 6. MAVLink Console - Operations Center View
**Status: PASS**

Screenshot evidence: `mavlink_console_operations_center.png`

The MAVLink Console provides a multi-panel operations center overlay during flight:
- **Satellite map** visible in background with red triangle mission path
- **Drone icon** showing current position on the map
- **Vehicle Messages** panel (left): timestamped real-time log entries showing system events, mode changes, waypoint progress
- **Sensor Status** panel (bottom-left): all sensor health indicators
  - Gyro, Accelerometer, Magnetometer, Barometer, GPS: all "Normal"
  - Angular rate control, Attitude, Position: all "Normal"
- **Telemetry HUD** (bottom-right): altitude 170.7 ft, speed 22.4 mph, compass
- **"Flying Auto"** mode indicator in top toolbar

### 7. Vehicle Configuration & Parameters
**Status: PASS**

Screenshot evidence: `vehicle_config_summary.png`, `parameters_view.png`

Vehicle Configuration Summary:
- Frame Class: Quad, Frame Type: Plus, Firmware: 4.7.0dev
- Radio: Roll/Pitch/Yaw/Throttle channels configured
- Flight Modes: Circle, Land, RTL, Auto, Loiter, Stabilize
- Sensors: 3 compasses (External/Internal), accelerometers, barometers (SITL)
- Power: 3300 mAh battery, analog voltage/current monitoring
- Safety: Throttle failsafe enabled (always RTL), GeoFence disabled
- Left sidebar: Summary, Frame, Radio, Flight Modes, Sensors, Power, Motors, Safety, Tuning, Camera, Remote Support, Parameters, Firmware

Parameters View:
- Parameter categories listed alphabetically (ACRO, ADSB, AHRS, ARSPD, ATC, AUTOTUNE, AVOID, BATT, BRD, CAM, CAN, CHUTE, CIRCLE, COMPASS, EAHRS, FENCE, ...)
- Search box functional for filtering parameters
- **WPNAV_SPEED = 500.000** confirmed present (Waypoint Horizontal Speed Target)
- "Tools" button available for parameter import/export

### 8. Task Start State Verification
**Status: PASS**

- Task setup completes in ~6 seconds
- Sample mission data copied to `/home/ga/Documents/QGC/`
- QGC focused and maximized
- Dialogs dismissed via click-based approach (not Escape key)

## Screenshots

| File | Description |
|------|-------------|
| `fly_view_clean_connected.png` | Fly View pre-flight: satellite map, drone connected, "Ready To Fly", telemetry HUD |
| `fly_view_active_flight.png` | **Fly View during active flight**: drone flying AUTO mission, red triangle path on satellite map, 22.2 mph, 50m altitude, telemetry HUD updating |
| `plan_view_accessible.png` | Plan View: Create Plan panel, Survey/Corridor Scan/Structure Scan options, satellite map |
| `plan_view_altitude_profile.png` | **Plan View during flight**: altitude profile graph at bottom, waypoints on satellite map, mission summary |
| `mavlink_console_operations_center.png` | **Operations Center view**: Vehicle Messages + Sensor Status overlaid on satellite map during flight, telemetry HUD |
| `mavlink_inspector.png` | MAVLink Console: real-time vehicle messages, sensor health status, all overlaid on map with mission path |
| `vehicle_config_summary.png` | Vehicle Configuration: Summary with Frame/Radio/Flight Modes/Sensors/Power/Safety panels |
| `parameters_view.png` | Parameters: alphabetical category list (ACRO through FRSKY+), search box, Tools button |

## Multi-Panel Operations Center Look

The environment demonstrates a professional multi-panel operations center appearance during **active drone flight**:

### Fly View During Flight (`fly_view_active_flight.png`)
All of these elements visible simultaneously while the drone is flying:
- **Satellite map** with real Bing imagery (terrain, roads, buildings)
- **Mission path** rendered as red triangle/polygon on the map
- **Drone icon** (red arrow) moving along the mission path in real-time
- **Telemetry HUD** (bottom-right): altitude, ground speed, heading, distance, elapsed time
- **Compass widget** with heading indicators
- **Flight mode indicator** ("Flying Auto") confirming autonomous mission execution
- **Battery drain** visible (100% -> 56% during flight)
- **ArduPilot branding** and record/timer controls

### Plan View During Flight (`plan_view_altitude_profile.png`)
- **Satellite map** paired with **altitude profile graph** at the bottom
- **Mission summary bar** showing per-waypoint data (altitude, azimuth, distance)
- Waypoint markers visible on map alongside home position

### MAVLink Console During Flight (`mavlink_console_operations_center.png`)
- **Vehicle Messages** stream: timestamped log of system events, mode changes, waypoint arrivals
- **Sensor Status** dashboard: real-time health of all vehicle sensors (gyro, accelerometer, magnetometer, barometer, GPS, etc.)
- All overlaid on the satellite map with mission path visible in the background
- Telemetry HUD still accessible at bottom-right

## Active Flight Details

The drone was flown autonomously using pymavlink (connected via SITL TCP port 5762):

```
Mission uploaded: 6 waypoints (Home -> Takeoff 50m -> 3 triangle vertices -> RTL)
Triangle size: ~111m per side (0.001 degree offset)
Flight altitude: 50m above home
Max speed: ~10 m/s (22 mph) in AUTO mode
Total mission time: ~2 minutes
```

Pymavlink telemetry log excerpt during flight:
```
[ 84s] Lat:-35.363211 Lon:149.165237 Alt:50.0m Hdg:0   Spd:4.5m/s
[ 87s] Lat:-35.363200 Lon:149.165237 Alt:50.0m Hdg:0   Spd:5.0m/s
[ 90s] Lat:-35.363188 Lon:149.165237 Alt:50.0m Hdg:0   Spd:5.5m/s
[ 93s] Lat:-35.363175 Lon:149.165237 Alt:50.0m Hdg:0   Spd:6.0m/s
[108s] Lat:-35.363093 Lon:149.165237 Alt:50.0m Hdg:0   Spd:8.3m/s
[117s] Lat:-35.363035 Lon:149.165237 Alt:50.0m Hdg:0   Spd:9.0m/s
```

## Key Technical Findings

### NetworkManager / Map Tile Fix
Qt 6 (QGC v5) checks NetworkManager's D-Bus API for connectivity status. The base image uses systemd-networkd via netplan, causing NM to report "unmanaged" and Qt to report "Network Not Available". Fix: Change netplan renderer from `networkd` to `NetworkManager` in `/etc/netplan/50-cloud-init.yaml`.

### Dialog Dismissal
- QGC v5 shows 3 first-run dialogs (Serial permissions, Measurement Units, Vehicle Information)
- **Do NOT use Escape key** - it triggers "Close QGroundControl" quit dialog
- Use click-based dismissal at verified Ok button positions (1920x1080):
  - Serial permissions Ok: (1262, 459)
  - Measurement Units Ok: (1065, 383)
  - Vehicle Information Ok: (1031, 444)

### QGC Window Maximization
- QGC saves window state in `~/.config/QGroundControl/QGroundControl.ini` under `[MainWindowState]`
- Pre-set `visibility=5, x=0, y=0, width=1920, height=1048` for reliable maximization
- GNOME dock hidden via gsettings to prevent overlap

### Q Icon Navigation
- The Q icon is at the extreme top-left of the QGC toolbar (~10, 14 in 1920x1080)
- Opens a drawer with menu items (1920x1080 coordinates):
  - Plan Flight: (96, 95)
  - Analyze Tools: (105, 146)
  - Vehicle Configuration: (126, 197)
  - Application Settings: (122, 248)
  - Close (Disconnect): (131, 299)

### Pymavlink Flight Control
- SITL exposes TCP ports 5762/5763 for additional MAVLink connections (separate from QGC's UDP 14550)
- Must disable ARMING_CHECK parameter for force-arming in SITL
- GUIDED mode + `set_position_target_global_int` for takeoff, then AUTO for mission execution
- Request data streams (`MAV_DATA_STREAM_ALL` at 4Hz) after connecting on TCP ports

## Timing Summary

| Phase | Duration |
|-------|----------|
| pre_start (install) | ~260 seconds |
| post_start (setup) | ~40 seconds |
| pre_task (task setup) | ~6 seconds |
| Total | ~306 seconds |
