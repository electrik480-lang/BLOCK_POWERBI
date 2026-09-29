-- 1.расчет общей суммы продаж, количества проданных единиц товара и среднего чека по базе транзакций

SELECT 
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(quantity) AS total_quantity_sold,
    SUM(sale_amount) AS total_sales_amount,
    AVG(sale_amount) AS average_order_value
FROM public_sales;

-- 1.2.анализ продаж по месяцам

SELECT 
    DATE_FORMAT(sale_date, '%Y-%m') AS sales_month,
    SUM(sale_amount) AS monthly_sales,
    SUM(quantity) AS monthly_quantity
FROM public_sales
GROUP BY DATE_FORMAT(sale_date, '%Y-%m')
ORDER BY sales_month;

-- 1.3.Расчет доходов

SELECT 
    region,
    SUM(total_income) AS total_regional_income,
    COUNT(income_id) AS income_records_count
FROM public_incomes
GROUP BY region
ORDER BY total_regional_income DESC;

-- 1.4.Расчет расходов

SELECT 
    shipping_method,
    region,
    SUM(base_tariff) AS total_base_costs,
    SUM(additional_costs) AS total_additional_costs,
    SUM(base_tariff + additional_costs) AS total_shipping_expenses
FROM tariffs_and_shipping
GROUP BY shipping_method, region
ORDER BY total_shipping_expenses DESC;

-- 1.5.Итоговый финансовый результат, сравнение общего дохода (public_incomes) и общих расходов на доставку

SELECT 
    (SELECT SUM(total_income) FROM public_incomes) AS total_income,
    (SELECT SUM(base_tariff + additional_costs) FROM tariffs_and_shipping) AS total_expenses,
    (
        (SELECT SUM(total_income) FROM public_incomes) - 
        (SELECT SUM(base_tariff + additional_costs) FROM tariffs_and_shipping)
    ) AS net_profit;
    
    -- 2.Оценка эффективности работы складов, для оценки работы складов учитываем объем выручки и остатки товаров
    
    SELECT 
    w.warehouse_id,
    w.warehouse_name,
    w.location_city,
    w.location_region,
    COUNT(r.revenue_id) AS total_transactions,
    SUM(r.revenue_amount) AS total_revenue,
    ROUND(AVG(r.revenue_amount), 2) AS avg_revenue_per_transaction
FROM public_wb w
LEFT JOIN public_revenue_wb r ON w.warehouse_id = r.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name, w.location_city, w.location_region
ORDER BY total_revenue DESC;

-- 2.1.Оценивает суммарный объем товаров и количество SKU на каждом складе по таблице 

SELECT 
    w.warehouse_id,
    w.warehouse_name,
    COUNT(DISTINCT s.item_id) AS total_unique_items,
    SUM(s.quantity_in_stock) AS total_units_in_stock,
    MAX(s.last_update) AS last_stock_update
FROM public_wb w
LEFT JOIN public_stocks s ON w.warehouse_id = s.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name
ORDER BY total_units_in_stock DESC;

-- 2.2.Стоимость запасов на каждом складе, связываем остатки с ценами товаров из public_items

SELECT 
    w.warehouse_id,
    w.warehouse_name,
    SUM(s.quantity_in_stock) AS total_items,
    ROUND(SUM(s.quantity_in_stock * i.price), 2) AS total_stock_value
FROM Student.public_wb w
JOIN Student.public_stocks s ON w.warehouse_id = s.warehouse_id
JOIN Student.public_items i ON s.item_id = i.item_id
GROUP BY w.warehouse_id, w.warehouse_name
ORDER BY total_stock_value DESC;

-- 2.3.Оценка эффективности и затрат на сотрудников

SELECT 
    w.warehouse_id,
    w.warehouse_name,
    COUNT(st.staff_id) AS total_employees,
    ROUND(SUM(st.salary), 2) AS total_payroll_cost,
    ROUND(AVG(st.salary), 2) AS avg_salary
