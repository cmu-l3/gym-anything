# LibreOffice Impress Environment

A comprehensive LibreOffice Impress presentation software environment for `gym-anything`, designed for training agents on slide creation, formatting, animations, multimedia embedding, and presentation design tasks.

## Overview

This environment provides a complete LibreOffice Impress setup with:
- **LibreOffice Impress 7.x+** with full suite capabilities
- **Python libraries** for programmatic presentation file parsing and verification
- **Template system** with pre-configured themes and layouts
- **7 progressive tasks** from basic slide creation to advanced diagram building
- **Multi-format support** (ODP, PPTX, PDF, HTML)
- **VNC access** for visual observation and debugging
- **Full GUI automation** support via `xdotool` and `wmctrl`

## Features

### Core Capabilities

1. **Slide Creation & Editing**
   - Text boxes, bullet points, numbered lists
   - Master slides and slide layouts
   - Slide notes and hidden slides
   - Slide numbering and footers

2. **Content Insertion**
   - Images (PNG, JPEG, SVG)
   - Charts and graphs (from Calc or manual data)
   - Tables with formatting
   - Shapes, lines, connectors
   - Multimedia (audio, video)

3. **Formatting & Design**
   - Templates and themes
   - Font styles, colors, sizes
   - Paragraph formatting and alignment
   - Background colors, gradients, images
   - Object positioning and layering

4. **Animations & Transitions**
   - Slide transitions (fade, dissolve, wipe, etc.)
   - Object animations (entrance, emphasis, exit, motion paths)
   - Animation timing and sequencing
   - Transition effects and speeds

5. **Advanced Features**
   - SmartArt-like diagrams and flowcharts
   - Drawing tools and shape editing
   - Presenter console with notes
   - Custom slide shows
   - Handout and notes printing

6. **File Formats**
   - Native: ODP (Open Document Presentation)
   - Import/Export: PPTX, PPT, PDF
   - Export: HTML, images (PNG, JPEG, SVG)

7. **Verification Access**
   - Parse ODP files via `odfpy` library
   - Parse PPTX files via `python-pptx` library
   - Headless mode for conversions and checks
   - UNO API for advanced inspection

## Directory Structure

```
libreoffice_impress_env/
├── env.json                          # Environment specification
├── README.md                         # This file
├── scripts/
│   ├── install_impress.sh           # LibreOffice installation script
│   ├── setup_impress.sh             # Impress configuration script
│   └── task_utils.sh                # Shared task utilities
├── config/
│   ├── registrymodifications.xcu    # Impress preferences
│   └── default_template.otp         # Default presentation template
├── utils/
│   ├── __init__.py
│   └── impress_verification_utils.py # Verification utilities
└── tasks/                            # Task definitions (7 tasks)
```

## Usage

### Quick Start

```python
import gym_anything as ga

# Load the Impress environment
env = ga.from_config("libreoffice_impress_env")

# Reset the environment
obs = env.reset(seed=42)

# Environment is ready with Impress launched
# VNC viewer accessible on port 5953
```

### Running Tasks

```bash
# Run a specific task
python -m gym_anything.cli run libreoffice_impress_env --task create_basic_presentation

# Validate task configuration
python -m gym_anything.cli validate libreoffice_impress_env --task create_basic_presentation

# Run all tasks sequentially
python -m gym_anything.cli run libreoffice_impress_env --all-tasks
```

## Task Overview

### 🟢 Easy Tasks

1. **Create Basic Presentation** (`create_basic_presentation`)
   - Create 5 slides with titles and bullet points
   - **Skills**: Basic slide creation, text entry, slide navigation

2. **Apply Template** (`apply_template`)
   - Apply a specific theme/template to presentation
   - **Skills**: Template application, theme management

3. **Export PDF** (`export_pdf`)
   - Export presentation to PDF with specific settings
   - **Skills**: File export, format conversion

### 🟡 Medium Tasks

4. **Insert Chart** (`insert_chart`)
   - Insert and format a data chart on slide
   - **Skills**: Chart insertion, data entry, formatting

5. **Add Animations** (`add_animations`)
   - Add slide transitions and object animations
   - **Skills**: Animation timeline, transition effects

6. **Create Flowchart** (`create_flowchart`)
   - Build flowchart using shapes and connectors
   - **Skills**: Shape tools, connectors, diagram layout

### 🔴 Medium-Hard Tasks

7. **Bulk Text Replace** (`bulk_text_replace`)
   - Find and replace text across all slides
   - **Skills**: Find/replace dialog, bulk editing

