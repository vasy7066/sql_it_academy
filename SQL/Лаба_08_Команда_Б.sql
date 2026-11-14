-- ==========================================================================
-- Лабораторная работа №8. Динамика, рейтинги и ABC-анализ
-- Курс «Углублённый SQL». Вариант 2 — Команда Б «Производство и закупки»
-- Тема: Оконные функции: DENSE_RANK, ROW_NUMBER, LAG, скользящее среднее, нарастающий итог, ABC-анализ
-- СУБД: PostgreSQL, схема pitanie
-- ==========================================================================

-- Схема pitanie, только чтение
SET search_path TO pitanie, public;


-- --------------------------------------------------------------------------
-- Б1. Рейтинг поставщиков по цене внутри материала и переплата
-- --------------------------------------------------------------------------
WITH base AS (
    SELECT poi.material_id, po.supplier_id,
           SUM(poi.quantity) AS qty,
           SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity) AS avg_price
    FROM   purchase_order_items AS poi
    JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
    WHERE  po.order_date >= DATE '2025-01-01' AND po.order_date < DATE '2026-01-01'
    GROUP  BY poi.material_id, po.supplier_id
), w AS (
    SELECT base.*,
           DENSE_RANK() OVER (PARTITION BY material_id ORDER BY avg_price) AS price_rank,
           MIN(avg_price) OVER (PARTITION BY material_id)                  AS best_price,
           COUNT(*)       OVER (PARTITION BY material_id)                  AS suppliers_cnt
    FROM   base
)
SELECT m.material_name, s.supplier_name, w.price_rank,
       ROUND(w.avg_price, 2) AS avg_price, ROUND(w.best_price, 2) AS best_price,
       ROUND(100 * (w.avg_price / w.best_price - 1), 1) AS overprice_pct,
       ROUND(w.qty * (w.avg_price - w.best_price), 0)   AS overpay_rub
FROM   w
JOIN   raw_materials AS m ON m.material_id = w.material_id
JOIN   suppliers     AS s ON s.supplier_id = w.supplier_id
WHERE  w.suppliers_cnt > 1 AND w.price_rank > 1
ORDER  BY overpay_rub DESC
LIMIT  10;

WITH base AS (
    SELECT poi.material_id, po.supplier_id,
           SUM(poi.quantity) AS qty,
           SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity) AS avg_price
    FROM   purchase_order_items AS poi
    JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
    WHERE  po.order_date >= DATE '2025-01-01' AND po.order_date < DATE '2026-01-01'
    GROUP  BY poi.material_id, po.supplier_id
), w AS (
    SELECT base.*, MIN(avg_price) OVER (PARTITION BY material_id) AS best_price
    FROM   base
)
SELECT s.supplier_name, ROUND(SUM(w.qty * (w.avg_price - w.best_price)), 0) AS overpay_total
FROM   w
JOIN   suppliers AS s ON s.supplier_id = w.supplier_id
GROUP  BY s.supplier_name
HAVING SUM(w.qty * (w.avg_price - w.best_price)) > 0
ORDER  BY overpay_total DESC;


