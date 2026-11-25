-- ==========================================
-- ICT371 QUESTION 1: Pharmacy Stock & Sales
-- ==========================================

-- Clean up existing tables to prevent errors
DROP TABLE IF EXISTS stock_audit, sales, daily_sales, medicines CASCADE;

-- ---------------------------------------------------------
-- (a) Database and seed data [6 marks]
-- ---------------------------------------------------------
CREATE TABLE medicines (
  medicine_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  medicine_name VARCHAR(100) NOT NULL,
  unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
  stock_qty     INT NOT NULL CHECK (stock_qty >= 0)
);

CREATE TABLE sales (
  sale_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  medicine_id INT NOT NULL REFERENCES medicines(medicine_id),
  quantity    INT NOT NULL CHECK (quantity > 0),
  unit_price  NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
  sold_on     DATE NOT NULL
);

CREATE TABLE stock_audit (
  audit_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  medicine_id INT NOT NULL REFERENCES medicines(medicine_id),
  old_qty     INT NOT NULL,
  new_qty     INT NOT NULL,
  changed_at  TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE daily_sales (
  sales_date   DATE PRIMARY KEY,
  total_qty    INT NOT NULL DEFAULT 0,
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------
-- (b) Function [6 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_sale_value(p_medicine_id INT, p_quantity INT)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_price NUMERIC(10,2);
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be positive';
  END IF;
  SELECT unit_price INTO v_price FROM medicines WHERE medicine_id = p_medicine_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown medicine %', p_medicine_id;
  END IF;
  RETURN v_price * p_quantity;
END $$;

-- ---------------------------------------------------------
-- (c) Procedure [8 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_record_sale(p_medicine_id INT, p_quantity INT, p_sold_on DATE)
LANGUAGE plpgsql AS $$
DECLARE v_price NUMERIC(10,2);
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Invalid quantity';
  END IF;
  
  SELECT unit_price INTO v_price FROM medicines WHERE medicine_id = p_medicine_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown medicine'; END IF;

  -- Deduct stock exactly once
  UPDATE medicines
     SET stock_qty = stock_qty - p_quantity
   WHERE medicine_id = p_medicine_id
     AND stock_qty >= p_quantity;
     
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Insufficient stock for medicine %', p_medicine_id;
  END IF;

  -- Store current price in the sale
  INSERT INTO sales(medicine_id, quantity, unit_price, sold_on)
  VALUES (p_medicine_id, p_quantity, v_price, p_sold_on);
END $$;

-- ---------------------------------------------------------
-- (d) Trigger [8 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_stock_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO stock_audit(medicine_id, old_qty, new_qty)
  VALUES (NEW.medicine_id, OLD.stock_qty, NEW.stock_qty);
  RETURN NEW;
END $$;

-- Only fires when stock_qty ACTUALLY changes
CREATE TRIGGER trg_medicines_stock_audit
AFTER UPDATE ON medicines
FOR EACH ROW
WHEN (OLD.stock_qty IS DISTINCT FROM NEW.stock_qty)
EXECUTE FUNCTION trg_stock_audit();

-- ---------------------------------------------------------
-- (e) View [5 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW v_low_stock AS
SELECT medicine_name, unit_price, stock_qty
FROM medicines
WHERE stock_qty < 10;

-- ---------------------------------------------------------
-- (f) Index [5 marks]
-- ---------------------------------------------------------
CREATE INDEX idx_sales_med_date ON sales(medicine_id, sold_on);
-- (EXPLAIN for your report, not strictly needed for execution):
-- EXPLAIN SELECT * FROM sales WHERE medicine_id = 1 AND sold_on BETWEEN '2025-01-01' AND '2025-01-31';

-- ---------------------------------------------------------
-- (g) Scheduled job [6 marks]
-- ---------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_refresh_sales(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
  -- ON CONFLICT ensures rerunning does not duplicate data
  INSERT INTO daily_sales(sales_date, total_qty, total_amount)
  SELECT p_day, COALESCE(SUM(quantity),0), COALESCE(SUM(quantity*unit_price),0)
  FROM sales WHERE sold_on = p_day
  ON CONFLICT (sales_date) DO UPDATE
    SET total_qty = EXCLUDED.total_qty,
        total_amount = EXCLUDED.total_amount;
END $$;

-- NOTE: The cron.schedule command requires the pg_cron extension, which is 
-- often disabled on student laptops. I have commented it out so your code runs.
-- SELECT cron.schedule('pharmacy-daily', '15 0 * * *', $$CALL pr_refresh_sales(CURRENT_DATE - 1)$$);


-- ==========================================
-- SEED DATA & TESTING
-- ==========================================

-- 1. Insert 3 medicines
INSERT INTO medicines(medicine_name, unit_price, stock_qty) VALUES
 ('Paracetamol', 5.00, 40), 
 ('Amoxicillin', 12.50, 8), 
 ('Ibuprofen', 7.25, 25);

-- 2. Load 6 valid sales through the procedure
CALL pr_record_sale(1, 5, CURRENT_DATE);
CALL pr_record_sale(1, 3, CURRENT_DATE);
CALL pr_record_sale(2, 2, CURRENT_DATE);
CALL pr_record_sale(3, 1, CURRENT_DATE - 1);
CALL pr_record_sale(2, 1, CURRENT_DATE - 1);
CALL pr_record_sale(3, 4, CURRENT_DATE);

-- 3. Query the view after sales
SELECT * FROM v_low_stock;

-- 4. Run the daily refresh and check results
CALL pr_refresh_sales(CURRENT_DATE);
SELECT * FROM daily_sales;

-- 5. Verify the trigger worked (Audit history)
SELECT * FROM stock_audit;