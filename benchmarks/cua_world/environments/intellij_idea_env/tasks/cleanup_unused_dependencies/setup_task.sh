#!/bin/bash
set -e
echo "=== Setting up cleanup_unused_dependencies task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/dependency-cleanup"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/cleanup"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/cleanup"

# 1. Create pom.xml with mixed used/unused dependencies
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>dependency-cleanup</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <name>Dependency Cleanup Demo</name>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- Used: StringHelper.java, App.java -->
        <dependency>
            <groupId>org.apache.commons</groupId>
            <artifactId>commons-lang3</artifactId>
            <version>3.12.0</version>
        </dependency>

        <!-- Used: App.java, DataProcessor.java -->
        <dependency>
            <groupId>com.google.code.gson</groupId>
            <artifactId>gson</artifactId>
            <version>2.10.1</version>
        </dependency>

        <!-- Used: DataProcessor.java -->
        <dependency>
            <groupId>org.slf4j</groupId>
            <artifactId>slf4j-api</artifactId>
            <version>2.0.9</version>
        </dependency>

        <!-- NOT USED - was added for caching but never implemented -->
        <dependency>
            <groupId>com.google.guava</groupId>
            <artifactId>guava</artifactId>
            <version>32.1.3-jre</version>
        </dependency>

        <!-- NOT USED - was added for file utilities but streams are used instead -->
        <dependency>
            <groupId>commons-io</groupId>
            <artifactId>commons-io</artifactId>
            <version>2.15.0</version>
        </dependency>

        <!-- NOT USED - was added for JSON but Gson is used instead -->
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
            <version>2.16.0</version>
        </dependency>

        <!-- NOT USED - was added for MultiValuedMap but never utilized -->
        <dependency>
            <groupId>org.apache.commons</groupId>
            <artifactId>commons-collections4</artifactId>
            <version>4.4</version>
        </dependency>

        <!-- NOT USED - was added for date handling but java.time is used instead -->
        <dependency>
            <groupId>joda-time</groupId>
            <artifactId>joda-time</artifactId>
            <version>2.12.5</version>
        </dependency>

        <!-- Used: AppTest.java -->
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.13.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
EOF

# 2. Create Java Source Files (App.java)
cat > "$PROJECT_DIR/src/main/java/com/example/cleanup/App.java" << 'EOF'
package com.example.cleanup;

import org.apache.commons.lang3.StringUtils;
import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

public class App {

    private final Gson gson;

    public App() {
        this.gson = new GsonBuilder().setPrettyPrinting().create();
    }

    public String createGreeting(String firstName, String lastName) {
        if (StringUtils.isBlank(firstName) || StringUtils.isBlank(lastName)) {
            return "Hello, Guest!";
        }
        String fullName = StringUtils.capitalize(firstName.trim()) + " "
                + StringUtils.capitalize(lastName.trim());
        return "Hello, " + fullName + "!";
    }

    public String toJson(Object obj) {
        return gson.toJson(obj);
    }

    public static void main(String[] args) {
        App app = new App();
        String greeting = app.createGreeting("jane", "doe");
        System.out.println(greeting);

        Message msg = new Message(greeting, "system");
        String json = app.toJson(msg);
        System.out.println(json);

        DataProcessor processor = new DataProcessor();
        processor.parseJson("[\"alpha\", \"beta\", \"gamma\"]");

        System.out.println("Formatted: " + StringHelper.formatName("john", "smith"));
        System.out.println("Timestamp: " + LocalDateTime.now().format(
                DateTimeFormatter.ISO_LOCAL_DATE_TIME));
    }
}
EOF

# 3. Create Java Source Files (Message.java)
cat > "$PROJECT_DIR/src/main/java/com/example/cleanup/Message.java" << 'EOF'
package com.example.cleanup;

import java.time.Instant;

public class Message {

    private String content;
    private String sender;
    private long timestamp;

    public Message(String content, String sender) {
        this.content = content;
        this.sender = sender;
        this.timestamp = Instant.now().toEpochMilli();
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public String getSender() {
        return sender;
    }

    public void setSender(String sender) {
        this.sender = sender;
    }

    public long getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(long timestamp) {
        this.timestamp = timestamp;
    }

    @Override
    public String toString() {
        return "Message{content='" + content + "', sender='" + sender
                + "', timestamp=" + timestamp + "}";
    }
}
EOF

# 4. Create Java Source Files (DataProcessor.java)
cat > "$PROJECT_DIR/src/main/java/com/example/cleanup/DataProcessor.java" << 'EOF'
package com.example.cleanup;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.lang.reflect.Type;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

public class DataProcessor {

    private static final Logger logger = LoggerFactory.getLogger(DataProcessor.class);
    private final Gson gson;

