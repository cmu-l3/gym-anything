# Setup Custom Problem Matcher Task

**Difficulty**: 🟡 Medium  
**Skills**: IDE configuration, build tool integration, regex patterns, problem matchers  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Configure VSCode to automatically parse and display errors from a proprietary build tool (Hardware Compiler - `hwc`) in the Problems panel. Create a custom problem matcher that converts non-standard error output into clickable diagnostics.

## Background

Your team uses a proprietary hardware compiler called `hwc` (hardware compiler) that outputs errors in this format:
