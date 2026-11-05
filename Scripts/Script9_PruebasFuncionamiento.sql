
/*
    Script 09 - Pruebas de funcionamiento
     Demuestra:
      1) el circuito completo de punta a punta;
      2) el rechazo y corrección de una línea de picking;
      3) los errores controlados por triggers, procedimientos y restricciones.
    Criterios:
      - Ninguna prueba deja datos modificados: los casos correctos corren dentro de una
        transacción que termina en ROLLBACK, y los de error se deshacen solos. 
      - Las pruebas de error usan TRY/CATCH y comparan el número de error obtenido con el
        esperado. El resultado se lee en la pestaña Mensajes: cada prueba imprime OK o FALLA.
      - Cada prueba es un lote separado por GO: si una falla, las siguientes se ejecutan igual.
      - Los IDENTITY consumidos por inserciones deshechas no se recuperan: después de este
        script pueden quedar saltos en la numeración. Es el comportamiento normal de SQL Server.
*/
USE Andreani;
GO
SET NOCOUNT ON;
GO

/* =====================================================================
   PRUEBA 1 - Circuito completo con el pedido 10 (Recibido, destino 2)
   Pedido -> picking -> validación -> confirmación -> caja -> entrega -> recepción.
   Esperado: stock del lote 2 de 750 a 735 y del lote 3 de 190 a 180;
   pedido 10 termina Entregado; la trazabilidad del lote 3 muestra 2 filas.
   Las transiciones En preparación y Despachado se registran con UPDATE directo:
   no tienen procedimiento propio en el alcance del proyecto.
   ===================================================================== */
BEGIN TRANSACTION;

DECLARE @Id_Picking INT, @Linea_1 INT, @Linea_2 INT, @Id_Caja INT, @Id_Entrega INT;

-- 1) Inicio del picking
INSERT INTO PICKING (Id_Pedido, Id_Operario, Fecha_Inicio) VALUES (10, 1, SYSDATETIME());
SET @Id_Picking = @@IDENTITY;
UPDATE PEDIDO SET Estado = 'En preparación' WHERE Id_Pedido = 10;

-- 2) Líneas con criterio FEFO: lote 2 para la aspirina y lote 3 (vence antes que el 4)
INSERT INTO DETALLE_PICKING (Id_Picking, Id_Detalle_Pedido, Id_Lote, Cantidad_Preparada)
VALUES (@Id_Picking, 19, 2, 15);
SET @Linea_1 = @@IDENTITY;
INSERT INTO DETALLE_PICKING (Id_Picking, Id_Detalle_Pedido, Id_Lote, Cantidad_Preparada)
VALUES (@Id_Picking, 20, 3, 10);
SET @Linea_2 = @@IDENTITY;

-- 3) Validación con el lector
EXEC dbo.sp_Validar_Linea_Picking @Id_Detalle_Picking = @Linea_1, @Id_Lote_Leido = 2, @Cantidad_Leida = 15;
EXEC dbo.sp_Validar_Linea_Picking @Id_Detalle_Picking = @Linea_2, @Id_Lote_Leido = 3, @Cantidad_Leida = 10;

-- 4) Confirmación: descuenta stock y deja el pedido Preparado
EXEC dbo.sp_Confirmar_Picking @Id_Picking = @Id_Picking;
SELECT 'P1 - stock tras confirmar' AS Prueba, Id_Lote, Cantidad_Disponible
FROM STOCK WHERE Id_Lote IN (2, 3);                                   -- 735 y 180
SELECT 'P1 - pedido tras confirmar' AS Prueba, Id_Pedido, Estado
FROM PEDIDO WHERE Id_Pedido = 10;                                     -- Preparado

-- 5) Consolidación en una caja del destino 2
INSERT INTO CAJA (Codigo_QR, Codigo_Barras, Id_Destino, Fecha_Consolidacion)
VALUES ('QR-AND-0011', '7791234500011', 2, SYSDATETIME());
SET @Id_Caja = @@IDENTITY;
INSERT INTO DETALLE_CAJA (Id_Caja, Id_Detalle_Picking, Cantidad)
VALUES (@Id_Caja, @Linea_1, 15), (@Id_Caja, @Linea_2, 10);           -- INSERT de dos filas: pasa por el trigger

