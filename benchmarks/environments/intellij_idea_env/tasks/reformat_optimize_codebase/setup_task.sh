#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up reformat_optimize_codebase task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing IntelliJ instances
pkill -f idea 2>/dev/null || true
sleep 2

PROJECT_DIR="/home/ga/IdeaProjects/inventory-manager"
SRC_DIR="$PROJECT_DIR/src/main/java/com/inventory"

# Clean up any previous task artifacts
rm -rf "$PROJECT_DIR"
mkdir -p "$SRC_DIR"
mkdir -p "$PROJECT_DIR/src/test/java"

# Create .editorconfig (real standard formatting rules)
cat > "$PROJECT_DIR/.editorconfig" << 'EDITORCONFIG'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.java]
indent_style = space
indent_size = 4
max_line_length = 120
EDITORCONFIG

# Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMXML'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.inventory</groupId>
    <artifactId>inventory-manager</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>
</project>
POMXML

# --- Create messy Java source files ---
# These files have DELIBERATELY bad formatting that represents real-world messiness

# 1. Product.java - Mixed tabs and spaces, wildcard imports, unused imports
# Using printf to write tabs literally
cat > "$SRC_DIR/Product.java" << 'JAVAEOF'
package com.inventory;

import java.util.*;
import java.io.Serializable;
import java.math.BigDecimal;
import java.awt.Color;
import java.io.FileNotFoundException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

public class Product implements Serializable    {
	private static final long serialVersionUID = 1L;
	private String id;
    private String name;
  private BigDecimal price;
      private int quantity;
	private Category category;
    private LocalDateTime createdAt;   
	private LocalDateTime updatedAt;

  public Product(String id, String name, BigDecimal price, int quantity, Category category)   {
	    this.id = id;
	    this.name = name;
        this.price = price;
      this.quantity = quantity;
	    this.category = category;
        this.createdAt = LocalDateTime.now();   
	    this.updatedAt = LocalDateTime.now();
    }



    public String getId()  {   return id;  }
  public void setId(  String id  ) { this.id = id;   }

	public String getName() { return name; }
    public void setName(String name) {    this.name = name;    }

  public BigDecimal getPrice() {
      return price;
    }
    public void setPrice(  BigDecimal price  ) {
	    if (price.compareTo(BigDecimal.ZERO) < 0) {
		    throw new IllegalArgumentException("Price cannot be negative");
	    }
        this.price = price;   
    }


    public int getQuantity() {   return quantity;   }
  public void setQuantity(int quantity)
    {
	    if (quantity < 0) 
        {
		    throw new IllegalArgumentException("Quantity cannot be negative");   
        }
      this.quantity = quantity;
	    this.updatedAt = LocalDateTime.now();
    }

	public Category getCategory() { return category; }
  public void setCategory(Category category)  { this.category = category;  }

    public LocalDateTime getCreatedAt()  { return createdAt;  }
	public LocalDateTime getUpdatedAt() { return updatedAt; }

  public String getFormattedCreatedAt() {
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
	    return createdAt.format(formatter);
    }


    @Override
	public boolean equals(Object o) {
        if (this == o) return true;   
      if (o == null || getClass() != o.getClass()) return false;
	    Product product = (Product) o;
        return Objects.equals(id, product.id);
    }

  @Override
	public int hashCode() {
      return Objects.hash(id);
    }


	@Override
    public String toString()  {
      return "Product{" +
	        "id='" + id + '\'' +
            ", name='" + name + '\'' +   
          ", price=" + price +
	        ", quantity=" + quantity +
            ", category=" + category +
          '}';
    }
}
JAVAEOF

# 2. Warehouse.java - Inconsistent indentation, wildcard imports, trailing whitespace
cat > "$SRC_DIR/Warehouse.java" << 'JAVAEOF'
package com.inventory;

import java.util.*;
import java.util.stream.*;
import java.math.BigDecimal;
import java.io.PrintWriter;
import java.io.IOException;

public class Warehouse    {
  private final String name;
    private final String location;
	private final Map<String, Product> products;
      private final List<String> operationLog;

    public Warehouse(String name, String location) {   
	this.name = name;
  this.location = location;
      this.products = new HashMap<>();
	this.operationLog = new ArrayList<>();
    }



  public void addProduct(Product product) {
	    if (product == null) {
            throw new IllegalArgumentException("Product cannot be null");   
      }
        products.put(product.getId(), product);   
	    operationLog.add("Added product: " + product.getName());
    }

