#!/bin/bash
set -e
echo "=== Setting up externalize_config_values task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/config-app"
mkdir -p "$PROJECT_DIR/src/main/java/com/appworks"
mkdir -p "$PROJECT_DIR/src/main/resources"

# Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.appworks</groupId>
  <artifactId>config-app</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <name>config-app</name>
  <url>http://maven.apache.org</url>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
POM

# Create DatabaseService.java with hardcoded values
cat > "$PROJECT_DIR/src/main/java/com/appworks/DatabaseService.java" << 'JAVA'
package com.appworks;

public class DatabaseService {
    // HARDCODED CONFIGURATION
    private static final String DB_URL = "jdbc:postgresql://prod-db.internal:5432/appworks";
    private static final String DB_USER = "app_user";
    private static final String DB_PASS = "s3cureP@ss!";
    private static final int POOL_SIZE = 10;

    public void connect() {
        System.out.println("Connecting to " + DB_URL + " as " + DB_USER);
        System.out.println("Pool size: " + POOL_SIZE);
        // Simulate connection logic...
    }
}
JAVA

# Create ApiClient.java with hardcoded values
cat > "$PROJECT_DIR/src/main/java/com/appworks/ApiClient.java" << 'JAVA'
package com.appworks;

public class ApiClient {
    // HARDCODED CONFIGURATION
    private static final String BASE_URL = "https://api.external-service.com/v2";
    private static final String API_KEY = "ak_live_7f8g9h0j1k2l3m4n";
    private static final int TIMEOUT_MS = 5000;

    public void fetchData() {
        System.out.println("Requesting " + BASE_URL + " with key " + API_KEY);
        System.out.println("Timeout set to " + TIMEOUT_MS + "ms");
        // Simulate API call...
    }
}
JAVA

# Create FileProcessor.java with hardcoded values
cat > "$PROJECT_DIR/src/main/java/com/appworks/FileProcessor.java" << 'JAVA'
package com.appworks;

public class FileProcessor {
    // HARDCODED CONFIGURATION
    private static final String INPUT_DIR = "/data/incoming";
    private static final String OUTPUT_DIR = "/data/processed";
    private static final int MAX_FILE_SIZE_MB = 50;

    public void processFiles() {
        System.out.println("Scanning " + INPUT_DIR + " for files under " + MAX_FILE_SIZE_MB + "MB");
        System.out.println("Moving processed files to " + OUTPUT_DIR);
        // Simulate file processing...
    }
}
JAVA

# Create App.java (Main class)
cat > "$PROJECT_DIR/src/main/java/com/appworks/App.java" << 'JAVA'
package com.appworks;

public class App {
    public static void main(String[] args) {
        System.out.println("Starting App...");
        
        DatabaseService db = new DatabaseService();
        db.connect();
        
        ApiClient api = new ApiClient();
        api.fetchData();
        
        FileProcessor fp = new FileProcessor();
        fp.processFiles();
        
        System.out.println("App started successfully.");
    }
}
JAVA

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# Open project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "config-app" 120

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="