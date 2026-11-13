-- ============================================================
-- OLIST E-COMMERCE DATASET
-- 03 - BUSINESS ANALYSIS
-- ============================================================
-- Main business question:
-- How is the Olist marketplace performing, what is driving that
-- performance, and where are the main opportunities to improve
-- customer experience and sales?
--
-- Analysis areas:
--   1. Sales performance
--   2. Product / category performance
--   3. Delivery / customer experience
--   4. Seller performance
--
-- NOTE:
-- product_analysis_view is created in 02_data_cleaning.sql because
-- it is an analysis-ready data preparation layer, not a business
-- analysis query itself.
-- ============================================================


-- ============================================================
-- 1. SALES PERFORMANCE
-- ============================================================

-- ------------------------------------------------------------
-- 1.1 Total orders
-- ------------------------------------------------------------
SELECT COUNT(*) AS total_orders
FROM order_view;

-- Result: 99,441


-- ------------------------------------------------------------
-- 1.2 Total product revenue
-- Revenue definition:
-- Sum of item price only. Freight is kept separate.
-- ------------------------------------------------------------
SELECT
    ROUND(SUM(price), 2) AS total_product_revenue
FROM order_items_view;


-- ------------------------------------------------------------
-- 1.3 Overall average order value (product value only)
-- ------------------------------------------------------------
WITH order_value_cte AS (
    SELECT
        order_id,
        SUM(price) AS order_value
    FROM order_items_view
    GROUP BY order_id
)
SELECT
    ROUND(AVG(order_value), 2) AS average_order_value
FROM order_value_cte;

-- Interpretation:
-- This is average product value per order among orders that contain
-- at least one order_item.
-- 775 orders have no matching order_items and therefore do not enter
-- this calculation.
--
-- Previously observed AOV: approximately R$137.75.


-- ------------------------------------------------------------
-- 1.4 Monthly order volume
-- ------------------------------------------------------------
SELECT
    order_month,
    COUNT(*) AS order_count
FROM order_view
GROUP BY order_month
ORDER BY order_month;

-- Data coverage note:
-- 2016 contains very sparse early-period data.
-- September/October 2018 are also sparse/incomplete.
-- These edge periods should not be used for meaningful MoM trend
-- interpretation.


-- ------------------------------------------------------------
-- 1.5 Monthly revenue, order count, AOV and MoM revenue change
-- LAG() is used to compare each month with the previous month.
-- ------------------------------------------------------------
WITH monthly_revenue_cte AS (
    SELECT
        ov.order_month,
        COUNT(DISTINCT oiv.order_id) AS monthly_order_count,
        ROUND(SUM(oiv.price), 2) AS monthly_revenue
    FROM order_items_view oiv
    LEFT JOIN order_view ov
        ON oiv.order_id = ov.order_id
    GROUP BY ov.order_month
),
lagged_revenue_cte AS (
    SELECT
        order_month,
        monthly_order_count,
        monthly_revenue,
        LAG(monthly_revenue) OVER (
            ORDER BY order_month
        ) AS previous_month_revenue
    FROM monthly_revenue_cte
)
SELECT
    order_month,
    monthly_order_count,
    ROUND(
        monthly_revenue / NULLIF(monthly_order_count, 0),
        2
    ) AS monthly_aov,
    monthly_revenue,
    previous_month_revenue,
    ROUND(
        (monthly_revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0)
        * 100,
        2
    ) AS revenue_mom_percentage_change
FROM lagged_revenue_cte
ORDER BY order_month;

-- Key finding:
-- November 2017 revenue increased by approximately 52.1% MoM.
-- AOV did not increase; it was slightly lower than October.
-- This indicates that the November revenue spike was primarily
-- volume-driven rather than caused by larger-value baskets.
--
-- Revenue fell in December 2017, but remained above the September
-- and October 2017 levels.
--
-- Do not interpret January 2017 MoM percentage because its comparison
-- month (December 2016) contains only one order.
-- Exclude sparse 2016 and September/October 2018 edge periods from
-- trend conclusions.


-- ============================================================
-- 2. PRODUCT / CATEGORY PERFORMANCE
-- ============================================================

-- ------------------------------------------------------------
-- 2.1 Revenue by product category
-- ------------------------------------------------------------
SELECT
    pav.product_category_final AS product_category,
    SUM(oiv.price) AS revenue
FROM order_items_view oiv
LEFT JOIN product_analysis_view pav
    ON oiv.product_id = pav.product_id
GROUP BY pav.product_category_final
ORDER BY revenue DESC;

