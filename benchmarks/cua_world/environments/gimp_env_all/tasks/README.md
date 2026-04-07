# GIMP Tasks Suite - Complete Training Environment

## Overview

This comprehensive GIMP tasks suite provides a complete training environment for multimodal agents to learn image editing skills. The suite consists of **7 carefully designed tasks** that progressively build from basic operations to advanced image manipulation techniques, covering all essential GIMP workflows used in professional digital content creation.

## Tasks Overview

| Task | Difficulty | Skills Tested | Primary Tools | Duration |
|------|------------|---------------|---------------|----------|
| [**Horizontal Mirror**](horizontal_mirror/) | 🟢 Easy | Transform operations, basic tool usage | Flip Tool | ~5 steps |
| [**Undo Configuration**](undo_config/) | 🟢 Easy | Preferences management, settings navigation | Preferences Dialog | ~5 steps |
| [**Crop and Resize**](crop_resize/) | 🟢 Easy | Selection, scaling, composition basics | Crop Tool, Scale Image | ~10 steps |
| [**Brightness Reduction**](brightness_reduction/) | 🟡 Medium | Image adjustments, slider control | Brightness-Contrast | ~10 steps |
| [**Color Replacement**](color_replacement/) | 🟡 Medium | Color theory, selection tools, HSV manipulation | Select by Color, Hue-Saturation | ~10 steps |
| [**Styled Text Overlay**](text_overlay/) | 🟡 Medium | Text tools, styling, effects application | Text Tool, Layer Effects | ~10 steps |
| [**Green Background Fill**](green_background/) | 🔴 Medium+ | Layer management, XCF handling, advanced workflow | Layers, Fill Tools | ~10 steps |

## Skill Progression Matrix

### 🎯 **Interaction Skills Covered**
- **Basic Clicking & Selection**: All tasks require precise tool selection and clicking
- **Drag Operations**: Crop areas, adjust sliders, position elements
- **Menu Navigation**: Multi-level menu systems (Image → Transform, Colors → Adjust)
- **Dialog Management**: Working with complex dialogs (Preferences, Hue-Saturation, Scale Image)
- **Keyboard Shortcuts**: Tool shortcuts (T for text, Shift+C for crop, Shift+O for color select)
- **Multi-step Workflows**: Combining multiple tools in logical sequences

### 🛠️ **GIMP Knowledge Domains**
- **Core Tools**: Flip, Crop, Text, Select by Color, Fill Tools
- **Adjustment Systems**: Brightness-Contrast, Hue-Saturation, Color manipulation
- **Layer Management**: Layer creation, background fills, transparency handling
- **File Format Handling**: JPEG, PNG, XCF (GIMP native format)
- **Preferences System**: Application settings, undo configuration
- **Export Workflows**: Automated and manual export processes

### 🎨 **Domain-Specific Skills**
- **Image Composition**: Subject identification, cropping for focus, aspect ratio management
- **Color Theory**: HSV color space, hue relationships, color replacement techniques
- **Typography**: Text placement, styling, effects application, readability optimization
- **Photo Enhancement**: Brightness adjustment, contrast control, visual appeal improvement
- **Technical Configuration**: Settings management, workflow optimization

## Task Difficulty Progression

### 🟢 **Beginner Level (Easy)**
Perfect for agents learning basic GIMP interactions and fundamental concepts.

**Horizontal Mirror** - *Transform Operations*
- **Skill Focus**: Basic tool usage, transform operations
- **Key Learning**: Tool selection, single-action operations
- **Interaction Pattern**: Select tool → Apply transform → Export

**Undo Configuration** - *Settings Management*  
- **Skill Focus**: Preferences navigation, settings modification
- **Key Learning**: Menu systems, dialog interaction, configuration persistence
- **Interaction Pattern**: Navigate preferences → Modify setting → Apply changes

**Crop and Resize** - *Selection and Scaling*
- **Skill Focus**: Subject identification, precise dimension control
- **Key Learning**: Composition basics, tool combination workflows
- **Interaction Pattern**: Select area → Crop → Scale to dimensions → Export

### 🟡 **Intermediate Level (Medium)**
Builds on basic skills with more complex tool combinations and decision-making.

