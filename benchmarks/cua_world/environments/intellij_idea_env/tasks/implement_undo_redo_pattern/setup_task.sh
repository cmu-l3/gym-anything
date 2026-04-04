#!/bin/bash
set -e
echo "=== Setting up Implement Undo/Redo Pattern task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/IdeaProjects/undo-redo-app"

# Clean previous attempts
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/editor"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.editor</groupId>
    <artifactId>undo-redo-app</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
POMEOF

# 2. Create TextEditor.java (The existing working class)
cat > "$PROJECT_DIR/src/main/java/com/editor/TextEditor.java" << 'JAVAEOF'
package com.editor;

public class TextEditor {
    private final StringBuilder buffer;

    public TextEditor() {
        this.buffer = new StringBuilder();
    }

    public void insert(int position, String text) {
        if (position < 0 || position > buffer.length()) throw new IndexOutOfBoundsException();
        buffer.insert(position, text);
    }

    public String delete(int position, int length) {
        if (position < 0 || position + length > buffer.length()) throw new IndexOutOfBoundsException();
        String deleted = buffer.substring(position, position + length);
        buffer.delete(position, position + length);
        return deleted;
    }

    public String replace(int position, int length, String newText) {
        if (position < 0 || position + length > buffer.length()) throw new IndexOutOfBoundsException();
        String original = buffer.substring(position, position + length);
        buffer.replace(position, position + length, newText);
        return original;
    }

    public String getText() {
        return buffer.toString();
    }
}
JAVAEOF

# 3. Create Main.java (Skeleton)
cat > "$PROJECT_DIR/src/main/java/com/editor/Main.java" << 'JAVAEOF'
package com.editor;

import java.io.FileWriter;
import java.io.IOException;

public class Main {
    public static void main(String[] args) {
        // TODO: Implement the Command pattern demonstration
        // 1. Create TextEditor and CommandHistory
        // 2. Execute operations (insert, delete, replace)
        // 3. Demonstrate Undo and Redo
        // 4. Save output to "output.txt"
        
        System.out.println("Command pattern not implemented yet.");
    }
}
JAVAEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Open project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "undo-redo-app" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="