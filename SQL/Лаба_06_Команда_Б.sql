-- ==========================================================================
-- Лабораторная работа №6. Объединение наборов: единые журналы и сравнение периодов
-- Курс «Углублённый SQL». Вариант 2 — Команда Б «Производство и закупки»
-- Тема: UNION / UNION ALL, INTERSECT, EXCEPT, единые журналы событий, LATERAL, generate_series
-- СУБД: PostgreSQL, схема pitanie
-- ==========================================================================

SET search_path TO pitanie, public;


-- --------------------------------------------------------------------------
-- Общая часть. UNION ALL / UNION, INTERSECT, дубли ИНН
-- --------------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM (SELECT inn FROM customers UNION ALL SELECT inn FROM suppliers) AS t) AS union_all,
       (SELECT COUNT(*) FROM (SELECT inn FROM customers UNION     SELECT inn FROM suppliers) AS t) AS union_distinct;

SELECT inn FROM customers
INTERSECT
SELECT inn FROM suppliers;

SELECT inn, COUNT(*) AS cnt
FROM   customers
GROUP  BY inn
HAVING COUNT(*) > 1;


-- --------------------------------------------------------------------------
-- Задание Б-1. Единый журнал потерь производства
-- --------------------------------------------------------------------------
-- Задание Б-1
SELECT t.event_type, EXTRACT(YEAR FROM t.event_date) AS yr, t.unit,
       COUNT(*) AS events, ROUND(SUM(t.qty), 1) AS qty, ROUND(SUM(t.amount_rub), 0) AS amount_rub
FROM  (SELECT 'Брак'::text            AS event_type,
              b.production_date       AS event_date,
              b.line_id               AS line_id,
              b.defect_qty::numeric   AS qty,
              'шт'::text              AS unit,
              b.defect_qty * p.standard_cost AS amount_rub
       FROM   production_batches AS b
       JOIN   products           AS p ON p.product_id = b.product_id
       WHERE  b.defect_qty > 0
       UNION ALL
       SELECT 'Простой', d.start_time::date, d.line_id,
              EXTRACT(EPOCH FROM (d.end_time - d.start_time)) / 3600, 'ч', NULL
       FROM   equipment_downtime AS d
       WHERE  d.end_time IS NOT NULL
       UNION ALL
       SELECT 'Списание', w.writeoff_date, NULL, w.quantity, m.unit, w.amount
       FROM   material_writeoffs AS w
       JOIN   raw_materials      AS m ON m.material_id = w.material_id
       WHERE  w.quantity > 0) AS t
GROUP  BY t.event_type, EXTRACT(YEAR FROM t.event_date), t.unit
ORDER  BY t.event_type, yr, t.unit;


-- --------------------------------------------------------------------------
-- Задание Б-2. Простои по линиям
-- --------------------------------------------------------------------------
-- Задание Б-2
SELECT d.line_id,
       ROUND(SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600)
             FILTER (WHERE d.start_time <  '2025-01-01'), 1)  AS hours_2024,
       ROUND(SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600)
             FILTER (WHERE d.start_time >= '2025-01-01'), 1)  AS hours_2025
FROM   equipment_downtime AS d
WHERE  d.end_time IS NOT NULL
GROUP  BY d.line_id
ORDER  BY d.line_id;


-- --------------------------------------------------------------------------
-- Задание Б-3. Закупаем то, что не используем? (EXCEPT)
-- --------------------------------------------------------------------------
-- Задание Б-3.1: закупается, но нет в рецептурах
SELECT material_id FROM purchase_order_items
EXCEPT
SELECT material_id FROM recipes;

-- Задание Б-3.2: есть в рецептурах, но не закупалось
SELECT material_id FROM recipes
EXCEPT
SELECT material_id FROM purchase_order_items;

