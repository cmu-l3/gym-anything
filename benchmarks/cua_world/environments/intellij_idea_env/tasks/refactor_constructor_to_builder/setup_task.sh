#!/bin/bash
set -e

echo "=== Setting up refactor_constructor_to_builder task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Project directory
PROJECT_DIR="/home/ga/IdeaProjects/iot-device-manager"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# 1. Create Maven Project Structure
echo "Generating project files..."

# pom.xml
mkdir -p "$PROJECT_DIR"
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" 
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.iot</groupId>
  <artifactId>iot-device-manager</artifactId>
  <version>1.0-SNAPSHOT</version>

  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter-api</artifactId>
      <version>5.9.2</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter-engine</artifactId>
      <version>5.9.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
EOF

# SmartHomeDevice.java (The Messy Constructor)
mkdir -p "$PROJECT_DIR/src/main/java/com/iot/manager/model"
cat > "$PROJECT_DIR/src/main/java/com/iot/manager/model/SmartHomeDevice.java" << 'EOF'
package com.iot.manager.model;

import java.util.UUID;

public class SmartHomeDevice {
    private final UUID id;
    private final String name;
    private final String ipAddress;
    private final String macAddress;
    private final String firmwareVersion;
    private final String location;
    private final boolean isActive;

    // Telescoping constructor - difficult to read and maintain
    public SmartHomeDevice(UUID id, String name, String ipAddress, String macAddress, 
                          String firmwareVersion, String location, boolean isActive) {
        this.id = id;
        this.name = name;
        this.ipAddress = ipAddress;
        this.macAddress = macAddress;
        this.firmwareVersion = firmwareVersion;
        this.location = location;
        this.isActive = isActive;
    }

    // Getters
    public UUID getId() { return id; }
    public String getName() { return name; }
    public String getIpAddress() { return ipAddress; }
    public String getMacAddress() { return macAddress; }
    public String getFirmwareVersion() { return firmwareVersion; }
    public String getLocation() { return location; }
    public boolean isActive() { return isActive; }
}
EOF

# DeviceService.java (Client usage 1)
mkdir -p "$PROJECT_DIR/src/main/java/com/iot/manager/service"
cat > "$PROJECT_DIR/src/main/java/com/iot/manager/service/DeviceService.java" << 'EOF'
package com.iot.manager.service;

import com.iot.manager.model.SmartHomeDevice;
import java.util.UUID;

public class DeviceService {

    public SmartHomeDevice registerDefaultBulb(String name, String ip) {
        // Usage of the complex constructor
        return new SmartHomeDevice(
            UUID.randomUUID(),
            name,
            ip,
            "00:00:00:00:00:00",
            "1.0.0",
            "Living Room",
            true
        );
    }
    
    public SmartHomeDevice createThermostat(String ip, String loc) {
        // Another usage
        return new SmartHomeDevice(
            UUID.randomUUID(),
            "Nest-01",
            ip,
            "AA:BB:CC:DD:EE:FF",
            "2.5.4",
            loc,
            true
        );
    }
}
EOF

# DeviceServiceTest.java (Client usage 2 - Tests)
mkdir -p "$PROJECT_DIR/src/test/java/com/iot/manager/service"
cat > "$PROJECT_DIR/src/test/java/com/iot/manager/service/DeviceServiceTest.java" << 'EOF'
package com.iot.manager.service;

import com.iot.manager.model.SmartHomeDevice;
import org.junit.jupiter.api.Test;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

public class DeviceServiceTest {

    @Test
    public void testManualCreation() {
        // Test usage of constructor
        SmartHomeDevice device = new SmartHomeDevice(
            UUID.randomUUID(),
            "Camera-Front",
            "192.168.1.105",
            "11:22:33:44:55:66",
            "3.0.1",
            "Porch",
            true
        );
        
        assertNotNull(device.getId());
        assertEquals("Camera-Front", device.getName());
        assertEquals("Porch", device.getLocation());
        assertTrue(device.isActive());
    }

    @Test
    public void testServiceCreation() {
        DeviceService service = new DeviceService();
        SmartHomeDevice bulb = service.registerDefaultBulb("Hue-01", "192.168.1.50");
        
        assertEquals("Hue-01", bulb.getName());
        assertEquals("1.0.0", bulb.getFirmwareVersion());
    }
}
EOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# 2. Record initial state checks
date +%s > /tmp/task_start_time.txt
md5sum "$PROJECT_DIR/src/main/java/com/iot/manager/model/SmartHomeDevice.java" > /tmp/initial_file_hash.txt

# 3. Open Project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "iot-device-manager" 120

# 4. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="