    public void removeProduct(String productId)  {
      Product removed = products.remove(productId);
	    if (removed != null)  {
          operationLog.add("Removed product: " + removed.getName());   
        }
    }


  public Optional<Product> findProduct(String productId) {
	    return Optional.ofNullable(products.get(productId));
    }

      public List<Product> findByCategory(Category category) {
        return products.values().stream()   
	        .filter(p -> p.getCategory() == category)
          .sorted(Comparator.comparing(Product::getName))
            .collect(Collectors.toList());
    }

	public List<Product> findByPriceRange(BigDecimal min, BigDecimal max) {
      return products.values().stream()
	        .filter(p -> p.getPrice().compareTo(min) >= 0 && p.getPrice().compareTo(max) <= 0)
            .sorted(Comparator.comparing(Product::getPrice))   
          .collect(Collectors.toList());
    }


    public BigDecimal getTotalInventoryValue()  {
	    return products.values().stream()
          .map(p -> p.getPrice().multiply(BigDecimal.valueOf(p.getQuantity())))
      .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

  public int getTotalProductCount() {
	    return products.values().stream()
            .mapToInt(Product::getQuantity)   
      .sum();
    }

	public Map<Category, Long> getProductCountByCategory() {
        return products.values().stream()
          .collect(Collectors.groupingBy(Product::getCategory, Collectors.counting()));
    }


      public List<Product> getLowStockProducts(int threshold)  {
	    return products.values().stream()
            .filter(p -> p.getQuantity() < threshold)
          .sorted(Comparator.comparingInt(Product::getQuantity))   
	        .collect(Collectors.toList());
    }

    public String getName()  { return name;  }
  public String getLocation() { return location; }
	public int getProductTypeCount() { return products.size(); }
    public List<String> getOperationLog() {
        return Collections.unmodifiableList(operationLog);   
    }
}
JAVAEOF

# 3. InventoryService.java - Bad formatting, unused imports, wildcard imports
cat > "$SRC_DIR/InventoryService.java" << 'JAVAEOF'
package com.inventory;

import java.util.*;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.stream.Collectors;
import java.net.URL;
import java.net.MalformedURLException;

public class InventoryService  {
	private final List<Warehouse> warehouses;
    private final Map<String, BigDecimal> discountRules;   

  public InventoryService() {
	    this.warehouses = new ArrayList<>();
        this.discountRules = new HashMap<>();
      initializeDefaultDiscounts();
    }



    private void initializeDefaultDiscounts() {
	discountRules.put("BULK_10", new BigDecimal("0.05"));
  discountRules.put("BULK_50", new BigDecimal("0.10"));
      discountRules.put("BULK_100", new BigDecimal("0.15"));
	discountRules.put("CLEARANCE", new BigDecimal("0.30"));
    }

  public void registerWarehouse(Warehouse warehouse) {
	    if (warehouse == null) {
          throw new IllegalArgumentException("Warehouse cannot be null");
        }
        warehouses.add(warehouse);   
    }


	public List<Product> searchProducts(String keyword) {
      return warehouses.stream()
	        .flatMap(w -> {
                List<Product> found = new ArrayList<>();
              for (Category cat : Category.values()) {
	                found.addAll(w.findByCategory(cat));
                }   
              return found.stream();
	        })
            .filter(p -> p.getName().toLowerCase().contains(keyword.toLowerCase()))
          .distinct()
	        .sorted(Comparator.comparing(Product::getName))
            .collect(Collectors.toList());   
    }


  public BigDecimal calculateDiscountedPrice(Product product, int quantity) {
	    BigDecimal basePrice = product.getPrice().multiply(BigDecimal.valueOf(quantity));
        BigDecimal discountRate = BigDecimal.ZERO;

      if (quantity >= 100) {
	        discountRate = discountRules.getOrDefault("BULK_100", BigDecimal.ZERO);
        } else if (quantity >= 50) {   
          discountRate = discountRules.getOrDefault("BULK_50", BigDecimal.ZERO);
	    } else if (quantity >= 10)  {
            discountRate = discountRules.getOrDefault("BULK_10", BigDecimal.ZERO);
        }

      BigDecimal discount = basePrice.multiply(discountRate);
	    return basePrice.subtract(discount).setScale(2, RoundingMode.HALF_UP);
    }


