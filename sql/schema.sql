-- Source OLTP schema, standing in for an upstream application database.
CREATE SCHEMA IF NOT EXISTS retail;

CREATE TABLE IF NOT EXISTS retail.user_purchase (
    purchase_id    SERIAL PRIMARY KEY,
    invoice_id     VARCHAR(20)   NOT NULL,
    product_code   VARCHAR(20)   NOT NULL,
    product_name   VARCHAR(500),
    quantity       INTEGER       NOT NULL,
    purchase_ts    TIMESTAMP     NOT NULL,
    unit_price     NUMERIC(10,2) NOT NULL,
    customer_id    INTEGER,       -- nullable: real guest/anonymous purchases
    country        VARCHAR(50)
);
