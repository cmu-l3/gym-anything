#!/bin/bash
set -e

echo "=== Setting up Externalize Strings i18n task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---- Create the LibraryApp Maven project ----
PROJECT_DIR="/home/ga/eclipse-workspace/LibraryApp"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/library/app"
mkdir -p "$PROJECT_DIR/src/main/java/com/library/model"
mkdir -p "$PROJECT_DIR/src/test/java/com/library/app"

# ---- Create pom.xml ----
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.library</groupId>
    <artifactId>LibraryApp</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>jar</packaging>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
POMEOF

# ---- Create BookStatus.java ----
cat > "$PROJECT_DIR/src/main/java/com/library/model/BookStatus.java" << 'JAVAEOF'
package com.library.model;
public enum BookStatus {
    AVAILABLE, CHECKED_OUT, RESERVED, LOST
}
JAVAEOF

# ---- Create Book.java ----
cat > "$PROJECT_DIR/src/main/java/com/library/model/Book.java" << 'JAVAEOF'
package com.library.model;
public class Book {
    private final String title;
    private final String author;
    private final String isbn;
    private BookStatus status;
    public Book(String title, String author, String isbn) {
        this.title = title;
        this.author = author;
        this.isbn = isbn;
        this.status = BookStatus.AVAILABLE;
    }
    public String getTitle() { return title; }
    public String getAuthor() { return author; }
    public String getIsbn() { return isbn; }
    public BookStatus getStatus() { return status; }
    public void setStatus(BookStatus status) { this.status = status; }
    @Override
    public String toString() { return String.format("[%s] %s by %s", isbn, title, author); }
}
JAVAEOF

# ---- Create LibraryException.java ----
cat > "$PROJECT_DIR/src/main/java/com/library/app/LibraryException.java" << 'JAVAEOF'
package com.library.app;
public class LibraryException extends Exception {
    public LibraryException(String message) { super(message); }
}
JAVAEOF

# ---- Create BookManager.java ----
cat > "$PROJECT_DIR/src/main/java/com/library/app/BookManager.java" << 'JAVAEOF'
package com.library.app;
import com.library.model.Book;
import com.library.model.BookStatus;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

public class BookManager {
    private final List<Book> catalog = new ArrayList<>();
    public BookManager() {
        catalog.add(new Book("The Great Gatsby", "F. Scott Fitzgerald", "978-0743273565"));
        catalog.add(new Book("1984", "George Orwell", "978-0451524935"));
    }
    public void addBook(Book book) { catalog.add(book); }
    public List<Book> getAllBooks() { return new ArrayList<>(catalog); }
}
JAVAEOF

# ---- Create LibraryApp.java (TARGET FILE) ----
cat > "$PROJECT_DIR/src/main/java/com/library/app/LibraryApp.java" << 'JAVAEOF'
package com.library.app;

import com.library.model.Book;
import java.util.List;
import java.util.Scanner;

public class LibraryApp {
    private final BookManager bookManager;
    private final Scanner scanner;

    public LibraryApp() {
        this.bookManager = new BookManager();
        this.scanner = new Scanner(System.in);
    }

    public void run() {
        System.out.println("Welcome to the Library Management System");
        System.out.println("=========================================");
        System.out.println("Please select an option from the menu below.");

        boolean running = true;
        while (running) {
            displayMenu();
            String choice = scanner.nextLine().trim();

            switch (choice) {
                case "1":
                    listAllBooks();
                    break;
                case "2":
                    addNewBook();
                    break;
                case "3":
                    running = false;
                    System.out.println("Thank you for using the Library Management System. Goodbye!");
                    break;
                default:
                    System.out.println("Invalid option. Please try again.");
            }
        }
    }

    private void displayMenu() {
        System.out.println("\n--- Main Menu ---");
        System.out.println("1. List all books");
        System.out.println("2. Add a new book");
        System.out.println("3. Exit");
        System.out.print("Enter your choice: ");
    }

    private void listAllBooks() {
        System.out.println("\n--- Library Catalog ---");
        List<Book> books = bookManager.getAllBooks();
        if (books.isEmpty()) {
            System.out.println("The catalog is empty.");
        } else {
            System.out.println("Total books: " + books.size());
            for (Book book : books) {
                System.out.println("  " + book);
            }
        }
    }

    private void addNewBook() {
        System.out.println("\n--- Add New Book ---");
        System.out.print("Enter title: ");
        String title = scanner.nextLine();
        System.out.print("Enter author: ");
        String author = scanner.nextLine();
        System.out.print("Enter ISBN: ");
        String isbn = scanner.nextLine();
        
        bookManager.addBook(new Book(title, author, isbn));
        System.out.println("Book added successfully.");
    }

    public static void main(String[] args) {
        new LibraryApp().run();
    }
}
JAVAEOF

# ---- Setup Eclipse Project Metadata ----
cat > "$PROJECT_DIR/.project" << 'PROJEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>LibraryApp</name>
    <comment></comment>
    <projects></projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments></arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments></arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
PROJEOF

cat > "$PROJECT_DIR/.classpath" << 'CPEOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER"/>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
CPEOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Calculate hash of original file for verification
sha256sum "$PROJECT_DIR/src/main/java/com/library/app/LibraryApp.java" | awk '{print $1}' > /tmp/original_hash.txt

# Start Eclipse
if ! pgrep -f "eclipse" > /dev/null; then
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace > /tmp/eclipse.log 2>&1 &"
fi

# Wait for Eclipse
wait_for_eclipse 60

# Maximize
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="