/* Script 05 - Vistas
   vw_Kpi_Entregas_A_Tiempo usa fn_Fecha_Entrega_Pedido y vw_Lotes_Proximos_Vencer usa fn_Dias_Para_Vencer.
   Las vistas simplifican y reutilizan las consultas más importantes del TP.
   Las vistas de trazabilidad e indicadores son lo único que vería el perfil Auditor.
   Una vista no garantiza orden: el ORDER BY se pone al consultarla.
   CREATE OR ALTER VIEW debe ser la primera sentencia del lote, por eso lleva GO.
*/
USE Andreani;
GO

/* ---------------------------------------------------------------------
   vw_Trazabilidad_Lote (consulta central del TP, RF13, pregunta 8 y 9)
   Una fila por cada línea de picking encajada de un lote. 
   Uso: SELECT * FROM vw_Trazabilidad_Lote WHERE Id_Lote = 2;
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_Trazabilidad_Lote
AS
SELECT
    l.Id_Lote,
    l.Numero_Lote,
    l.Fecha_Vencimiento,
    pr.Codigo_Producto,
    pr.Nombre AS Producto,
    cp.Razon_Social AS Cliente_Propietario,
    pe.Id_Pedido,
    cl.Razon_Social AS Cliente_Pedido,
    d.Nombre_Destino AS Destino_Pedido,
    dpk.Id_Detalle_Picking,
    dpk.Cantidad_Preparada,
    dpk.Estado_Validacion,
    c.Id_Caja,
    c.Codigo_QR,
    dc.Cantidad AS Cantidad_Encajada,
    c.Estado_Recepcion,
    c.Motivo_Rechazo,
    e.Id_Entrega,
    v.Patente AS Vehiculo,
    co.Apellido + N', ' + co.Nombre AS Conductor,
    e.Fecha_Hora_Salida,
    e.Fecha_Hora_Entrega
FROM LOTE l
INNER JOIN DETALLE_PICKING dpk ON dpk.Id_Lote = l.Id_Lote
INNER JOIN DETALLE_PEDIDO dp ON dp.Id_Detalle_Pedido = dpk.Id_Detalle_Pedido
INNER JOIN PEDIDO pe ON pe.Id_Pedido = dp.Id_Pedido
INNER JOIN PRODUCTO pr ON pr.Id_Producto = l.Id_Producto
INNER JOIN CLIENTE cp ON cp.Id_Cliente = pr.Id_Cliente_Propietario
INNER JOIN CLIENTE cl ON cl.Id_Cliente = pe.Id_Cliente
INNER JOIN DESTINO d ON d.Id_Destino = pe.Id_Destino
INNER JOIN DETALLE_CAJA dc ON dc.Id_Detalle_Picking = dpk.Id_Detalle_Picking
INNER JOIN CAJA c ON c.Id_Caja = dc.Id_Caja
LEFT JOIN ENTREGA e ON e.Id_Entrega = c.Id_Entrega
LEFT JOIN VEHICULO v ON v.Id_Vehiculo = e.Id_Vehiculo
LEFT JOIN CONDUCTOR co ON co.Id_Conductor = e.Id_Conductor;
GO

/* ---------------------------------------------------------------------
   vw_Kpi_Entregas_A_Tiempo (KPI 1)
   Porcentaje de pedidos entregados completos en la fecha solicitada o antes.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_Kpi_Entregas_A_Tiempo
AS
WITH Pedidos_Con_Entrega AS (
    SELECT p.Id_Pedido,
           p.Fecha_Entrega_Solicitada,
           CAST(dbo.fn_Fecha_Entrega_Pedido(p.Id_Pedido) AS DATE) AS Fecha_Entrega
    FROM PEDIDO p
    WHERE p.Estado <> 'Cancelado'
      AND p.Fecha_Entrega_Solicitada < CAST(GETDATE() AS DATE)
),
Pedidos_Vencidos AS (
    SELECT Id_Pedido,
           CASE WHEN Fecha_Entrega IS NOT NULL AND Fecha_Entrega <= Fecha_Entrega_Solicitada THEN 1 ELSE 0 END AS A_Tiempo
    FROM Pedidos_Con_Entrega
)
SELECT COUNT(*) AS Pedidos_Evaluados,
       SUM(A_Tiempo) AS Pedidos_A_Tiempo,
       CAST(CASE WHEN COUNT(*) = 0 THEN NULL ELSE 100.0 * SUM(A_Tiempo) / COUNT(*) END AS DECIMAL(5,1)) AS Porcentaje_A_Tiempo
FROM Pedidos_Vencidos;
GO

/* ---------------------------------------------------------------------
   vw_Kpi_Errores_Picking (KPI 2)
   Porcentaje de pickings confirmados con al menos una línea Rechazada.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_Kpi_Errores_Picking
AS
WITH Por_Picking AS (
    SELECT
        pk.Id_Picking,
        pk.Id_Operario,
        CASE WHEN EXISTS (SELECT 1 FROM DETALLE_PICKING d WHERE d.Id_Picking = pk.Id_Picking AND d.Estado_Validacion = 'Rechazada') THEN 1 ELSE 0 END AS Con_Rechazo
    FROM PICKING pk
    WHERE pk.Estado = 'Confirmado'
)
SELECT
    o.Id_Operario,
    CAST(o.Nombre + N' ' + o.Apellido AS NVARCHAR(130)) AS Operario,
    COUNT(*) AS Pickings_Confirmados,
    SUM(pp.Con_Rechazo) AS Pickings_Con_Rechazo,
    CAST(100.0 * SUM(pp.Con_Rechazo) / COUNT(*) AS DECIMAL(5,1)) AS Porcentaje_Errores
FROM Por_Picking pp
INNER JOIN OPERARIO o ON o.Id_Operario = pp.Id_Operario
GROUP BY o.Id_Operario, o.Nombre, o.Apellido
UNION ALL
SELECT
    NULL,
    N'TOTAL',
    COUNT(*),
    SUM(Con_Rechazo),
    CAST(100.0 * SUM(Con_Rechazo) / NULLIF(COUNT(*), 0) AS DECIMAL(5,1))
FROM Por_Picking;
GO

/* ---------------------------------------------------------------------
   vw_Kpi_Consolidacion (KPI 3)
   Promedio de pedidos distintos por caja.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_Kpi_Consolidacion
AS
WITH Pedidos_Por_Caja AS (
    SELECT
        dc.Id_Caja,
        COUNT(DISTINCT pk.Id_Pedido) AS Pedidos_Distintos
    FROM DETALLE_CAJA dc
    INNER JOIN DETALLE_PICKING dpk ON dpk.Id_Detalle_Picking = dc.Id_Detalle_Picking
    INNER JOIN PICKING pk ON pk.Id_Picking = dpk.Id_Picking
    GROUP BY dc.Id_Caja
)
SELECT
    COUNT(*) AS Cajas_Consolidadas,
    CAST(AVG(CAST(Pedidos_Distintos AS DECIMAL(5,2))) AS DECIMAL(5,2)) AS Indice_Consolidacion
FROM Pedidos_Por_Caja;
GO

/* ---------------------------------------------------------------------
   vw_Lotes_Proximos_Vencer (RF14)
   Lotes con stock disponible clasificados según días para vencer.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_Lotes_Proximos_Vencer
AS
SELECT
    l.Id_Lote,
    l.Numero_Lote,
    pr.Nombre AS Producto,
    cp.Razon_Social AS Cliente_Propietario,
    l.Fecha_Vencimiento,
    dbo.fn_Dias_Para_Vencer(l.Fecha_Vencimiento) AS Dias_Para_Vencer,
    s.Cantidad_Disponible,
    CASE
        WHEN dbo.fn_Dias_Para_Vencer(l.Fecha_Vencimiento) < 0  THEN N'Vencido'
        WHEN dbo.fn_Dias_Para_Vencer(l.Fecha_Vencimiento) <= 60 THEN N'Próximo a vencer'
        ELSE N'Vigente'
    END AS Situacion
FROM LOTE l
INNER JOIN STOCK s ON s.Id_Lote = l.Id_Lote
INNER JOIN PRODUCTO pr ON pr.Id_Producto = l.Id_Producto
INNER JOIN CLIENTE cp ON cp.Id_Cliente = pr.Id_Cliente_Propietario
WHERE s.Cantidad_Disponible > 0;
GO