-- Key finding:
-- Highest-revenue categories include:
--   Health & Beauty
--   Watches & Gifts
--   Bed, Bath & Table
--   Sports & Leisure
--   Computers Accessories
--
-- Unknown-category products still generate meaningful revenue, so
-- missing source categories should not be silently removed.


-- ------------------------------------------------------------
-- 2.2 Category revenue contribution and cumulative contribution
-- ------------------------------------------------------------
WITH product_category_revenue_cte AS (
    SELECT
        pav.product_category_final AS product_category,
        SUM(oiv.price) AS revenue
    FROM order_items_view oiv
    LEFT JOIN product_analysis_view pav
        ON oiv.product_id = pav.product_id
    GROUP BY pav.product_category_final
)
SELECT
    product_category,
    RANK() OVER (
        ORDER BY revenue DESC
    ) AS revenue_rank,
    revenue,
    ROUND(
        revenue / SUM(revenue) OVER () * 100,
        2
    ) AS revenue_percentage,
    ROUND(
        SUM(revenue) OVER (
            ORDER BY revenue DESC
        )
        / SUM(revenue) OVER ()
        * 100,
        2
    ) AS cumulative_revenue_percentage
FROM product_category_revenue_cte
ORDER BY revenue DESC;

-- Key findings:
-- Top 5 categories contribute approximately 39.7% of product revenue.
-- Top 10 contribute approximately 62.4%.
-- The cumulative total reaches roughly 80% at rank 18 (Pet Shop).
--
-- Interpretation:
-- Revenue is concentrated in the leading categories, but there is
-- still a meaningful long tail rather than dependence on only one or
-- two categories.


-- ------------------------------------------------------------
-- 2.3 Category revenue, item volume and average item price
-- ------------------------------------------------------------
SELECT
    pav.product_category_final AS product_category,
    SUM(oiv.price) AS category_revenue,
    COUNT(*) AS items_sold,
    ROUND(AVG(oiv.price), 2) AS average_item_price
FROM order_items_view oiv
LEFT JOIN product_analysis_view pav
    ON oiv.product_id = pav.product_id
GROUP BY pav.product_category_final
ORDER BY category_revenue DESC;

-- Interpretation:
-- High revenue can be driven by:
--   - high item volume,
--   - higher average item prices,
--   - or both.
--
-- Examples:
-- Computers = high-value / low-volume.
-- Bed, Bath & Table = very high-volume / lower average item price.
-- Watches & Gifts = strong revenue with relatively high item price.
-- Health & Beauty performs strongly through both scale and item value.


-- ------------------------------------------------------------
-- 2.4 Compare category revenue rank vs volume rank vs price rank
-- ------------------------------------------------------------
WITH product_revenue_ranking_cte AS (
    SELECT
        pav.product_category_final AS product_category,

        RANK() OVER (
            ORDER BY SUM(oiv.price) DESC
        ) AS revenue_rank,
        SUM(oiv.price) AS revenue,

        RANK() OVER (
            ORDER BY COUNT(*) DESC
        ) AS items_sold_rank,
        COUNT(*) AS items_sold,

        RANK() OVER (
            ORDER BY AVG(oiv.price) DESC
        ) AS average_price_rank,
        ROUND(AVG(oiv.price), 2) AS average_item_price

    FROM order_items_view oiv
    LEFT JOIN product_analysis_view pav
        ON oiv.product_id = pav.product_id
    GROUP BY pav.product_category_final
)
SELECT
    *,
    items_sold_rank - revenue_rank AS volume_vs_revenue_rank_gap
FROM product_revenue_ranking_cte
ORDER BY revenue_rank;

-- Interpretation of volume_vs_revenue_rank_gap:
-- Positive = revenue rank is stronger than item-volume rank;
--            often associated with higher-value items.
-- Negative = item-volume rank is stronger than revenue rank;
--            often associated with lower-value items.
-- Near zero = revenue and volume rankings are broadly aligned.
--
-- Strong positive examples:
-- Computers (+30), Small Home Appliances/Oven/Coffee (+20),
-- Home Appliances 2 (+16).
--
-- Strong negative examples:
-- Drinks (-15), Food & Drink (-14), Food (-13).
--
-- Rank gaps are useful for pattern detection, but small niche
-- categories can show large rank differences. Actual revenue,
-- volume and average price should therefore be considered alongside
-- the ranks.


-- ============================================================
-- 3. DELIVERY / CUSTOMER EXPERIENCE
-- ============================================================