-- 6) Entrega planificada y asignación de la caja
INSERT INTO ENTREGA (Id_Destino, Id_Vehiculo, Id_Conductor) VALUES (2, 3, 3);   -- Planificada por defecto
SET @Id_Entrega = @@IDENTITY;
EXEC dbo.sp_Asignar_Caja_Entrega @Id_Caja = @Id_Caja, @Id_Entrega = @Id_Entrega;
UPDATE PEDIDO SET Estado = 'Despachado' WHERE Id_Pedido = 10;

-- 7) Salida y llegada del vehículo
UPDATE ENTREGA SET Fecha_Hora_Salida = DATEADD(HOUR, -3, SYSDATETIME()), Estado = 'En viaje'
WHERE Id_Entrega = @Id_Entrega;
UPDATE ENTREGA SET Fecha_Hora_Entrega = SYSDATETIME(), Estado = 'Finalizada'
WHERE Id_Entrega = @Id_Entrega;

-- 8) Recepción conforme: el pedido pasa a Entregado
EXEC dbo.sp_Registrar_Recepcion_Caja @Id_Caja = @Id_Caja, @Estado_Recepcion = 'Recibida';
SELECT 'P1 - pedido tras recepción' AS Prueba, Id_Pedido, Estado,
       dbo.fn_Fecha_Entrega_Pedido(Id_Pedido) AS Fecha_Entrega
FROM PEDIDO WHERE Id_Pedido = 10;                                     -- Entregado, fecha de hoy

-- 9) Trazabilidad: el lote 3 ahora llegó también al pedido 10
EXEC dbo.sp_Trazabilidad_Lote @Id_Lote = 3;                           -- 2 filas: pedido 1 y pedido 10

ROLLBACK TRANSACTION;
PRINT N'P1 circuito completo ejecutado y deshecho (revisar resultados en la pestaña Resultados)';
GO

/* =====================================================================
   PRUEBA 2 - Rechazo y corrección de una línea (picking 8, Lucía Fernández)
   La línea 19 se lee con el lote equivocado y queda Rechazada; se registra una
   línea nueva que la corrige. La rechazada no se borra y no descuenta stock.
   Esperado: stock del lote 9 de 54 a 44 (una sola vez) y del lote 12 de 895 a 875;
   KPI 2: Lucía 3/1/33.3 y TOTAL 8/4/50.0.
   ===================================================================== */
BEGIN TRANSACTION;

DECLARE @Linea_Corregida INT;

EXEC dbo.sp_Validar_Linea_Picking @Id_Detalle_Picking = 19, @Id_Lote_Leido = 12, @Cantidad_Leida = 10;  -- Rechazada

-- Corrección: la línea rechazada no cuenta para RN03, por eso se pueden volver a preparar 10
INSERT INTO DETALLE_PICKING (Id_Picking, Id_Detalle_Pedido, Id_Lote, Cantidad_Preparada)
VALUES (8, 15, 9, 10);
SET @Linea_Corregida = @@IDENTITY;

EXEC dbo.sp_Validar_Linea_Picking @Id_Detalle_Picking = @Linea_Corregida, @Id_Lote_Leido = 9, @Cantidad_Leida = 10;  -- Validada
EXEC dbo.sp_Validar_Linea_Picking @Id_Detalle_Picking = 20, @Id_Lote_Leido = 12, @Cantidad_Leida = 20;                -- Validada
EXEC dbo.sp_Confirmar_Picking @Id_Picking = 8;

SELECT 'P2 - stock tras confirmar' AS Prueba, Id_Lote, Cantidad_Disponible
FROM STOCK WHERE Id_Lote IN (9, 12);                                  -- 44 y 875
SELECT 'P2 - KPI 2' AS Prueba, Operario, Pickings_Confirmados, Pickings_Con_Rechazo, Porcentaje_Errores
FROM vw_Kpi_Errores_Picking
ORDER BY CASE WHEN Id_Operario IS NULL THEN 1 ELSE 0 END, Id_Operario;

ROLLBACK TRANSACTION;
PRINT N'P2 rechazo y corrección ejecutado y deshecho';
GO

/* =====================================================================
   PRUEBA 3 - Lote que vence mientras la línea espera
   El operario lee bien, pero el lote ya venció: el procedimiento la deja Rechazada
   (no se traba el picking). Esperado: Rechazada.
   ===================================================================== */
