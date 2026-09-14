-- The same orders table in MySQL, for the alternative source step.
--
-- tag::table[]
CREATE TABLE orders (
  order_id    INT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT NOT NULL,
  total       DECIMAL(10,2) NOT NULL,
  status      VARCHAR(16) NOT NULL DEFAULT 'placed',
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
-- end::table[]

-- tag::seed[]
INSERT INTO orders (customer_id, total, status) VALUES
  (7, 20.00, 'placed'),
  (8, 35.50, 'placed');
-- end::seed[]

-- tag::grants[]
-- mysql_cdc reads the binary log, which needs the replication privileges as
-- well as SELECT on the tables it snapshots.
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT
  ON *.* TO 'pandashop'@'%';
FLUSH PRIVILEGES;
-- end::grants[]
