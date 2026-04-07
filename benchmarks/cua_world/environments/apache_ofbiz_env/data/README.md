# Apache OFBiz Demo Data Reference

This directory documents the real demo data that comes pre-loaded in Apache OFBiz
when started with `OFBIZ_DATA_LOAD=demo`.

## Data Source

All data comes from the official Apache OFBiz demo data, loaded via the OFBiz
framework's seed and demo data loading mechanism. This is **real** data from
the Apache OFBiz project, not synthetic or handwritten.

Sources:
- https://github.com/apache/ofbiz-framework (applications/*/data/ directories)
- https://github.com/apache/ofbiz (applications/accounting/data/DemoPaymentsInvoices.xml)
- https://demo-stable.ofbiz.apache.org (live demo)

## Demo Users

| Username | Password | Role |
|----------|----------|------|
| admin | ofbiz | Administrator |
| DemoCustomer | ofbiz | Customer |
| DemoSupplier | ofbiz | Supplier |
| DemoEmployee | ofbiz | Employee |
| DemoCustAgent | ofbiz | Sales Representative |
| AcctBuyer | ofbiz | Accounting Buyer |

## Demo Products (from Product Catalog)

| Product ID | Name | Price | Type |
|-----------|------|-------|------|
| GZ-1000 | Tiny Gizmo | $9.99 | FINISHED_GOOD |
| GZ-2644 | Round Gizmo | $38.40 | FINISHED_GOOD |
| WG-1111 | Micro Chrome Widget | $59.99 | FINISHED_GOOD |
| WG-5569 | Tiny Chrome Widget | $48.00 | FINISHED_GOOD |
| WG-9943 | Giant Widget | $440.00 | FINISHED_GOOD |
| GC-001 | Gift Card Activation | $1.00+ | DIGITAL_GOOD |
| PC001 | Configurable PC | $700.00 | AGGREGATED |

## Demo Parties (Customers, Suppliers)

| Party ID | Name | Type |
|----------|------|------|
| Company | Company (default org) | PARTY_GROUP |
| AcctBuyer | Accounting Buyer | PERSON |
| AcctBigSupplier | Big Supplier | PARTY_GROUP |
| DemoCustCompany | Demo Customer Company | PARTY_GROUP |
| EuroCustomer | Euro Customer | PARTY_GROUP |

## Demo Invoices

| Invoice ID | Type | From | To | Amount | Currency |
|-----------|------|------|----|--------|----------|
| demo10000 | SALES_INVOICE | Company | AcctBuyer | $323.54 | USD |
| demo10001 | PURCHASE_INVOICE | AcctBigSupplier | Company | $36.43 | USD |
| demo10002 | SALES_INVOICE | Company | AcctBuyer | $56.99 | USD |
| demo11000 | SALES_INVOICE | Company | EuroCustomer | EUR 20.00 | EUR |
| demo1200 | SALES_INVOICE | Company | DemoCustCompany | $511.23 | USD |

## OFBiz Web Modules

| Module | URL Path | Description |
|--------|----------|-------------|
| Accounting | /accounting/control/main | Financial management, invoices, payments |
| Order Manager | /ordermgr/control/main | Sales orders, purchase orders |
| Catalog | /catalog/control/main | Product catalog management |
| Party Manager | /partymgr/control/main | Customer/supplier management |
| Manufacturing | /manufacturing/control/main | Production management |
| Facility | /facility/control/main | Warehouse/inventory |
| WebTools | /webtools/control/main | System administration |
