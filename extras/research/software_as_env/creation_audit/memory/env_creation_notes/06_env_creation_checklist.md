# Environment Creation Checklist

## Before Starting
- [ ] **Read `10_cross_cutting_patterns.md`** — essential patterns from 100+ envs (service readiness, dialog suppression, Docker v2, snap gotchas, verification, setsid, pgrep bugs, XAUTHORITY, verify-against-user-flow #35, convention-following #36, probe-before-speculating #37, and more)
- [ ] **If Windows app:** Read `11_windows_environments.md` — Session 0, schtasks /IT, Win32 vs PyAutoGUI, Office installs
- [ ] **If macOS app:** Read `12_macos_environments.md` — UseComputerRunner, `/Users/lume/workspace` (SIP read-only root), Rosetta, DMG / .pkg install patterns, TCC over SSH, no checkpoint caching
- [ ] Verify application is free/has appropriate license
- [ ] Find official download URL (.deb preferred for Ubuntu; .dmg for macOS) — have fallback URLs (see pattern #7) and **probe the URL is alive before relying on it** (see pattern #37)
- [ ] Identify application dependencies
- [ ] Check if application has first-run dialogs that need handling — plan two-layer suppression (see pattern #2)
- [ ] Check if it's a snap package — review snap-specific gotchas (see pattern #4)
- [ ] Check `specific_env_notes/` for notes on similar applications — **conventions there are authoritative defaults** (pattern #36)

## File Creation
- [ ] Create directory structure: `benchmarks/cua_world/environments/<env_name>/{scripts,config,tasks,utils}`
- [ ] Create `env.json`
- [ ] Create `scripts/install_<app>.sh`
- [ ] Create `scripts/setup_<app>.sh`
- [ ] **Set execute permissions on all .sh files immediately**

```bash
chmod +x benchmarks/cua_world/environments/<env_name>/scripts/*.sh
```

## For Each Task
- [ ] Create task directory: `tasks/<task_name>/`
- [ ] Create `task.json`
- [ ] Create `verifier.py` (stub — VLM verification is external)
- [ ] Create `setup_task.sh` (ensure correct start state with real data)
- [ ] **Set execute permissions**

```bash
chmod +x benchmarks/cua_world/environments/<env_name>/tasks/*/*.sh
```

## Testing Sequence (ALL INTERACTIVE)

**CRITICAL: Do NOT write test scripts. All testing must be done interactively.**

### The Interactive Testing Loop

```
1. Start environment: env.reset()
2. Take screenshot: DISPLAY=:1 scrot /tmp/screen.png
3. Analyze screenshot (Claude: `visual_grounding`; Codex: native/`ask_cua.py`)
4. Perform action: DISPLAY=:1 xdotool mousemove X Y click 1
5. Repeat 2-4 until task complete
6. Run export script, verify results
7. If issues → fix scripts → env.close() → restart
```

### Step-by-Step

1. **Start environment with task:**
   ```python
   env = from_config("benchmarks/cua_world/environments/<env_name>", task_id="<task_name>")
   obs = env.reset(seed=42, use_cache=False)
   ssh.connect('localhost', port=env._runner.ssh_port, ...)
   ```

2. **Take screenshot and get UI guidance:**
   ```bash
   # Take screenshot
   ssh.exec_command('DISPLAY=:1 scrot /tmp/screen.png')
   sftp.get('/tmp/screen.png', '/tmp/local_screen.png')

   # Claude: call `visual_grounding` MCP tool with:
   #   - question: "Where do I click to open File menu?"
   #   - screenshot_path: "/tmp/local_screen.png"
   #
   # Codex: either inspect the screenshot directly, or run:
   #   python ask_cua.py --question "Where do I click to open File menu?" --screenshot_path "/tmp/local_screen.png"
   ```

3. **Execute action with xdotool:**
   ```python
   # Scale normalized 1280x720 coords to actual resolution (1920x1080)
   actual_x = int(vg_x * 1920 / 1280)
   actual_y = int(vg_y * 1080 / 720)
   ssh.exec_command(f'DISPLAY=:1 xdotool mousemove {actual_x} {actual_y} click 1')
   ```

4. **Repeat until task is complete**

5. **Verify task start state:**
   Use screenshot grounding (Claude: `visual_grounding`; Codex: native/`ask_cua.py`) to confirm the application is in the correct state with real data visible.

See `03_interactive_testing.md` for complete details.

## Common Issues to Watch For

> For comprehensive explanations and solutions, see `10_cross_cutting_patterns.md`.

1. **Scripts not executable** - Most common issue. Always chmod +x
2. **Hook logs empty** - Script failed before producing output
3. **Application not starting** - Check DISPLAY variable is set
4. **Multiple dialogs blocking** - Use two-layer suppression: config files + runtime xdotool + warm-up launch (pattern #2, #13)
5. **Network-dependent app fails** - Ensure `net: true` in env.json
6. **Hook timeout errors** - Ensure base class exec() signature matches derived class
7. **xdotool automation fails** - Use command-line macros instead (e.g., `-macro` for ImageJ)
8. **Large downloads timeout** - Cache at install time, use longer wget timeouts, have fallback URLs (pattern #7)
9. **Directory names case-sensitive** - Check both `astroimagej` and `AstroImageJ`
10. **Invalid macro commands** - Test macros in actual app (commands differ between versions)
11. **Coordinate scaling wrong** - Remember to scale from 1280x720 to actual resolution (pattern #16)
12. **GNOME Activities triggers** - Avoid clicking near top-left; use keyboard shortcuts
13. **Docker Compose v1 bugs** - Use v2 (`docker compose`, not `docker-compose`) (pattern #8)
14. **Process detection collisions** - Use `pgrep -f /full/path/to/binary`, not short names (pattern #3)
15. **Service not ready after container start** - Add health-check polling with timeout (pattern #1)
16. **Snap package quirks** - Different profile paths, confinement restrictions, no --profile flag (pattern #4)
17. **File permissions after docker cp** - Match container's runtime UID/GID (pattern #9)
18. **SQLite database locked** - Copy to temp before querying (pattern #10)

## Verification Checklist

Before considering a task complete:

- [ ] **Environment starts correctly** - Software opens to expected state
- [ ] **Task start state is correct** - App in correct screen/view with real data (verified via screenshot grounding)
- [ ] **Task is completable** - Sufficient evidence (screenshots of key steps) that it can be done end-to-end

## Scientific Applications Checklist

For astronomy, medical imaging, GIS applications:

- [ ] **Use real datasets** - Never synthetic data for tasks
- [ ] **Cache large downloads** - At install time, not task setup
- [ ] **Handle data count variations** - Download may have fewer files than expected
- [ ] **Pre-load data when specified** - Some tasks require data ready on start
