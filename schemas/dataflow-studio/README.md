# dataflow-studio — Schemas

## Ownership

DataFlow Studio owns three data surfaces:

| Store | Database / schema | Role |
|---|---|---|
| SQL Server AG | `OltpDb` | Source of truth — relational OLTP |
| StarRocks | `dwh` + `analytics` | Kimball DWH + real-time serving |
| ClickHouse | `analytics` | Pipeline telemetry, latency observability |

**Migration tools:** FluentMigrator for `OltpDb`; DbUp (SQL-script) for StarRocks and ClickHouse.
**Acceptance gate:** MASTER-PLAN §6. FluentMigrator up → down → up passes in CI.
**Status:** DDL authored; migrations begin in Phase 1.

## SQL Server — `OltpDb` (source)

11 tables. Standard audit columns (`created_utc, created_by, modified_utc, modified_by, row_version, is_deleted`) on every business table.

```sql
-- Customers
CREATE TABLE dbo.Customers (
    CustomerId       BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CustomerCode     VARCHAR(32) NOT NULL UNIQUE,
    DisplayName      NVARCHAR(200) NOT NULL,
    Email            NVARCHAR(256) NOT NULL,
    PhoneE164        VARCHAR(20) NULL,
    PreferredLocale  VARCHAR(10) NOT NULL DEFAULT 'en-US',
    Status           TINYINT NOT NULL DEFAULT 1,
    LifetimeValueUsd DECIMAL(18,2) NOT NULL DEFAULT 0,
    created_utc      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by       NVARCHAR(100) NOT NULL,
    modified_utc     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by      NVARCHAR(100) NOT NULL,
    row_version      ROWVERSION NOT NULL,
    is_deleted       BIT NOT NULL DEFAULT 0,
    ValidFrom        DATETIME2(3) GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo          DATETIME2(3) GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.CustomersHistory));

CREATE TABLE dbo.CustomerAddresses (
    AddressId      BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CustomerId     BIGINT NOT NULL REFERENCES dbo.Customers(CustomerId),
    AddressType    TINYINT NOT NULL,    -- 1=billing 2=shipping
    Line1          NVARCHAR(200) NOT NULL,
    Line2          NVARCHAR(200) NULL,
    City           NVARCHAR(100) NOT NULL,
    Region         NVARCHAR(100) NULL,
    PostalCode     VARCHAR(20) NOT NULL,
    CountryIso2    CHAR(2) NOT NULL,
    IsDefault      BIT NOT NULL DEFAULT 0,
    created_utc    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by     NVARCHAR(100) NOT NULL,
    modified_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by    NVARCHAR(100) NOT NULL,
    row_version    ROWVERSION NOT NULL,
    is_deleted     BIT NOT NULL DEFAULT 0
);

CREATE TABLE dbo.ProductCategories (
    CategoryId     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ParentId       INT NULL REFERENCES dbo.ProductCategories(CategoryId),
    Name           NVARCHAR(200) NOT NULL,
    Slug           VARCHAR(200) NOT NULL UNIQUE,
    DisplayOrder   INT NOT NULL DEFAULT 0,
    created_utc    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by     NVARCHAR(100) NOT NULL,
    modified_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by    NVARCHAR(100) NOT NULL,
    row_version    ROWVERSION NOT NULL,
    is_deleted     BIT NOT NULL DEFAULT 0
);

CREATE TABLE dbo.Products (
    ProductId      BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Sku            VARCHAR(64) NOT NULL UNIQUE,
    CategoryId     INT NOT NULL REFERENCES dbo.ProductCategories(CategoryId),
    DisplayName    NVARCHAR(300) NOT NULL,
    Description    NVARCHAR(MAX) NULL,
    ListPriceUsd   DECIMAL(18,4) NOT NULL,
    Weight_g       INT NULL,
    Status         TINYINT NOT NULL DEFAULT 1,
    created_utc    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by     NVARCHAR(100) NOT NULL,
    modified_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by    NVARCHAR(100) NOT NULL,
    row_version    ROWVERSION NOT NULL,
    is_deleted     BIT NOT NULL DEFAULT 0,
    ValidFrom      DATETIME2(3) GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo        DATETIME2(3) GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.ProductsHistory));

CREATE TABLE dbo.Warehouses (
    WarehouseId   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Code          VARCHAR(16) NOT NULL UNIQUE,
    Name          NVARCHAR(200) NOT NULL,
    Region        NVARCHAR(100) NOT NULL,
    CountryIso2   CHAR(2) NOT NULL,
    TimezoneIana  VARCHAR(64) NOT NULL,
    created_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by    NVARCHAR(100) NOT NULL,
    modified_utc  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by   NVARCHAR(100) NOT NULL,
    row_version   ROWVERSION NOT NULL,
    is_deleted    BIT NOT NULL DEFAULT 0
);

CREATE TABLE dbo.ProductInventory (
    ProductId      BIGINT NOT NULL REFERENCES dbo.Products(ProductId),
    WarehouseId    INT    NOT NULL REFERENCES dbo.Warehouses(WarehouseId),
    OnHand         INT NOT NULL DEFAULT 0,
    Reserved       INT NOT NULL DEFAULT 0,
    ReorderPoint   INT NOT NULL DEFAULT 0,
    SafetyStock    INT NOT NULL DEFAULT 0,
    created_utc    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by     NVARCHAR(100) NOT NULL,
    modified_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by    NVARCHAR(100) NOT NULL,
    row_version    ROWVERSION NOT NULL,
    is_deleted     BIT NOT NULL DEFAULT 0,
    PRIMARY KEY (ProductId, WarehouseId)
);

CREATE TABLE dbo.Orders (
    OrderId        BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    OrderNumber    VARCHAR(32) NOT NULL UNIQUE,
    CustomerId     BIGINT NOT NULL REFERENCES dbo.Customers(CustomerId),
    BillingAddressId  BIGINT NOT NULL REFERENCES dbo.CustomerAddresses(AddressId),
    ShippingAddressId BIGINT NOT NULL REFERENCES dbo.CustomerAddresses(AddressId),
    PlacedAtUtc    DATETIME2(3) NOT NULL,
    Status         TINYINT NOT NULL,     -- 1 new, 2 paid, 3 shipped, 4 delivered, 5 cancelled
    SubtotalUsd    DECIMAL(18,2) NOT NULL,
    TaxUsd         DECIMAL(18,2) NOT NULL,
    ShippingUsd    DECIMAL(18,2) NOT NULL,
    TotalUsd       DECIMAL(18,2) NOT NULL,
    Currency       CHAR(3) NOT NULL DEFAULT 'USD',
    created_utc    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by     NVARCHAR(100) NOT NULL,
    modified_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by    NVARCHAR(100) NOT NULL,
    row_version    ROWVERSION NOT NULL,
    is_deleted     BIT NOT NULL DEFAULT 0
);

CREATE TABLE dbo.OrderLines (
    OrderLineId   BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    OrderId       BIGINT NOT NULL REFERENCES dbo.Orders(OrderId),
    ProductId     BIGINT NOT NULL REFERENCES dbo.Products(ProductId),
    WarehouseId   INT    NOT NULL REFERENCES dbo.Warehouses(WarehouseId),
    Quantity      INT NOT NULL,
    UnitPriceUsd  DECIMAL(18,4) NOT NULL,
    DiscountUsd   DECIMAL(18,4) NOT NULL DEFAULT 0,
    LineTotalUsd  AS (CAST(Quantity * UnitPriceUsd - DiscountUsd AS DECIMAL(18,2))) PERSISTED,
    created_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by    NVARCHAR(100) NOT NULL,
    modified_utc  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by   NVARCHAR(100) NOT NULL,
    row_version   ROWVERSION NOT NULL,
    is_deleted    BIT NOT NULL DEFAULT 0
);

CREATE TABLE dbo.Transactions (
    TransactionId   BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    OrderId         BIGINT NOT NULL REFERENCES dbo.Orders(OrderId),
    Provider        VARCHAR(32) NOT NULL,     -- stripe, paypal, ach
    ProviderRef     VARCHAR(64) NOT NULL,
    Kind            TINYINT NOT NULL,         -- 1 auth, 2 capture, 3 refund, 4 chargeback
    AmountUsd       DECIMAL(18,2) NOT NULL,
    OccurredAtUtc   DATETIME2(3) NOT NULL,
    Status          TINYINT NOT NULL,         -- 1 pending, 2 settled, 3 failed
    created_utc     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by      NVARCHAR(100) NOT NULL,
    modified_utc    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by     NVARCHAR(100) NOT NULL,
    row_version     ROWVERSION NOT NULL,
    is_deleted      BIT NOT NULL DEFAULT 0
);

CREATE TABLE dbo.Shipments (
    ShipmentId     BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    OrderId        BIGINT NOT NULL REFERENCES dbo.Orders(OrderId),
    Carrier        VARCHAR(32) NOT NULL,
    TrackingNumber VARCHAR(64) NOT NULL,
    ShippedAtUtc   DATETIME2(3) NULL,
    DeliveredAtUtc DATETIME2(3) NULL,
    Status         TINYINT NOT NULL,
    created_utc    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by     NVARCHAR(100) NOT NULL,
    modified_utc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    modified_by    NVARCHAR(100) NOT NULL,
    row_version    ROWVERSION NOT NULL,
    is_deleted     BIT NOT NULL DEFAULT 0
);

CREATE TABLE audit.ChangeLog (
    ChangeId     BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TableName    SYSNAME NOT NULL,
    PrimaryKey   NVARCHAR(256) NOT NULL,
    Operation    CHAR(1) NOT NULL,    -- I / U / D
    BeforeJson   NVARCHAR(MAX) NULL,
    AfterJson    NVARCHAR(MAX) NULL,
    ChangedBy    NVARCHAR(100) NOT NULL,
    ChangedUtc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
```