-- Задание Б-3.4: новые пары поставщик-материал в 2025
(SELECT po.supplier_id, poi.material_id
 FROM   purchase_order_items AS poi
 JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
 WHERE  po.order_date >= DATE '2025-01-01')
EXCEPT
(SELECT po.supplier_id, poi.material_id
 FROM   purchase_order_items AS poi
 JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
 WHERE  po.order_date < DATE '2025-01-01')
ORDER  BY 1, 2;


-- --------------------------------------------------------------------------
-- Задание Б-4. Поставщики одних и тех же материалов (INTERSECT)
-- --------------------------------------------------------------------------
-- Задание Б-4.1
SELECT poi.material_id
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
WHERE  s.supplier_name = 'ООО "АгроСнаб-М"'
INTERSECT
SELECT poi.material_id
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
WHERE  s.supplier_name <> 'ООО "АгроСнаб-М"'
ORDER  BY 1;

SELECT COUNT(DISTINCT poi.material_id) AS agro_materials_total
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
WHERE  po.supplier_id = 3;

-- Задание Б-4.2 ★
SELECT s1.supplier_name AS supplier_1, s2.supplier_name AS supplier_2, x.common_cnt
FROM   suppliers AS s1
JOIN   suppliers AS s2 ON s1.supplier_id < s2.supplier_id
CROSS  JOIN LATERAL (
       SELECT COUNT(*) AS common_cnt
       FROM  (SELECT poi.material_id FROM purchase_order_items AS poi
              JOIN purchase_orders AS po ON po.po_id = poi.po_id WHERE po.supplier_id = s1.supplier_id
              INTERSECT
              SELECT poi.material_id FROM purchase_order_items AS poi
              JOIN purchase_orders AS po ON po.po_id = poi.po_id WHERE po.supplier_id = s2.supplier_id) AS c
) AS x
WHERE  x.common_cnt > 0
ORDER  BY x.common_cnt DESC;


-- --------------------------------------------------------------------------
-- Задание Б-5. Последние 3 поставки и цена конкурента (LATERAL)
-- --------------------------------------------------------------------------
-- Задание Б-5
SELECT s.supplier_name, last3.order_date, m.material_name, last3.unit_price,
       comp.min_price AS competitor_price,
       ROUND(100.0 * (last3.unit_price / comp.min_price - 1), 1) AS over_pct
FROM   suppliers AS s
CROSS  JOIN LATERAL (
       SELECT po.order_date, poi.material_id, poi.unit_price
       FROM   purchase_order_items AS poi
       JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
       WHERE  po.supplier_id = s.supplier_id
       ORDER  BY po.order_date DESC, poi.po_item_id DESC
       LIMIT  3) AS last3
LEFT   JOIN LATERAL (
       SELECT MIN(poi2.unit_price) AS min_price
       FROM   purchase_order_items AS poi2
       JOIN   purchase_orders      AS po2 ON po2.po_id = poi2.po_id
       WHERE  poi2.material_id = last3.material_id
         AND  po2.supplier_id <> s.supplier_id
         AND  po2.order_date BETWEEN last3.order_date - 90 AND last3.order_date) AS comp
       ON TRUE
JOIN   raw_materials AS m ON m.material_id = last3.material_id
ORDER  BY over_pct DESC NULLS LAST;


-- --------------------------------------------------------------------------
-- ★ Задание Б-6. Календарь простоев линии 2
-- --------------------------------------------------------------------------
-- Задание Б-6
SELECT mon::date AS month, x.events, x.hours
FROM   generate_series(DATE '2024-01-01', DATE '2025-12-01', INTERVAL '1 month') AS mon
LEFT   JOIN LATERAL (
       SELECT COUNT(*) AS events,
              COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time)) / 3600, 1), 0) AS hours
       FROM   equipment_downtime AS d
       WHERE  d.line_id = 2
         AND  d.start_time >= mon AND d.start_time < mon + INTERVAL '1 month') AS x ON TRUE
ORDER  BY mon;