-- ------------------------------------------------------------
-- 3.1 Overall late vs on-time delivery rate
-- ------------------------------------------------------------
SELECT
    delivery_status,
    COUNT(*) AS order_count,
    ROUND(
        COUNT(*)::numeric
        / SUM(COUNT(*)) OVER ()
        * 100,
        2
    ) AS percentage
FROM order_view
WHERE order_status = 'delivered'
  AND delivery_status IS NOT NULL
GROUP BY delivery_status;

-- Result:
-- Late    = 6,534 orders = 6.77%
-- On Time = 89,936 orders = 93.23%
--
-- Finding:
-- Most delivered orders arrived on time, with an overall late-delivery
-- rate of 6.77%.


-- ------------------------------------------------------------
-- 3.2 Monthly late-delivery rate
-- ------------------------------------------------------------
WITH late_cte AS (
    SELECT
        order_month,
        COUNT(*) AS delivered_orders,
        SUM(
            CASE
                WHEN delivery_status = 'Late' THEN 1
                ELSE 0
            END
        ) AS late_orders
    FROM order_view
    WHERE order_status = 'delivered'
      AND delivery_status IS NOT NULL
    GROUP BY order_month
)
SELECT
    order_month,
    delivered_orders,
    late_orders,
    ROUND(
        late_orders::numeric
        / NULLIF(delivered_orders, 0)
        * 100,
        2
    ) AS late_percentage
FROM late_cte
ORDER BY order_month;

-- Key findings:
-- Late-delivery performance deteriorated sharply in specific periods:
--   Nov 2017 = 12.40%
--   Dec 2017 = 7.46%
--   Feb 2018 = ~14.1%
--   Mar 2018 = 18.96% (worst meaningful month)
--
-- Performance then recovered substantially:
--   Apr 2018 = 4.50%
--   Jun 2018 = 1.16%
--
-- Sparse 2016 months should not be interpreted as meaningful trends.


-- ------------------------------------------------------------
-- 3.3 Monthly order volume vs late-delivery rate
-- ------------------------------------------------------------
WITH monthly_delivery_cte AS (
    SELECT
        order_month,
        COUNT(*) AS order_count,

        SUM(
            CASE
                WHEN order_status = 'delivered'
                 AND delivery_status IS NOT NULL
                    THEN 1
                ELSE 0
            END
        ) AS delivered_orders,

        SUM(
            CASE
                WHEN delivery_status = 'Late'
                    THEN 1
                ELSE 0
            END
        ) AS late_orders

    FROM order_view
    GROUP BY order_month
)
SELECT
    order_month,
    order_count,
    delivered_orders,
    late_orders,
    ROUND(
        late_orders::numeric
        / NULLIF(delivered_orders, 0)
        * 100,
        2
    ) AS late_percentage
FROM monthly_delivery_cte
ORDER BY order_month;

-- Interpretation:
-- November 2017 combined very high order volume with a 12.4% late rate.
-- However, similarly high-volume months often had much lower late rates.
--
-- Example:
--   Jan 2018: 7,269 orders, ~5.7% late
--   Mar 2018: 7,211 orders, 18.96% late
--   Apr 2018: 6,939 orders, 4.50% late
--
-- Conclusion:
-- High order volume may have contributed to lateness in some periods,
-- but volume alone does not explain the delivery disruption.


-- ============================================================
-- 4. SELLER PERFORMANCE
-- ============================================================

-- ------------------------------------------------------------
-- 4.1 Seller revenue, item volume and average item price
-- ------------------------------------------------------------
SELECT
    seller_id,
    SUM(price) AS total_sales,
    COUNT(*) AS items_sold,
    ROUND(AVG(price), 2) AS average_item_price
FROM order_items_view
GROUP BY seller_id
ORDER BY total_sales DESC;

-- Interpretation:
-- Leading sellers show different business models:
--
-- seller 53243585a1d6dc2643021fd1853d8905
--   R$222,776.05 revenue
--   410 items
--   ~R$543.36 average item price
--   => high-value / lower-volume seller
--
-- seller 6560211a19b47992c3666cc44a7e94c0
--   R$123,304.83 revenue
--   2,033 items
--   ~R$60.65 average item price
--   => high-volume / lower-value seller
--
-- seller 4869f7a5dfa277a7dca6462dcf3b52b2
--   highest observed seller revenue
--   1,156 items
--   ~R$198.51 average item price
--   => strong combination of scale and item value.


