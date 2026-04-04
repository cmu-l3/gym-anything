#!/bin/bash
set -e
echo "=== Setting up convert_maven_to_gradle task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Install Gradle (if not present)
# We install it to /opt/gradle and link it so the agent has access
GRADLE_VERSION="8.5"
if [ ! -f /opt/gradle/bin/gradle ]; then
    echo "Installing Gradle ${GRADLE_VERSION}..."
    wget -q "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -O /tmp/gradle.zip
    mkdir -p /opt/gradle
    unzip -q -o /tmp/gradle.zip -d /opt/gradle-tmp
    cp -r /opt/gradle-tmp/gradle-${GRADLE_VERSION}/* /opt/gradle/
    rm -rf /opt/gradle-tmp /tmp/gradle.zip
    ln -sf /opt/gradle/bin/gradle /usr/local/bin/gradle
fi

# Add Gradle to ga's PATH for convenience
if ! grep -q "GRADLE_HOME" /home/ga/.bashrc; then
    echo 'export GRADLE_HOME=/opt/gradle' >> /home/ga/.bashrc
    echo 'export PATH=$GRADLE_HOME/bin:$PATH' >> /home/ga/.bashrc
fi

# 2. Create Project Structure
PROJECT_DIR="/home/ga/IdeaProjects/data-utils"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/datautils"
mkdir -p "$PROJECT_DIR/src/test/java/com/datautils"

# 3. Create pom.xml (The starting point)
cat > "$PROJECT_DIR/pom.xml" << 'POMXML'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.datautils</groupId>
    <artifactId>data-utils</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.slf4j</groupId>
            <artifactId>slf4j-api</artifactId>
            <version>2.0.9</version>
        </dependency>
        <dependency>
            <groupId>com.google.guava</groupId>
            <artifactId>guava</artifactId>
            <version>32.1.3-jre</version>
        </dependency>
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
            <version>2.16.0</version>
        </dependency>
        <dependency>
            <groupId>org.apache.commons</groupId>
            <artifactId>commons-lang3</artifactId>
            <version>3.14.0</version>
        </dependency>
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.13.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.8.1</version>
                <configuration>
                    <source>17</source>
                    <target>17</target>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-jar-plugin</artifactId>
                <version>3.2.0</version>
                <configuration>
                    <archive>
                        <manifest>
                            <mainClass>com.datautils.App</mainClass>
                        </manifest>
                    </archive>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
POMXML

# 4. Create Source Files (App.java and DataRecord.java)
cat > "$PROJECT_DIR/src/main/java/com/datautils/App.java" << 'JAVA'
package com.datautils;

import com.google.common.collect.Lists;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.util.List;

public class App {
    private static final Logger logger = LoggerFactory.getLogger(App.class);

    public static void main(String[] args) {
        logger.info("Starting Data Utils App");
        List<String> list = Lists.newArrayList("one", "two", "three");
        System.out.println("Joined: " + StringUtils.join(list, ", "));
    }
}
JAVA

cat > "$PROJECT_DIR/src/main/java/com/datautils/DataRecord.java" << 'JAVA'
package com.datautils;

import com.fasterxml.jackson.annotation.JsonProperty;

public class DataRecord {
    @JsonProperty
    private String id;
    
    public DataRecord() {}
    public DataRecord(String id) { this.id = id; }
    public String getId() { return id; }
}
JAVA

# 5. Create Test File
cat > "$PROJECT_DIR/src/test/java/com/datautils/AppTest.java" << 'JAVA'
package com.datautils;

import org.junit.Test;
import static org.junit.Assert.*;
import org.apache.commons.lang3.StringUtils;

public class AppTest {
    @Test
    public void testStringUtils() {
        assertTrue(StringUtils.isNotBlank("test"));
    }

    @Test
    public void testDataRecord() {
        DataRecord r = new DataRecord("123");
        assertEquals("123", r.getId());
    }
}
JAVA

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 6. Verify Maven builds initially (sanity check)
echo "Verifying initial Maven build..."
su - ga -c "cd $PROJECT_DIR && mvn clean compile test -q" || echo "WARNING: Initial Maven build failed!"

# 7. Open Project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "data-utils" 120

# 8. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="