BEGIN TRANSACTION;
UPDATE LOTE SET Fecha_Vencimiento = DATEADD(DAY, -1, CAST(GETDATE() AS DATE)) WHERE Id_Lote = 9;
EXEC dbo.sp_Validar_Linea_Picking @Id_Detalle_Picking = 19, @Id_Lote_Leido = 9, @Cantidad_Leida = 10;
SELECT 'P3 - línea con lote vencido' AS Prueba, Id_Detalle_Picking, Estado_Validacion
FROM DETALLE_PICKING WHERE Id_Detalle_Picking = 19;                   -- Rechazada
ROLLBACK TRANSACTION;
PRINT N'P3 lote vencido durante la espera ejecutado y deshecho';
GO

/* =====================================================================
   ERRORES CONTROLADOS POR TRIGGERS
   Si la operación no da error, se deshace igual y se informa FALLA.
   ===================================================================== */

-- E01 - RN01: asignar un lote vencido (lote 1)
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO DETALLE_PICKING (Id_Picking, Id_Detalle_Pedido, Id_Lote, Cantidad_Preparada) VALUES (8, 15, 1, 5);
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E01: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50050 PRINT N'OK    E01 RN01 lote vencido: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E01: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E02 - RN02: el lote 11 es de otro producto
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO DETALLE_PICKING (Id_Picking, Id_Detalle_Pedido, Id_Lote, Cantidad_Preparada) VALUES (8, 15, 11, 5);
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E02: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50051 PRINT N'OK    E02 RN02 lote de otro producto: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E02: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E03 - RN02: la línea de pedido 1 no pertenece al pedido del picking 8
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO DETALLE_PICKING (Id_Picking, Id_Detalle_Pedido, Id_Lote, Cantidad_Preparada) VALUES (8, 1, 2, 5);
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E03: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50052 PRINT N'OK    E03 RN02 línea de otro pedido: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E03: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E04 - RN03: preparar más de lo solicitado (ya hay 10 de 10)
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO DETALLE_PICKING (Id_Picking, Id_Detalle_Pedido, Id_Lote, Cantidad_Preparada) VALUES (8, 15, 9, 5);
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E04: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50053 PRINT N'OK    E04 RN03 preparado mayor al solicitado: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E04: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E05 - Trigger sobre varias filas: una fila válida y una inválida en el mismo INSERT.
-- Se rechaza la sentencia completa: no entra ninguna de las dos.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO DETALLE_PICKING (Id_Picking, Id_Detalle_Pedido, Id_Lote, Cantidad_Preparada, Estado_Validacion)
    VALUES (8, 15, 9, 10, 'Rechazada'),    -- válida
           (8, 15, 1, 5,  'Pendiente');    -- lote vencido
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E05: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50050 PRINT N'OK    E05 INSERT de varias filas rechazado completo: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E05: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E06 - RN01: validar a mano una línea cuyo lote venció
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE LOTE SET Fecha_Vencimiento = DATEADD(DAY, -1, CAST(GETDATE() AS DATE)) WHERE Id_Lote = 9;
    UPDATE DETALLE_PICKING SET Estado_Validacion = 'Validada' WHERE Id_Detalle_Picking = 19;
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E06: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50050 PRINT N'OK    E06 RN01 validar línea con lote vencido: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E06: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E07 - RN05: encajar en una caja de otro destino (línea del destino 5 en la caja del destino 1)
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO DETALLE_CAJA (Id_Caja, Id_Detalle_Picking, Cantidad) VALUES (1, 6, 1);
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E07: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50060 PRINT N'OK    E07 RN05 caja de otro destino: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E07: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E08 - RN06: encajar una línea rechazada
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO DETALLE_CAJA (Id_Caja, Id_Detalle_Picking, Cantidad) VALUES (7, 15, 1);
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E08: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50061 PRINT N'OK    E08 RN06 línea no validada: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E08: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E09 - RN06: encajar más de lo preparado (línea 17: 4 preparadas, ya hay 4 encajadas)
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO DETALLE_CAJA (Id_Caja, Id_Detalle_Picking, Cantidad) VALUES (9, 17, 1);
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E09: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50062 PRINT N'OK    E09 RN06 encajado mayor al preparado: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E09: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

