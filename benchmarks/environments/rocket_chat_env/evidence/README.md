# Evidence Documentation (Rocket.Chat)

This folder contains evidence from real interactive testing of `rocket_chat_env`.

## Verification Checklist

- [x] Installation script completes without errors (see `env_setup_pre_start.log`)
- [x] Setup script completes without errors (see `env_setup_post_start.log`)
- [x] Application is visible in screenshot (see `01_login_page_start_state.png`)
- [x] Application is in correct initial state with real data loaded (see `02_release_updates_channel_with_data.png`)
- [x] Task setup runs without errors for all 10 tasks (see task setup test results below)
- [x] Task start state is correct (verified via `visual_grounding` MCP tool)
- [x] Task is completable interactively (`set_channel_topic` completed end-to-end, see `03_set_channel_topic_completed.png`)
- [x] Setup wizard bypassed via REST API (fix applied during testing)

## Evidence Screenshots

| File | Description |
|------|-------------|
| `01_login_page_start_state.png` | Clean Rocket.Chat login page shown on task start (set_channel_topic). Verified with `visual_grounding` MCP tool. |
| `02_release_updates_channel_with_data.png` | #release-updates channel showing 12 real seeded release messages (7.8.5 through 8.1.0 from GitHub API). |
| `03_set_channel_topic_completed.png` | Successfully completed `set_channel_topic` task: topic visible in header, "Room updated successfully!" toast, system message confirming change. |
| `04_react_to_message_start_state.png` | Fresh boot with `react_to_message` task using pre_start cache. Login page shown correctly. |
| `task_start.png` | Initial task start screenshot from automated `setup_task.sh`. |
| `live_screen.png` | Screenshot captured immediately after `env.reset(...)`. |

## Log Files

| File | Description |
|------|-------------|
| `env_setup_pre_start.log` | Full output from `scripts/install_rocket_chat.sh` (pre_start hook). |
| `env_setup_post_start.log` | Full output from `scripts/setup_rocket_chat.sh` (post_start hook). |
| `task_pre_task.log` | Output from task-specific `setup_task.sh` (pre_task hook). |
| `seed_manifest.json` | Seed manifest with message IDs for all 12 seeded releases. |
| `summary.json` | Run metadata from `env.reset(seed=42, use_cache=False)`. |

## Log Snippets

### Post-start log (setup_rocket_chat.sh)

```text
Rocket.Chat responded with HTTP 200 after 20s
Seeding Rocket.Chat workspace with real release data...
{"status": "ok", "channel": "release-updates", "seeded_message_count": 12, "target_release": {"tag_name": "8.1.0", ...}}
Marking setup wizard completed via REST API...
Setup wizard marked as completed
Setting up Firefox profile for deterministic startup
=== Rocket.Chat setup complete ===
Rocket.Chat URL: http://localhost:3000
Admin credentials: admin / Admin1234!
Agent credentials: agent.user / AgentPass123!
```

### Task pre_task log (react_to_message/setup_task.sh)

```text
=== Setting up react_to_message task ===
[rocket_chat_task] Waiting for HTTP readiness: http://localhost:3000/api/info
[rocket_chat_task] HTTP ready after 0s (HTTP 200)
{"success":true}Cleared any existing thumbsup reaction on 8.1.0 message
[rocket_chat_task] Starting browser (attempt 1/4): http://localhost:3000/login
Task start screenshot: /tmp/task_start.png
=== Task setup complete ===
```

## Task Setup Script Test Results

All 10 task setup scripts tested successfully on a running environment:

```text
pin_release_message:     OK (exit 0)
react_to_message:        OK (exit 0)
star_release_message:    OK (exit 0)
create_private_channel:  OK (exit 0)
send_direct_message:     OK (exit 0)
search_release_keyword:  OK (exit 0)
change_user_status:      OK (exit 0)
invite_user_to_channel:  OK (exit 0)
post_release_followup:   OK (exit 0)
set_channel_topic:       OK (exit 0)
```

## Interactive Task Completion (set_channel_topic)

The `set_channel_topic` task was completed interactively using `visual_grounding` MCP tool:

1. Started at login page (screenshot verified with visual_grounding)
2. Logged in as `admin` / `Admin1234!` using visual_grounding coordinates
3. Navigated through setup wizard bypass (fixed via API)
4. Clicked `#release-updates` channel in sidebar
5. Clicked "Add topic" link in channel header
6. Clicked "Edit" in Channel Info panel
7. Typed topic text in Topic input field
8. Clicked "Save" button
9. Verified: "Room updated successfully!" toast, topic visible in header, system message confirming change

## Environment Details

```text
Rocket.Chat version: 8.1.0
Docker containers:
  - rc-rocketchat: Up, port 3000
  - rc-mongodb: Up, healthy (mongodb-community-server:8.2-ubi8, replSet rs0)
  - rc-nats: Up (nats:2.11-alpine)
Resolution: 1920x1080
Browser: Epiphany (GNOME Web)
```

## Full Task List (10 tasks)

| # | Task | Difficulty | Description |
|---|------|-----------|-------------|
| 1 | post_release_followup | easy | Post a follow-up message about 8.1.0 release |
| 2 | create_private_channel | medium | Create private channel "security-incidents" with agent.user |
| 3 | pin_release_message | medium | Pin the 8.0.0 release message in #release-updates |
| 4 | send_direct_message | easy | Send DM to agent.user about 8.0.0 review |
| 5 | search_release_keyword | hard | Search for "7.8.5" and reply in thread |
| 6 | invite_user_to_channel | medium | Create "deployment-log" channel and invite agent.user |
| 7 | star_release_message | medium | Star the 7.10.7 release message |
| 8 | set_channel_topic | easy | Set topic on #release-updates |
| 9 | react_to_message | medium | Add thumbsup reaction to 8.1.0 message |
| 10 | change_user_status | easy | Change status to "Busy" with custom text |

## Data Provenance

The seeded channel messages come from real Rocket.Chat GitHub releases:
- Source file: `assets/rocketchat_releases_github_api_2026-02-16.json`
- API endpoint: `https://api.github.com/repos/RocketChat/Rocket.Chat/releases?per_page=25`
- 12 releases seeded (7.8.5 through 8.1.0), each with real tag names, dates, and GitHub URLs
