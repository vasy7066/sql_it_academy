-- ==========================================================================
-- Лабораторная работа №3. Извлечение данных из нескольких таблиц
-- Курс «Углублённый SQL». Вариант 2 — Команда Б «Производство и закупки»
-- Тема: JOIN (INNER / LEFT / SELF), составной ключ соединения, CROSS JOIN, поиск «сирот» и пропусков
-- СУБД: PostgreSQL, схема pitanie
-- ==========================================================================

SET search_path TO pitanie, public;


-- --------------------------------------------------------------------------
-- Общая часть. Количество строк в таблицах
-- --------------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM production_batches)   AS batches,
       (SELECT COUNT(*) FROM production_lines)     AS lines,
       (SELECT COUNT(*) FROM products)             AS products,
       (SELECT COUNT(*) FROM recipes)              AS recipes,
       (SELECT COUNT(*) FROM raw_materials)        AS materials,
       (SELECT COUNT(*) FROM material_consumption) AS consumption,
       (SELECT COUNT(*) FROM purchase_orders)      AS po,
       (SELECT COUNT(*) FROM purchase_order_items) AS po_items,
       (SELECT COUNT(*) FROM suppliers)            AS suppliers,
       (SELECT COUNT(*) FROM equipment_downtime)   AS downtime;


-- --------------------------------------------------------------------------
-- Б1. Партии с линией, продуктом и оператором (2025)
-- --------------------------------------------------------------------------
SELECT b.batch_number, b.production_date, b.shift, l.line_name, p.product_name,
       e.full_name AS operator, b.produced_qty, b.defect_qty,
       ROUND(100.0 * b.defect_qty / NULLIF(b.produced_qty, 0), 2) AS defect_pct
FROM   production_batches AS b
JOIN   production_lines   AS l ON l.line_id    = b.line_id
JOIN   products           AS p ON p.product_id = b.product_id
LEFT   JOIN employees     AS e ON e.employee_id = b.operator_id
WHERE  b.production_date >= DATE '2025-01-01' AND b.production_date < DATE '2026-01-01'
ORDER  BY b.production_date, b.line_id, b.shift;


-- --------------------------------------------------------------------------
-- Б2. Партии с высоким браком (> 6 %)
-- --------------------------------------------------------------------------
SELECT b.batch_number, b.line_id, b.shift, e.full_name AS operator,
       ROUND(100.0 * b.defect_qty / NULLIF(b.produced_qty, 0), 2) AS defect_pct
FROM   production_batches AS b
LEFT   JOIN employees AS e ON e.employee_id = b.operator_id
WHERE  100.0 * b.defect_qty / NULLIF(b.produced_qty, 0) > 6
ORDER  BY defect_pct DESC;

SELECT l.line_name, b.shift, e.full_name AS operator, COUNT(*) AS batches
FROM   production_batches AS b
JOIN   production_lines   AS l ON l.line_id = b.line_id
LEFT   JOIN employees     AS e ON e.employee_id = b.operator_id
WHERE  100.0 * b.defect_qty / NULLIF(b.produced_qty, 0) > 6
GROUP  BY l.line_name, b.shift, e.full_name
ORDER  BY batches DESC;


-- --------------------------------------------------------------------------
-- Б3. Ответственные за линии и их руководители
-- --------------------------------------------------------------------------
SELECT l.line_id, l.line_name, l.launch_year,
       r.full_name AS responsible, r.position,
       m.full_name AS manager
FROM   production_lines AS l
LEFT   JOIN employees   AS r ON r.employee_id = l.responsible_id
LEFT   JOIN employees   AS m ON m.employee_id = r.manager_id
ORDER  BY l.line_id;