    public Map<String, BigDecimal> generateInventoryReport() {
	Map<String, BigDecimal> report = new LinkedHashMap<>();

  BigDecimal totalValue = BigDecimal.ZERO;
        int totalProducts = 0;
      int totalWarehouses = warehouses.size();

	    for (Warehouse warehouse : warehouses) {
          BigDecimal warehouseValue = warehouse.getTotalInventoryValue();
            report.put("warehouse_" + warehouse.getName() + "_value", warehouseValue);   
	        report.put("warehouse_" + warehouse.getName() + "_products",
                BigDecimal.valueOf(warehouse.getProductTypeCount()));
          totalValue = totalValue.add(warehouseValue);
	        totalProducts += warehouse.getTotalProductCount();
        }


        report.put("total_value", totalValue);
      report.put("total_products", BigDecimal.valueOf(totalProducts));
	    report.put("total_warehouses", BigDecimal.valueOf(totalWarehouses));

        if (totalWarehouses > 0) {   
          report.put("avg_value_per_warehouse",
	            totalValue.divide(BigDecimal.valueOf(totalWarehouses), 2, RoundingMode.HALF_UP));
        }

      return report;
    }


	public List<Product> getGlobalLowStock(int threshold) {
        return warehouses.stream()   
          .flatMap(w -> w.getLowStockProducts(threshold).stream())
	        .sorted(Comparator.comparingInt(Product::getQuantity))
            .collect(Collectors.toList());
    }

    public List<Warehouse> getWarehouses() {
      return Collections.unmodifiableList(warehouses);   
    }
}
JAVAEOF

# 4. Category.java - Messy enum formatting, unused import
cat > "$SRC_DIR/Category.java" << 'JAVAEOF'
package com.inventory;

import java.util.*;
import java.io.File;

public enum Category    {
	ELECTRONICS("Electronics", "Electronic devices and components"),
    CLOTHING(  "Clothing"  ,   "Apparel and accessories"  ),
  FOOD("Food & Beverages", "Consumable food items and drinks"),
      FURNITURE("Furniture", "Home and office furniture"),
	TOOLS("Tools & Hardware", "Tools and hardware supplies"),
    BOOKS("Books & Media", "Books, magazines, and digital media"),   
  OTHER("Other", "Miscellaneous items");



	private final String displayName;
    private final String description;   

  Category(String displayName, String description) {
	    this.displayName = displayName;
        this.description = description;
    }


    public String getDisplayName()  {   return displayName;  }
	public String getDescription() { return description; }


  public static Category fromDisplayName(String displayName) {
	    for (Category category : values()) {
            if (category.displayName.equalsIgnoreCase(displayName))   {
              return category;
	        }
        }
      throw new IllegalArgumentException("Unknown category: " + displayName);
    }


	public static List<Category> getProductCategories() {
        List<Category> categories = new ArrayList<>();
      for (Category cat : values()) {
	        if (cat != OTHER) {
                categories.add(cat);   
          }
        }
	    return categories;
    }

    @Override
  public String toString()  {
	    return displayName;
    }
}
JAVAEOF

# 5. InventoryApp.java - Main class with all kinds of formatting issues
cat > "$SRC_DIR/InventoryApp.java" << 'JAVAEOF'
package com.inventory;

import java.util.*;
import java.math.BigDecimal;
import java.util.stream.*;
import java.io.BufferedReader;
import java.io.InputStreamReader;

public class InventoryApp    {

	private static final String APP_NAME = "Inventory Manager v1.0";
    private static final String SEPARATOR = "=".repeat(50);   

  public static void main(String[] args) {
	    System.out.println(APP_NAME);
        System.out.println(SEPARATOR);

      InventoryService service = new InventoryService();

	    Warehouse mainWarehouse = new Warehouse("Main", "Building A, Floor 1");
        Warehouse backupWarehouse = new Warehouse("Backup", "Building B, Floor 2");   

      service.registerWarehouse(mainWarehouse);
	    service.registerWarehouse(backupWarehouse);


        populateWarehouse(mainWarehouse);
      populateBackupWarehouse(backupWarehouse);

	    printInventorySummary(service);
        printLowStockAlert(service);   
      printCategoryBreakdown(mainWarehouse);
	    printPricingExample(service, mainWarehouse);
    }



