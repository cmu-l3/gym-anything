# LibreOffice Impress Tasks Suite

## Overview

This comprehensive Impress tasks suite provides a complete training environment for multimodal agents to learn presentation creation and editing skills. The suite consists of **7 carefully designed tasks** that progressively build from basic slide creation to advanced diagram building and bulk editing operations.

## Tasks Overview

| Task | Difficulty | Skills Tested | Primary Tools | Duration |
|------|------------|---------------|---------------|----------|
| [**Create Basic Presentation**](create_basic_presentation/) | 🟢 Easy | Slide creation, text entry, navigation | Slide layouts, text boxes | ~60s |
| [**Apply Template**](apply_template/) | 🟢 Easy | Theme application, style management | Templates, master slides | ~45s |
| [**Export PDF**](export_pdf/) | 🟢 Easy | File export, format conversion | Export dialog | ~30s |
| [**Insert Chart**](insert_chart/) | 🟡 Medium | Chart creation, data visualization | Chart wizard, data entry | ~90s |
| [**Add Animations**](add_animations/) | 🟡 Medium | Animation timeline, transition effects | Animation pane, transitions | ~120s |
| [**Create Flowchart**](create_flowchart/) | 🟡 Medium | Shape tools, connectors, diagram layout | Drawing tools, connectors | ~180s |
| [**Bulk Text Replace**](bulk_text_replace/) | 🔴 Medium-Hard | Find/replace, bulk editing | Find & Replace dialog | ~60s |

## Task Categories

### 🟢 Beginner Level (Easy)

**Create Basic Presentation** - *Slide Creation Fundamentals*
- **Skill Focus**: Basic slide operations, text entry, slide navigation
- **Key Learning**: Creating new slides, entering titles and bullets, slide management
- **Interaction Pattern**: New slide → Enter title → Add bullets → Repeat

**Apply Template** - *Styling and Theming*
- **Skill Focus**: Template application, theme management, consistent styling
- **Key Learning**: Accessing template gallery, applying themes, preview functionality
- **Interaction Pattern**: Open presentation → Select template → Apply theme

**Export PDF** - *File Format Management*
- **Skill Focus**: File export operations, format conversion, output settings
- **Key Learning**: Export dialog navigation, format selection, quality settings
- **Interaction Pattern**: File menu → Export as PDF → Configure options → Save

### 🟡 Intermediate Level (Medium)

**Insert Chart** - *Data Visualization*
- **Skill Focus**: Chart creation, data entry, formatting and labeling
- **Key Learning**: Chart wizard workflow, data input, chart type selection
- **Interaction Pattern**: Insert chart → Enter data → Format chart → Position on slide

**Add Animations** - *Dynamic Presentations*
- **Skill Focus**: Object animations, slide transitions, timing control
- **Key Learning**: Animation pane, effect selection, transition gallery
- **Interaction Pattern**: Select object → Add animation → Configure timing → Preview

**Create Flowchart** - *Diagram Building*
- **Skill Focus**: Shape manipulation, connector tools, diagram layout
- **Key Learning**: Drawing toolbar, shape types, connector routing, alignment
- **Interaction Pattern**: Insert shapes → Add text → Connect shapes → Arrange layout

### 🔴 Advanced Level (Medium-Hard)

**Bulk Text Replace** - *Advanced Editing*
- **Skill Focus**: Find and replace operations, bulk editing across slides
- **Key Learning**: Search functionality, replace all, scope control
- **Interaction Pattern**: Open Find & Replace → Enter search term → Enter replacement → Replace all

## Verification Strategy

### Automated Verification System

Each task employs sophisticated automated verification using ODP/PPTX file parsing:

**Structural Validation**
- **Slide Count**: Verify correct number of slides created
- **Layout Verification**: Check slide layouts and structure
- **Content Presence**: Ensure required elements exist (text, images, shapes)

**Content Analysis**
- **Text Matching**: Verify titles, bullet points, and body text
- **Image Detection**: Check for presence of required images
- **Chart Validation**: Confirm chart type and data representation
- **Shape Analysis**: Count and classify shapes (rectangles, ellipses, connectors)

**Formatting Checks**
- **Template Application**: Verify theme/template is applied correctly
- **Font Properties**: Check font sizes, styles, colors
- **Alignment**: Verify object positioning and alignment
- **Color Schemes**: Validate color palette usage

