-- ==========================================================================
-- Лабораторная работа №2. Приводим данные в порядок и считаем точно
-- Курс «Углублённый SQL». Вариант 2 — Команда Б «Производство и закупки»
-- Тема: Типы данных, деление целых и numeric, даты и интервалы, CASE, NULLIF, ROUND, to_char
-- СУБД: PostgreSQL, схема pitanie
-- ==========================================================================

SET search_path TO pitanie, public;
SET lc_time = 'ru_RU.UTF-8';   -- дата среза: 31.12.2025


-- --------------------------------------------------------------------------
-- О1. Столбцы production_batches
-- --------------------------------------------------------------------------
SELECT column_name, data_type
FROM   information_schema.columns
WHERE  table_schema = 'pitanie'
  AND  table_name   = 'production_batches'
ORDER  BY ordinal_position;


-- --------------------------------------------------------------------------
-- О2. Календарь декабря 2025
-- --------------------------------------------------------------------------
SELECT d::date                       AS dt,
       to_char(d, 'TMDay')            AS day_name,
       CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN 'выходной'
            ELSE 'рабочий' END        AS day_type
FROM   generate_series(DATE '2025-12-01', DATE '2025-12-31', INTERVAL '1 day') AS d;


-- --------------------------------------------------------------------------
-- Б1. Длительность простоев
-- --------------------------------------------------------------------------
SELECT downtime_id, line_id, start_time, end_time,
       (end_time - start_time)::text                                      AS dur,
       ROUND(EXTRACT(EPOCH FROM end_time - start_time) / 3600, 2)         AS hours,
       reason
FROM   equipment_downtime
WHERE  end_time IS NOT NULL
ORDER  BY end_time - start_time DESC
LIMIT  10;


-- --------------------------------------------------------------------------
-- Б2. Незакрытые простои
-- --------------------------------------------------------------------------
SELECT downtime_id, line_id, start_time, reason,
       DATE '2026-01-01' - start_time::date                                            AS days_open,
       ROUND(EXTRACT(EPOCH FROM TIMESTAMP '2026-01-01 00:00' - start_time) / 3600, 1)  AS hours_if_cut
FROM   equipment_downtime
WHERE  end_time IS NULL
ORDER  BY start_time;


-- --------------------------------------------------------------------------
-- ★ Б3. Простои линии 2 по годам
-- --------------------------------------------------------------------------
SELECT EXTRACT(YEAR FROM start_time)                                         AS yr,
       COUNT(*)                                                              AS events,
       ROUND(SUM(EXTRACT(EPOCH FROM end_time - start_time)) / 3600, 1)       AS hours
FROM   equipment_downtime
WHERE  line_id = 2
GROUP  BY EXTRACT(YEAR FROM start_time)
ORDER  BY yr;


-- --------------------------------------------------------------------------
-- Б4. Процент брака: правильная формула
-- --------------------------------------------------------------------------
SELECT batch_number, produced_qty, defect_qty,
       defect_qty / produced_qty                       AS v1,
       100 * defect_qty / produced_qty                 AS v2,
       ROUND(100.0 * defect_qty / produced_qty, 2)     AS v3
FROM   production_batches
WHERE  batch_number IN ('П250602-3Д', 'П250602-3Н');

SELECT COUNT(*) FILTER (WHERE 100   * defect_qty / produced_qty > 5)  AS int_formula,
       COUNT(*) FILTER (WHERE 100.0 * defect_qty / produced_qty > 5)  AS num_formula
FROM   production_batches;

SELECT batch_number, line_id, shift, produced_qty, defect_qty,
       ROUND(100.0 * defect_qty / produced_qty, 2) AS defect_pct
FROM   production_batches
WHERE  100.0 * defect_qty / produced_qty > 5
  AND  NOT (100 * defect_qty / produced_qty > 5);


-- --------------------------------------------------------------------------
-- Б5. Разбор номера партии
-- --------------------------------------------------------------------------
SELECT batch_number,
       to_date(SUBSTRING(batch_number FROM 2 FOR 6), 'YYMMDD')                                 AS num_date,
       regexp_replace(SPLIT_PART(batch_number, '-', 2), '\D', '', 'g')::int                    AS num_line,
       CASE RIGHT(batch_number, 1) WHEN 'Д' THEN 'День' WHEN 'Н' THEN 'Ночь' END              AS num_shift,
       production_date, line_id, shift