-- --------------------------------------------------------------------------
-- Б4. Поставки сахара в 2025 г.
-- --------------------------------------------------------------------------
SELECT po.po_number, po.order_date, s.supplier_name, m.material_name,
       e.full_name AS buyer, poi.quantity, poi.unit_price,
       ROUND(poi.quantity * poi.unit_price, 2) AS line_sum
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
JOIN   raw_materials        AS m  ON m.material_id = poi.material_id
JOIN   employees            AS e  ON e.employee_id = po.employee_id
WHERE  poi.material_id = 4
  AND  po.order_date >= DATE '2025-01-01' AND po.order_date < DATE '2026-01-01'
ORDER  BY poi.unit_price DESC;


-- --------------------------------------------------------------------------
-- Б5. Один материал — разные цены (SELF-JOIN)
-- --------------------------------------------------------------------------
SELECT m.material_name,
       sa.supplier_name AS expensive_supplier, sb.supplier_name AS cheap_supplier,
       a.unit_price AS price_a, b.unit_price AS price_b,
       ROUND(100.0 * (a.unit_price / b.unit_price - 1), 1) AS overpay_pct
FROM   purchase_order_items AS a
JOIN   purchase_orders      AS pa ON pa.po_id = a.po_id
JOIN   suppliers            AS sa ON sa.supplier_id = pa.supplier_id
JOIN   purchase_order_items AS b  ON b.material_id = a.material_id
JOIN   purchase_orders      AS pb ON pb.po_id = b.po_id
JOIN   suppliers            AS sb ON sb.supplier_id = pb.supplier_id
JOIN   raw_materials        AS m  ON m.material_id = a.material_id
WHERE  pa.supplier_id <> pb.supplier_id
  AND  date_trunc('month', pa.order_date) = date_trunc('month', pb.order_date)
  AND  a.unit_price > b.unit_price * 1.2
ORDER  BY overpay_pct DESC;

SELECT sa.supplier_name AS expensive_supplier, m.material_name, COUNT(*) AS pairs
FROM   purchase_order_items AS a
JOIN   purchase_orders      AS pa ON pa.po_id = a.po_id
JOIN   suppliers            AS sa ON sa.supplier_id = pa.supplier_id
JOIN   purchase_order_items AS b  ON b.material_id = a.material_id
JOIN   purchase_orders      AS pb ON pb.po_id = b.po_id
JOIN   raw_materials        AS m  ON m.material_id = a.material_id
WHERE  pa.supplier_id <> pb.supplier_id
  AND  date_trunc('month', pa.order_date) = date_trunc('month', pb.order_date)
  AND  a.unit_price > b.unit_price * 1.2
GROUP  BY sa.supplier_name, m.material_name
ORDER  BY pairs DESC;


-- --------------------------------------------------------------------------
-- Б6. Опоздания и качество поставок
-- --------------------------------------------------------------------------
SELECT s.supplier_name, m.material_name, po.expected_date, poi.received_date,
       poi.received_date - po.expected_date AS delay_days, poi.quality_status
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
JOIN   raw_materials        AS m  ON m.material_id = poi.material_id
WHERE  poi.received_date > po.expected_date + 3
ORDER  BY delay_days DESC;

SELECT s.supplier_name, m.material_name, poi.quantity, poi.received_qty, poi.quality_status
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
JOIN   raw_materials        AS m  ON m.material_id = poi.material_id
WHERE  poi.quality_status <> 'Принято'
ORDER  BY s.supplier_name;

SELECT po.po_number, po.status, s.supplier_name, m.material_name, po.expected_date, poi.quantity
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
JOIN   raw_materials        AS m  ON m.material_id = poi.material_id
WHERE  poi.received_date IS NULL
ORDER  BY po.po_number;


-- --------------------------------------------------------------------------
-- Б7. Простои с линией и ответственным
-- --------------------------------------------------------------------------
SELECT l.line_name, e.full_name AS responsible, d.start_time,
       COALESCE(d.end_time::text, 'НЕ ЗАКРЫТ') AS end_time,
       ROUND(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600, 2) AS hours,
       d.downtime_category, d.reason