-- --------------------------------------------------------------------------
-- Б2. Скользящее среднее брака за 7 смен по линии
-- --------------------------------------------------------------------------
WITH b AS (
    SELECT line_id, production_date, shift,
           100.0 * defect_qty / produced_qty AS defect_pct
    FROM   production_batches
    WHERE  production_date >= DATE '2025-01-01' AND production_date < DATE '2026-01-01'
), w AS (
    SELECT b.*,
           AVG(defect_pct) OVER (PARTITION BY line_id ORDER BY production_date, shift
                                 ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ma7
    FROM   b
)
SELECT line_id,
       ROUND(AVG(ma7), 2)                 AS avg_ma7,
       ROUND(MAX(ma7), 2)                 AS max_ma7,
       COUNT(*) FILTER (WHERE ma7 > 3)    AS shifts_ma7_over_3
FROM   w
GROUP  BY line_id
ORDER  BY line_id;


-- --------------------------------------------------------------------------
-- Б3. Изменение цены к предыдущей закупке (LAG) — молочный жир
-- --------------------------------------------------------------------------
WITH p AS (
    SELECT po.order_date, s.supplier_name, poi.unit_price,
           LAG(poi.unit_price) OVER (ORDER BY po.order_date, poi.po_item_id) AS prev_price
    FROM   purchase_order_items AS poi
    JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
    JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
    WHERE  poi.material_id = 14
)
SELECT order_date, supplier_name, prev_price, unit_price,
       ROUND(100 * (unit_price / prev_price - 1), 1) AS change_pct
FROM   p
WHERE  unit_price > 1.1 * prev_price
ORDER  BY order_date;

WITH m AS (
    SELECT poi.material_id, date_trunc('month', po.order_date)::date AS mon,
           AVG(poi.unit_price) AS avg_price
    FROM   purchase_order_items AS poi
    JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
    GROUP  BY poi.material_id, date_trunc('month', po.order_date)
), w AS (
    SELECT m.*, LAG(avg_price) OVER (PARTITION BY material_id ORDER BY mon) AS prev_month
    FROM   m
)
SELECT rm.material_name, w.mon, ROUND(w.prev_month, 2) AS prev_month, ROUND(w.avg_price, 2) AS avg_price,
       ROUND(100 * (w.avg_price / w.prev_month - 1), 1) AS change_pct
FROM   w
JOIN   raw_materials AS rm ON rm.material_id = w.material_id
WHERE  w.avg_price > 1.15 * w.prev_month
ORDER  BY change_pct DESC;


-- --------------------------------------------------------------------------
-- Б4. Нарастающие часы простоя линии 2 по месяцам
-- --------------------------------------------------------------------------
WITH d AS (
    SELECT EXTRACT(YEAR FROM start_time)  AS y,
           EXTRACT(MONTH FROM start_time) AS mon,
           EXTRACT(EPOCH FROM end_time - start_time) / 3600 AS hours
    FROM   equipment_downtime
    WHERE  line_id = 2 AND end_time IS NOT NULL
)
SELECT mon,
       ROUND(SUM(hours) FILTER (WHERE y = 2024), 1) AS h2024,
       ROUND(SUM(hours) FILTER (WHERE y = 2025), 1) AS h2025,
       ROUND(SUM(SUM(hours) FILTER (WHERE y = 2024)) OVER (ORDER BY mon
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 1) AS cum2024,
       ROUND(SUM(SUM(hours) FILTER (WHERE y = 2025)) OVER (ORDER BY mon
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 1) AS cum2025
FROM   d
GROUP  BY mon
ORDER  BY mon;


-- --------------------------------------------------------------------------
-- Б5. Интервалы между поломками
-- --------------------------------------------------------------------------
WITH b AS (
    SELECT line_id, start_time,
           start_time - LAG(end_time) OVER (PARTITION BY line_id ORDER BY start_time) AS gap
    FROM   equipment_downtime
    WHERE  downtime_category = 'Поломка оборудования'
)
SELECT line_id, EXTRACT(YEAR FROM start_time) AS yr,
       COUNT(*) AS breakdowns,
       ROUND(AVG(EXTRACT(EPOCH FROM gap) / 86400)::numeric, 1) AS avg_gap_days
FROM   b
GROUP  BY line_id, EXTRACT(YEAR FROM start_time)
ORDER  BY line_id, yr;


-- --------------------------------------------------------------------------
-- Б6. ABC-анализ закупок по материалам
-- --------------------------------------------------------------------------
WITH s AS (
    SELECT poi.material_id, SUM(poi.quantity * poi.unit_price) AS amount
    FROM   purchase_order_items AS poi
    JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
    WHERE  po.order_date >= DATE '2025-01-01' AND po.order_date < DATE '2026-01-01'
    GROUP  BY poi.material_id
), w AS (
    SELECT s.*,
           100.0 * SUM(amount) OVER (ORDER BY amount DESC, material_id
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                 / SUM(amount) OVER () AS cum_pct
    FROM   s
)
SELECT m.material_name, ROUND(w.amount, 0) AS amount, ROUND(w.cum_pct, 1) AS cum_pct,
       CASE WHEN w.cum_pct <= 80 THEN 'A' WHEN w.cum_pct <= 95 THEN 'B' ELSE 'C' END AS abc
FROM   w
JOIN   raw_materials AS m ON m.material_id = w.material_id
ORDER  BY w.amount DESC;


-- --------------------------------------------------------------------------
-- ★ Б7. Перерасход какао-порошка: топ-3 партии каждого месяца
-- --------------------------------------------------------------------------
WITH r AS (
    SELECT b.batch_number, b.line_id, date_trunc('month', b.production_date)::date AS mon,
           mc.quantity / (rc.qty_per_unit * b.produced_qty) AS ratio
    FROM   production_batches   AS b
    JOIN   recipes              AS rc ON rc.product_id = b.product_id AND rc.material_id = 8
    JOIN   material_consumption AS mc ON mc.batch_id = b.batch_id AND mc.material_id = 8
    WHERE  b.production_date >= DATE '2025-01-01' AND b.production_date < DATE '2026-01-01'
), w AS (
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY mon ORDER BY ratio DESC, batch_number) AS rn
    FROM   r
)
SELECT COUNT(*) AS places, COUNT(*) FILTER (WHERE line_id = 5) AS on_line5,
       ROUND(100 * (AVG(ratio) - 1), 1) AS avg_overuse_pct
FROM   w
WHERE  rn <= 3;
