-- ==========================================================================
-- Лабораторная работа №4. Группирование и агрегирование данных
-- Курс «Углублённый SQL». Вариант 2 — Команда Б «Производство и закупки»
-- Тема: GROUP BY, HAVING, FILTER, CUBE / ROLLUP / GROUPING SETS, взвешенные средние, CTE
-- СУБД: PostgreSQL, схема pitanie
-- ==========================================================================

SET search_path TO pitanie, public;
-- Формулы, о которых договорились:
--   процент брака  = 100.0 * SUM(defect_qty) / SUM(produced_qty)   (взвешенный, не AVG процентов)
--   перерасход     = SUM(mc.quantity) / SUM(r.qty_per_unit * b.produced_qty)
--   средняя цена   = SUM(quantity * unit_price) / SUM(quantity)


-- --------------------------------------------------------------------------
-- Б1. Брак по линиям и сменам (CUBE)
-- --------------------------------------------------------------------------
SELECT CASE WHEN GROUPING(line_id) = 1 THEN 'Все линии' ELSE 'Линия ' || line_id END AS line,
       CASE WHEN GROUPING(shift)   = 1 THEN 'Все смены'  ELSE shift END                    AS shift,
       COUNT(*)            AS batches,
       SUM(produced_qty)   AS produced,
       SUM(defect_qty)     AS defects,
       ROUND(100.0 * SUM(defect_qty) / SUM(produced_qty), 2) AS defect_pct
FROM   production_batches
GROUP  BY CUBE (line_id, shift)
ORDER  BY GROUPING(line_id), line_id, GROUPING(shift), shift;

SELECT e.full_name AS operator, COUNT(*) AS batches,
       ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2) AS defect_pct
FROM   production_batches AS b
LEFT   JOIN employees AS e ON e.employee_id = b.operator_id
WHERE  b.line_id = 3 AND b.shift = 'Ночь'
GROUP  BY e.full_name
ORDER  BY defect_pct DESC;


-- --------------------------------------------------------------------------
-- Б2. Цены материалов по поставщикам и переплата
-- --------------------------------------------------------------------------
SELECT poi.material_id, s.supplier_name,
       COUNT(*)                                                            AS deliveries,
       SUM(poi.quantity)                                                   AS qty,
       ROUND(SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity), 2)    AS w_avg_price,
       ROUND(AVG(poi.unit_price), 2)                                       AS simple_avg
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
WHERE  poi.material_id IN (4, 5, 8)
GROUP  BY poi.material_id, s.supplier_name
ORDER  BY poi.material_id, w_avg_price;

SELECT poi.material_id, m.material_name,
       ROUND(SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id = 3)
             / SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3), 2)    AS price_agro,
       ROUND(SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id <> 3)
             / SUM(poi.quantity) FILTER (WHERE po.supplier_id <> 3), 2)   AS price_others,
       ROUND(100.0 * SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3)
             / SUM(poi.quantity), 1)                                      AS agro_share_pct,
       ROUND(SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3)
             * (SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id = 3)
                  / SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3)
              - SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id <> 3)
                  / SUM(poi.quantity) FILTER (WHERE po.supplier_id <> 3)), 0) AS overpay
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   raw_materials        AS m  ON m.material_id = poi.material_id
WHERE  poi.material_id IN (SELECT DISTINCT poi2.material_id
                           FROM   purchase_order_items AS poi2
                           JOIN   purchase_orders      AS po2 ON po2.po_id = poi2.po_id
                           WHERE  po2.supplier_id = 3)
GROUP  BY poi.material_id, m.material_name
ORDER  BY overpay DESC;

SELECT ROUND(SUM(overpay), 0) AS overpay_total
FROM  (SELECT SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3)
              * (SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id = 3)
                   / SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3)
               - SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id <> 3)
                   / SUM(poi.quantity) FILTER (WHERE po.supplier_id <> 3)) AS overpay
       FROM   purchase_order_items AS poi
       JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
       GROUP  BY poi.material_id
       HAVING COUNT(*) FILTER (WHERE po.supplier_id = 3) > 0) AS t;

SELECT e.full_name AS buyer, COUNT(*) AS items,
       COUNT(*) FILTER (WHERE po.supplier_id = 3) AS agro_items,
       ROUND(100.0 * COUNT(*) FILTER (WHERE po.supplier_id = 3) / COUNT(*), 1) AS agro_share_pct
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   employees            AS e  ON e.employee_id = po.employee_id
GROUP  BY e.full_name
ORDER  BY agro_share_pct DESC;


