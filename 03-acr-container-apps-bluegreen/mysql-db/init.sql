CREATE DATABASE IF NOT EXISTS inventory_db;
USE inventory_db;
CREATE TABLE items (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50), status VARCHAR(20));
INSERT INTO items (name, status) VALUES ('Core-Router-JHB', 'Active'), ('Firewall-Midrand', 'Active');
