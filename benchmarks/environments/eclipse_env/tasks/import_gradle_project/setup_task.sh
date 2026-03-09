#!/bin/bash
set -e
echo "=== Setting up import_gradle_project task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -rf /home/ga/projects/datautils 2>/dev/null || true
rm -rf /home/ga/eclipse-workspace/datautils 2>/dev/null || true

# Create project directory structure
mkdir -p /home/ga/projects/datautils/src/main/java/com/datautils/core
mkdir -p /home/ga/projects/datautils/src/test/java/com/datautils/core
mkdir -p /home/ga/projects/datautils/gradle/wrapper

# Create build.gradle
cat > /home/ga/projects/datautils/build.gradle << 'GRADLE'
plugins {
    id 'java'
    id 'application'
}

group = 'com.datautils'
version = '1.0-SNAPSHOT'

repositories {
    mavenCentral()
}

dependencies {
    testImplementation 'junit:junit:4.13.2'
}

application {
    mainClass = 'com.datautils.core.App'
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
GRADLE

# Create settings.gradle
cat > /home/ga/projects/datautils/settings.gradle << 'SETTINGS'
rootProject.name = 'datautils'
SETTINGS

# Create App.java
cat > /home/ga/projects/datautils/src/main/java/com/datautils/core/App.java << 'JAVA'
package com.datautils.core;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

public class App {
    private List<String> items;

    public App() {
        this.items = new ArrayList<>();
    }

    public void addItem(String item) {
        if (item != null && !item.isBlank()) {
            items.add(item.trim());
        }
    }

    public List<String> getItems() {
        return List.copyOf(items);
    }

    public static void main(String[] args) {
        App app = new App();
        app.addItem("Hello");
        app.addItem("World");
        System.out.println(app.getItems());
    }
}
JAVA

# Create AppTest.java
cat > /home/ga/projects/datautils/src/test/java/com/datautils/core/AppTest.java << 'JAVA'
package com.datautils.core;

import org.junit.Test;
import static org.junit.Assert.*;

public class AppTest {
    @Test
    public void testApp() {
        App app = new App();
        app.addItem("test");
        assertEquals(1, app.getItems().size());
    }
}
JAVA

# Copy Gradle wrapper (assuming it exists in env or create a simple one)
# Since the environment has gradle installed, we can generate the wrapper
cd /home/ga/projects/datautils
gradle wrapper > /dev/null 2>&1 || true

# Set ownership
chown -R ga:ga /home/ga/projects/datautils

# Setup Eclipse
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Project created at /home/ga/projects/datautils"