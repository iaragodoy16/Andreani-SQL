/*
    Script 07 - Triggers
    Se usan triggers solo para reglas que comparan varias tablas y deben aplicarse
    sobre CUALQUIER inserción o modificación, venga de un procedimiento o de un
    INSERT directo. Las reglas de una sola fila se resuelven con CHECK.

    Criterios de diseño:
      - AFTER INSERT, UPDATE: el trigger se ejecuta DESPUÉS de que la fila quedó grabada
        y, si la regla se viola, deshace la operación con ROLLBACK.
      - Un trigger se ejecuta UNA VEZ por sentencia, no una vez por fila: un INSERT
        de varias filas llega con todas ellas en la tabla inserted. Por eso cada
        control se escribe sobre el conjunto completo (EXISTS sobre inserted) y no
        sobre una sola fila.
      - ROLLBACK TRANSACTION deshace la sentencia y la transacción que la contenía.
        Luego THROW devuelve el error a quien ejecutó la operación.
      - Códigos de error: 50050-50053 trg_Detalle_Picking_Ins (RN01 a RN03)
                          50060-50062 trg_Detalle_Caja_Ins (RN05 y RN06)
        Siguen el criterio del 06: un bloque de 10 números por objeto, desde 50000
        (los números menores están reservados para errores del sistema).
*/
USE Andreani;
GO

/* ---------------------------------------------------------------------
   trg_Detalle_Picking_Ins  (RN01, RN02, RN03)
   Controla cada línea de picking que se inserta o modifica:
     RN01: el lote no puede estar vencido (vence hoy o antes = vencido).
           Se controla en un INSERT, si en un UPDATE cambia el lote, o si la línea
           pasa a 'Validada'. No aplica a una línea 'Rechazada': el rechazo registra
           el error (incluso haber leído un lote vencido) y no mueve stock.
           Así un lote que vence mientras la línea espera no traba el picking, ni
           bloquea modificaciones posteriores sobre líneas ya confirmadas.
     RN02: el lote debe ser del producto de la línea de pedido que se prepara,
           y esa línea debe pertenecer al pedido del picking.
     RN03: lo preparado de una línea de pedido (sin contar líneas rechazadas)
           no puede superar lo solicitado.
   En un INSERT la tabla deleted está vacía: por eso el LEFT JOIN deja
   d.Id_Detalle_Picking en NULL, y esa condición identifica que es un INSERT.
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_Detalle_Picking_Ins
ON DETALLE_PICKING
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- RN01: lote vencido
    IF EXISTS (SELECT 1
               FROM inserted i
               INNER JOIN LOTE l ON l.Id_Lote = i.Id_Lote
               LEFT JOIN deleted d ON d.Id_Detalle_Picking = i.Id_Detalle_Picking
               WHERE l.Fecha_Vencimiento <= CAST(GETDATE() AS DATE)
                 AND i.Estado_Validacion <> 'Rechazada'
                 AND (d.Id_Detalle_Picking IS NULL                     -- es un INSERT
                      OR d.Id_Lote <> i.Id_Lote                        -- cambió el lote
                      OR (i.Estado_Validacion = 'Validada'
                          AND d.Estado_Validacion <> 'Validada')))     -- se está validando
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50050, N'RN01: no se puede asignar un lote vencido a una línea de picking.', 1;
    END;

    -- RN02 (a): el producto del lote debe coincidir con el de la línea de pedido
    IF EXISTS (SELECT 1
               FROM inserted i
               INNER JOIN LOTE l            ON l.Id_Lote = i.Id_Lote
               INNER JOIN DETALLE_PEDIDO dp ON dp.Id_Detalle_Pedido = i.Id_Detalle_Pedido
               WHERE l.Id_Producto <> dp.Id_Producto)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50051, N'RN02: el lote no corresponde al producto de la línea de pedido.', 1;
    END;

    -- RN02 (b): la línea de pedido debe pertenecer al pedido del picking
    IF EXISTS (SELECT 1
               FROM inserted i
               INNER JOIN DETALLE_PEDIDO dp ON dp.Id_Detalle_Pedido = i.Id_Detalle_Pedido
               INNER JOIN PICKING pk        ON pk.Id_Picking = i.Id_Picking
               WHERE dp.Id_Pedido <> pk.Id_Pedido)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50052, N'RN02: la línea de pedido no pertenece al pedido del picking.', 1;
    END;

    -- RN03: lo preparado (sin rechazadas) no puede superar lo solicitado
    IF EXISTS (SELECT 1
               FROM DETALLE_PEDIDO dp
               WHERE dp.Id_Detalle_Pedido IN (SELECT Id_Detalle_Pedido FROM inserted)
                 AND (SELECT SUM(d.Cantidad_Preparada)
                      FROM DETALLE_PICKING d
                      WHERE d.Id_Detalle_Pedido = dp.Id_Detalle_Pedido
                        AND d.Estado_Validacion <> 'Rechazada') > dp.Cantidad_Solicitada)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50053, N'RN03: la cantidad preparada supera la cantidad solicitada.', 1;
    END;
END;
GO

/* ---------------------------------------------------------------------
   trg_Detalle_Caja_Ins  (RN05, RN06)
   Controla cada línea que se encaja en una caja:
     RN05: el destino del pedido de la línea debe coincidir con el de la caja
           (una caja solo contiene unidades de pedidos con su mismo destino).
           El control caja-entrega lo hace sp_Asignar_Caja_Entrega.
     RN06: solo se encajan líneas Validadas de pickings Confirmados, y lo
           encajado de una línea (sumando todas sus cajas) no puede superar
           lo preparado.
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_Detalle_Caja_Ins
ON DETALLE_CAJA
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- RN05: destino del pedido = destino de la caja
    IF EXISTS (SELECT 1
               FROM inserted i
               INNER JOIN CAJA c              ON c.Id_Caja = i.Id_Caja
               INNER JOIN DETALLE_PICKING dpk ON dpk.Id_Detalle_Picking = i.Id_Detalle_Picking
               INNER JOIN PICKING pk          ON pk.Id_Picking = dpk.Id_Picking
               INNER JOIN PEDIDO p            ON p.Id_Pedido = pk.Id_Pedido
               WHERE p.Id_Destino <> c.Id_Destino)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50060, N'RN05: el destino del pedido no coincide con el destino de la caja.', 1;
    END;

    -- RN06 (a): línea validada de un picking confirmado
    IF EXISTS (SELECT 1
               FROM inserted i
               INNER JOIN DETALLE_PICKING dpk ON dpk.Id_Detalle_Picking = i.Id_Detalle_Picking
               INNER JOIN PICKING pk          ON pk.Id_Picking = dpk.Id_Picking
               WHERE dpk.Estado_Validacion <> 'Validada'
                  OR pk.Estado <> 'Confirmado')
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50061, N'RN06: solo se encajan líneas validadas de pickings confirmados.', 1;
    END;

    -- RN06 (b): lo encajado no puede superar lo preparado
    IF EXISTS (SELECT 1
               FROM DETALLE_PICKING dpk
               WHERE dpk.Id_Detalle_Picking IN (SELECT Id_Detalle_Picking FROM inserted)
                 AND (SELECT SUM(dc.Cantidad)
                      FROM DETALLE_CAJA dc
                      WHERE dc.Id_Detalle_Picking = dpk.Id_Detalle_Picking) > dpk.Cantidad_Preparada)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50062, N'RN06: la cantidad encajada supera la cantidad preparada.', 1;
    END;
END;
GO