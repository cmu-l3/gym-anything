#!/bin/bash
set -e
echo "=== Setting up reorganize_package_structure task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/ShopManager"
SRC_DIR="$PROJECT_DIR/src/main/java/myapp"

# 1. Clean up any previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$SRC_DIR"

# 2. Create Maven POM
cat > "$PROJECT_DIR/pom.xml" << 'EOFPOM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.myapp</groupId>
  <artifactId>ShopManager</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
EOFPOM

# 3. Create Java Source Files (Flat Structure with Dependencies)

# Models
cat > "$SRC_DIR/User.java" << 'EOF'
package myapp;
public class User {
    private String name;
    public User(String name) { this.name = name; }
    public String getName() { return name; }
}
EOF

cat > "$SRC_DIR/Product.java" << 'EOF'
package myapp;
public class Product {
    private String title;
    private double price;
    public Product(String title, double price) {
        this.title = title;
        this.price = price;
    }
    public double getPrice() { return price; }
}
EOF

cat > "$SRC_DIR/Order.java" << 'EOF'
package myapp;
import java.util.List;
public class Order {
    private User user;
    private List<Product> products;
    public Order(User user, List<Product> products) {
        this.user = user;
        this.products = products;
    }
}
EOF

# Utils
cat > "$SRC_DIR/StringUtils.java" << 'EOF'
package myapp;
public class StringUtils {
    public static boolean isEmpty(String s) { return s == null || s.isEmpty(); }
}
EOF

cat > "$SRC_DIR/DateUtils.java" << 'EOF'
package myapp;
import java.time.LocalDate;
public class DateUtils {
    public static LocalDate getToday() { return LocalDate.now(); }
}
EOF

# Config
cat > "$SRC_DIR/AppConfig.java" << 'EOF'
package myapp;
public class AppConfig {
    public String getDbUrl() { return "jdbc:mysql://localhost:3306/shop"; }
}
EOF

# Services (Dependencies on Models, Utils, Config)
cat > "$SRC_DIR/UserService.java" << 'EOF'
package myapp;
public class UserService {
    private AppConfig config;
    public UserService(AppConfig config) { this.config = config; }
    public void register(User user) {
        if(StringUtils.isEmpty(user.getName())) throw new IllegalArgumentException();
        System.out.println("Registered " + user.getName());
    }
}
EOF

cat > "$SRC_DIR/ProductService.java" << 'EOF'
package myapp;
public class ProductService {
    private AppConfig config;
    public ProductService(AppConfig config) { this.config = config; }
    public void addProduct(Product p) {
        System.out.println("Added product: " + p.getPrice());
    }
}
EOF

cat > "$SRC_DIR/OrderService.java" << 'EOF'
package myapp;
public class OrderService {
    private UserService userService;
    private ProductService productService;
    public OrderService(UserService u, ProductService p) {
        this.userService = u;
        this.productService = p;
    }
    public void process(Order order) {
        System.out.println("Processing order on " + DateUtils.getToday());
    }
}
EOF

# Main App
cat > "$SRC_DIR/App.java" << 'EOF'
package myapp;
import java.util.ArrayList;
public class App {
    public static void main(String[] args) {
        AppConfig config = new AppConfig();
        UserService us = new UserService(config);
        ProductService ps = new ProductService(config);
        OrderService os = new OrderService(us, ps);
        
        User user = new User("Alice");
        us.register(user);
        System.out.println("Shop Manager Started");
    }
}
EOF

# 4. Create Eclipse Metadata (.project, .classpath)
cat > "$PROJECT_DIR/.project" << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>ShopManager</name>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOFPROJECT

cat > "$PROJECT_DIR/.classpath" << 'EOFCLASSPATH'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER"/>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOFCLASSPATH

# 5. Set Permissions
chown -R ga:ga "$PROJECT_DIR"

# 6. Record Initial State
date +%s > /tmp/task_start_time.txt
find "$SRC_DIR" -type f > /tmp/initial_file_list.txt

# 7. Launch Eclipse
# Ensure no previous instance
pkill -f eclipse || true
sleep 1

# Launch Eclipse with workspace
echo "Launching Eclipse..."
su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace -nosplash > /tmp/eclipse.log 2>&1 &"

# Wait for Eclipse
wait_for_eclipse 120 || echo "WARNING: Eclipse start timeout"

# Focus and Maximize
focus_eclipse_window
sleep 2
dismiss_dialogs

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="