    public DataProcessor() {
        this.gson = new Gson();
    }

    public List<String> parseJson(String json) {
        logger.info("Parsing JSON array data");
        try {
            Type listType = new TypeToken<List<String>>() {}.getType();
            List<String> items = gson.fromJson(json, listType);
            logger.info("Successfully parsed {} items", items.size());
            return items;
        } catch (Exception e) {
            logger.error("Failed to parse JSON: {}", e.getMessage());
            return Collections.emptyList();
        }
    }

    public List<String> filterNonEmpty(List<String> items) {
        logger.debug("Filtering non-empty items from list of size {}", items.size());
        return items.stream()
                .filter(s -> s != null && !s.trim().isEmpty())
                .collect(Collectors.toList());
    }

    public String toJsonArray(List<String> items) {
        return gson.toJson(items);
    }
}
EOF

# 5. Create Java Source Files (StringHelper.java)
cat > "$PROJECT_DIR/src/main/java/com/example/cleanup/StringHelper.java" << 'EOF'
package com.example.cleanup;

import org.apache.commons.lang3.StringUtils;

import java.util.Arrays;
import java.util.stream.Collectors;

public class StringHelper {

    public static String formatName(String first, String last) {
        String capitalized = StringUtils.capitalize(StringUtils.lowerCase(first));
        String upper = StringUtils.upperCase(last);
        return StringUtils.joinWith(" ", capitalized, upper);
    }

    public static boolean isBlankOrNull(String s) {
        return StringUtils.isBlank(s);
    }

    public static String abbreviate(String text, int maxWidth) {
        return StringUtils.abbreviate(text, maxWidth);
    }

    public static String reverseWords(String sentence) {
        if (StringUtils.isBlank(sentence)) {
            return sentence;
        }
        String[] words = StringUtils.split(sentence);
        return Arrays.stream(words)
                .map(StringUtils::reverse)
                .collect(Collectors.joining(" "));
    }
}
EOF

# 6. Create Test File (AppTest.java)
cat > "$PROJECT_DIR/src/test/java/com/example/cleanup/AppTest.java" << 'EOF'
package com.example.cleanup;

import org.junit.Test;
import static org.junit.Assert.*;

public class AppTest {

    @Test
    public void testCreateGreeting() {
        App app = new App();
        assertEquals("Hello, Jane Doe!", app.createGreeting("jane", "doe"));
    }

    @Test
    public void testCreateGreetingBlankName() {
        App app = new App();
        assertEquals("Hello, Guest!", app.createGreeting("", ""));
    }

    @Test
    public void testCreateGreetingNullName() {
        App app = new App();
        assertEquals("Hello, Guest!", app.createGreeting(null, "doe"));
    }

    @Test
    public void testStringHelperFormatName() {
        assertEquals("John SMITH", StringHelper.formatName("john", "smith"));
        assertEquals("Alice JONES", StringHelper.formatName("ALICE", "jones"));
    }

    @Test
    public void testStringHelperIsBlank() {
        assertTrue(StringHelper.isBlankOrNull(null));
        assertTrue(StringHelper.isBlankOrNull(""));
        assertTrue(StringHelper.isBlankOrNull("   "));
        assertFalse(StringHelper.isBlankOrNull("test"));
    }

    @Test
    public void testStringHelperAbbreviate() {
        assertEquals("Hell...", StringHelper.abbreviate("Hello World", 7));
    }

    @Test
    public void testToJson() {
        App app = new App();
        Message msg = new Message("test", "user");
        String json = app.toJson(msg);
        assertNotNull(json);
        assertTrue(json.contains("test"));
        assertTrue(json.contains("user"));
    }

    @Test
    public void testDataProcessorParse() {
        DataProcessor dp = new DataProcessor();
        var items = dp.parseJson("[\"one\", \"two\", \"three\"]");
        assertEquals(3, items.size());
        assertEquals("one", items.get(0));
    }

    @Test
    public void testDataProcessorFilterNonEmpty() {
        DataProcessor dp = new DataProcessor();
        var items = dp.filterNonEmpty(java.util.List.of("hello", "", "world", "  "));
        assertEquals(2, items.size());
    }
}
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Pre-download dependencies to avoid slow start (agent should not have to wait for downloads)
echo "Pre-resolving dependencies..."
su - ga -c "cd '$PROJECT_DIR' && mvn dependency:resolve -q"

# Record initial pom hash
md5sum "$PROJECT_DIR/pom.xml" > /tmp/initial_pom_hash.txt
date +%s > /tmp/task_start_time.txt

# Open project
setup_intellij_project "$PROJECT_DIR" "dependency-cleanup" 120

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="