-- ------------------------------------------------------------
-- NEXT SELLER ANALYSIS STEP
-- ------------------------------------------------------------
-- Question:
-- Which high-revenue sellers also have high late-delivery rates?
--
-- Planned metrics:
--   seller_id
--   seller_revenue
--   distinct delivered orders
--   distinct late orders
--   late_delivery_percentage
--
-- IMPORTANT:
-- Use DISTINCT order_id for seller delivery metrics because a seller
-- can have multiple item rows within the same order.
--
-- This query had not yet been completed at the point this file was
-- reconstructed, so it is intentionally left as the next analysis task.


-- ============================================================
-- 5. CURRENT ANALYSIS SUMMARY
-- ============================================================
-- SALES:
-- Marketplace sales grew strongly through 2017 into 2018.
-- November 2017 was an exceptional revenue month, driven mainly by
-- order volume rather than higher AOV.
--
-- PRODUCT / CATEGORY:
-- Revenue concentration is meaningful but not extreme:
-- approximately 80% of product revenue comes from the top 18 categories.
-- Categories reach high revenue through different combinations of
-- volume and average item price.
--
-- DELIVERY:
-- Overall late-delivery rate is 6.77%, but lateness was concentrated
-- in specific periods, especially late 2017 / early 2018.
-- High monthly order volume alone does not explain the pattern.
--
-- SELLERS:
-- Top sellers also differ substantially in volume and average item value.
-- The next step is to connect seller commercial importance with
-- seller-level late-delivery performance.

WITH sellers_cte AS(
	SELECT 
		seller_id,
		SUM(price) AS total_sales,
		COUNT(DISTINCT oiv.order_id) AS delivered_orders,
		COUNT(DISTINCT CASE
			WHEN delivery_status = 'Late' THEN oiv.order_id 
			END
			) AS late_orders
	FROM order_items_view oiv 
	LEFT JOIN order_view ov 
	ON oiv.order_id = ov.order_id
	WHERE order_status = 'delivered'
	AND delivery_status IS NOT NULL 
	GROUP BY seller_id
	HAVING COUNT(DISTINCT oiv.order_id) > 50
)
SELECT 
	seller_id,
	total_sales,
	delivered_orders,
	late_orders,
	ROUND(late_orders::numeric / NULLIF(delivered_orders,0) * 100,2) AS late_percentage
FROM sellers_cte
ORDER BY late_percentage DESC
-- Seller delivery performance was reviewed only for sellers with
-- at least 50 delivered orders to avoid misleading rates from very
-- small samples.

-- Several commercially important sellers have late-delivery rates
-- above the marketplace average of 6.77%.

-- The highest-revenue seller generated approximately R$227k in sales
-- and had a 10.50% late-delivery rate across 1,124 delivered orders.

-- Other notable sellers combine meaningful revenue/order volume with
-- late-delivery rates above 10%, suggesting fulfilment issues are
-- concentrated among some important sellers rather than only small sellers.

-- Seller performance should therefore be assessed using both commercial
-- importance (revenue/order volume) and delivery performance, rather than
-- late-delivery percentage alone.

WITH order_items_cte AS(
	SELECT 
		seller_id,
		SUM(price) AS total_sales
	FROM order_items_view
	GROUP BY seller_id
)
SELECT 
	seller_id,
	total_sales,
	sum(total_sales) OVER() AS marketplace_sales,
	ROUND(sum(total_sales) OVER(ORDER BY total_sales DESC)/ 
		  sum(total_sales) over()
		  * 100
		  ,2
		  ) AS cumulative_percentage
FROM order_items_cte
ORDER BY total_sales DESC

-- Around 18% of sellers generate 80% of total product revenue, 
-- showing that marketplace sales are concentrated among a relatively small share of sellers.






--Payments

-- Number ofpayments by payment type
SELECT 
	payment_type, 
	COUNT(*) AS payment_count
FROM payments_view pv 
GROUP BY payment_type
ORDER BY count(*) DESC 

-- 76,795 credit card, 19,784 boleto, 5775 voucher, 1529 debit card, 3 not defined

-- -- Distinct orders by payment type
SELECT payment_type, COUNT(DISTINCT order_id) FROM payments_view
GROUP BY payment_type 
ORDER BY count(DISTINCT order_id) DESC 

--99,440 orders
-- 76,505 credit car, 19,784 boleto, 3886 voucher, 1528 credit card, 3 not defined

-- Total and average value by payment type
SELECT 
	payment_type, 
	SUM(payment_value) AS total_payment_value, 
	ROUND(AVG(payment_value),2) AS average_payment_value
FROM payments_view
GROUP BY payment_type
ORDER BY SUM(payment_value) DESC