## User Accounts

The environment includes one pre-configured user account:

- **`ga`** (primary user)
  - Full sudo access
  - Home: `/home/ga`
  - VNC display: `:1`
  - Impress profile: `/home/ga/.config/libreoffice/4/user`

## Network Ports

- **5953**: VNC server (external access)

## File Locations

### LibreOffice Profile
- `/home/ga/.config/libreoffice/4/user/`

### Important Directories
- **User Profile**: `.config/libreoffice/4/user/`
- **Templates**: `.config/libreoffice/4/user/template/`
- **Gallery**: `.config/libreoffice/4/user/gallery/`
- **Extensions**: `.config/libreoffice/4/user/uno_packages/`

### Task Files
- **Workspace**: `/home/ga/Documents/Presentations/`
- **Task Assets**: `/workspace/tasks/<task_id>/assets/`
- **Results**: `/home/ga/Documents/results/`

## Verification Utilities

The `utils/impress_verification_utils.py` module provides helper functions:

```python
from impress_verification_utils import *

# Parse presentation files
odp_data = parse_odp_file("/path/to/file.odp")
pptx_data = parse_pptx_file("/path/to/file.pptx")

# Get slide count
count = get_slide_count(odp_data)

# Get slide content
title, bullets = get_slide_text_content(odp_data, slide_index=0)

# Check for images
has_images = check_slide_has_images(odp_data, slide_index=0)

# Check for animations
has_animations = check_slide_has_animations(odp_data, slide_index=0)

# Verify slide transitions
has_transition = verify_slide_transition(odp_data, slide_index=0)

# Check for shapes
shapes = get_slide_shapes(odp_data, slide_index=0)

# Verify chart existence
has_chart = check_slide_has_chart(odp_data, slide_index=0)
```

## GUI Automation

The environment includes `xdotool` and `wmctrl` for GUI automation:

```bash
# Focus Impress window
wmctrl -a "LibreOffice Impress"

# Insert new slide
xdotool key ctrl+m

# Start presentation
xdotool key F5

# Take screenshot
import -window root screenshot.png
```

## Headless Mode

LibreOffice Impress can be used in headless mode for conversions:

```bash
# Convert ODP to PPTX
libreoffice --headless --convert-to pptx file.odp

# Convert to PDF
libreoffice --headless --convert-to pdf file.odp

# Export as images
libreoffice --headless --convert-to png file.odp
```

## Logs

- **Impress**: `/tmp/impress_ga.log`
- **Setup**: Check Docker logs or `/tmp/` directory

## Debugging

### Enable VNC Viewer
Connect to `localhost:5953` with password `password` to see the desktop.

### Check Impress Status
```bash
# Inside container
ps aux | grep soffice
ls -la /home/ga/.config/libreoffice/

# Test headless mode
libreoffice --headless --version
```

### Verify File Parsing
```bash
# Test ODP parsing
python3 -c "from odf import opendocument; doc = opendocument.load('file.odp'); print('OK')"

# Test PPTX parsing
python3 -c "from pptx import Presentation; prs = Presentation('file.pptx'); print('OK')"
```

## Advanced Configuration

### Custom Templates

Place custom templates in `config/` directory and they will be available in Impress template gallery.

### Custom Preferences

Modify `config/registrymodifications.xcu` to set default preferences:

```xml
<item oor:path="/org.openoffice.Office.Impress/Layout">
  <prop oor:name="Display" oor:op="fuse">
    <value>1</value>
  </prop>
</item>
```

## Troubleshooting

### Impress Won't Start
- Check `/tmp/impress_ga.log` for errors
- Ensure X11 display is running (`DISPLAY=:1`)
- Verify user permissions

### VNC Connection Issues
- Ensure VNC server is running on port 5953
- Check password is correct: `password`
- Verify port mapping in Docker configuration

### File Parsing Issues
- Ensure presentation is saved before verification
- Check file format (ODP vs PPTX)
- Verify file is not corrupted

## Contributing

To add new verification utilities:

1. Add functions to `utils/impress_verification_utils.py`
2. Update `utils/__init__.py` exports
3. Document in this README
4. Add example usage

## License

This environment configuration is part of the `gym-anything` project.

## References

- [LibreOffice Impress Documentation](https://help.libreoffice.org/Impress)
- [ODF (Open Document Format) Specification](https://docs.oasis-open.org/office/OpenDocument/)
- [python-pptx Documentation](https://python-pptx.readthedocs.io/)
- [odfpy Documentation](https://github.com/eea/odfpy)
