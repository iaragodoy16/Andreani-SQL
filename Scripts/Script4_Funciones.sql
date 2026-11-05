/*
    Script 04 - Funciones definidas por el usuario
    Ambas son funciones escalares
    Se resuelven como función y no se almacenan como columna porque
    son datos derivados,guardarlos generaría redundancia.
    CREATE OR ALTER permite volver a ejecutar el script.
*/
USE Andreani;
GO

/* ---------------------------------------------------------------------
   fn_Fecha_Entrega_Pedido
   Devuelve la fecha y hora en que un pedido quedó entregado completo.

   Decisión de diseño: la caja no tiene fecha de recepción propia, así que la
   fecha sale de ENTREGA.Fecha_Hora_Entrega de la entrega que transportó cada caja.
   Un pedido está entregado cuando TODAS sus cajas fueron recibidas
   Devuelve:
     - la fecha de la última entrega, si todas las cajas del pedido están
       'Recibida' y tienen entrega con fecha de llegada;
     - NULL en cualquier otro caso: pedido sin cajas (aún sin picking o sin
       consolidar), alguna caja Pendiente o Rechazada, o caja sin entrega.
   Camino de datos: PICKING -> DETALLE_PICKING -> DETALLE_CAJA -> CAJA -> ENTREGA.
   Limitación conocida: considera solo las cajas ya armadas; si quedaran líneas
   validadas sin encajar, el pedido podría figurar como entregado antes de tiempo.
   Se usa en el KPI 1 (vw_Kpi_Entregas_A_Tiempo).
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_Fecha_Entrega_Pedido (@Id_Pedido INT)
RETURNS DATETIME2(0)
AS
BEGIN
    DECLARE @Fecha_Entrega DATETIME2(0);

    SELECT @Fecha_Entrega =
        CASE
            -- Con cajas, y ninguna "mala" (no recibida o sin fecha de llegada)
            WHEN COUNT(*) > 0
             AND SUM(CASE WHEN c.Estado_Recepcion = 'Recibida'
                           AND e.Fecha_Hora_Entrega IS NOT NULL
                          THEN 0 ELSE 1 END) = 0
            THEN MAX(e.Fecha_Hora_Entrega)
            ELSE NULL
        END
    FROM PICKING pk
    INNER JOIN DETALLE_PICKING dpk ON dpk.Id_Picking = pk.Id_Picking
    INNER JOIN DETALLE_CAJA dc ON dc.Id_Detalle_Picking = dpk.Id_Detalle_Picking
    INNER JOIN CAJA c ON c.Id_Caja = dc.Id_Caja
    LEFT JOIN ENTREGA e ON e.Id_Entrega = c.Id_Entrega   -- LEFT: la caja puede no tener entrega
    WHERE pk.Id_Pedido = @Id_Pedido;

    RETURN @Fecha_Entrega;
END;
GO

/* ---------------------------------------------------------------------
   fn_Dias_Para_Vencer
   Devuelve los días que faltan para el vencimiento de un lote, contando desde hoy.
   Positivo: días restantes. Cero: vence hoy. Negativo: ya está vencido.
   Se usa en vw_Lotes_Proximos_Vencer para mostrar los días
   restantes y señalar los vencidos, como apoyo al criterio FEFO.
   Se calcula con la fecha actual cada vez, por eso no se almacena.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_Dias_Para_Vencer (@Fecha_Vencimiento DATE)
RETURNS INT
AS
BEGIN
    RETURN DATEDIFF(DAY, CAST(GETDATE() AS DATE), @Fecha_Vencimiento);
END;
GO

