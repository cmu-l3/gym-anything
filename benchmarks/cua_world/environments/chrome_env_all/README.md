# Chrome Environment (`chrome_env_all`)

A comprehensive Google Chrome browser environment for `gym-anything` with full Chrome DevTools Protocol (CDP) support, designed for web automation, testing, and benchmarking tasks.

## Overview

This environment provides a complete Chrome browser setup with:
- **Chrome DevTools Protocol (CDP)** access on port 9222
- **Remote debugging** support for programmatic control
- **Comprehensive utilities** for verification tasks
- **Multiple user accounts** for different access levels
- **VNC access** for visual observation and debugging
- **Full GUI automation** support via `xdotool` and `wmctrl`

## Features

### Core Capabilities

1. **Browser Control**
   - Launch Chrome with custom flags and settings
   - CDP remote debugging on configurable ports
   - Socat port forwarding for external CDP access
   - Full keyboard and mouse automation

2. **Data Access & Verification**
   - **Bookmarks**: Read/verify bookmark folders and URLs
   - **History**: Access browsing history database
   - **Cookies**: Query cookie storage
   - **Extensions**: List and verify installed extensions
   - **Settings**: Font sizes, experiments/flags, preferences
   - **Downloads**: Access downloaded files
   - **Screenshots/PDFs**: Capture and verify visual output

3. **File Handling**
   - PDF comparison utilities
   - HTML comparison tools
   - Archive extraction and comparison
   - Image/audio/video verification

4. **Configuration**
   - Custom Chrome preferences
   - Default download directory setup
   - Bookmark structure initialization
   - Extension management

### Supported OSWorld Chrome Metrics

This environment is designed to support all OSWorld Chrome evaluation metrics:

- `is_expected_active_tab`: URL verification
- `is_expected_url_pattern_match`: Regex pattern matching
- `is_expected_tabs`: Multiple tab verification
- `is_expected_bookmarks`: Bookmark folder and URL checks
- `is_expected_installed_extensions`: Extension verification
- `is_expected_search_query`: Search query validation
- `compare_pdfs`: PDF content comparison
- `compare_pdf_images`: PDF image comparison
- `compare_htmls`: HTML structure comparison
- `compare_archive`: Archive content comparison
- `is_cookie_deleted`: Cookie deletion verification
- `is_shortcut_on_desktop`: Desktop shortcut verification
- `check_history_deleted`: History deletion verification
- `check_enabled_experiments`: Chrome flags/experiments
- `check_font_size`: Font size settings
- `is_added_to_steam_cart`: Content verification

## Directory Structure

```
chrome_env_all/
├── env.json                          # Environment specification
├── README.md                         # This file
├── scripts/
│   ├── install_chrome.sh            # Chrome installation script
│   └── setup_chrome.sh              # Chrome configuration script
├── config/
│   └── chrome_preferences.json      # Default Chrome preferences
├── utils/
│   ├── __init__.py
│   └── chrome_verification_utils.py # Verification utilities
└── tasks/                            # Task definitions (add your tasks here)
```

## Usage

### Quick Start

```python
import gym_anything as ga

# Load the Chrome environment
env = ga.from_config("examples/chrome_env_all")

# Reset the environment
obs = env.reset(seed=42)

# Environment is ready with Chrome launched
# Chrome CDP available on port 9222
# VNC viewer accessible on port 5951
```

### Creating Tasks

Tasks should be placed in the `tasks/` directory. Each task needs:

1. **`task.json`**: Task specification
2. **`setup_task.sh`** (optional): Pre-task setup script
3. **`export_result.sh`** (optional): Post-task export script
4. **`verifier.py`**: Verification logic

Example task structure:

```json
{
  "id": "navigate_to_url@1",
  "version": "1.0",
  "env_id": "example.chrome_env@0.1",
  "description": "Navigate to a specific URL",
  "init": {
    "timeout_sec": 60,
    "max_steps": 10,
    "reward_type": "sparse"
  },
  "hooks": {
    "pre_task": "/workspace/tasks/navigate_to_url/setup_task.sh",
    "post_task": "/workspace/tasks/navigate_to_url/export_result.sh"
  },
  "success": {
    "spec": {
      "program": "verifier.py::check_url_navigation"
    }
  }
}
```

### Using Verification Utilities

```python
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
from chrome_verification_utils import *

def check_url_navigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    
    # Get active tab URL using CDP utility
    # Or copy and parse Chrome files
    success, files, error = setup_chrome_verification(
        copy_from_env,
        ["Bookmarks", "History", "Preferences"]
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": error}
    
    # Verify bookmarks
    bookmarks_ok = verify_bookmarks_folders(
        files["Bookmarks"],
        expected_folders=["Work", "Personal"]
    )
    
    # Clean up
    cleanup_verification_temp()
    
    return {
        "passed": bookmarks_ok,
        "score": 100 if bookmarks_ok else 0,
        "feedback": "Bookmarks verified" if bookmarks_ok else "Bookmarks mismatch"
    }
```