FROM   production_batches
ORDER  BY batch_id
LIMIT  5;

SELECT COUNT(*) AS bad_numbers
FROM   production_batches
WHERE  to_date(SUBSTRING(batch_number FROM 2 FOR 6), 'YYMMDD') <> production_date
   OR  regexp_replace(SPLIT_PART(batch_number, '-', 2), '\D', '', 'g')::int <> line_id
   OR  CASE RIGHT(batch_number, 1) WHEN 'Д' THEN 'День' WHEN 'Н' THEN 'Ночь' END
         IS DISTINCT FROM shift;


-- --------------------------------------------------------------------------
-- Б6. Задержка поставок
-- --------------------------------------------------------------------------
SELECT poi.po_item_id, po.po_number, po.supplier_id, po.expected_date, poi.received_date,
       poi.received_date - po.expected_date                    AS delay,
       GREATEST(poi.received_date - po.expected_date, 0)       AS delay_pos
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
WHERE  poi.received_date IS NOT NULL
ORDER  BY delay DESC
LIMIT  10;

SELECT COUNT(*)                                       AS late_4plus,
       COUNT(*) FILTER (WHERE po.supplier_id = 1)     AS from_supplier_1
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
WHERE  poi.received_date - po.expected_date >= 4;

SELECT supplier_id, supplier_name, rating FROM suppliers WHERE supplier_id = 1;


-- --------------------------------------------------------------------------
-- Б7. Возраст линий
-- --------------------------------------------------------------------------
SELECT line_id, line_name, launch_year,
       2025 - launch_year                                              AS age_years,
       AGE(DATE '2025-12-31', make_date(launch_year, 1, 1))::text      AS age_exact,
       CASE WHEN 2025 - launch_year >= 15 THEN 'кандидат на модернизацию'
            WHEN 2025 - launch_year >= 8  THEN 'плановый контроль'
            ELSE 'в норме' END                                         AS status
FROM   production_lines
ORDER  BY line_id;


-- --------------------------------------------------------------------------
-- Б8. Стоимость списаний
-- --------------------------------------------------------------------------
SELECT w.writeoff_id, m.material_name, w.quantity, w.amount,
       ROUND(w.amount / NULLIF(w.quantity, 0), 2)         AS unit_price,
       ROUND(w.amount, -3)                                AS amount_k,
       to_char(w.amount, 'FM999G999G990D00')              AS amount_txt
FROM   material_writeoffs AS w
JOIN   raw_materials      AS m ON m.material_id = w.material_id
WHERE  w.reason = 'Истёк срок годности'
ORDER  BY w.amount DESC
LIMIT  10;

SELECT writeoff_id, ROUND(amount / quantity, 2) AS unit_price
FROM   material_writeoffs;

SELECT COUNT(*)                                              AS all_rows,
       COUNT(*) FILTER (WHERE quantity = 0)                  AS zero_qty,
       MAX(ROUND(amount / NULLIF(quantity, 0), 2))           AS max_unit_price
FROM   material_writeoffs;

SELECT SUM(amount)                  AS exact_rub,
       ROUND(SUM(amount), -3)         AS rounded_k,
       ROUND(SUM(amount) / 1e6, 2)    AS mln
FROM   material_writeoffs
WHERE  material_id = 10;


-- --------------------------------------------------------------------------
-- ★ Б9. Когда ломается линия 2
-- --------------------------------------------------------------------------
SELECT downtime_id,
       to_char(start_time, 'TMDy')                                        AS dow,
       EXTRACT(HOUR FROM start_time)                                      AS hr,
       CASE WHEN EXTRACT(HOUR FROM start_time) BETWEEN 8 AND 19
            THEN 'день' ELSE 'ночь' END                                   AS part_of_day,
       ROUND(EXTRACT(EPOCH FROM end_time - start_time) / 3600, 2)         AS hours,
       reason
FROM   equipment_downtime
WHERE  line_id = 2
  AND  downtime_category = 'Поломка оборудования'
  AND  start_time >= '2025-01-01' AND start_time < '2026-01-01'
ORDER  BY start_time;
