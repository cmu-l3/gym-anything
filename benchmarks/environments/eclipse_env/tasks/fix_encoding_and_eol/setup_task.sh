#!/bin/bash
echo "=== Setting up fix_encoding_and_eol task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/InternationalApp"

# 1. clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/src/com/legacy"
mkdir -p "$PROJECT_DIR/.settings"

# 2. Create Eclipse project metadata
# .project file
cat > "$PROJECT_DIR/.project" << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>InternationalApp</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
    </natures>
</projectDescription>
EOFPROJECT

# .classpath file
cat > "$PROJECT_DIR/.classpath" << 'EOFCLASSPATH'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
EOFCLASSPATH

# 3. Create the Java file with CRLF (Windows) line endings
# We use printf to ensure \r\n is written explicitly
cat > "$PROJECT_DIR/src/com/legacy/WindowsService.java" << 'EOFJAVA'
package com.legacy;

public class WindowsService {
    
    public void executeService() {
        // This file was originally created on Windows
        // It uses CRLF line delimiters
        System.out.println("Service executing...");
    }
    
    public String getStatus() {
        return "Active";
    }
}
EOFJAVA

# Convert to CRLF
unix2dos "$PROJECT_DIR/src/com/legacy/WindowsService.java" 2>/dev/null || \
sed -i 's/$/\r/' "$PROJECT_DIR/src/com/legacy/WindowsService.java"

# 4. Create properties file with Japanese content (UTF-8 encoded)
# Content: "Welcome=Welcome\nError=Error\nSave=Save" in Japanese
cat > "$PROJECT_DIR/src/messages_jp.properties" << 'EOFPROP'
welcome=ようこそ
error=エラー
save=保存
EOFPROP

# 5. Force project encoding to ISO-8859-1 (Latin-1) so Japanese looks like garbage
# This simulates the "wrong encoding" state
cat > "$PROJECT_DIR/.settings/org.eclipse.core.resources.prefs" << 'EOFPREFS'
eclipse.preferences.version=1
encoding/<project>=ISO-8859-1
EOFPREFS

chown -R ga:ga "$PROJECT_DIR"

# 6. Start Eclipse
# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Dismiss any dialogs
dismiss_dialogs 3
close_welcome_tab

# Focus and maximize Eclipse window
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="
echo "Project created at $PROJECT_DIR"
echo "WindowsService.java has CRLF line endings."
echo "Project encoding set to ISO-8859-1 (causing mojibake)."