**Brightness Reduction** - *Image Adjustment*
- **Skill Focus**: Visual assessment, slider control, image enhancement
- **Key Learning**: Adjustment dialogs, real-time preview, quality evaluation
- **Interaction Pattern**: Open adjustment → Analyze image → Adjust values → Apply

**Color Replacement** - *Advanced Color Manipulation*
- **Skill Focus**: Color theory, selection refinement, HSV understanding
- **Key Learning**: Color space manipulation, selection tools, threshold adjustment
- **Interaction Pattern**: Select colors → Adjust selection → Transform hue → Validate results

**Styled Text Overlay** - *Typography and Effects*
- **Skill Focus**: Text placement, styling, visual hierarchy, readability
- **Key Learning**: Text tool mastery, effects application, composition integration
- **Interaction Pattern**: Position text → Style typography → Apply effects → Integrate with image

### 🔴 **Advanced Level (Medium+)**
Complex workflows requiring multiple tool mastery and advanced file handling.

**Green Background Fill** - *Layer Management and XCF Workflow*
- **Skill Focus**: Layer operations, advanced file formats, precision editing
- **Key Learning**: XCF handling, layer isolation, non-destructive editing
- **Interaction Pattern**: Open XCF → Select background layer → Fill with color → Preserve foreground

## Verification Strategy

### 🔍 **Multi-Modal Verification System**
Each task employs sophisticated verification tailored to its specific requirements:

**Mathematical Analysis**
- **Dimensional Verification**: Exact pixel measurements for resize operations
- **Color Space Analysis**: RGB/HSV mathematical validation for color tasks
- **Statistical Comparison**: Image similarity metrics, brightness calculations
- **Geometric Validation**: Transform accuracy, positioning verification

**Perceptual Quality Assessment**  
- **Visual Change Detection**: Pixel-wise difference analysis with clustering
- **Composition Evaluation**: Subject focus, text placement, visual balance
- **Quality Preservation**: Detail retention, edge preservation during edits
- **Artistic Merit**: Color harmony, typography effectiveness, overall appeal

**Technical Validation**
- **File Format Compliance**: Proper export format and quality
- **Workflow Correctness**: Proper tool usage sequence and technique
- **Setting Persistence**: Configuration changes properly saved
- **Error Handling**: Graceful handling of edge cases and variations

### 📊 **Scoring and Feedback System**
- **4-Criteria Evaluation**: Each task evaluates 4 key aspects for comprehensive assessment
- **Percentage Scoring**: 0-100% scores with detailed breakdown and feedback
- **Pass Threshold**: 75% minimum (3/4 criteria) ensures quality standards
- **Granular Feedback**: Specific feedback on each criterion with actionable insights

## Technical Architecture

### 🏗️ **File Structure**
```
tasks/
├── README.md                    # This comprehensive overview
├── verification_utils.py        # Shared verification utilities
├── brightness_reduction/         # Image adjustment task
│   ├── task.json
│   ├── setup_brightness_task.sh
│   ├── export_result.sh
│   └── verifier.py
├── horizontal_mirror/            # Transform operation task
│   ├── task.json
│   ├── setup_mirror_task.sh
│   ├── export_mirror.sh
│   └── verifier.py
├── green_background/            # Layer management task
│   ├── task.json
│   ├── setup_green_task.sh
│   ├── export_green.sh
│   └── verifier.py
├── undo_config/                # Configuration task
│   ├── task.json
│   ├── setup_undo_task.sh
│   ├── close_gimp.sh
│   └── verifier.py
├── text_overlay/               # Typography task
│   ├── task.json
│   ├── setup_text_task.sh
│   ├── export_text.sh
│   └── verifier.py
├── crop_resize/                # Selection and scaling task
│   ├── task.json
│   ├── setup_crop_task.sh
│   ├── export_crop.sh
│   ├── verifier.py
│   └── README.md
└── color_replacement/          # Color manipulation task
    ├── task.json
    ├── setup_color_task.sh
    ├── export_color.sh
    ├── verifier.py
    └── README.md
```

### ⚙️ **Shared Infrastructure**
**`verification_utils.py`** - Central utility system providing:
- **File Management**: Robust container-to-host file transfer with fallback search
- **Image Validation**: Format verification, corruption detection, size validation
- **Error Handling**: Graceful degradation and comprehensive error reporting
- **Resource Cleanup**: Automatic temporary file management and memory cleanup
- **Fallback Search**: Smart pattern matching for user-named files

