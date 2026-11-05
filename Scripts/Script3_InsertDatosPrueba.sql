
--Script 03, insert de datos de prueba, estimados por el grupo
--datos como cuit son inventados, al igual que temperaturas minimas y maximas
-- Se usa @hoy para garantizar la trazabilidad de los datos sin importar el momento de ejecución del script, evitando fechas fijas
--elegimos en las columnas de VARCHAR hacer el insert con N, identificando asi para una mejor lecutra los caracteres especiales(acentos, ñ, °)

USE Andreani;
GO

/* =====================================================================
   CATÁLOGOS Y NEGOCIO
   ===================================================================== */

INSERT INTO TIPO_CLIENTE (Nombre) VALUES
('Laboratorio'), (N'Droguería'), ('Distribuidor');

INSERT INTO TIPO_DESTINO (Nombre) VALUES
('Farmacia'), (N'Clínica'), ('Hospital');

INSERT INTO PROVINCIA (Nombre) VALUES
('Buenos Aires'), ('CABA'), (N'Córdoba'), ('Santa Fe');

INSERT INTO LOCALIDAD (Nombre, Codigo_Postal, Id_Provincia) VALUES
('Malvinas Argentinas', '1613', 1),
('La Plata', '1900', 1),
(N'San Martín', '1650', 1),
('Palermo', '1425', 2),
('Caballito', '1406', 2),
(N'Córdoba', '5000', 3),
(N'San Martín', '5101', 3),
('Rosario', '2000', 4);

INSERT INTO CONDICION_CONSERVACION (Nombre, Temp_Min, Temp_Max) VALUES
('Ambiente', NULL, NULL),
('Temperatura controlada', 15.0, 25.0),
(N'Cadena de frío', 2.0, 8.0);

INSERT INTO CLIENTE (Razon_Social, Cuit, Id_Tipo_Cliente, Activo) VALUES
('Bayer S.A.', '30500012341', 1, 1),
('Roche S.A.Q. e I.', '30500023452', 1, 1),
('Pfizer S.R.L.', '30500034563', 1, 1),
(N'Laboratorios Bagó S.A.', '30500045674', 1, 1),
(N'Droguería del Sud S.A.', '30500056785', 2, 1),
('Distribuidora Federal Salud S.R.L.', '30500067896', 3, 0);

INSERT INTO DESTINO (Nombre_Destino, Direccion, Id_Localidad, Id_Tipo_Destino) VALUES
('Farmacia Central Malvinas', N'Av. Presidente Perón 1250', 1, 1),
('Farmacia Del Pueblo', N'Calle 7 N° 845', 2, 1),
('Hospital Zonal San Roque', N'Calle 508 N° 1200', 2, 3),
(N'Clínica Santa Rita', N'Av. Ricardo Balbín 4100', 3, 2),
('Farmacia Palermo Salud', 'Av. Santa Fe 3500', 4, 1),
(N'Clínica Del Parque', 'Av. Las Heras 2800', 4, 2),
('Hospital Municipal Caballito', 'Av. Rivadavia 5100', 5, 3),
('Farmacia Cordobesa', N'Av. Colón 800', 6, 1),
(N'Hospital Regional San Martín', N'Av. San Martín 1500', 7, 3),
(N'Clínica Rosario Norte', N'Bv. Oroño 1900', 8, 2);

INSERT INTO PRODUCTO (Codigo_Producto, Nombre, Descripcion, Id_Cliente_Propietario, Id_Condicion) VALUES
('BAY-ASP-100', 'Aspirina 100 mg', 'Caja x 28 comprimidos', 1, 1),
('BAY-CIP-500', 'Ciprofloxacina 500 mg', 'Caja x 14 comprimidos', 1, 2),
('ROC-TRA-150', 'Trastuzumab 150 mg', 'Vial polvo liofilizado', 2, 3),
('ROC-OSE-075', 'Oseltamivir 75 mg', N'Caja x 10 cápsulas', 2, 2),
('PFI-VAC-001', N'Vacuna antineumocócica', 'Jeringa prellenada 0,5 ml', 3, 3),
('PFI-ATO-020', 'Atorvastatina 20 mg', 'Caja x 30 comprimidos', 3, 2),
('BAG-INS-100', 'Insulina NPH 100 UI/ml', 'Frasco ampolla 10 ml', 4, 3),
('BAG-ENA-010', 'Enalapril 10 mg', 'Caja x 30 comprimidos', 4, 1),
('DRO-ALC-070', 'Alcohol en gel 70%', 'Frasco 500 ml', 5, 1),
('DRO-OME-020', 'Omeprazol 20 mg', N'Caja x 14 cápsulas', 5, 2);

