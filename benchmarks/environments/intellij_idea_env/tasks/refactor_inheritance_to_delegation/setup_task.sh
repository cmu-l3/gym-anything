#!/bin/bash
set -e
echo "=== Setting up refactor_inheritance_to_delegation task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/network-module"
mkdir -p "$PROJECT_DIR/src/main/java/com/network"

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Create Project Files
echo "Creating project files..."

# pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.network</groupId>
  <artifactId>network-module</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
EOF

# LegacySocket.java
cat > "$PROJECT_DIR/src/main/java/com/network/LegacySocket.java" << 'EOF'
package com.network;

public class LegacySocket {
    public void connectInsecure() {
        System.out.println("Connecting via plaintext...");
    }

    public void sendData(String data) {
        System.out.println("Sending: " + data);
    }

    public Object getRawStream() {
        return new Object();
    }

    public void close() {
        System.out.println("Closing socket");
    }
}
EOF

# SecureDataTransmitter.java (The Target)
cat > "$PROJECT_DIR/src/main/java/com/network/SecureDataTransmitter.java" << 'EOF'
package com.network;

public class SecureDataTransmitter extends LegacySocket {
    
    public void secureHandshake() {
        System.out.println("Performing TLS handshake...");
    }
    
    @Override
    public void sendData(String data) {
        // Encrypt before sending
        String encrypted = "Encrypted[" + data + "]";
        super.sendData(encrypted);
    }
}
EOF

# App.java
cat > "$PROJECT_DIR/src/main/java/com/network/App.java" << 'EOF'
package com.network;

public class App {
    public static void main(String[] args) {
        SecureDataTransmitter transmitter = new SecureDataTransmitter();
        transmitter.secureHandshake();
        transmitter.sendData("Secret Payload");
        
        // These might break after refactoring if not handled, 
        // but the task focuses on the class structure.
        // transmitter.close(); 
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record initial hash of the target file
md5sum "$PROJECT_DIR/src/main/java/com/network/SecureDataTransmitter.java" > /tmp/initial_file_hash.txt

# 2. Launch IntelliJ
echo "Opening project in IntelliJ..."
setup_intellij_project "$PROJECT_DIR" "network-module" 120

# 3. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="