FROM public_wb w
LEFT JOIN public_staff st ON w.warehouse_id = st.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name
ORDER BY total_payroll_cost DESC;

-- 2.4.Анализ штата по должностям и средним окладам

SELECT 
    position,
    COUNT(staff_id) AS employee_count,
    ROUND(MIN(salary), 2) AS min_salary,
    ROUND(MAX(salary), 2) AS max_salary,
    ROUND(AVG(salary), 2) AS avg_salary,
    ROUND(SUM(salary), 2) AS total_cost
FROM public_staff
GROUP BY position
ORDER BY total_cost DESC;

-- 2.5.Сравниваем выручку склада с затратами на содержание его персонала

SELECT 
    w.warehouse_id,
    w.warehouse_name,
    COALESCE(rev.total_revenue, 0) AS total_revenue,
    COALESCE(staff.total_payroll, 0) AS total_payroll,
    COALESCE(rev.total_revenue, 0) - COALESCE(staff.total_payroll, 0) AS net_operating_margin,
    ROUND(
        COALESCE(rev.total_revenue, 0) / NULLIF(COALESCE(staff.total_payroll, 0), 0), 2
    ) AS revenue_per_payroll_ratio
FROM public_wb w
LEFT JOIN (
    SELECT warehouse_id, SUM(revenue_amount) AS total_revenue 
    FROM public_revenue_wb 
    GROUP BY warehouse_id
) rev ON w.warehouse_id = rev.warehouse_id
LEFT JOIN (
    SELECT warehouse_id, SUM(salary) AS total_payroll 
    FROM public_staff 
    GROUP BY warehouse_id
) staff ON w.warehouse_id = staff.warehouse_id
ORDER BY revenue_per_payroll_ratio DESC;

-- 3.Разобраться, в каких городах и регионах снижаются продажи и почему
  -- Для анализа снижения продаж по городам и регионам необходимо объединить данные о продажах, заказах, клиентах, статусах заказов и товарах
  
  WITH monthly_regional_sales AS (
    SELECT 
        c.region,
        c.city,
        DATE_FORMAT(o.order_date, '%Y-%m') AS sales_month,
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(o.total_amount) AS total_revenue
    FROM public_orders o
    JOIN public_clients c ON o.client_id = c.client_id
    GROUP BY c.region, c.city, DATE_FORMAT(o.order_date, '%Y-%m')
),
sales_with_lag AS (
    SELECT 
        region,
        city,
        sales_month,
        total_revenue,
        LAG(total_revenue) OVER (PARTITION BY region, city ORDER BY sales_month) AS prev_month_revenue
    FROM monthly_regional_sales
)
SELECT 
    region,
    city,
    sales_month,
    total_revenue,
    prev_month_revenue,
    ROUND(total_revenue - prev_month_revenue, 2) AS absolute_change,
    ROUND(((total_revenue - prev_month_revenue) / NULLIF(prev_month_revenue, 0)) * 100, 2) AS percentage_change
FROM sales_with_lag
WHERE prev_month_revenue IS NOT NULL
ORDER BY percentage_change ASC; -- На первых строчках будут города с наибольшим падением

-- 3.1.Анализ причин снижения продаж
-- Причина №1: Высокий процент отмен и возвратов
SELECT 
    c.region,
    c.city,
    COUNT(o.order_id) AS total_orders,
    SUM(CASE WHEN os.status_name = 'Canceled' THEN 1 ELSE 0 END) AS canceled_orders,
    SUM(CASE WHEN os.status_name = 'Returned' THEN 1 ELSE 0 END) AS returned_orders,
    ROUND(
        (SUM(CASE WHEN os.status_name IN ('Canceled', 'Returned') THEN 1 ELSE 0 END) * 100.0) / COUNT(o.order_id), 
        2
    ) AS cancel_return_rate_pct
FROM public_orders o
JOIN public_clients c ON o.client_id = c.client_id
JOIN public_order_status os ON o.order_status_id = os.status_id
GROUP BY c.region, c.city
HAVING total_orders >= 5
ORDER BY cancel_return_rate_pct DESC;

