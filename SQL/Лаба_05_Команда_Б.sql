-- ==========================================================================
-- Лабораторная работа №5. Вложенные запросы: ищем потери
-- Курс «Углублённый SQL». Вариант 2 — Команда Б «Производство и закупки»
-- Тема: Подзапросы (скалярные, коррелированные), IN / NOT IN, EXISTS / NOT EXISTS, ALL и ловушка NULL
-- СУБД: PostgreSQL, схема pitanie
-- ==========================================================================

SET search_path TO pitanie, public;


-- --------------------------------------------------------------------------
-- Общая часть. 2. Продукты дороже средней базовой цены
-- --------------------------------------------------------------------------
SELECT p.product_id, p.product_name, p.base_price
FROM   products AS p
WHERE  p.base_price > (SELECT AVG(p2.base_price) FROM products AS p2)
ORDER  BY p.base_price DESC;

SELECT c.customer_id, c.customer_name
FROM   customers AS c
WHERE  c.customer_id NOT IN (SELECT o.customer_id FROM orders AS o);

SELECT c.customer_id, c.customer_name
FROM   customers AS c
WHERE  NOT EXISTS (SELECT 1 FROM orders AS o WHERE o.customer_id = c.customer_id);


-- --------------------------------------------------------------------------
-- Задание Б-1. Закупки дороже средней цены материала
-- --------------------------------------------------------------------------
-- Задание Б-1, вариант 1
SELECT COUNT(*) AS cnt
FROM   purchase_order_items AS poi
WHERE  poi.unit_price > (SELECT AVG(p2.unit_price)
                         FROM   purchase_order_items AS p2
                         WHERE  p2.material_id = poi.material_id);

-- Задание Б-1, вариант 2
SELECT (SELECT s.supplier_name FROM suppliers AS s WHERE s.supplier_id = po.supplier_id) AS supplier,
       (SELECT m.material_name FROM raw_materials AS m WHERE m.material_id = poi.material_id) AS material,
       COUNT(*) AS items
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
WHERE  poi.unit_price > 1.1 * (SELECT AVG(p2.unit_price)
                               FROM   purchase_order_items AS p2
                               JOIN   purchase_orders      AS o2 ON o2.po_id = p2.po_id
                               WHERE  p2.material_id = poi.material_id
                                 AND  date_trunc('quarter', o2.order_date) = date_trunc('quarter', po.order_date))
GROUP  BY 1, 2
ORDER  BY items DESC;


-- --------------------------------------------------------------------------
-- Задание Б-2. Переплата относительно лучшей цены
-- --------------------------------------------------------------------------
-- Задание Б-2
SELECT s.supplier_name,
       ROUND(SUM(poi.quantity * (poi.unit_price -
             (SELECT MIN(t.avg_price)
              FROM  (SELECT SUM(p2.quantity * p2.unit_price) / SUM(p2.quantity) AS avg_price
                     FROM   purchase_order_items AS p2
                     JOIN   purchase_orders      AS o2 ON o2.po_id = p2.po_id
                     WHERE  p2.material_id = poi.material_id
                     GROUP  BY o2.supplier_id) AS t))), 0) AS overpay
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
GROUP  BY s.supplier_name
ORDER  BY overpay DESC;

SELECT e.full_name AS buyer, COUNT(*) AS orders_cnt
FROM   purchase_orders AS po
JOIN   employees       AS e ON e.employee_id = po.employee_id
WHERE  po.supplier_id = (SELECT s.supplier_id FROM suppliers AS s WHERE s.supplier_name = 'ООО "АгроСнаб-М"')
GROUP  BY e.full_name
ORDER  BY orders_cnt DESC;


-- --------------------------------------------------------------------------
-- Задание Б-3. Надёжные поставщики (NOT EXISTS)
-- --------------------------------------------------------------------------
-- Задание Б-3.1
SELECT s.supplier_id, s.supplier_name, s.rating
FROM   suppliers AS s
WHERE  NOT EXISTS (SELECT 1
                   FROM   purchase_order_items AS poi
                   JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
                   WHERE  po.supplier_id = s.supplier_id
                     AND  poi.quality_status = 'Отклонено')
ORDER  BY s.supplier_id;

-- Задание Б-3.2
SELECT s.supplier_id, s.supplier_name, s.rating
FROM   suppliers AS s
WHERE  NOT EXISTS (SELECT 1
                   FROM   purchase_order_items AS poi
                   JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
                   WHERE  po.supplier_id = s.supplier_id
                     AND  poi.quality_status IN ('Отклонено', 'Принято частично'));

-- Задание Б-3.3: цена сахара
SELECT s.supplier_name,
       ROUND(SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity), 2) AS sugar_price
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
WHERE  poi.material_id = 4
GROUP  BY s.supplier_name
ORDER  BY sugar_price;


-- --------------------------------------------------------------------------
-- Задание Б-4. Партии с браком выше среднего по своей линии
-- --------------------------------------------------------------------------
-- Задание Б-4.1
SELECT b.line_id, b.shift, COUNT(*) AS batches_above_avg
FROM   production_batches AS b
WHERE  1.0 * b.defect_qty / b.produced_qty >
       (SELECT 1.0 * SUM(b2.defect_qty) / SUM(b2.produced_qty)
        FROM   production_batches AS b2
        WHERE  b2.line_id = b.line_id)
