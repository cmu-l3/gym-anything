#!/bin/bash
set -e
echo "=== Setting up git_history_revert task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project Directory
PROJECT_DIR="/home/ga/IdeaProjects/git-bisect-lab"
mkdir -p "$PROJECT_DIR"

# Configure Git for the environment
git config --global user.email "dev@example.com"
git config --global user.name "Developer"
git config --global init.defaultBranch main

# Create Project Structure
mkdir -p "$PROJECT_DIR/src/main/java/com/example"
mkdir -p "$PROJECT_DIR/src/test/java/com/example"

# Initialize Git
cd "$PROJECT_DIR"
git init

# --- Commit 1: Initial Setup ---
cat > pom.xml << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>git-bisect-lab</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.12</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
EOF
git add pom.xml
git commit -m "Initial project setup with Maven structure" --date="3 days ago"

# --- Commit 2: StringUtils ---
cat > src/main/java/com/example/StringUtils.java << 'EOF'
package com.example;

public class StringUtils {
    public static String reverse(String input) {
        if (input == null) return null;
        return new StringBuilder(input).reverse().toString();
    }
    
    public static String capitalize(String input) {
        if (input == null || input.isEmpty()) return input;
        return input.substring(0, 1).toUpperCase() + input.substring(1);
    }
}
EOF
git add src/main/java/com/example/StringUtils.java
git commit -m "Add StringUtils class with reverse and capitalize methods" --date="2 days ago 10:00"

# --- Commit 3: MathUtils (Correct Version) ---
cat > src/main/java/com/example/MathUtils.java << 'EOF'
package com.example;

public class MathUtils {
    public static long factorial(int n) {
        if (n < 0) throw new IllegalArgumentException("Negative input");
        if (n <= 1) return 1;
        return n * factorial(n - 1);
    }
    
    public static long fibonacci(int n) {
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    }
}
EOF
git add src/main/java/com/example/MathUtils.java
git commit -m "Add MathUtils class with factorial and fibonacci methods" --date="2 days ago 12:00"

# --- Commit 4: Unit Tests ---
cat > src/test/java/com/example/StringUtilsTest.java << 'EOF'
package com.example;
import org.junit.Test;
import static org.junit.Assert.*;

public class StringUtilsTest {
    @Test
    public void testReverse() {
        assertEquals("cba", StringUtils.reverse("abc"));
    }
}
EOF

cat > src/test/java/com/example/MathUtilsTest.java << 'EOF'
package com.example;
import org.junit.Test;
import static org.junit.Assert.*;

public class MathUtilsTest {
    @Test
    public void testFactorial() {
        assertEquals(120, MathUtils.factorial(5));
        assertEquals(1, MathUtils.factorial(0));
    }
    
    @Test
    public void testFibonacci() {
        assertEquals(5, MathUtils.fibonacci(5));
    }
}
EOF
git add src/test/java/com/example/
git commit -m "Add unit tests for StringUtils and MathUtils" --date="2 days ago 14:00"

# --- Commit 5: THE BUG (Optimize factorial) ---
# Changes n-1 to n-2 (Bug!)
cat > src/main/java/com/example/MathUtils.java << 'EOF'
package com.example;

public class MathUtils {
    /**
     * Calculates factorial.
     * Optimized recursion for better stack usage.
     */
    public static long factorial(int n) {
        if (n < 0) throw new IllegalArgumentException("Negative input");
        if (n <= 1) return 1;
        // Optimization attempt: skip a step? (BUG introduced here)
        return n * factorial(n - 2); 
    }
    
    public static long fibonacci(int n) {
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    }
}
EOF
git add src/main/java/com/example/MathUtils.java
git commit -m "Optimize factorial method for better performance" --date="yesterday 09:00"

# --- Commit 6: More String Utils ---
# Edit StringUtils to add isPalindrome
sed -i 's/}/    public static boolean isPalindrome(String input) {\n        return input.equals(reverse(input));\n    }\n}/' src/main/java/com/example/StringUtils.java
git add src/main/java/com/example/StringUtils.java
git commit -m "Add palindrome check to StringUtils" --date="yesterday 11:00"

# --- Commit 7: More Math Utils ---
# Edit MathUtils to add GCD and LCM (keeping the bug in factorial)
cat > src/main/java/com/example/MathUtils.java << 'EOF'
package com.example;

public class MathUtils {
    /**
     * Calculates factorial.
     * Optimized recursion for better stack usage.
     */
    public static long factorial(int n) {
        if (n < 0) throw new IllegalArgumentException("Negative input");
        if (n <= 1) return 1;
        // Optimization attempt: skip a step? (BUG introduced here)
        return n * factorial(n - 2); 
    }
    
    public static long fibonacci(int n) {
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    }
    
    public static int gcd(int a, int b) {
        return b == 0 ? a : gcd(b, a % b);
    }
    
    public static int lcm(int a, int b) {
        return (a * b) / gcd(a, b);
    }
}
EOF
git add src/main/java/com/example/MathUtils.java
git commit -m "Add GCD and LCM methods to MathUtils" --date="yesterday 15:00"

# --- Commit 8: README ---
echo "# Git Bisect Lab" > README.md
git add README.md
git commit -m "Add documentation and README" --date="today 08:00"

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Pre-compile to save time, but allow tests to fail
su - ga -c "cd '$PROJECT_DIR' && mvn compile -q"

# Setup IntelliJ
setup_intellij_project "$PROJECT_DIR" "git-bisect-lab" 120

# Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="