-- Причина №2: Сокращение клиентской базы

SELECT 
    c.region,
    c.city,
    DATE_FORMAT(o.order_date, '%Y-%m') AS sales_month,
    COUNT(DISTINCT o.client_id) AS active_clients,
    ROUND(SUM(o.total_amount) / COUNT(DISTINCT o.client_id), 2) AS revenue_per_client
FROM public_orders o
JOIN public_clients c ON o.client_id = c.client_id
GROUP BY c.region, c.city, DATE_FORMAT(o.order_date, '%Y-%m')
ORDER BY c.region, sales_month DESC;

-- Причина №3: Проблемы с наличием товара на складе

SELECT 
    w.location_region,
    w.location_city,
    w.warehouse_name,
    COUNT(s.item_id) AS total_skus,
    SUM(CASE WHEN s.quantity_in_stock = 0 THEN 1 ELSE 0 END) AS out_of_stock_skus,
    SUM(s.quantity_in_stock) AS total_available_stock
FROM public_wb w
LEFT JOIN public_stocks s ON w.warehouse_id = s.warehouse_id
GROUP BY w.location_region, w.location_city, w.warehouse_name
ORDER BY out_of_stock_skus DESC;

-- 4.Предложить идеи по оптимизации логистики и улучшению маржинальности
-- 4.1.Отправлять заказы клиентам с ближайшего к ним склада

SELECT 
    c.region AS client_region,
    w.location_region AS warehouse_region,
    COUNT(o.order_id) AS cross_region_orders,
    SUM(o.total_amount) AS order_volume
FROM public_orders o
JOIN public_clients c ON o.client_id = c.client_id
-- Связь с фактическим складом отгрузки через запасы/товары
JOIN public_sales s ON o.order_id = s.order_id
JOIN public_stocks st ON s.item_id = st.item_id
JOIN public_wb w ON st.warehouse_id = w.warehouse_id
WHERE c.region <> w.location_region
GROUP BY c.region, w.location_region
ORDER BY cross_region_orders DESC;

-- 4.2.Пересмотр структуры способов доставки

SELECT 
    shipping_method,
    COUNT(tariff_id) AS shipment_count,
    ROUND(AVG(base_tariff), 2) AS avg_base_tariff,
    ROUND(AVG(additional_costs), 2) AS avg_additional_cost,
    ROUND(SUM(base_tariff + additional_costs), 2) AS total_shipping_cost
FROM tariffs_and_shipping
GROUP BY shipping_method
ORDER BY total_shipping_cost DESC;

-- 4.3.Сокращение отмен и возвратов

SELECT 
    os.status_name,
    COUNT(o.order_id) AS total_orders,
    ROUND(SUM(o.total_amount), 2) AS lost_revenue_volume
FROM public_orders o
JOIN public_order_status os ON o.order_status_id = os.status_id
WHERE os.status_name IN ('Canceled', 'Returned')
GROUP BY os.status_name;

-- 4.4.Оптимизация неликвидных запасов и освобождение капитала
-- Распродажа неликвидов высвобождает рабочие площади и оборотные средства для закупки высокооборачиваемых маржинальных позиций.
-- 4.5.Повышение производительности персонала складов

SELECT 
    w.warehouse_id,
    w.warehouse_name,
    COUNT(DISTINCT st.staff_id) AS staff_count,
    SUM(st.salary) AS total_payroll,
    COALESCE(SUM(r.revenue_amount), 0) AS total_warehouse_revenue,
    ROUND(COALESCE(SUM(r.revenue_amount), 0) / NULLIF(SUM(st.salary), 0), 2) AS revenue_per_payroll_dollar
FROM public_wb w
LEFT JOIN public_staff st ON w.warehouse_id = st.warehouse_id
LEFT JOIN public_revenue_wb r ON w.warehouse_id = r.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name
ORDER BY revenue_per_payroll_dollar ASC;

