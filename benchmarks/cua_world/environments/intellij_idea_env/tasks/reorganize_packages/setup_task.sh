#!/bin/bash
echo "=== Setting up reorganize_packages task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/library-system"
SRC_DIR="$PROJECT_DIR/src/main/java/com/library/app"

# 1. Create Project Structure
mkdir -p "$SRC_DIR"
chown -R ga:ga /home/ga/IdeaProjects

# 2. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.library</groupId>
  <artifactId>library-system</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
POM

# 3. Generate Java Files (Flat Structure)

# Book.java
cat > "$SRC_DIR/Book.java" << 'EOF'
package com.library.app;

public class Book {
    private String id;
    private String title;
    private String author;

    public Book(String id, String title, String author) {
        this.id = id;
        this.title = title;
        this.author = author;
    }

    public String getId() { return id; }
    public String getTitle() { return title; }
}
EOF

# Member.java
cat > "$SRC_DIR/Member.java" << 'EOF'
package com.library.app;

public class Member {
    private String id;
    private String name;

    public Member(String id, String name) {
        this.id = id;
        this.name = name;
    }

    public String getName() { return name; }
}
EOF

# Loan.java
cat > "$SRC_DIR/Loan.java" << 'EOF'
package com.library.app;

import java.time.LocalDate;

public class Loan {
    private Book book;
    private Member member;
    private LocalDate loanDate;

    public Loan(Book book, Member member) {
        this.book = book;
        this.member = member;
        this.loanDate = LocalDate.now();
    }
}
EOF

# DateUtils.java
cat > "$SRC_DIR/DateUtils.java" << 'EOF'
package com.library.app;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;

public class DateUtils {
    public static String format(LocalDate date) {
        return date.format(DateTimeFormatter.ISO_DATE);
    }
}
EOF

# ValidationUtils.java
cat > "$SRC_DIR/ValidationUtils.java" << 'EOF'
package com.library.app;

public class ValidationUtils {
    public static boolean isValidMember(Member member) {
        return member.getName() != null && !member.getName().isEmpty();
    }
}
EOF

# LibraryService.java
cat > "$SRC_DIR/LibraryService.java" << 'EOF'
package com.library.app;

import java.util.ArrayList;
import java.util.List;

public class LibraryService {
    private List<Book> books = new ArrayList<>();
    private List<Loan> loans = new ArrayList<>();

    public void addBook(Book book) {
        books.add(book);
    }

    public void loanBook(Book book, Member member) {
        if (ValidationUtils.isValidMember(member)) {
            loans.add(new Loan(book, member));
            System.out.println("Loaned on " + DateUtils.format(java.time.LocalDate.now()));
        }
    }
}
EOF

# SearchService.java
cat > "$SRC_DIR/SearchService.java" << 'EOF'
package com.library.app;

import java.util.List;

public class SearchService {
    public Book findBook(List<Book> books, String query) {
        for (Book b : books) {
            if (b.getTitle().contains(query)) return b;
        }
        return null;
    }
}
EOF

# LibraryApp.java
cat > "$SRC_DIR/LibraryApp.java" << 'EOF'
package com.library.app;

public class LibraryApp {
    public static void main(String[] args) {
        LibraryService lib = new LibraryService();
        lib.addBook(new Book("1", "The Hobbit", "Tolkien"));
        System.out.println("Library System initialized.");
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record file modification times
find "$PROJECT_DIR" -type f -exec stat -c "%n %Y" {} + > /tmp/initial_timestamps.txt

# Open Project
setup_intellij_project "$PROJECT_DIR" "library-system" 120

# Take screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="