  private static void populateWarehouse(Warehouse warehouse)  {
	    warehouse.addProduct(new Product("P001", "Laptop Pro 15",
            new BigDecimal("1299.99"), 25, Category.ELECTRONICS));
      warehouse.addProduct(new Product("P002", "Wireless Mouse",
	        new BigDecimal("29.99"), 150, Category.ELECTRONICS));   
        warehouse.addProduct(new Product("P003", "Cotton T-Shirt",
          new BigDecimal("19.99"), 200, Category.CLOTHING));
	    warehouse.addProduct(new Product("P004", "Office Desk",
            new BigDecimal("449.99"), 8, Category.FURNITURE));
      warehouse.addProduct(new Product("P005", "Java Programming Guide",   
	        new BigDecimal("49.99"), 75, Category.BOOKS));
        warehouse.addProduct(new Product("P006", "Organic Coffee Beans",
          new BigDecimal("14.99"), 3, Category.FOOD));
    }


	private static void populateBackupWarehouse(Warehouse warehouse) {
      warehouse.addProduct(new Product("P007", "Power Drill",
            new BigDecimal("89.99"), 45, Category.TOOLS));   
	    warehouse.addProduct(new Product("P008", "Winter Jacket",
          new BigDecimal("129.99"), 60, Category.CLOTHING));
        warehouse.addProduct(new Product("P009", "Standing Desk",
      new BigDecimal("599.99"), 5, Category.FURNITURE));
    }

    private static void printInventorySummary(InventoryService service)  {
	System.out.println("\n--- Inventory Summary ---");
  Map<String, BigDecimal> report = service.generateInventoryReport();

        for (Map.Entry<String, BigDecimal> entry : report.entrySet()) {   
	    System.out.printf("  %-35s: %10s%n", entry.getKey(), entry.getValue());
  }
      System.out.println(SEPARATOR);
    }


	private static void printLowStockAlert(InventoryService service) {
        System.out.println("\n--- Low Stock Alert (< 10 units) ---");
      List<Product> lowStock = service.getGlobalLowStock(10);   

	    if (lowStock.isEmpty()) {
            System.out.println("  All products are well-stocked.");
        } else {
          for (Product p : lowStock) {
	            System.out.printf("  WARNING: %s (ID: %s) - Only %d units remaining%n",
                    p.getName(), p.getId(), p.getQuantity());
          }
        }
	    System.out.println(SEPARATOR);
    }


    private static void printCategoryBreakdown(Warehouse warehouse)   {
      System.out.println("\n--- Category Breakdown: " + warehouse.getName() + " ---");
	    Map<Category, Long> breakdown = warehouse.getProductCountByCategory();

        for (Map.Entry<Category, Long> entry : breakdown.entrySet()) {
          System.out.printf("  %-20s: %d product type(s)%n",   
	            entry.getKey().getDisplayName(), entry.getValue());
        }
      System.out.println(SEPARATOR);
    }


	private static void printPricingExample(InventoryService service, Warehouse warehouse) {
        System.out.println("\n--- Pricing Examples ---");

      Optional<Product> laptop = warehouse.findProduct("P001");   
	    laptop.ifPresent(p -> {
            int[] quantities = {1, 10, 50, 100};
          for (int qty : quantities)  {
	            BigDecimal total = service.calculateDiscountedPrice(p, qty);
                System.out.printf("  %s x%d = $%s%n", p.getName(), qty, total);
          }
	    });
        System.out.println(SEPARATOR);
    }
}
JAVAEOF

# Save copies of the original messy files for verification comparison
mkdir -p /tmp/original_messy_files
cp "$SRC_DIR"/*.java /tmp/original_messy_files/
chmod 644 /tmp/original_messy_files/*.java

# Verify the project compiles before handing off (sanity check)
echo "Verifying project compiles in its messy state..."
cd "$PROJECT_DIR"
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q 2>/tmp/initial_compile.log
if [ $? -eq 0 ]; then
    echo "Project compiles successfully in initial messy state"
else
    echo "ERROR: Project does not compile in initial state!"
    cat /tmp/initial_compile.log
    exit 1
fi

# Set proper ownership
chown -R ga:ga "$PROJECT_DIR"
chown -R ga:ga /tmp/original_messy_files

# Launch IntelliJ with the project
setup_intellij_project "$PROJECT_DIR" "inventory-manager" 120

# Take screenshot of initial state
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="