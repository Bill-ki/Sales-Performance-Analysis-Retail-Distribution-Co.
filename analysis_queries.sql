
THIS IS WHERE I MANUALLY SAVE THE CODES I USED
1. SALES ANALYSIS

1 Headline KPIs: orders, revenue, AOV, units, cancellation & return rate
SELECT
    COUNT(*)                                                         AS total_orders,
    COUNT(*) FILTER (WHERE status = 'Cancelled')                     AS cancelled_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'Cancelled') / COUNT(*), 1) AS cancellation_rate_pct,
    COUNT(*) FILTER (WHERE status = 'Returned')                      AS returned_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'Returned') / COUNT(*), 1)  AS return_rate_pct
FROM orders;

2 Revenue, cost, profit, margin, AOV (join orders -> order_items -> products)
SELECT
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2)                    AS gross_revenue,
    ROUND(SUM(oi.quantity * p.unit_cost), 2)                                          AS total_cogs,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) - SUM(oi.quantity * p.unit_cost), 2) AS gross_profit,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount))
          / NULLIF(COUNT(DISTINCT o.order_id), 0), 2)                                 AS avg_order_value
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p      ON p.product_id = oi.product_id
WHERE o.status <> 'Cancelled';

3 Monthly revenue trend with month-over-month growth (window function)
WITH monthly AS (
    SELECT DATE_TRUNC('month', o.order_date)::date                       AS month,
           SUM(oi.quantity * oi.unit_price * (1 - oi.discount))          AS revenue,
           COUNT(DISTINCT o.order_id)                                    AS orders
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status <> 'Cancelled'
    GROUP BY 1
)
SELECT month, revenue, orders,
       ROUND(revenue - LAG(revenue) OVER (ORDER BY month), 2)                     AS mom_change,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 1)                  AS mom_growth_pct
FROM monthly
ORDER BY month;

-- 1.4 Revenue by product category
SELECT c.category_name,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2) AS revenue,
       SUM(oi.quantity)                                               AS units_sold,
       COUNT(DISTINCT p.product_id)                                   AS sku_count
FROM order_items oi
JOIN products p    ON p.product_id = oi.product_id
JOIN categories c  ON c.category_id = p.category_id
JOIN orders o      ON o.order_id = oi.order_id
WHERE o.status <> 'Cancelled'
GROUP BY c.category_name
ORDER BY revenue DESC;

5 Revenue by ship region and by customer segment (grouping sets in one pass)
SELECT
    COALESCE(o.ship_region, 'ALL REGIONS')   AS ship_region,
    COALESCE(cu.segment, 'ALL SEGMENTS')     AS segment,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN customers cu   ON cu.customer_id = o.customer_id
WHERE o.status <> 'Cancelled'
GROUP BY GROUPING SETS ((o.ship_region), (cu.segment), ())
ORDER BY revenue DESC;

6 Top 10 products by revenue, with rank and running % of total revenue
WITH prod_rev AS (
    SELECT p.product_id, p.product_name, c.category_name,
           SUM(oi.quantity * oi.unit_price * (1 - oi.discount)) AS revenue,
           SUM(oi.quantity)                                     AS units_sold
    FROM order_items oi
    JOIN products p   ON p.product_id = oi.product_id
    JOIN categories c ON c.category_id = p.category_id
    JOIN orders o     ON o.order_id = oi.order_id
    WHERE o.status <> 'Cancelled'
    GROUP BY p.product_id, p.product_name, c.category_name
)
SELECT *,
       RANK() OVER (ORDER BY revenue DESC)                                            AS revenue_rank,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 1) AS running_pct_of_total
FROM prod_rev
ORDER BY revenue DESC
LIMIT 10;

7 Top 10 customers by revenue with order count and average order value
SELECT cu.company_name, cu.segment, cu.country,
       COUNT(DISTINCT o.order_id)                                     AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2) AS revenue,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount))
             / COUNT(DISTINCT o.order_id), 2)                         AS avg_order_value
FROM customers cu
JOIN orders o        ON o.customer_id = cu.customer_id
JOIN order_items oi  ON oi.order_id = o.order_id
WHERE o.status <> 'Cancelled'
GROUP BY cu.customer_id, cu.company_name, cu.segment, cu.country
ORDER BY revenue DESC
LIMIT 10;

8 Sales rep performance (only employees who own orders)
SELECT e.first_name || ' ' || e.last_name AS sales_rep,
       e.region,
       COUNT(DISTINCT o.order_id)                                     AS orders_handled,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2) AS revenue_generated,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount))
             / COUNT(DISTINCT o.order_id), 2)                         AS avg_order_value
FROM employees e
JOIN orders o        ON o.employee_id = e.employee_id
JOIN order_items oi  ON oi.order_id = o.order_id
WHERE o.status <> 'Cancelled'
GROUP BY e.employee_id, e.first_name, e.last_name, e.region
ORDER BY revenue_generated DESC;

9 Discounting behaviour: how much margin is given away, by category
SELECT c.category_name,
       ROUND(AVG(oi.discount) * 100, 1)                                       AS avg_discount_pct,
       ROUND(SUM(oi.quantity * oi.unit_price * oi.discount), 2)               AS discount_dollars_given,
       COUNT(*) FILTER (WHERE oi.discount > 0)                                AS discounted_line_items,
       COUNT(*)                                                               AS total_line_items
FROM order_items oi
JOIN products p   ON p.product_id = oi.product_id
JOIN categories c ON c.category_id = p.category_id
GROUP BY c.category_name
ORDER BY discount_dollars_given DESC;

10 Order fulfillment speed (order_date -> ship_date) by status
SELECT status,
       COUNT(*)                                                     AS orders,
       ROUND(AVG(ship_date - order_date), 1)                        AS avg_days_to_ship,
       MIN(ship_date - order_date)                                  AS min_days,
       MAX(ship_date - order_date)                                  AS max_days
FROM orders
WHERE ship_date IS NOT NULL
GROUP BY status
ORDER BY avg_days_to_ship DESC;

-- 1.11 New vs. repeat customer revenue split, by customer's first order month
WITH first_order AS (
    SELECT customer_id, MIN(order_date) AS first_order_date
    FROM orders
    WHERE status <> 'Cancelled'
    GROUP BY customer_id
)
SELECT
    CASE WHEN o.order_date = fo.first_order_date THEN 'New Customer Order' ELSE 'Repeat Customer Order' END AS order_type,
    COUNT(*)                                                          AS orders,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount)), 2)    AS revenue
FROM orders o
JOIN first_order fo ON fo.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status <> 'Cancelled'
GROUP BY 1
ORDER BY revenue DESC;


