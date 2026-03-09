# Jitsi Meet Environment — Evidence Documentation

## Environment Overview
- **Application**: Jitsi Meet (open-source video conferencing)
- **Docker stack**: `jitsi/web`, `jitsi/prosody`, `jitsi/jicofo`, `jitsi/jvb` (stable-9753)
- **URL**: `http://localhost:8080`
- **Tasks**: 5 (create_meeting, set_display_name, share_invite_link, toggle_lobby, change_background)

## Setup Logs
- `pre_start_log.txt` — Output of `install_jitsi.sh` (Docker + Firefox installation)
- `post_start_log.txt` — Output of `setup_jitsi.sh` (container start + Firefox warmup)

## Task Verification Checklist

All items verified via interactive testing (SSH + xdotool + visual_grounding):

- [x] Installation script completes without errors (pre_start_log.txt)
- [x] Setup script completes without errors (post_start_log.txt)
- [x] Jitsi Meet home page loads at http://localhost:8080
- [x] All 4 Docker containers start: web, prosody, jicofo, jvb
- [x] Meetings can be created and joined (pre-join → active meeting)
- [x] Security Options dialog shows Lobby toggle (ENABLE_LOBBY=1)
- [x] Lobby toggle works (can be turned ON/OFF)
- [x] Invite dialog opens with copyable meeting link
- [x] All 5 task setup scripts exit code 0
- [x] All 5 task start states correct (verified via visual_grounding)
- [x] toggle_lobby and share_invite_link: agent placed inside active meeting
- [x] End-to-end task completion demonstrated for toggle_lobby and share_invite_link

## Screenshots — Environment Setup

| File | Description |
|------|-------------|
| `01_jitsi_home_page.png` | Jitsi Meet home page at http://localhost:8080 |
| `02_meeting_name_typed.png` | "TeamStandup" typed in the meeting name input |
| `03_prejoin_screen.png` | Pre-join screen for "Team Standup" meeting |
| `04_meeting_active_avatar.png` | Active meeting with user avatar |
| `05_meeting_toolbar_visible.png` | Full meeting toolbar — all controls visible, timer running |
| `06_meeting_security_options.png` | Meeting room with (...) more options menu |
| `07_security_options_dialog.png` | Security Options dialog (before ENABLE_LOBBY fix) |
| `08_fresh_env_home_page.png` | Fresh environment home page |
| `09_fresh_env_prejoin.png` | Pre-join screen from fresh environment |

## Screenshots — Lobby Feature

| File | Description |
|------|-------------|
| `10_security_options_with_lobby.png` | Security Options showing Lobby toggle (ENABLE_LOBBY=1 confirmed) |
| `11_lobby_enabled.png` | Lobby toggle turned ON |
| `12_toggle_lobby_start_state.png` | Initial toggle_lobby start state (agent inside SecurityMeeting) |

## Screenshots — End-to-End Task Demonstrations

### toggle_lobby task
| File | Description |
|------|-------------|
| `13_toggle_lobby_correct_start.png` | Correct start: agent inside SecurityMeeting, toolbar visible |
| `14_toggle_lobby_more_menu.png` | "..." more options menu open, "Security options" visible |
| `15_toggle_lobby_security_panel_off.png` | Security Options panel open, Lobby toggle = OFF |
| `16_toggle_lobby_enabled.png` | Lobby toggle = ON (task completed) |

### share_invite_link task
| File | Description |
|------|-------------|
| `17_share_invite_start_state.png` | Correct start: agent inside DesignReview meeting |
| `18_share_invite_dialog.png` | "Invite more people" dialog open, link visible |
| `19_share_invite_copied.png` | "Copied" toast notification — link in clipboard |

### create_meeting task
| File | Description |
|------|-------------|
| `20_create_meeting_typed.png` | "TeamStandup" typed in meeting name field |
| `21_create_meeting_prejoin.png` | Pre-join screen for "Team Standup" |
| `22_create_meeting_joined.png` | Agent inside active TeamStandup meeting |

## Screenshots — Final Task Start States (all 5 tasks)

| File | Description | Correct? |
|------|-------------|---------|
| `23_final_create_meeting_start.png` | Home page with meeting input field + recent meetings list | ✅ |
| `24_final_set_display_name_start.png` | Pre-join screen for ProductReview with name input field | ✅ |
| `25_final_share_invite_link_start.png` | Agent inside active DesignReview meeting with toolbar | ✅ |
| `26_final_toggle_lobby_start.png` | Agent inside active SecurityMeeting with toolbar | ✅ |
| `27_final_change_background_start.png` | Jitsi home page with Settings gear icon visible | ✅ |

## Key Technical Fixes Applied

1. **`docker-compose-v2`** — not `docker-compose-plugin` (correct Ubuntu 22.04 package)
2. **`BOSH_RELATIVE=true` + `ENABLE_XMPP_WEBSOCKET=0`** — prevents `wss://http://` broken URLs
3. **`JVB_ADVERTISE_IPS=127.0.0.1`** — WebRTC ICE for localhost browser connectivity
4. **`ENABLE_LOBBY=1`** in both prosody AND jicofo — enables lobby toggle in Security Options
5. **`restart_firefox` uses `/tmp/firefox_task.log`** — avoids root-owned `/tmp/firefox.log`
6. **`join_meeting()` uses Enter key** — clicks name input then presses Enter to join meeting