-- --------------------------------------------------------------------------
-- Б3. Опоздания и качество поставщиков
-- --------------------------------------------------------------------------
SELECT s.supplier_name,
       COUNT(*)                                                         AS items,
       ROUND(AVG(poi.received_date - po.expected_date), 2)              AS avg_delay,
       MAX(poi.received_date - po.expected_date)                        AS max_delay,
       COUNT(*) FILTER (WHERE poi.received_date > po.expected_date)     AS late_items,
       COUNT(*) FILTER (WHERE poi.quality_status IN ('Принято частично', 'Отклонено')) AS quality_problems,
       ROUND(100.0 * SUM(poi.received_qty) / SUM(poi.quantity)
             FILTER (WHERE poi.received_qty IS NOT NULL), 1)            AS accepted_pct
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
GROUP  BY s.supplier_name
HAVING AVG(poi.received_date - po.expected_date) > 1
ORDER  BY avg_delay DESC;


-- --------------------------------------------------------------------------
-- Б4. Часы простоя по линиям и годам
-- --------------------------------------------------------------------------
SELECT CASE WHEN GROUPING(line_id) = 1 THEN 'Все линии' ELSE 'Линия ' || line_id END AS line,
       CASE WHEN GROUPING(EXTRACT(YEAR FROM start_time)) = 1 THEN 'Итого'
            ELSE EXTRACT(YEAR FROM start_time)::text END                                    AS yr,
       COUNT(*)                                                    AS events,
       COUNT(*) - COUNT(end_time)                                  AS not_closed,
       ROUND(SUM(EXTRACT(EPOCH FROM end_time - start_time)) / 3600, 1) AS hours
FROM   equipment_downtime
GROUP  BY ROLLUP (line_id, EXTRACT(YEAR FROM start_time))
ORDER  BY GROUPING(line_id), line_id, GROUPING(EXTRACT(YEAR FROM start_time)), 2;

SELECT line_id,
       ROUND(SUM(EXTRACT(EPOCH FROM end_time - start_time) / 3600)
             FILTER (WHERE start_time <  '2025-01-01'), 1) AS hours_2024,
       ROUND(SUM(EXTRACT(EPOCH FROM end_time - start_time) / 3600)
             FILTER (WHERE start_time >= '2025-01-01'), 1) AS hours_2025,
       COUNT(*) FILTER (WHERE downtime_category = 'Поломка оборудования') AS breakdowns
FROM   equipment_downtime
GROUP  BY line_id
ORDER  BY line_id;

SELECT DISTINCT expense_category FROM expenses ORDER BY 1;

SELECT EXTRACT(YEAR FROM expense_date) AS yr,
       ROUND(SUM(amount) / 1e6, 2)     AS repair_mln
FROM   expenses
WHERE  expense_category = 'Ремонт оборудования'
GROUP  BY EXTRACT(YEAR FROM expense_date)
ORDER  BY yr;


-- --------------------------------------------------------------------------
-- Б5. Списания сырья
-- --------------------------------------------------------------------------
SELECT m.material_name, COUNT(*) AS writeoffs, SUM(w.quantity) AS qty, SUM(w.amount) AS amount,
       ROUND(100.0 * SUM(w.amount) / (SELECT SUM(amount) FROM material_writeoffs), 1) AS share_pct,
       STRING_AGG(DISTINCT w.reason, ', ') AS reasons
FROM   material_writeoffs AS w
JOIN   raw_materials      AS m ON m.material_id = w.material_id
GROUP  BY m.material_name
HAVING SUM(w.amount) > 50000
ORDER  BY amount DESC;

SELECT r.yr, r.received, c.consumed, ROUND(r.received - c.consumed, 1) AS diff
FROM  (SELECT EXTRACT(YEAR FROM received_date) AS yr, SUM(received_qty) AS received
       FROM   purchase_order_items
       WHERE  material_id = 10 AND received_date IS NOT NULL
       GROUP  BY 1) AS r
