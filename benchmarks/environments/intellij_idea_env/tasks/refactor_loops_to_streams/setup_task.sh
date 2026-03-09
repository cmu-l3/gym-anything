#!/bin/bash
echo "=== Setting up refactor_loops_to_streams task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/IdeaProjects/user-analytics"
mkdir -p "$PROJECT_DIR/src/main/java/com/analytics"
mkdir -p "$PROJECT_DIR/src/test/java/com/analytics"

echo "Creating Maven project structure..."

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.analytics</groupId>
    <artifactId>user-analytics</artifactId>
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
POMEOF

# 2. Create Role enum
cat > "$PROJECT_DIR/src/main/java/com/analytics/Role.java" << 'ROLEEOF'
package com.analytics;

public enum Role {
    ADMIN,
    PREMIUM,
    STANDARD
}
ROLEEOF

# 3. Create User class
cat > "$PROJECT_DIR/src/main/java/com/analytics/User.java" << 'USEREOF'
package com.analytics;

public class User {
    private int id;
    private String username;
    private String email;
    private boolean active;
    private Role role;
    private int loginCount;
    private String region;

    public User(int id, String username, String email, boolean active, Role role, int loginCount, String region) {
        this.id = id;
        this.username = username;
        this.email = email;
        this.active = active;
        this.role = role;
        this.loginCount = loginCount;
        this.region = region;
    }

    public int getId() { return id; }
    public String getUsername() { return username; }
    public String getEmail() { return email; }
    public boolean isActive() { return active; }
    public Role getRole() { return role; }
    public int getLoginCount() { return loginCount; }
    public String getRegion() { return region; }
}
USEREOF

# 4. Create AnalyticsService (The target file to refactor)
cat > "$PROJECT_DIR/src/main/java/com/analytics/AnalyticsService.java" << 'SERVEOF'
package com.analytics;

import java.util.ArrayList;
import java.util.List;

public class AnalyticsService {

    // TASK: Refactor this method to use Streams
    public List<User> findActiveUsers(List<User> users) {
        List<User> result = new ArrayList<>();
        for (User user : users) {
            if (user.isActive()) {
                result.add(user);
            }
        }
        return result;
    }

    // TASK: Refactor this method to use Streams
    public List<String> getEmailsOfPremiumUsers(List<User> users) {
        List<String> result = new ArrayList<>();
        for (User user : users) {
            if (user.getRole() == Role.PREMIUM) {
                result.add(user.getEmail());
            }
        }
        return result;
    }

    // TASK: Refactor this method to use Streams
    public int countLoginsByRegion(List<User> users, String region) {
        int count = 0;
        for (User user : users) {
            if (user.getRegion().equals(region)) {
                count += user.getLoginCount();
            }
        }
        return count;
    }

    // TASK: Refactor this method to use Streams
    public boolean hasUserWithId(List<User> users, int id) {
        for (User user : users) {
            if (user.getId() == id) {
                return true;
            }
        }
        return false;
    }
}
SERVEOF

# 5. Create Test class
cat > "$PROJECT_DIR/src/test/java/com/analytics/AnalyticsServiceTest.java" << 'TESTEOF'
package com.analytics;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;

class AnalyticsServiceTest {

    private AnalyticsService service;
    private List<User> testUsers;

    @BeforeEach
    void setUp() {
        service = new AnalyticsService();
        testUsers = Arrays.asList(
            new User(1, "alice", "alice@example.com", true, Role.ADMIN, 10, "US"),
            new User(2, "bob", "bob@example.com", false, Role.STANDARD, 5, "EU"),
            new User(3, "charlie", "charlie@example.com", true, Role.PREMIUM, 20, "US"),
            new User(4, "dave", "dave@example.com", true, Role.PREMIUM, 15, "EU"),
            new User(5, "eve", "eve@example.com", false, Role.STANDARD, 0, "US")
        );
    }

    @Test
    void testFindActiveUsers() {
        List<User> active = service.findActiveUsers(testUsers);
        assertEquals(3, active.size());
        assertTrue(active.stream().allMatch(User::isActive));
    }

    @Test
    void testFindActiveUsersEmpty() {
        assertTrue(service.findActiveUsers(Collections.emptyList()).isEmpty());
    }

    @Test
    void testGetEmailsOfPremiumUsers() {
        List<String> emails = service.getEmailsOfPremiumUsers(testUsers);
        assertEquals(2, emails.size());
        assertTrue(emails.contains("charlie@example.com"));
        assertTrue(emails.contains("dave@example.com"));
    }

    @Test
    void testCountLoginsByRegion() {
        assertEquals(30, service.countLoginsByRegion(testUsers, "US")); // 10 + 20 + 0
        assertEquals(20, service.countLoginsByRegion(testUsers, "EU")); // 5 + 15
        assertEquals(0, service.countLoginsByRegion(testUsers, "JP"));
    }

    @Test
    void testHasUserWithId() {
        assertTrue(service.hasUserWithId(testUsers, 3));
        assertFalse(service.hasUserWithId(testUsers, 99));
    }
}
TESTEOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Pre-compile to download dependencies
echo "Pre-compiling project..."
cd "$PROJECT_DIR"
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q"

# Record initial file checksums
md5sum "$PROJECT_DIR/src/main/java/com/analytics/AnalyticsService.java" > /tmp/initial_service_hash.txt
md5sum "$PROJECT_DIR/src/test/java/com/analytics/AnalyticsServiceTest.java" > /tmp/initial_test_hash.txt

# Open IntelliJ
setup_intellij_project "$PROJECT_DIR" "user-analytics" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="