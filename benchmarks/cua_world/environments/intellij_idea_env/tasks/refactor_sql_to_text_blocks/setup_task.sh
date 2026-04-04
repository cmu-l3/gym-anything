#!/bin/bash
set -e

echo "=== Setting up refactor_sql_to_text_blocks task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-reporting"
mkdir -p "$PROJECT_DIR"

# 1. Create Maven Project Structure
mkdir -p "$PROJECT_DIR/src/main/java/com/reporting"
mkdir -p "$PROJECT_DIR/src/test/java/com/reporting"

# 2. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.reporting</groupId>
  <artifactId>legacy-reporting</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <!-- JUnit for testing -->
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
    <!-- H2 Database for validating SQL syntax -->
    <dependency>
      <groupId>com.h2database</groupId>
      <artifactId>h2</artifactId>
      <version>2.1.214</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
POMEOF

# 3. Create the Target Java File (With Single-line String and Typo)
cat > "$PROJECT_DIR/src/main/java/com/reporting/ReportQuery.java" << 'JAVAEOF'
package com.reporting;

public class ReportQuery {
    
    // TODO: Refactor this to a Text Block and fix the syntax error
    public static final String QUERY = "SELECT u.id, u.email, COUNT(o.id) as total_orders, SUM(oi.price * oi.quantity) as total_spent FROM users u JOIN orders o ON u.id = o.user_id JOIN order_items oi ON o.id = oi.order_id WHERE o.status = 'COMPLETED' AND o.created_at >= '2023-01-01' GROU BY u.id, u.email HAVING total_spent > 1000 ORDER BY total_spent DESC";

    public String getQuery() {
        return QUERY;
    }
}
JAVAEOF

# 4. Create the Test File (Validates SQL syntax)
cat > "$PROJECT_DIR/src/test/java/com/reporting/ReportQueryTest.java" << 'TESTEOF'
package com.reporting;

import org.junit.jupiter.api.Test;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import static org.junit.jupiter.api.Assertions.fail;
import static org.junit.jupiter.api.Assertions.assertTrue;

public class ReportQueryTest {

    @Test
    public void testSqlSyntax() {
        String sql = ReportQuery.QUERY;
        
        // Basic check to ensure it's not empty
        if (sql == null || sql.trim().isEmpty()) {
            fail("Query is empty");
        }

        // Validate SQL syntax using H2 in-memory database
        // We create a dummy schema so the query prepares successfully
        try (Connection conn = DriverManager.getConnection("jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1", "sa", "")) {
            setupSchema(conn);
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                // If we get here, syntax is valid
                assertTrue(true);
            }
        } catch (SQLException e) {
            fail("SQL Syntax Error: " + e.getMessage());
        }
    }

    private void setupSchema(Connection conn) throws SQLException {
        try (java.sql.Statement s = conn.createStatement()) {
            s.execute("CREATE TABLE users (id INT, email VARCHAR(255))");
            s.execute("CREATE TABLE orders (id INT, user_id INT, status VARCHAR(50), created_at TIMESTAMP)");
            s.execute("CREATE TABLE order_items (id INT, order_id INT, price DECIMAL, quantity INT)");
        }
    }
}
TESTEOF

chown -R ga:ga "$PROJECT_DIR"

# 5. Record initial state for anti-gaming
date +%s > /tmp/task_start_time.txt
md5sum "$PROJECT_DIR/src/main/java/com/reporting/ReportQuery.java" > /tmp/initial_file_hash.txt

# 6. Setup IntelliJ
# Pre-download dependencies to avoid waiting during task
echo "Pre-warming Maven..."
cd "$PROJECT_DIR"
su - ga -c "mvn dependency:resolve -q"

# Launch IntelliJ with the project
setup_intellij_project "$PROJECT_DIR" "legacy-reporting" 120

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="