JOIN  (SELECT EXTRACT(YEAR FROM b.production_date) AS yr, SUM(mc.quantity) AS consumed
       FROM   material_consumption AS mc
       JOIN   production_batches   AS b ON b.batch_id = mc.batch_id
       WHERE  mc.material_id = 10
       GROUP  BY 1) AS c ON c.yr = r.yr
ORDER  BY r.yr;


-- --------------------------------------------------------------------------
-- Б6. Перерасход сырья: факт / норма
-- --------------------------------------------------------------------------
SELECT b.line_id, m.material_name,
       ROUND(SUM(r.qty_per_unit * b.produced_qty), 1)                          AS norm,
       ROUND(SUM(mc.quantity), 1)                                              AS fact,
       ROUND(SUM(mc.quantity) / SUM(r.qty_per_unit * b.produced_qty), 4)       AS ratio
FROM   production_batches   AS b
JOIN   recipes              AS r  ON r.product_id = b.product_id
JOIN   material_consumption AS mc ON mc.batch_id = b.batch_id AND mc.material_id = r.material_id
JOIN   raw_materials        AS m  ON m.material_id = r.material_id
GROUP  BY b.line_id, m.material_name
HAVING SUM(mc.quantity) / SUM(r.qty_per_unit * b.produced_qty) > 1.03
ORDER  BY ratio DESC;

SELECT b.shift,
       ROUND(SUM(mc.quantity) / SUM(r.qty_per_unit * b.produced_qty), 4) AS ratio
FROM   production_batches   AS b
JOIN   recipes              AS r  ON r.product_id = b.product_id
JOIN   material_consumption AS mc ON mc.batch_id = b.batch_id AND mc.material_id = r.material_id
WHERE  b.line_id = 3 AND r.material_id = 1
GROUP  BY b.shift;


-- --------------------------------------------------------------------------
-- Б7. GROUPING SETS: выполнение плана выпуска
-- --------------------------------------------------------------------------
SELECT CASE WHEN GROUPING(line_id) = 1 THEN 'Все' ELSE line_id::text END AS line,
       CASE WHEN GROUPING(EXTRACT(YEAR FROM production_date)) = 1 THEN 'Все'
            ELSE EXTRACT(YEAR FROM production_date)::text END                    AS yr,
       SUM(planned_qty) AS plan, SUM(produced_qty) AS fact,
       SUM(planned_qty) - SUM(produced_qty) AS shortfall,
       ROUND(100.0 * SUM(produced_qty) / SUM(planned_qty), 1) AS plan_pct
FROM   production_batches
GROUP  BY GROUPING SETS ((line_id, EXTRACT(YEAR FROM production_date)), (line_id),
                         (EXTRACT(YEAR FROM production_date)), ())
ORDER  BY GROUPING(line_id), line_id, GROUPING(EXTRACT(YEAR FROM production_date)), 2;


-- --------------------------------------------------------------------------
-- ★ Б8. Цена молочного жира по кварталам
-- --------------------------------------------------------------------------
SELECT date_trunc('quarter', po.order_date)::date AS quarter,
       ROUND(SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity), 2) AS w_avg,
       MIN(poi.unit_price) AS min_price, MAX(poi.unit_price) AS max_price
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
WHERE  poi.material_id = 14
GROUP  BY date_trunc('quarter', po.order_date)
ORDER  BY quarter;


-- --------------------------------------------------------------------------
-- ★ Б9. Стоимость перерасхода какао на линии 5
-- --------------------------------------------------------------------------
WITH price AS (
    SELECT material_id, SUM(quantity * unit_price) / SUM(quantity) AS avg_price
    FROM   purchase_order_items
    GROUP  BY material_id
)
SELECT m.material_name,
       ROUND(SUM(mc.quantity) - SUM(r.qty_per_unit * b.produced_qty), 1) AS over_qty,
       ROUND((SUM(mc.quantity) - SUM(r.qty_per_unit * b.produced_qty)) * MAX(pr.avg_price), 0) AS over_rub
FROM   production_batches   AS b
JOIN   recipes              AS r  ON r.product_id = b.product_id
JOIN   material_consumption AS mc ON mc.batch_id = b.batch_id AND mc.material_id = r.material_id
JOIN   raw_materials        AS m  ON m.material_id = r.material_id
JOIN   price                AS pr ON pr.material_id = r.material_id
WHERE  b.line_id = 5 AND r.material_id IN (8, 9)
GROUP  BY m.material_name;