## StarRocks — `dwh` (Kimball) + `analytics` (real-time serving)

```sql
-- dwh.dim_date
CREATE TABLE dwh.dim_date (
    date_key INT NOT NULL,
    full_date DATE NOT NULL,
    year SMALLINT, quarter TINYINT, month TINYINT, day TINYINT,
    day_of_week TINYINT, is_weekend BOOLEAN, iso_week SMALLINT
) PRIMARY KEY(date_key)
DISTRIBUTED BY HASH(date_key) BUCKETS 1;

CREATE TABLE dwh.dim_customer (
    customer_sk BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    customer_code VARCHAR(32),
    display_name VARCHAR(200),
    email VARCHAR(256),
    preferred_locale VARCHAR(10),
    status TINYINT,
    lifetime_value_usd DECIMAL(18,2),
    valid_from DATETIME NOT NULL,
    valid_to   DATETIME NOT NULL,
    is_current BOOLEAN NOT NULL
) PRIMARY KEY(customer_sk)
DISTRIBUTED BY HASH(customer_id) BUCKETS 12;

CREATE TABLE dwh.dim_product (
    product_sk BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    sku VARCHAR(64),
    category_id INT,
    category_name VARCHAR(200),
    display_name VARCHAR(300),
    list_price_usd DECIMAL(18,4),
    valid_from DATETIME NOT NULL,
    valid_to   DATETIME NOT NULL,
    is_current BOOLEAN NOT NULL
) PRIMARY KEY(product_sk)
DISTRIBUTED BY HASH(product_id) BUCKETS 12;

CREATE TABLE dwh.dim_warehouse (
    warehouse_sk INT NOT NULL,
    warehouse_id INT NOT NULL,
    code VARCHAR(16), name VARCHAR(200), region VARCHAR(100),
    country_iso2 CHAR(2), timezone_iana VARCHAR(64)
) PRIMARY KEY(warehouse_sk)
DISTRIBUTED BY HASH(warehouse_id) BUCKETS 1;

CREATE TABLE dwh.dim_carrier (
    carrier_sk INT NOT NULL,
    carrier VARCHAR(32) NOT NULL,
    service_level VARCHAR(32)
) PRIMARY KEY(carrier_sk)
DISTRIBUTED BY HASH(carrier_sk) BUCKETS 1;

CREATE TABLE dwh.fact_order (
    order_id BIGINT NOT NULL,
    order_date_key INT NOT NULL,
    customer_sk BIGINT NOT NULL,
    billing_address_id BIGINT, shipping_address_id BIGINT,
    status TINYINT,
    subtotal_usd DECIMAL(18,2), tax_usd DECIMAL(18,2),
    shipping_usd DECIMAL(18,2), total_usd DECIMAL(18,2),
    currency CHAR(3), placed_at_utc DATETIME
) DUPLICATE KEY(order_id, order_date_key)
PARTITION BY RANGE(order_date_key) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 32;

CREATE TABLE dwh.fact_order_line (
    order_line_id BIGINT NOT NULL,
    order_id BIGINT NOT NULL,
    order_date_key INT NOT NULL,
    customer_sk BIGINT, product_sk BIGINT, warehouse_sk INT,
    quantity INT, unit_price_usd DECIMAL(18,4),
    discount_usd DECIMAL(18,4), line_total_usd DECIMAL(18,2)
) DUPLICATE KEY(order_line_id)
PARTITION BY RANGE(order_date_key) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES("colocate_with" = "order_group");

CREATE TABLE dwh.fact_transaction (
    transaction_id BIGINT NOT NULL,
    order_id BIGINT NOT NULL,
    txn_date_key INT NOT NULL,
    provider VARCHAR(32), kind TINYINT,
    amount_usd DECIMAL(18,2), status TINYINT, occurred_at_utc DATETIME
) DUPLICATE KEY(transaction_id)
PARTITION BY RANGE(txn_date_key) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 16
PROPERTIES("colocate_with" = "order_group");

CREATE TABLE dwh.fact_inventory_snap (
    snap_date_key INT NOT NULL,
    product_sk BIGINT NOT NULL, warehouse_sk INT NOT NULL,
    on_hand INT, reserved INT, reorder_point INT, safety_stock INT
) DUPLICATE KEY(snap_date_key, product_sk, warehouse_sk)
DISTRIBUTED BY HASH(product_sk) BUCKETS 16;

CREATE TABLE dwh.bridge_customer_seg (
    customer_sk BIGINT NOT NULL,
    segment_code VARCHAR(32) NOT NULL,
    weight DECIMAL(9,6) NOT NULL,
    as_of_date_key INT NOT NULL
) DUPLICATE KEY(customer_sk, segment_code, as_of_date_key)
DISTRIBUTED BY HASH(customer_sk) BUCKETS 12;
```

