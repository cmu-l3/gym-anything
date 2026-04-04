# GIMP Undo Configuration Task (`undo_config@1`)

## Overview

This task tests an agent's ability to navigate GIMP's preferences system and modify application settings that affect workflow behavior. The agent must access the Preferences dialog, locate the undo configuration settings, modify the number of undo steps, and ensure the changes are properly saved. This represents essential software configuration skills required for customizing creative applications to user needs.

## Rationale

**Why this task is valuable:**
- **Preferences System Mastery:** Introduces GIMP's extensive preferences and configuration system
- **Workflow Optimization:** Teaches how to customize application behavior for improved efficiency
- **Settings Persistence:** Tests understanding of how configuration changes are saved and applied
- **Menu System Navigation:** Builds familiarity with complex, nested interface hierarchies
- **Professional Configuration:** Represents real-world customization skills needed in production environments
- **Foundation for Advanced Use:** Establishes concepts needed for other GIMP customizations

**Skill Progression:** This task bridges basic tool usage with advanced application customization, preparing agents for more sophisticated GIMP workflows.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through multiple menu levels (`Edit → Preferences`)
- **Dialog Management:** Work with complex, multi-section preference dialogs
- **Setting Identification:** Locate specific settings within extensive option lists
- **Numeric Input:** Enter precise numeric values in configuration fields
- **Change Persistence:** Understand how to save and apply configuration changes
- **Interface Exploration:** Navigate unfamiliar dialog sections to find required options

### B. GIMP Knowledge
- **Preferences System:** Understand GIMP's comprehensive configuration architecture
- **Undo System Concepts:** Know how undo functionality works and its memory implications
- **Setting Categories:** Navigate the hierarchical organization of preference sections
- **Application Behavior:** Understand how preference changes affect GIMP's operation
- **Configuration Persistence:** Know that changes to preferences persist across sessions
- **Memory Management:** Understand the relationship between undo steps and memory usage

### C. Task-Specific Skills
- **Setting Location:** Identify where undo-related settings are found in the preferences
- **Value Assessment:** Understand appropriate ranges for undo step configuration
- **Impact Understanding:** Recognize how changing undo steps affects workflow and performance
- **Verification Skills:** Confirm that settings have been properly changed and saved
- **System Optimization:** Balance undo capability with system resource management

## Task Steps

### 1. Access Preferences System
- Navigate to `Edit → Preferences` in the menu bar
- Wait for the Preferences dialog to open
- Observe the hierarchical structure of configuration categories

### 2. Locate System Settings
- In the Preferences dialog, look for "System Resources" or similar category
- Click on the appropriate category to expand its options
- Navigate to sections related to undo or history management

### 3. Find Undo Configuration
- Locate the "Undo" or "Undo History" section within System Resources
- Identify the setting that controls the number of undo steps/levels
- Note the current value (typically 5 by default)

### 4. Modify Undo Steps
- Change the undo levels setting to a different value (e.g., 20 steps)
- Use either direct typing or increment/decrement controls
- Ensure the new value is within reasonable limits (typically 1-100)

### 5. Apply Configuration Changes
- Look for "OK" or "Apply" button to save the changes
- Click the appropriate button to apply the new configuration
- Confirm that the dialog closes properly

### 6. Verification (Optional)
- Optionally, reopen the Preferences to verify the setting was saved
- The new undo steps value should persist in the configuration

### 7. Automatic Verification
- The post-task hook will automatically close GIMP to save settings
- The verifier will check the saved configuration file for the new value

## Verification Strategy

### Verification Approach
The verifier uses **direct configuration file analysis** to validate setting changes:

### A. Configuration File Access
- **File Location Detection:** Locates GIMP's configuration directory and `gimprc` file
- **Container File Transfer:** Uses framework utilities to copy config files to host for analysis
- **Cross-platform Compatibility:** Handles different GIMP config file locations and formats
- **Backup Protection:** Non-destructive reading that doesn't modify configuration