/* =====================================================================
   ERRORES CONTROLADOS POR PROCEDIMIENTOS
   ===================================================================== */

-- E10 - RN04: confirmar un picking con líneas pendientes (picking 8)
BEGIN TRY
    EXEC dbo.sp_Confirmar_Picking @Id_Picking = 8;
    PRINT N'FALLA E10: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50012 PRINT N'OK    E10 RN04 picking con líneas pendientes: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E10: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E11 - Confirmar un picking ya confirmado (picking 1)
BEGIN TRY
    EXEC dbo.sp_Confirmar_Picking @Id_Picking = 1;
    PRINT N'FALLA E11: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50011 PRINT N'OK    E11 picking ya confirmado: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E11: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E12 - RN04: confirmar con stock insuficiente (lote 9 con 5 unidades, se necesitan 10).
-- El CHECK de STOCK falla y se deshace TODA la confirmación.
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE STOCK SET Cantidad_Disponible = 5 WHERE Id_Lote = 9;
    EXEC dbo.sp_Validar_Linea_Picking @Id_Detalle_Picking = 19, @Id_Lote_Leido = 9,  @Cantidad_Leida = 10;
    EXEC dbo.sp_Validar_Linea_Picking @Id_Detalle_Picking = 20, @Id_Lote_Leido = 12, @Cantidad_Leida = 20;
    EXEC dbo.sp_Confirmar_Picking @Id_Picking = 8;
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E12: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%chk_Stock_Cantidad%'
        PRINT N'OK    E12 RN04 stock insuficiente, confirmación deshecha: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E12: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E13 - Validar una línea ya validada (línea 1)
BEGIN TRY
    EXEC dbo.sp_Validar_Linea_Picking @Id_Detalle_Picking = 1, @Id_Lote_Leido = 2, @Cantidad_Leida = 20;
    PRINT N'FALLA E13: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50002 PRINT N'OK    E13 línea ya validada: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E13: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E14 - RN05: asignar una caja que ya tiene entrega (caja 8)
BEGIN TRY
    EXEC dbo.sp_Asignar_Caja_Entrega @Id_Caja = 8, @Id_Entrega = 6;
    PRINT N'FALLA E14: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50022 PRINT N'OK    E14 caja ya asignada: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E14: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E15 - Asignar a una entrega que ya salió (entrega 5, En viaje)
BEGIN TRY
    EXEC dbo.sp_Asignar_Caja_Entrega @Id_Caja = 9, @Id_Entrega = 5;
    PRINT N'FALLA E15: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50023 PRINT N'OK    E15 entrega no planificada: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E15: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E16 - RN05: caja y entrega de destinos distintos (caja 9 destino 3, entrega 6 destino 6)
BEGIN TRY
    EXEC dbo.sp_Asignar_Caja_Entrega @Id_Caja = 9, @Id_Entrega = 6;
    PRINT N'FALLA E16: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50024 PRINT N'OK    E16 RN05 destino distinto: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E16: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E17 - Recepción con estado NULL
BEGIN TRY
    EXEC dbo.sp_Registrar_Recepcion_Caja @Id_Caja = 8, @Estado_Recepcion = NULL;
    PRINT N'FALLA E17: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50031 PRINT N'OK    E17 estado de recepción NULL: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E17: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E18 - Recepción ya registrada (caja 1)
BEGIN TRY
    EXEC dbo.sp_Registrar_Recepcion_Caja @Id_Caja = 1, @Estado_Recepcion = 'Recibida';
    PRINT N'FALLA E18: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50032 PRINT N'OK    E18 recepción ya registrada: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E18: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E19 - Recepción de una caja cuya entrega no llegó (caja 8, entrega 5 en viaje)
BEGIN TRY
    EXEC dbo.sp_Registrar_Recepcion_Caja @Id_Caja = 8, @Estado_Recepcion = 'Recibida';
    PRINT N'FALLA E19: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 50034 PRINT N'OK    E19 entrega sin llegada: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E19: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E20 - Trazabilidad de un lote inexistente
BEGIN TRY
    EXEC dbo.sp_Trazabilidad_Lote @Id_Lote = 999;
    PRINT N'FALLA E20: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50040 PRINT N'OK    E20 lote inexistente: ' + ERROR_MESSAGE();
    ELSE PRINT N'FALLA E20: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

