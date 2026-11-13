-- ============================================================
-- OLIST E-COMMERCE DATASET
-- 04 - POWER BI SUPPORT VIEWS
-- ============================================================
-- Purpose:
-- Create order-level helper views used by Power BI so slicers and
-- relationships can filter the additional analysis dynamically.
-- ============================================================


-- ============================================================
-- 1. DELIVERY REGION ANALYSIS
-- ============================================================
-- Classify each delivered order as either:
--   Same State      = all sellers for the order are in the same state
--                     as the customer.
--   Different State = at least one seller is in a different state.
--
-- The view remains at one row per order so Power BI can relate it to
-- order_view and recalculate late-delivery rates under slicer context.

DROP VIEW IF EXISTS delivery_region_analysis;

CREATE VIEW delivery_region_analysis AS
SELECT
    ov.order_id,
    ov.delivery_status,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE s.seller_state <> c.customer_state
        ) > 0
            THEN 'Different State'
        ELSE 'Same State'
    END AS delivery_region
FROM order_view ov
JOIN customers c
    ON ov.customer_id = c.customer_id
JOIN order_items_view oiv
    ON ov.order_id = oiv.order_id
JOIN sellers s
    ON oiv.seller_id = s.seller_id
WHERE ov.order_status = 'delivered'
  AND ov.delivery_status IS NOT NULL
GROUP BY
    ov.order_id,
    ov.delivery_status;


-- Sanity check:
-- Each order_id should appear once.
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT order_id) AS distinct_order_count
FROM delivery_region_analysis;


-- ============================================================
-- 2. CUSTOMER TYPE SPEND ANALYSIS
-- ============================================================
-- Customer type is based on the number of delivered orders placed by
-- customer_unique_id during the dataset period.
--
-- One-time = exactly one delivered order.
-- Repeat   = more than one delivered order.
--
-- The view remains at one row per delivered order so Power BI can
-- relate it to order_view and calculate average spend dynamically
-- under customer-state and other slicer context.

DROP VIEW IF EXISTS customer_type_spend_analysis;

CREATE VIEW customer_type_spend_analysis AS
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS number_of_orders
    FROM customers c
    JOIN order_view o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    o.order_id,
    c.customer_id,
    c.customer_unique_id,
    co.number_of_orders,
    CASE
        WHEN co.number_of_orders = 1 THEN 'One-time'
        ELSE 'Repeat'
    END AS customer_type
FROM order_view o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN customer_orders co
    ON c.customer_unique_id = co.customer_unique_id
WHERE o.order_status = 'delivered';


-- Sanity check:
-- Each delivered order should appear once.
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT order_id) AS distinct_order_count
FROM customer_type_spend_analysis;
