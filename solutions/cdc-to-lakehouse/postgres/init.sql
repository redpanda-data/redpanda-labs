-- The operational schema: one orders table, seeded with five rows.
--
-- tag::table[]
CREATE TABLE orders (
  order_id    SERIAL PRIMARY KEY,
  customer_id INT NOT NULL,
  total       NUMERIC(10,2) NOT NULL,
  status      TEXT NOT NULL DEFAULT 'placed',
  created_at  TIMESTAMP NOT NULL DEFAULT now()
);

-- With the default replica identity, a Postgres delete writes only the
-- primary key to the write-ahead log, so the change event for a delete has
-- null in every other column. REPLICA IDENTITY FULL writes the whole row, so
-- the lakehouse keeps the values the row held when it was deleted.
ALTER TABLE orders REPLICA IDENTITY FULL;
-- end::table[]

-- tag::seed[]
INSERT INTO orders (customer_id, total, status) VALUES
  (1, 50.00,  'placed'),
  (2, 100.00, 'placed'),
  (2, 50.00,  'shipped'),
  (3, 10.00,  'placed'),
  (4, 90.00,  'shipped');
-- end::seed[]