### 🐳 **Container Integration**
- **Base Environment**: `ubuntu-gnome-systemd` with full desktop and systemd support
- **GIMP Installation**: Complete GIMP 2.10.x with plugins and extensions
- **VNC Access**: Interactive viewing and debugging capability
- **Automated Workflows**: Scripted setup, execution, and export processes
- **User Management**: Multi-user support with configurable permissions

## Usage Guide

### 🚀 **Running Individual Tasks**
```bash
# Run specific task
python -m gym_anything.cli run examples/gimp_env3 --task <task_name>

# Validate task configuration
python -m gym_anything.cli validate examples/gimp_env3 --task <task_name>

# Available tasks: brightness_reduction, horizontal_mirror, green_background, 
#                 undo_config, text_overlay, crop_resize, color_replacement
```

### 🔄 **Training Sequences**
**Beginner Sequence**: `horizontal_mirror` → `undo_config` → `crop_resize`
**Intermediate Sequence**: `brightness_reduction` → `color_replacement` → `text_overlay`  
**Advanced Challenge**: `green_background` (requires all previous skills)
**Complete Mastery**: All 7 tasks in random order

### 📺 **VNC Debugging**
```bash
# Access running environment via VNC
# URL provided in session output: vnc://localhost:<port>
# Default credentials: password
```

## Training Objectives

### 🎯 **Primary Learning Goals**
1. **Tool Mastery**: Proficient use of all major GIMP tools and interfaces
2. **Workflow Understanding**: Logical sequence of operations for common tasks
3. **Visual Assessment**: Ability to evaluate image quality and make improvements
4. **Technical Precision**: Accurate execution of measurements and transformations
5. **Creative Problem-Solving**: Adaptive approaches to achieve desired outcomes

### 📈 **Skill Development Trajectory**
- **Stage 1**: Basic tool interaction and single-step operations
- **Stage 2**: Multi-step workflows and tool combination
- **Stage 3**: Visual decision-making and quality assessment  
- **Stage 4**: Advanced techniques and complex file handling
- **Stage 5**: Creative application and adaptive problem-solving

### 🏆 **Mastery Indicators**
- **Consistent 90%+ scores** across all tasks
- **Efficient workflow execution** within time limits
- **Robust handling** of edge cases and variations
- **Creative adaptation** when standard approaches don't apply
- **Quality output** that meets professional standards

## Extensions and Customization

### 🔧 **Task Modification**
- **Difficulty Adjustment**: Modify timeout, step limits, or success criteria
- **Asset Variation**: Use different source images for varied challenges
- **Tool Substitution**: Require alternative tools for same outcomes
- **Quality Standards**: Adjust verification thresholds for different skill levels

### 🎨 **New Task Development**
- **Template Structure**: Use existing tasks as templates for new challenges
- **Verification Framework**: Leverage `verification_utils.py` for consistent validation
- **Asset Management**: Follow established patterns for image download and handling
- **Documentation Standards**: Maintain comprehensive README files for all new tasks

### 🤖 **Agent Integration**
- **Multi-Modal Input**: RGB screens, UI trees, audio feedback
- **Action Spaces**: Mouse, keyboard, voice commands, API calls  
- **Reward Signals**: Sparse rewards based on verification scores
- **Observation Formats**: Configurable screen resolutions and frame rates

---

## Quick Start

```bash
# 1. Validate all tasks
python -m gym_anything.cli validate examples/gimp_env3

# 2. Run beginner sequence
python -m gym_anything.cli run examples/gimp_env3 --task horizontal_mirror
python -m gym_anything.cli run examples/gimp_env3 --task undo_config  
python -m gym_anything.cli run examples/gimp_env3 --task crop_resize

# 3. Progress to intermediate
python -m gym_anything.cli run examples/gimp_env3 --task brightness_reduction
python -m gym_anything.cli run examples/gimp_env3 --task color_replacement
python -m gym_anything.cli run examples/gimp_env3 --task text_overlay

# 4. Master advanced techniques
python -m gym_anything.cli run examples/gimp_env3 --task green_background
```

This comprehensive GIMP training suite provides everything needed for world-class multimodal agent development in digital image editing! 🚀