**Advanced Features**
- **Animation Detection**: Check for object animations (where applicable)
- **Transition Verification**: Validate slide transitions (where applicable)
- **Export Quality**: Verify PDF export settings and output

### Scoring System

- **4-Criteria Evaluation**: Most tasks evaluate 4 key aspects for comprehensive assessment
- **Percentage Scoring**: 0-100% scores with detailed breakdown
- **Pass Threshold**: 75% minimum (3/4 criteria) ensures quality standards
- **Granular Feedback**: Specific feedback on each criterion with actionable insights

## Technical Architecture

### File Structure

Each task follows a consistent structure:

```
task_name/
├── task.json              # Task specification
├── setup_task.sh         # Pre-task setup (create/open presentation)
├── export_result.sh      # Post-task export (save presentation)
├── verifier.py          # Verification logic
├── README.md            # Task documentation
└── assets/              # Task-specific assets (optional)
    └── ...
```

### Verification Workflow

1. **Setup**: `setup_task.sh` creates initial presentation state
2. **Agent Interaction**: Agent performs required operations
3. **Export**: `export_result.sh` saves presentation to known location
4. **Copy**: Verifier copies presentation file from container to host
5. **Parse**: File is parsed using `odfpy` (ODP) or `python-pptx` (PPTX)
6. **Verify**: Content, structure, and formatting are validated
7. **Score**: Results are scored and feedback is generated
8. **Cleanup**: Temporary files are removed

### Shared Infrastructure

**`impress_verification_utils.py`** - Central utility system providing:
- **File Parsing**: ODP and PPTX file parsing with structure extraction
- **Content Extraction**: Text, images, shapes, charts, animations
- **Validation Helpers**: Common verification patterns and checks
- **Resource Management**: Temporary file handling and cleanup

**`task_utils.sh`** - Bash utility functions:
- **Window Management**: Focus windows, wait for appearance
- **Process Monitoring**: Wait for LibreOffice to start
- **File Operations**: Wait for files to be saved
- **Safe Execution**: User context preservation, error handling

## Usage Guide

### Running Individual Tasks

```bash
# Run specific task
python -m gym_anything.cli run libreoffice_impress_env --task create_basic_presentation

# Validate task configuration
python -m gym_anything.cli validate libreoffice_impress_env --task create_basic_presentation
```

### Training Sequences

**Beginner Sequence**: `create_basic_presentation` → `apply_template` → `export_pdf`

**Intermediate Sequence**: `insert_chart` → `add_animations` → `create_flowchart`

**Advanced Challenge**: `bulk_text_replace`

**Complete Mastery**: All 7 tasks in random order

### VNC Debugging

```bash
# Access running environment via VNC
# URL: vnc://localhost:5953
# Password: password
```

## Learning Objectives

### Primary Skills

1. **Presentation Structure**: Understanding slide organization and flow
2. **Content Creation**: Creating and formatting text, lists, titles
3. **Visual Design**: Applying themes, colors, layouts consistently
4. **Data Visualization**: Creating charts and graphs from data
5. **Diagram Building**: Constructing flowcharts and process diagrams
6. **Animation & Transitions**: Adding dynamic effects to presentations
7. **File Management**: Saving, exporting, format conversion

### Competency Progression

- **Stage 1**: Basic slide creation and text entry
- **Stage 2**: Template application and styling
- **Stage 3**: Content insertion (charts, images, shapes)
- **Stage 4**: Advanced formatting and layout
- **Stage 5**: Dynamic features (animations, transitions)
- **Stage 6**: Complex diagram creation
- **Stage 7**: Bulk editing and advanced operations

## Extensions and Customization

### Adding New Tasks

1. Create task directory in `tasks/`
2. Write `task.json` specification
3. Implement `setup_task.sh` for initialization
4. Implement `export_result.sh` for saving
5. Write `verifier.py` using verification utilities
6. Document in task `README.md`
7. Add any required assets to `assets/` directory

### Custom Templates

Place custom `.otp` template files in `config/` directory or task-specific `assets/` directories.

### Verification Enhancements

Add new verification functions to `utils/impress_verification_utils.py` for:
- Custom shape detection patterns
- Advanced animation parsing
- Template compliance checking
- Accessibility validation

---

This comprehensive LibreOffice Impress training suite provides everything needed for world-class multimodal agent development in presentation software! 🎯