INSERT INTO OPERARIO (Legajo, Nombre, Apellido, Activo) VALUES
('OP-001', N'Martín', N'Gómez', 1),
('OP-002', N'Lucía', N'Fernández', 1),
('OP-003', 'Diego', N'Ramírez', 1),
('OP-004', 'Carla', N'Suárez', 0);

INSERT INTO VEHICULO (Patente, Refrigerado) VALUES
('AB123CD', 1),
('AC456EF', 1),
('AD789GH', 0),
('AE012IJ', 0);

INSERT INTO CONDUCTOR (Documento, Nombre, Apellido) VALUES
('30123456', N'Raúl', N'Benítez'),
('28456789', 'Silvia', 'Molina'),
('32987654', N'Hernán', 'Acosta'),
('35111222', 'Valeria', 'Rojas');


/* =====================================================================
   LOTES Y STOCK INICIAL
   ===================================================================== */

INSERT INTO LOTE (Id_Producto, Numero_Lote, Fecha_Vencimiento) VALUES
(1, 'AS-2301', DATEADD(DAY, -30, CAST(GETDATE() AS DATE))),
(1, 'L-1001', DATEADD(DAY, 540, CAST(GETDATE() AS DATE))),
(2, 'CI-2310', DATEADD(DAY, 45, CAST(GETDATE() AS DATE))),
(2, 'CI-2405', DATEADD(DAY, 420, CAST(GETDATE() AS DATE))),
(3, 'TR-2312', DATEADD(DAY, 50, CAST(GETDATE() AS DATE))),
(3, 'TR-2406', DATEADD(DAY, 300, CAST(GETDATE() AS DATE))),
(4, 'OS-2308', DATEADD(DAY, -10, CAST(GETDATE() AS DATE))),
(4, 'OS-2407', DATEADD(DAY, 480, CAST(GETDATE() AS DATE))),
(5, 'VA-2403', DATEADD(DAY, 120, CAST(GETDATE() AS DATE))),
(5, 'VA-2404', DATEADD(DAY, 200, CAST(GETDATE() AS DATE))),
(6, 'AT-2311', DATEADD(DAY, 35, CAST(GETDATE() AS DATE))),
(6, 'AT-2408', DATEADD(DAY, 600, CAST(GETDATE() AS DATE))),
(7, 'IN-2309', DATEADD(DAY, -5, CAST(GETDATE() AS DATE))),
(7, 'IN-2404', DATEADD(DAY, 90, CAST(GETDATE() AS DATE))),
(8, 'EN-2405', DATEADD(DAY, 360, CAST(GETDATE() AS DATE))),
(8, 'L-1001', DATEADD(DAY, 400, CAST(GETDATE() AS DATE))),
(9, 'AG-2406', DATEADD(DAY, 700, CAST(GETDATE() AS DATE))),
(9, 'AG-2407', DATEADD(DAY, 720, CAST(GETDATE() AS DATE))),
(10, 'OM-2405', DATEADD(DAY, 400, CAST(GETDATE() AS DATE))),
(10, 'OM-2406', DATEADD(DAY, 500, CAST(GETDATE() AS DATE)));

INSERT INTO STOCK (Id_Lote, Cantidad_Disponible) VALUES
(1, 120), (2, 800), (3, 200), (4, 600), (5, 40),
(6, 90), (7, 150), (8, 400), (9, 60), (10, 0),
(11, 300), (12, 900), (13, 50), (14, 70), (15, 500),
(16, 300), (17, 1000), (18, 700), (19, 450), (20, 350);

GO

/* =====================================================================
   DATOS OPERATIVOS
   ===================================================================== */

DECLARE @hoy DATETIME2(0) = CAST(CAST(GETDATE() AS DATE) AS DATETIME2(0));

INSERT INTO PEDIDO (Id_Cliente, Id_Destino, Fecha_Pedido, Fecha_Entrega_Solicitada, Estado) VALUES
(1, 1, DATEADD(DAY, -30, @hoy), DATEADD(DAY, -22, CAST(@hoy AS DATE)), 'Entregado'),
(2, 1, DATEADD(DAY, -28, @hoy), DATEADD(DAY, -22, CAST(@hoy AS DATE)), 'Entregado'),
(3, 5, DATEADD(DAY, -26, @hoy), DATEADD(DAY, -20, CAST(@hoy AS DATE)), 'Entregado'),
(4, 5, DATEADD(DAY, -25, @hoy), DATEADD(DAY, -22, CAST(@hoy AS DATE)), 'Entregado'),
(1, 7, DATEADD(DAY, -20, @hoy), DATEADD(DAY, -12, CAST(@hoy AS DATE)), 'Entregado'),
(5, 8, DATEADD(DAY, -10, @hoy), DATEADD(DAY, -3, CAST(@hoy AS DATE)), 'Despachado'),
(2, 3, DATEADD(DAY, -6, @hoy), DATEADD(DAY, 2, CAST(@hoy AS DATE)), 'Despachado'),
(3, 6, DATEADD(DAY, -2, @hoy), DATEADD(DAY, 5, CAST(@hoy AS DATE)), N'En preparación'),
(4, 9, DATEADD(DAY, -15, @hoy), DATEADD(DAY, -10, CAST(@hoy AS DATE)), 'Cancelado'),
(1, 2, DATEADD(DAY, -1, @hoy), DATEADD(DAY, 6, CAST(@hoy AS DATE)), 'Recibido'),
(2, 10, DATEADD(DAY, -1, @hoy), DATEADD(DAY, 7, CAST(@hoy AS DATE)), 'Recibido'),
(5, 4, DATEADD(DAY, -20, @hoy), DATEADD(DAY, -8, CAST(@hoy AS DATE)), 'Recibido');