-- Credit cards are the dominant payment method by both usage and payment value.
-- Credit card payments also have the highest average payment value among
-- meaningful payment types.

-- Voucher payments have a much lower average value and appear more frequently
-- as multiple payment records per order, suggesting they are often used as
-- partial payments rather than as the sole payment method.


SELECT 
	payment_installments, 
	COUNT(*) AS payment_count,
	ROUND(AVG(payment_value),2) AS average_payment_value 
FROM payments_view
WHERE payment_installments != 0
AND payment_type = 'credit_card'
GROUP BY payment_installments
ORDER BY payment_installments DESC 

-- Credit-card payment value generally increases as the number of
-- installments increases.

-- One-installment credit-card payments average about R$96, compared
-- with about R$415 for 10-installment payments.

-- Installment groups above 10 contain relatively few transactions,
-- so their average values should not be treated as representative.

-- This suggests customers are more likely to spread higher-value
-- purchases across multiple installments.



----Reviews


SELECT 
	ROUND(AVG(review_score),2) AS average_review,
	COUNT(order_id) AS review_count,
	COUNT(DISTINCT order_id) AS distinct_review_count
FROM reviews
-- Average rating is 4.09
--99,224 reviews from 98,673 distinct orders

-- Count and percentage for each rating
SELECT 
	review_score, 
	COUNT(*) AS review_count, 
	ROUND(COUNT(*)/ SUM(COUNT(*)) OVER() * 100, 2) AS review_percentage
FROM reviews
GROUP BY review_score
ORDER BY count(*) DESC




-- Average review for late orders
SELECT 
	ROUND(AVG(review_score),2) AS average_late_review 
FROM reviews r 
LEFT JOIN order_view ov
ON r.order_id = ov.order_id
WHERE delivery_status = 'Late'
-- 2.27 average review when delivery is late

-- Count and percentage for each rating when late
SELECT 
	review_score,
	COUNT(*) AS late_review_count,
	ROUND(COUNT(*)/ SUM(COUNT(*)) OVER() * 100,2) AS late_percentage
FROM reviews r 
LEFT JOIN order_view ov
ON r.order_id = ov.order_id
WHERE delivery_status = 'Late'
GROUP BY review_score
ORDER BY count(*) DESC

-- Average review for late orders
SELECT 
	ROUND(AVG(review_score),2) AS average_ontime_review 
FROM reviews r 
LEFT JOIN order_view ov
ON r.order_id = ov.order_id
WHERE delivery_status = 'On Time'
-- 4.29 average review when delivery is On Time

-- Count and percentage for each rating when on time
SELECT 
	review_score,
	COUNT(*) AS ontime_review_count,
	ROUND(COUNT(*)/ SUM(COUNT(*)) OVER() * 100,2) AS ontime_percentage
FROM reviews r 
LEFT JOIN order_view ov
ON r.order_id = ov.order_id
WHERE delivery_status = 'On Time'
GROUP BY review_score
ORDER BY count(*) DESC

-- Delivery performance is strongly associated with customer satisfaction.

-- Late deliveries have an average review score of 2.27, compared
-- with 4.29 for on-time deliveries.

-- 53.73% of late deliveries receive a 1-star review, compared with
-- only 6.63% of on-time deliveries.

-- Conversely, 62.26% of on-time deliveries receive 5 stars, compared
-- with only 16.54% of late deliveries.

-- This suggests delivery reliability is a major driver of customer
-- experience and should be a key operational focus.



--Customers

SELECT 
	COUNT(customer_id)AS customer_id_count, 
	COUNT(DISTINCT(customer_unique_id)) AS customer_unique_id_count
FROM customers
--99,441 customer_ids, 96,096 distinct customer_unique_ids

WITH unique_id_cte AS(
	SELECT 
		customer_unique_id, 
		COUNT(*) AS number_of_orders 
	FROM customers
	GROUP BY customer_unique_id
)
SELECT 
	number_of_orders, 
	COUNT(number_of_orders) 
FROM unique_id_cte
GROUP BY number_of_orders
ORDER BY number_of_orders

--99,441 total customer/order records
--96,096 unique customers
-- 3,345 purchases beyond each customer's first purchase


-- Customer purchasing is overwhelmingly one-time.
-- Of 96,096 unique customers, 93,099 (about 96.9%) purchased only once,
-- while only 2,997 (about 3.1%) made more than one purchase.

-- Repeat purchasing therefore appears very limited in the dataset,
-- suggesting customer retention/repeat purchase is a potential
-- opportunity for marketplace growth.