GROUP  BY b.line_id, b.shift
ORDER  BY b.line_id, b.shift;

-- Задание Б-4.2: порог x2, по операторам
SELECT b.line_id, b.shift,
       (SELECT e.full_name FROM employees AS e WHERE e.employee_id = b.operator_id) AS operator,
       COUNT(*) AS batches
FROM   production_batches AS b
WHERE  1.0 * b.defect_qty / b.produced_qty > 2 *
       (SELECT 1.0 * SUM(b2.defect_qty) / SUM(b2.produced_qty)
        FROM   production_batches AS b2
        WHERE  b2.line_id = b.line_id)
GROUP  BY b.line_id, b.shift, b.operator_id
ORDER  BY batches DESC;

-- Задание Б-4.3: стоимость брака проблемной смены
SELECT SUM(b.defect_qty) AS defect_qty,
       ROUND(SUM(b.defect_qty * (SELECT p.standard_cost FROM products AS p
                                 WHERE p.product_id = b.product_id)), 0) AS defect_cost
FROM   production_batches AS b
WHERE  b.line_id = 3 AND b.shift = 'Ночь';


-- --------------------------------------------------------------------------
-- Задание Б-5. Закупали — и списывали (EXISTS)
-- --------------------------------------------------------------------------
-- Задание Б-5
SELECT m.material_name, m.shelf_life_days,
       (SELECT SUM(poi.received_qty) FROM purchase_order_items AS poi WHERE poi.material_id = m.material_id) AS received,
       (SELECT SUM(w.quantity) FROM material_writeoffs AS w WHERE w.material_id = m.material_id AND w.quantity > 0) AS written_off,
       (SELECT SUM(w.amount)   FROM material_writeoffs AS w WHERE w.material_id = m.material_id AND w.quantity > 0) AS writeoff_rub,
       ROUND(100.0 * (SELECT SUM(w.quantity) FROM material_writeoffs AS w WHERE w.material_id = m.material_id AND w.quantity > 0)
                   / (SELECT SUM(poi.received_qty) FROM purchase_order_items AS poi WHERE poi.material_id = m.material_id), 1) AS pct
FROM   raw_materials AS m
WHERE  EXISTS (SELECT 1 FROM purchase_order_items AS poi WHERE poi.material_id = m.material_id)
  AND  EXISTS (SELECT 1 FROM material_writeoffs   AS w   WHERE w.material_id = m.material_id AND w.quantity > 0)
ORDER  BY writeoff_rub DESC;


-- --------------------------------------------------------------------------
-- Задание Б-6. Перерасход сырья сверх нормы
-- --------------------------------------------------------------------------
-- Задание Б-6
SELECT t.line_id, t.material_id,
       (SELECT m.material_name FROM raw_materials AS m WHERE m.material_id = t.material_id) AS material,
       ROUND(t.norm, 1) AS norm, ROUND(t.fact, 1) AS fact,
       ROUND(100.0 * (t.fact / t.norm - 1), 2) AS overuse_pct,
       ROUND((t.fact - t.norm) *
             (SELECT SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity)
              FROM   purchase_order_items AS poi
              WHERE  poi.material_id = t.material_id), 0) AS overuse_rub
FROM  (SELECT b.line_id, r.material_id,
              SUM(mc.quantity)                      AS fact,
              SUM(r.qty_per_unit * b.produced_qty)  AS norm
       FROM   production_batches   AS b
       JOIN   recipes              AS r  ON r.product_id = b.product_id
       JOIN   material_consumption AS mc ON mc.batch_id = b.batch_id AND mc.material_id = r.material_id
       GROUP  BY b.line_id, r.material_id) AS t
WHERE  t.fact > 1.03 * t.norm
ORDER  BY overuse_rub DESC;


-- --------------------------------------------------------------------------
-- ★ Задание Б-7. Ловушка ALL + NULL
-- --------------------------------------------------------------------------
-- Задание Б-7, неправильно
SELECT s.supplier_id, s.supplier_name, s.rating
FROM   suppliers AS s
WHERE  s.rating > ALL (SELECT s2.rating FROM suppliers AS s2 WHERE s2.region_id = 1);

-- Задание Б-7, исправлено
SELECT s.supplier_id, s.supplier_name, s.rating
FROM   suppliers AS s
WHERE  s.rating > ALL (SELECT s2.rating FROM suppliers AS s2
                       WHERE  s2.region_id = 1 AND s2.rating IS NOT NULL)
ORDER  BY s.rating DESC;


-- --------------------------------------------------------------------------
-- ★ Последняя поставка материалов группы «Сахар и сиропы»
-- --------------------------------------------------------------------------
SELECT m.material_name, po.order_date, s.supplier_name
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
JOIN   raw_materials        AS m  ON m.material_id = poi.material_id
WHERE  m.material_group = 'Сахар и сиропы'
  AND  po.order_date = (SELECT MAX(o2.order_date)
                        FROM   purchase_order_items AS p2
                        JOIN   purchase_orders      AS o2 ON o2.po_id = p2.po_id
                        WHERE  p2.material_id = poi.material_id);
