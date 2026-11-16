START TRANSACTION;
ALTER TABLE products ADD stock_quantity integer NOT NULL DEFAULT 0;

INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20261115194451_AddStockQuantity', '10.0.15');

COMMIT;