/* =====================================================================
   ERRORES CONTROLADOS POR RESTRICCIONES (CHECK, UNIQUE, FK)
   547 = violación de CHECK o FK (se identifica por el nombre de la restricción);
   2627 = violación de UNIQUE.
   ===================================================================== */

-- E21 - RI22: caja rechazada sin motivo (caja 6)
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE CAJA SET Estado_Recepcion = 'Rechazada' WHERE Id_Caja = 6;
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E21: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%chk_Caja_Motivo%'
        PRINT N'OK    E21 RI22 caja rechazada sin motivo';
    ELSE PRINT N'FALLA E21: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E22 - RI22: caja recibida sin entrega asignada (caja 9)
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE CAJA SET Estado_Recepcion = 'Recibida' WHERE Id_Caja = 9;
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E22: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%chk_Caja_Entrega%'
        PRINT N'OK    E22 RI22 caja recibida sin entrega';
    ELSE PRINT N'FALLA E22: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E23 - RI20: temperatura fuera del rango físico
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE CAJA SET Temperatura_Entrega = 60 WHERE Id_Caja = 1;
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E23: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%chk_Caja_Temperatura%'
        PRINT N'OK    E23 RI20 temperatura fuera de rango';
    ELSE PRINT N'FALLA E23: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E24 - RI16: fecha de entrega solicitada anterior a la del pedido
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO PEDIDO (Id_Cliente, Id_Destino, Fecha_Entrega_Solicitada)
    VALUES (1, 1, DATEADD(DAY, -1, CAST(GETDATE() AS DATE)));
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E24: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%chk_Pedido_Fechas%'
        PRINT N'OK    E24 RI16 fecha solicitada anterior al pedido';
    ELSE PRINT N'FALLA E24: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E25 - RI07: pedido de un cliente inexistente
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO PEDIDO (Id_Cliente, Id_Destino, Fecha_Entrega_Solicitada)
    VALUES (999, 1, DATEADD(DAY, 1, CAST(GETDATE() AS DATE)));
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E25: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%fk_Pedido_Cliente%'
        PRINT N'OK    E25 RI07 cliente inexistente';
    ELSE PRINT N'FALLA E25: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E26 - RI02: CUIT duplicado (el de Bayer)
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO CLIENTE (Razon_Social, Cuit, Id_Tipo_Cliente) VALUES (N'Duplicado S.A.', '30500012341', 1);
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E26: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 2627 PRINT N'OK    E26 RI02 CUIT duplicado';
    ELSE PRINT N'FALLA E26: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

-- E27 - RI21: CUIT con letras
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO CLIENTE (Razon_Social, Cuit, Id_Tipo_Cliente) VALUES (N'Prueba S.A.', '30A00012341', 1);
    ROLLBACK TRANSACTION;
    PRINT N'FALLA E27: no se produjo el error esperado';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%chk_Cliente_Cuit%'
        PRINT N'OK    E27 RI21 CUIT con letras';
    ELSE PRINT N'FALLA E27: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE();
END CATCH
GO

/* =====================================================================
   CONTROL FINAL: las pruebas no dejaron cambios
   Esperado: 20 líneas de picking, 8 pickings, 10 cajas, 6 entregas,
   stock lote 9 = 54 y lote 2 = 750, pedido 10 Recibido y pedido 8 En preparación.
   ===================================================================== */
SELECT (SELECT COUNT(*) FROM DETALLE_PICKING)                          AS Lineas_Picking,
       (SELECT COUNT(*) FROM PICKING)                                  AS Pickings,
       (SELECT COUNT(*) FROM CAJA)                                     AS Cajas,
       (SELECT COUNT(*) FROM ENTREGA)                                  AS Entregas,
       (SELECT Cantidad_Disponible FROM STOCK WHERE Id_Lote = 9)       AS Stock_Lote_9,
       (SELECT Cantidad_Disponible FROM STOCK WHERE Id_Lote = 2)       AS Stock_Lote_2,
       (SELECT Estado FROM PEDIDO WHERE Id_Pedido = 10)                AS Estado_Pedido_10,
       (SELECT Estado FROM PEDIDO WHERE Id_Pedido = 8)                 AS Estado_Pedido_8;
GO