INSERT INTO DETALLE_PEDIDO (Id_Pedido, Id_Producto, Cantidad_Solicitada) VALUES
(1, 1, 20), (1, 2, 10), (2, 3, 5), (2, 4, 12), (3, 5, 6), (3, 6, 15),
(4, 7, 8), (4, 8, 25), (5, 1, 30), (5, 2, 20), (6, 9, 100), (6, 10, 40),
(7, 3, 4), (7, 4, 20), (8, 5, 10), (8, 6, 20), (9, 8, 40), (9, 7, 10),
(10, 1, 15), (10, 2, 10), (11, 3, 3), (11, 4, 6), (12, 9, 50), (12, 10, 20);

INSERT INTO PICKING (Id_Pedido, Id_Operario, Fecha_Inicio, Fecha_Fin, Estado) VALUES
(1, 1, DATEADD(HOUR, 9, DATEADD(DAY, -29, @hoy)), DATEADD(HOUR, 11, DATEADD(DAY, -29, @hoy)), 'Confirmado'),
(2, 2, DATEADD(HOUR, 9, DATEADD(DAY, -27, @hoy)), DATEADD(MINUTE, 30, DATEADD(HOUR, 11, DATEADD(DAY, -27, @hoy))), 'Confirmado'),
(3, 3, DATEADD(MINUTE, 30, DATEADD(HOUR, 8, DATEADD(DAY, -25, @hoy))), DATEADD(HOUR, 12, DATEADD(DAY, -25, @hoy)), 'Confirmado'),
(4, 1, DATEADD(HOUR, 9, DATEADD(DAY, -24, @hoy)), DATEADD(MINUTE, 30, DATEADD(HOUR, 12, DATEADD(DAY, -24, @hoy))), 'Confirmado'),
(5, 2, DATEADD(HOUR, 9, DATEADD(DAY, -19, @hoy)), DATEADD(HOUR, 11, DATEADD(DAY, -19, @hoy)), 'Confirmado'),
(6, 3, DATEADD(HOUR, 10, DATEADD(DAY, -9, @hoy)), DATEADD(HOUR, 13, DATEADD(DAY, -9, @hoy)), 'Confirmado'),
(7, 1, DATEADD(MINUTE, 30, DATEADD(HOUR, 9, DATEADD(DAY, -5, @hoy))), DATEADD(MINUTE, 30, DATEADD(HOUR, 11, DATEADD(DAY, -5, @hoy))), 'Confirmado'),
(8, 2, DATEADD(HOUR, 15, DATEADD(DAY, -1, @hoy)), NULL, 'En curso');

INSERT INTO DETALLE_PICKING (Id_Picking, Id_Detalle_Pedido, Id_Lote, Cantidad_Preparada, Estado_Validacion, Fecha_Hora_Validacion) VALUES
(1, 1, 2, 20, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -29, @hoy))),
(1, 2, 3, 10, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -29, @hoy))),
(2, 3, 5, 5, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -27, @hoy))),
(2, 4, 8, 12, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -27, @hoy))),
(3, 5, 9, 6, 'Rechazada', DATEADD(HOUR, 10, DATEADD(DAY, -25, @hoy))),
(3, 5, 9, 6, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -25, @hoy))),
(3, 6, 11, 10, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -25, @hoy))),
(3, 6, 12, 5, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -25, @hoy))),
(4, 7, 14, 8, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -24, @hoy))),
(4, 8, 15, 25, 'Rechazada', DATEADD(HOUR, 10, DATEADD(DAY, -24, @hoy))),
(4, 8, 16, 25, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -24, @hoy))),
(5, 9, 2, 30, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -19, @hoy))),
(5, 10, 4, 20, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -19, @hoy))),
(6, 11, 17, 100, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -9, @hoy))),
(6, 12, 19, 40, 'Rechazada', DATEADD(HOUR, 10, DATEADD(DAY, -9, @hoy))),
(6, 12, 20, 40, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -9, @hoy))),
(7, 13, 6, 4, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -5, @hoy))),
(7, 14, 8, 20, 'Validada', DATEADD(HOUR, 10, DATEADD(DAY, -5, @hoy))),
(8, 15, 9, 10, 'Pendiente', NULL),
(8, 16, 12, 20, 'Pendiente', NULL);

