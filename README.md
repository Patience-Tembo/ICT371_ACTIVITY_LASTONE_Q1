# ICT371 Question 1 - Pharmacy Stock and Daily Sales

## Overview
This repository contains the PostgreSQL solution for Question 1. It handles recording medicine sales, prevents overselling, retains stock-change history, and produces daily sales totals.

## Contents
*   **(a) Database & Seed Data:** Four tables created (`medicines`, `sales`, `stock_audit`, `daily_sales`). Constraints enforce positive prices and non-negative stock. 3 medicines and 6 sales are seeded.
*   **(b) Function:** `fn_sale_value` calculates current price * quantity, rejecting invalid inputs.
*   **(c) Procedure:** `pr_record_sale` checks stock, stores current price, and deducts stock exactly once (rollback on failure).
*   **(d) Trigger:** `trg_medicines_stock_audit` (AFTER UPDATE) writes to `stock_audit` only when stock actually changes.
*   **(e) View:** `v_low_stock` shows medicines with stock < 10.
*   **(f) Index:** `idx_sales_med_date` on `(medicine_id, sold_on)` optimizes date-range sales searches.
*   **(g) Scheduled Job:** `pr_refresh_sales` replaces daily totals. *(Note: pg_cron schedule script is included but commented out).*

## How to Run
1. Open pgAdmin (or terminal).
2. Create a database (e.g., `ict371_q1`).
3. Open the Query Tool, paste the contents of `solution.sql`, and execute (F5).