## User Accounts

The environment includes two pre-configured user accounts:

1. **`ga`** (primary user)
   - Full sudo access
   - Chrome debugging port: 1337
   - Home: `/home/ga`
   - VNC display: `:1`

2. **`webuser`** (secondary user)
   - Limited access
   - Chrome debugging port: 1338
   - Home: `/home/webuser`

## Network Ports

- **5951**: VNC server (external access)
- **9222**: CDP (Chrome DevTools Protocol) - forwarded to port 1337
- **1337**: Chrome remote debugging (ga user)
- **1338**: Chrome remote debugging (webuser user)

## CDP (Chrome DevTools Protocol) Access

### From Inside Container

```bash
# Get active tab info
chrome-cdp-util active-url
chrome-cdp-util active-tab

# List all tabs
chrome-cdp-util list-tabs
chrome-cdp-util tabs-json
```

### From Python (Inside Container)

```python
import requests

# Get all tabs
response = requests.get('http://localhost:9222/json')
tabs = response.json()

# Get active tab URL
active_tab = tabs[0] if tabs else {}
url = active_tab.get('url', '')
```

### From Host Machine

```python
import requests

# Access CDP through Docker port mapping
# (assuming port 9222 is mapped in Docker config)
response = requests.get('http://localhost:9222/json')
tabs = response.json()
```

## GUI Automation

The environment includes `xdotool` and `wmctrl` for GUI automation:

```bash
# Focus address bar and navigate
xdotool key ctrl+l
xdotool type "https://example.com"
xdotool key Return

# Take screenshot
import -window root screenshot.png

# Focus Chrome window
wmctrl -a "Google Chrome"
```

## File Locations

### Chrome Profile
- `/home/ga/.config/google-chrome/Default/`
- `/home/webuser/.config/google-chrome/Default/`

### Important Files
- **Bookmarks**: `.config/google-chrome/Default/Bookmarks`
- **History**: `.config/google-chrome/Default/History` (SQLite DB)
- **Cookies**: `.config/google-chrome/Default/Cookies` (SQLite DB)
- **Preferences**: `.config/google-chrome/Default/Preferences`
- **Extensions**: `.config/google-chrome/Default/Extensions/`

### Downloads
- `/home/ga/Downloads/`
- `/home/webuser/Downloads/`

## Logs

- **Chrome**: `/tmp/chrome_<username>.log`
- **Socat CDP**: `/tmp/socat_cdp.log`
- **Setup**: Check Docker logs or `/tmp/` directory

## Debugging

### Enable VNC Viewer
Connect to `localhost:5951` with password `password` to see the desktop.

### Check Chrome Status
```bash
# Inside container
ps aux | grep chrome
netstat -tlnp | grep 1337
chrome-cdp-util list-tabs
```

### Verify CDP Access
```bash
curl http://localhost:9222/json
```

## Advanced Configuration

### Custom Chrome Flags

Edit `scripts/setup_chrome.sh` and modify the `launch_chrome.sh` section to add custom flags:

```bash
google-chrome-stable \
    --remote-debugging-port=$remote_debugging_port \
    --your-custom-flag \
    ...
```

### Custom Preferences

Modify `config/chrome_preferences.json` to set default preferences.

### Extensions

To pre-install extensions, download `.crx` files and add them in `scripts/setup_chrome.sh`:

```bash
google-chrome-stable --pack-extension=/path/to/extension
```

## Integration with OSWorld

This environment is designed to be compatible with OSWorld Chrome tasks. The verification utilities in `utils/chrome_verification_utils.py` provide helper functions that align with OSWorld's evaluation metrics.

To adapt an OSWorld Chrome task:

1. Place the task definition in `tasks/`
2. Use the verification utilities for evaluation
3. Ensure CDP access for dynamic checks
4. Copy necessary Chrome files for static verification

## Troubleshooting

### Chrome Won't Start
- Check `/tmp/chrome_ga.log` for errors
- Ensure X11 display is running (`DISPLAY=:1`)
- Verify user permissions

### CDP Not Accessible
- Check socat is running: `ps aux | grep socat`
- Verify port forwarding: `netstat -tlnp | grep 9222`
- Check firewall settings

### VNC Connection Issues
- Ensure VNC server is running on port 5951
- Check password is correct: `password`
- Verify port mapping in Docker configuration

## Contributing

To add new verification utilities:

1. Add functions to `utils/chrome_verification_utils.py`
2. Update `utils/__init__.py` exports
3. Document in this README
4. Add example usage

## License

This environment configuration is part of the `gym-anything` project.

## References

- [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/)
- [gym-anything Documentation](../../docs/)
- [OSWorld Benchmark](https://os-world.github.io/)