## ClickHouse — `analytics` (telemetry)

```sql
CREATE TABLE analytics.pipeline_events_local ON CLUSTER nexus_ch (
    event_time  DateTime64(3),
    trace_id    String,
    pipeline    LowCardinality(String),
    stage       LowCardinality(String),
    status      LowCardinality(String),
    duration_ms UInt32,
    payload     String
) ENGINE = ReplicatedMergeTree('/ch/tables/{shard}/pipeline_events', '{replica}')
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (pipeline, stage, event_time);

CREATE TABLE analytics.pipeline_events ON CLUSTER nexus_ch AS analytics.pipeline_events_local
ENGINE = Distributed(nexus_ch, analytics, pipeline_events_local, rand());

CREATE MATERIALIZED VIEW analytics.pipeline_latency_by_hour
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(hour) ORDER BY (pipeline, stage, hour)
AS
SELECT
    toStartOfHour(event_time) AS hour,
    pipeline, stage,
    quantilesState(0.5, 0.95, 0.99)(duration_ms) AS p_state,
    countState() AS events_state
FROM analytics.pipeline_events_local
GROUP BY hour, pipeline, stage;

CREATE TABLE analytics.cdc_lag_seconds ON CLUSTER nexus_ch (
    event_time DateTime64(3),
    source LowCardinality(String),
    topic  LowCardinality(String),
    lag_seconds Float64
) ENGINE = ReplicatedMergeTree('/ch/tables/{shard}/cdc_lag', '{replica}')
PARTITION BY toYYYYMMDD(event_time) ORDER BY (source, topic, event_time);

CREATE TABLE analytics.error_events ON CLUSTER nexus_ch (
    event_time DateTime64(3),
    trace_id String,
    service LowCardinality(String),
    error_code LowCardinality(String),
    message String,
    stack String
) ENGINE = ReplicatedMergeTree('/ch/tables/{shard}/error_events', '{replica}')
PARTITION BY toYYYYMMDD(event_time) ORDER BY (service, error_code, event_time);
```
