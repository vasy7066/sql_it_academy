-- ==========================================================================
-- Лабораторная работа №1. Первые улики: фильтрация и сортировка
-- Курс «Углублённый SQL». Вариант 2 — Команда Б «Производство и закупки»
-- Тема: Фильтрация (WHERE), сортировка, NULL, диапазоны дат, LIMIT / FETCH WITH TIES
-- СУБД: PostgreSQL, схема pitanie
-- ==========================================================================

SET search_path TO pitanie, public;


-- --------------------------------------------------------------------------
-- О1. Сколько заказов и сколько отменено
-- --------------------------------------------------------------------------
SELECT COUNT(*) AS all_orders,
       COUNT(*) FILTER (WHERE status = 'Отменён') AS cancelled
FROM   orders;


-- --------------------------------------------------------------------------
-- О2. Продукция со сроком годности не более 14 дней
-- --------------------------------------------------------------------------
SELECT product_id, product_name, shelf_life_days
FROM   products
WHERE  shelf_life_days <= 14
ORDER  BY shelf_life_days, product_name;


-- --------------------------------------------------------------------------
-- О3. Сотрудники без email или без телефона
-- --------------------------------------------------------------------------
SELECT employee_id, department, full_name, email, phone
FROM   employees
WHERE  email IS NULL OR phone IS NULL      -- = NULL не работает
ORDER  BY department, full_name;


-- --------------------------------------------------------------------------
-- Б1. Партии с высоким браком
-- --------------------------------------------------------------------------
SELECT batch_id, batch_number, line_id, shift, produced_qty, defect_qty,
       ROUND(defect_qty * 1.0 / produced_qty, 4) AS defect_share
FROM   production_batches
WHERE  defect_qty > 0.05 * produced_qty
ORDER  BY defect_qty * 1.0 / produced_qty DESC;

SELECT COUNT(*) AS not_line3_night
FROM   production_batches
WHERE  defect_qty > 0.05 * produced_qty
  AND  NOT (line_id = 3 AND shift = 'Ночь');

SELECT COUNT(*) AS line3_night_total
FROM   production_batches
WHERE  line_id = 3 AND shift = 'Ночь';


-- --------------------------------------------------------------------------
-- Б2. Кто работает в проблемной смене
-- --------------------------------------------------------------------------
SELECT DISTINCT operator_id
FROM   production_batches
WHERE  line_id = 3 AND shift = 'Ночь'
ORDER  BY operator_id;

SELECT employee_id, full_name, position
FROM   employees
WHERE  employee_id IN (52, 58);


-- --------------------------------------------------------------------------
-- Б3. Незакрытые простои
-- --------------------------------------------------------------------------
SELECT *
FROM   equipment_downtime
WHERE  end_time IS NULL
ORDER  BY start_time;


-- --------------------------------------------------------------------------
-- Б4. Простои линии 2
-- --------------------------------------------------------------------------
SELECT COUNT(*) AS y2024
FROM   equipment_downtime
WHERE  line_id = 2
  AND  start_time >= '2024-01-01' AND start_time < '2025-01-01';

SELECT COUNT(*) AS y2025
FROM   equipment_downtime
WHERE  line_id = 2
  AND  start_time >= '2025-01-01' AND start_time < '2026-01-01';

SELECT downtime_id, start_time, end_time, reason
FROM   equipment_downtime
WHERE  line_id = 2
  AND  start_time >= '2025-01-01' AND start_time < '2026-01-01'
  AND  (reason ILIKE '%износ%' OR reason ILIKE 'отказ%')   -- скобки вокруг OR!
ORDER  BY start_time;


-- --------------------------------------------------------------------------
-- Б5. Поставки с отклонением качества
-- --------------------------------------------------------------------------
SELECT po_item_id, po_id, material_id, quantity, received_qty, received_date,
       quality_status
FROM   purchase_order_items
WHERE  quality_status IN ('Принято частично', 'Отклонено')
ORDER  BY received_date;

SELECT COUNT(*) FILTER (WHERE quality_status <> 'Принято')                AS cnt_neq,
       COUNT(*) FILTER (WHERE quality_status IS DISTINCT FROM 'Принято')  AS cnt_distinct
FROM   purchase_order_items;

SELECT po_item_id, po_id, material_id, quantity, received_qty, quality_status
FROM   purchase_order_items
WHERE  quality_status IN ('Принято частично', 'Отклонено')
  AND  material_id IN (1, 2)
ORDER  BY received_date;

SELECT po_id, po_number, supplier_id, order_date
FROM   purchase_orders
WHERE  po_id IN (45, 81, 109, 136, 319, 398, 423, 538, 564, 610, 645, 656)
ORDER  BY po_id;


-- --------------------------------------------------------------------------
-- Б6. Поставщики «на проверку»
-- --------------------------------------------------------------------------
SELECT supplier_id, supplier_name, rating, contract_date
FROM   suppliers
WHERE  rating IS NULL OR rating < 4.0
ORDER  BY rating ASC NULLS FIRST;


-- --------------------------------------------------------------------------
-- Б7. Недовыпуск
-- --------------------------------------------------------------------------
SELECT batch_number, line_id, production_date, planned_qty, produced_qty,
       planned_qty - produced_qty                    AS shortfall,
       ROUND(100.0 * produced_qty / planned_qty, 1)  AS plan_pct
FROM   production_batches
ORDER  BY shortfall DESC
FETCH  FIRST 10 ROWS WITH TIES;

SELECT COUNT(*) AS below_90
FROM   production_batches
WHERE  produced_qty < 0.9 * planned_qty;

SELECT COUNT(*) AS exceptions
FROM   production_batches
WHERE  produced_qty < 0.9 * planned_qty
  AND  NOT (line_id = 2 AND production_date >= DATE '2025-01-01'
                        AND production_date <  DATE '2026-01-01');


-- --------------------------------------------------------------------------
-- ★ Б8. Списания сырья
-- --------------------------------------------------------------------------
SELECT writeoff_id, material_id, writeoff_date, quantity, amount
FROM   material_writeoffs
WHERE  reason = 'Истёк срок годности'
ORDER  BY amount DESC
LIMIT  10;

SELECT material_id, material_name, shelf_life_days
FROM   raw_materials
WHERE  material_id = 10;


-- --------------------------------------------------------------------------
-- ★ Б9. Цифры для руководства
-- --------------------------------------------------------------------------
SELECT COUNT(*) AS writeoffs, SUM(amount) AS writeoff_rub
FROM   material_writeoffs
WHERE  material_id = 10
  AND  reason = 'Истёк срок годности';

SELECT SUM(planned_qty - produced_qty) AS line2_2025_shortfall_units
FROM   production_batches
WHERE  line_id = 2
  AND  production_date >= DATE '2025-01-01';
