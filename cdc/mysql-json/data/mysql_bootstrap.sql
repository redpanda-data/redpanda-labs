CREATE DATABASE IF NOT EXISTS pandashop;
USE pandashop;

GRANT ALL PRIVILEGES ON pandashop.* TO 'mysqluser';
GRANT FILE on *.* to 'mysqluser';

CREATE USER 'debezium' IDENTIFIED WITH mysql_native_password BY 'dbz';

GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium';

FLUSH PRIVILEGES;

-- Create the orders table
CREATE TABLE orders (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT,
    total FLOAT,
    created_at DATETIME DEFAULT NOW()
);

-- Populate the 'orders' table
INSERT INTO orders (customer_id, total) VALUES
    (1, 100.50),
    (2, 75.25),
    (1, 50.75),
    (3, 120.00);