INSERT INTO ENTREGA (Id_Destino, Id_Vehiculo, Id_Conductor, Fecha_Hora_Salida, Fecha_Hora_Entrega, Estado) VALUES
(1, 1, 1, DATEADD(HOUR, 8, DATEADD(DAY, -23, @hoy)), DATEADD(MINUTE, 30, DATEADD(HOUR, 11, DATEADD(DAY, -23, @hoy))), 'Finalizada'),
(5, 2, 2, DATEADD(HOUR, 8, DATEADD(DAY, -21, @hoy)), DATEADD(HOUR, 12, DATEADD(DAY, -21, @hoy)), 'Finalizada'),
(7, 3, 3, DATEADD(HOUR, 9, DATEADD(DAY, -13, @hoy)), DATEADD(HOUR, 13, DATEADD(DAY, -13, @hoy)), 'Finalizada'),
(8, 4, 4, DATEADD(HOUR, 9, DATEADD(DAY, -4, @hoy)), DATEADD(HOUR, 15, DATEADD(DAY, -4, @hoy)), 'Finalizada'),
(3, 2, 1, DATEADD(MINUTE, 30, DATEADD(HOUR, 7, @hoy)), NULL, 'En viaje'),
(6, 1, 2, NULL, NULL, 'Planificada');

INSERT INTO CAJA (Codigo_QR, Codigo_Barras, Id_Destino, Fecha_Consolidacion, Id_Entrega, Temperatura_Entrega, Estado_Recepcion, Motivo_Rechazo) VALUES
('QR-AND-0001', '7791234500001', 1, DATEADD(HOUR, 14, DATEADD(DAY, -24, @hoy)), 1, 4.5, 'Recibida', NULL),
('QR-AND-0002', '7791234500002', 1, DATEADD(HOUR, 14, DATEADD(DAY, -24, @hoy)), 1, NULL, 'Recibida', NULL),
('QR-AND-0003', '7791234500003', 5, DATEADD(HOUR, 14, DATEADD(DAY, -22, @hoy)), 2, 5.2, 'Recibida', NULL),
('QR-AND-0004', '7791234500004', 5, DATEADD(HOUR, 14, DATEADD(DAY, -22, @hoy)), 2, NULL, 'Recibida', NULL),
('QR-AND-0005', '7791234500005', 7, DATEADD(HOUR, 14, DATEADD(DAY, -14, @hoy)), 3, NULL, 'Recibida', NULL),
('QR-AND-0006', '7791234500006', 8, DATEADD(HOUR, 14, DATEADD(DAY, -5, @hoy)), 4, NULL, 'Recibida', NULL),
('QR-AND-0007', '7791234500007', 8, DATEADD(HOUR, 14, DATEADD(DAY, -5, @hoy)), 4, NULL, 'Rechazada', N'Embalaje dañado al momento de la recepción'),
('QR-AND-0008', '7791234500008', 3, DATEADD(HOUR, 14, DATEADD(DAY, -1, @hoy)), 5, NULL, 'Pendiente', NULL),
('QR-AND-0009', '7791234500009', 3, DATEADD(HOUR, 14, DATEADD(DAY, -1, @hoy)), NULL, NULL, 'Pendiente', NULL),
('QR-AND-0010', '7791234500010', 7, DATEADD(HOUR, 14, DATEADD(DAY, -14, @hoy)), 3, NULL, 'Recibida', NULL);

INSERT INTO DETALLE_CAJA (Id_Caja, Id_Detalle_Picking, Cantidad) VALUES
(1, 1, 20), (1, 3, 5), (2, 2, 10), (2, 4, 12), (3, 6, 6),
(3, 9, 8), (4, 7, 10), (4, 8, 5), (4, 11, 25), (5, 12, 30),
(10, 13, 20), (6, 14, 100), (7, 16, 40), (8, 17, 4), (9, 18, 20);

/* =====================================================================
   ACTUALIZACIÓN DE STOCK
   ===================================================================== */

UPDATE s
SET s.Cantidad_Disponible = s.Cantidad_Disponible - v.Descuento
FROM STOCK s
INNER JOIN (
    SELECT dp.Id_Lote, SUM(dp.Cantidad_Preparada) as Descuento
    FROM DETALLE_PICKING dp
    INNER JOIN PICKING p ON dp.Id_Picking = p.Id_Picking
    WHERE p.Estado = 'Confirmado' AND dp.Estado_Validacion = 'Validada'
    GROUP BY dp.Id_Lote
) v ON s.Id_Lote = v.Id_Lote;