### B. Setting Parsing and Analysis
- **Configuration Parser:** Reads and parses GIMP's `gimprc` configuration file format
- **Setting Identification:** Locates the specific `undo-levels` parameter within the configuration
- **Value Extraction:** Extracts the numeric value and validates it's within expected ranges
- **Format Validation:** Ensures the configuration file maintains proper syntax and structure

### C. Change Validation
- **Default Comparison:** Compares against GIMP's default undo levels (typically 5)
- **Range Verification:** Ensures the new value is within reasonable bounds (1-100 steps)
- **Setting Persistence:** Confirms the change was properly saved to the configuration file
- **Configuration Integrity:** Validates that other settings weren't corrupted during the change

### D. Workflow Verification
- **Proper Process:** Ensures the setting was changed through the Preferences interface
- **Clean Closure:** Verifies GIMP was properly closed to ensure settings were saved
- **No Corruption:** Checks that the configuration file remains valid and parseable

### Verification Checklist
- ✅ **Setting Located:** Successfully found and parsed the `undo-levels` configuration
- ✅ **Value Changed:** The undo levels value differs from the default (not equal to 5)
- ✅ **Valid Range:** New value is within reasonable bounds (1-100)
- ✅ **Properly Saved:** Configuration change was successfully persisted to disk

### Scoring System
- **100%:** Perfect configuration change with valid value properly saved
- **75-99%:** Setting changed correctly but with minor validation issues
- **50-74%:** Setting located and modified but with significant issues
- **0-49%:** Failed to properly change or save the undo configuration

**Pass Threshold:** 75% (requires successful setting modification and persistence)

### Configuration Analysis Details
```python
# Configuration File Parsing
def parse_gimprc_file(gimprc_path):
    """Parse GIMP configuration file and extract undo-levels setting."""
    with open(gimprc_path, 'r') as f:
        content = f.read()
    
    # Look for undo-levels setting in various formats
    patterns = [
        r'\(undo-levels\s+(\d+)\)',
        r'undo-levels:\s*(\d+)',
        r'undo-levels\s*=\s*(\d+)'
    ]
    
    for pattern in patterns:
        match = re.search(pattern, content)
        if match:
            return int(match.group(1))
    
    return None  # Setting not found or not set

# Validation Logic
def validate_undo_setting(undo_levels):
    """Validate that undo levels is reasonable and different from default."""
    if undo_levels is None:
        return False, "Undo levels setting not found"
    
    if undo_levels == 5:  # Default value
        return False, "Setting appears unchanged from default"
    
    if not (1 <= undo_levels <= 100):
        return False, f"Invalid undo levels value: {undo_levels}"
    
    return True, f"Valid undo levels: {undo_levels}"
```

## Technical Implementation

### Files Structure
```
undo_config/
├── task.json              # Task configuration (5 steps, 90s timeout)
├── setup_undo_task.sh     # Launches GIMP for configuration
├── close_gimp.sh          # Ensures GIMP closes to save settings
├── verifier.py           # Configuration file analysis verification
└── README.md            # This documentation
```

### Verification Features
- **Direct Config Analysis:** Bypasses GUI inspection by reading actual configuration files
- **Cross-platform Support:** Handles different GIMP versions and configuration formats
- **Robust Parsing:** Uses multiple regex patterns to handle various config file formats
- **Range Validation:** Ensures setting values are reasonable and safe
- **Change Detection:** Confirms actual modification occurred, not just dialog interaction

### Configuration Management
- **Safe File Access:** Non-destructive reading of configuration files
- **Format Preservation:** Maintains GIMP config file integrity during verification
- **Multi-version Support:** Handles different GIMP configuration file formats
- **Error Recovery:** Graceful handling of missing or corrupted configuration files

This task provides essential skills for GIMP application customization and configuration management, preparing agents for advanced workflow optimization and professional software setup scenarios.