FROM   equipment_downtime AS d
JOIN   production_lines   AS l ON l.line_id = d.line_id
LEFT   JOIN employees     AS e ON e.employee_id = l.responsible_id
ORDER  BY d.start_time;

SELECT l.line_name, d.start_time, COALESCE(d.end_time::text, 'НЕ ЗАКРЫТ') AS end_time, d.reason
FROM   equipment_downtime AS d
JOIN   production_lines   AS l ON l.line_id = d.line_id
WHERE  d.end_time IS NULL
ORDER  BY d.start_time;

SELECT EXTRACT(YEAR FROM d.start_time) AS yr, COUNT(*) AS breakdowns
FROM   equipment_downtime AS d
WHERE  d.line_id = 2
  AND  d.downtime_category = 'Поломка оборудования'
GROUP  BY EXTRACT(YEAR FROM d.start_time)
ORDER  BY yr;


-- --------------------------------------------------------------------------
-- Б8. Норма vs факт (составной ключ)
-- --------------------------------------------------------------------------
SELECT b.batch_number, p.product_name, m.material_name,
       ROUND(r.qty_per_unit * b.produced_qty, 3)                               AS norm_qty,
       mc.quantity                                                             AS fact_qty,
       ROUND(100.0 * (mc.quantity / (r.qty_per_unit * b.produced_qty) - 1), 1) AS overuse_pct
FROM   production_batches   AS b
JOIN   products             AS p  ON p.product_id = b.product_id
JOIN   recipes              AS r  ON r.product_id = b.product_id
JOIN   material_consumption AS mc ON mc.batch_id = b.batch_id
                                 AND mc.material_id = r.material_id
JOIN   raw_materials        AS m  ON m.material_id = r.material_id
WHERE  b.line_id = 5
  AND  b.production_date >= DATE '2025-01-01' AND b.production_date < DATE '2026-01-01'
  AND  mc.quantity > 1.1 * r.qty_per_unit * b.produced_qty
ORDER  BY overuse_pct DESC;

SELECT m.material_name, COUNT(*) AS rows_cnt
FROM   production_batches   AS b
JOIN   recipes              AS r  ON r.product_id = b.product_id
JOIN   material_consumption AS mc ON mc.batch_id = b.batch_id AND mc.material_id = r.material_id
JOIN   raw_materials        AS m  ON m.material_id = r.material_id
WHERE  b.line_id = 5
  AND  b.production_date >= DATE '2025-01-01' AND b.production_date < DATE '2026-01-01'
  AND  mc.quantity > 1.1 * r.qty_per_unit * b.produced_qty
GROUP  BY m.material_name;


-- --------------------------------------------------------------------------
-- ★ Б9. Списания и «сироты»
-- --------------------------------------------------------------------------
SELECT w.writeoff_date, m.material_name, m.shelf_life_days, w.quantity, w.amount, w.reason
FROM   material_writeoffs AS w
JOIN   raw_materials      AS m ON m.material_id = w.material_id
WHERE  w.material_id = 10
ORDER  BY w.writeoff_date;

SELECT m.material_id, m.material_name
FROM   raw_materials AS m
LEFT   JOIN material_writeoffs AS w ON w.material_id = m.material_id
WHERE  w.writeoff_id IS NULL;


-- --------------------------------------------------------------------------
-- ★ Б10. Пропущенные смены
-- --------------------------------------------------------------------------
SELECT l.line_id, s.shift, COUNT(*) AS missing
FROM   generate_series(DATE '2025-01-01', DATE '2025-12-31', INTERVAL '1 day') AS d
CROSS  JOIN production_lines AS l
CROSS  JOIN (VALUES ('День'), ('Ночь')) AS s(shift)
LEFT   JOIN production_batches AS b
       ON b.line_id = l.line_id AND b.production_date = d::date AND b.shift = s.shift
WHERE  b.batch_id IS NULL
GROUP  BY l.line_id, s.shift
ORDER  BY l.line_id, s.shift;
