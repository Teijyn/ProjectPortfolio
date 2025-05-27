-- Tesla Manufacturing SQL Query Repository
-- Description: This repository includes a progression of SQL queries from beginner to advanced levels
-- designed to support production and manufacturing data analysis for a Tesla-like environment.

-- TABLE ASSUMPTIONS:
-- production_data (id, model, production_date, shift, quantity_produced, defect_count)
-- tooling_logs (id, tool_id, timestamp, status, error_code)
-- employees (id, name, shift, role, department)
-- downtime_logs (id, line_id, start_time, end_time, reason)
-- inventory (part_id, part_name, quantity_available, reorder_level, last_updated)
-- inventory_transactions (id, part_id, transaction_type [IN/OUT], quantity, timestamp)

-- ============================
-- BEGINNER LEVEL QUERIES
-- ============================

-- 1. Retrieve total quantity produced per model
SELECT model, SUM(quantity_produced) AS total_units
FROM production_data
GROUP BY model;

-- 2. Get the number of defects per shift
SELECT shift, SUM(defect_count) AS total_defects
FROM production_data
GROUP BY shift;

-- 3. List all tools that logged an error today
SELECT tool_id, error_code, timestamp
FROM tooling_logs
WHERE DATE(timestamp) = CURDATE() AND error_code IS NOT NULL;

-- 4. Check inventory for parts below reorder level
SELECT part_id, part_name, quantity_available
FROM inventory
WHERE quantity_available < reorder_level;

-- 5. Count employees per department
SELECT department, COUNT(*) AS employee_count
FROM employees
GROUP BY department;

-- ============================
-- INTERMEDIATE LEVEL QUERIES
-- ============================

-- 6. Calculate average daily production by model
SELECT model, AVG(daily_quantity) AS avg_daily_production
FROM (
    SELECT model, production_date, SUM(quantity_produced) AS daily_quantity
    FROM production_data
    GROUP BY model, production_date
) AS sub
GROUP BY model;

-- 7. Get top 5 days with the most defects
SELECT production_date, SUM(defect_count) AS total_defects
FROM production_data
GROUP BY production_date
ORDER BY total_defects DESC
LIMIT 5;

-- 8. Identify tools with repeated errors in the last 7 days
SELECT tool_id, COUNT(*) AS error_count
FROM tooling_logs
WHERE timestamp >= CURDATE() - INTERVAL 7 DAY AND error_code IS NOT NULL
GROUP BY tool_id
HAVING error_count > 3;

-- 9. Total downtime hours per line
SELECT line_id, 
       SUM(TIMESTAMPDIFF(MINUTE, start_time, end_time)) / 60 AS total_downtime_hours
FROM downtime_logs
GROUP BY line_id;

-- 10. List employees who worked night shifts on production lines
SELECT DISTINCT e.name, e.role, e.shift
FROM employees e
JOIN production_data p ON e.shift = p.shift
WHERE e.shift = 'Night';

-- 11. LEFT JOIN example: List all parts and their latest quantity, even if not used in recent transactions
SELECT i.part_id, i.part_name, i.quantity_available, t.quantity, t.timestamp
FROM inventory i
LEFT JOIN inventory_transactions t ON i.part_id = t.part_id
ORDER BY t.timestamp DESC;

-- 12. RIGHT JOIN example: Show all transactions including parts that are no longer in inventory
SELECT t.part_id, i.part_name, t.transaction_type, t.quantity
FROM inventory_transactions t
RIGHT JOIN inventory i ON t.part_id = i.part_id;

-- 13. INNER JOIN example: Match only tools that had errors and are currently logged in tooling_logs
SELECT t.tool_id, t.status, t.error_code
FROM tooling_logs t
INNER JOIN (
    SELECT DISTINCT tool_id FROM tooling_logs WHERE error_code IS NOT NULL
) e ON t.tool_id = e.tool_id;

-- 14. Subquery: List employees who work in departments with more than 5 people
SELECT name, role, department
FROM employees
WHERE department IN (
    SELECT department FROM employees GROUP BY department HAVING COUNT(*) > 5
);

-- ============================
-- ADVANCED LEVEL QUERIES
-- ============================

-- 15. Defect rate per model (defects per 1000 units)
SELECT model,
       SUM(defect_count) / SUM(quantity_produced) * 1000 AS defect_rate_per_1000
FROM production_data
GROUP BY model;

-- 16. Identify peak production hour across shifts (assuming timestamp granularity)
SELECT HOUR(production_date) AS hour_block, SUM(quantity_produced) AS total_output
FROM production_data
GROUP BY hour_block
ORDER BY total_output DESC
LIMIT 1;

-- 17. Rolling 7-day average of daily production
SELECT production_date, model,
       AVG(SUM(quantity_produced)) OVER (PARTITION BY model ORDER BY production_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_avg
FROM production_data
GROUP BY production_date, model;

-- 18. Find longest continuous downtime per line
SELECT line_id, MAX(TIMESTAMPDIFF(MINUTE, start_time, end_time)) AS max_downtime_minutes
FROM downtime_logs
GROUP BY line_id;

-- 19. Inventory turnover indicator (quantity used vs. quantity restocked)
SELECT part_id,
       SUM(CASE WHEN transaction_type = 'OUT' THEN quantity ELSE 0 END) AS total_used,
       SUM(CASE WHEN transaction_type = 'IN' THEN quantity ELSE 0 END) AS total_restocked,
       SUM(CASE WHEN transaction_type = 'OUT' THEN quantity ELSE 0 END) / NULLIF(SUM(CASE WHEN transaction_type = 'IN' THEN quantity ELSE 0 END), 0) AS turnover_ratio
FROM inventory_transactions
GROUP BY part_id;

-- 20. Analyze cross-department performance during high-output production weeks
SELECT pd.model, pd.production_date, e.name AS employee_name, e.department, t.tool_id, t.status, 
       d.line_id, d.reason AS downtime_reason, i.part_name, it.transaction_type, it.quantity
FROM production_data pd
JOIN employees e ON pd.shift = e.shift
JOIN tooling_logs t ON DATE(pd.production_date) = DATE(t.timestamp)
JOIN downtime_logs d ON DATE(pd.production_date) = DATE(d.start_time)
JOIN inventory_transactions it ON DATE(pd.production_date) = DATE(it.timestamp)
JOIN inventory i ON it.part_id = i.part_id
JOIN (
    SELECT tool_id FROM tooling_logs 
    WHERE error_code IS NOT NULL
    GROUP BY tool_id HAVING COUNT(*) > 2
) frequent_errors ON t.tool_id = frequent_errors.tool_id
JOIN (
    SELECT shift, COUNT(*) AS shift_count FROM employees GROUP BY shift
) shift_summary ON pd.shift = shift_summary.shift
JOIN (
    SELECT model, AVG(quantity_produced) AS avg_output FROM production_data GROUP BY model
) avg_prod ON pd.model = avg_prod.model
WHERE pd.quantity_produced > avg_prod.avg_output
  AND pd.production_date >= CURDATE() - INTERVAL 30 DAY;
