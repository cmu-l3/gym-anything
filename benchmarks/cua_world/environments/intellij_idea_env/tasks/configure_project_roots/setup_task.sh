#!/bin/bash
set -e
echo "=== Setting up configure_project_roots task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="LegacyInventory"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# 1. Clean up previous runs
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# 2. Create Directory Structure
mkdir -p "$PROJECT_DIR/src/com/inventory"
mkdir -p "$PROJECT_DIR/test/com/inventory"
mkdir -p "$PROJECT_DIR/config"
mkdir -p "$PROJECT_DIR/lib"
mkdir -p "$PROJECT_DIR/.idea" # Basic idea folder so it opens as a project

# 3. Download Dependencies (Real JARs)
echo "Downloading dependencies..."
cd "$PROJECT_DIR/lib"
# Commons Lang 3 (used in Main.java)
wget -q -O commons-lang3.jar "https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0.jar"
# JUnit 4 (used in Test.java)
wget -q -O junit-4.13.2.jar "https://repo1.maven.org/maven2/junit/junit/4.13.2/junit-4.13.2.jar"
# Hamcrest (dependency of JUnit)
wget -q -O hamcrest-core.jar "https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar"

# 4. Generate Java Source (Main.java)
# Uses StringUtils to ensure library dependency is required
cat > "$PROJECT_DIR/src/com/inventory/Main.java" << 'JAVAEOF'
package com.inventory;

import org.apache.commons.lang3.StringUtils;
import java.io.InputStream;
import java.util.Properties;

public class Main {
    public static void main(String[] args) {
        String input = "inventory system initialized";
        System.out.println(StringUtils.capitalize(input));

        try (InputStream inputStr = Main.class.getClassLoader().getResourceAsStream("app.properties")) {
            Properties prop = new Properties();
            if (inputStr == null) {
                System.out.println("Sorry, unable to find app.properties");
                return;
            }
            prop.load(inputStr);
            System.out.println("Version: " + prop.getProperty("version"));
        } catch (Exception ex) {
            ex.printStackTrace();
        }
    }
}
JAVAEOF

# 5. Generate Java Test (InventoryTest.java)
# Uses JUnit to ensure test root and library dependency are required
cat > "$PROJECT_DIR/test/com/inventory/InventoryTest.java" << 'JAVAEOF'
package com.inventory;

import org.junit.Test;
import static org.junit.Assert.assertTrue;

public class InventoryTest {
    @Test
    public void testInitialization() {
        assertTrue("Always true", true);
    }
}
JAVAEOF

# 6. Generate Config Resource
cat > "$PROJECT_DIR/config/app.properties" << 'PROPEOF'
version=1.0.0
env=production
PROPEOF

# 7. Set Permissions
chown -R ga:ga "$PROJECT_DIR"

# 8. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 9. Launch IntelliJ
# We start it pointing to the directory. Since there is no .iml or valid setup yet,
# IntelliJ will open it but it will be unconfigured (files will be red).
echo "Launching IntelliJ with unconfigured project..."
su - ga -c "DISPLAY=:1 /opt/idea/bin/idea.sh '$PROJECT_DIR' > /tmp/intellij_task.log 2>&1 &"

# 10. Wait for IntelliJ and Handle Dialogs
wait_for_intellij 120
dismiss_dialogs 5
handle_trust_dialog 5
focus_intellij_window

# 11. Initial Screenshot
sleep 5
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="