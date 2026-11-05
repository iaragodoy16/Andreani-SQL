/*
    Script 08 - Consultas de negocio e indicadores (KPI)
    Los KPI se leen desde sus vistas (script 05): la lógica de cálculo queda en un
    solo lugar y la consulta solo la presenta.
    Los resultados esperados en cada comentario corresponden a los datos del 03.
    Las fechas son relativas a hoy, por eso los resultados no dependen del día de ejecución
    (salvo la apertura por mes de la pregunta 1).
    Las consultas que reciben un dato concreto (pedido 3, lote 8, caja 4, destino 5)
    usan valores de ejemplo: se cambian en el WHERE.
*/
USE Andreani;
GO

/* =====================================================================
   PEDIDOS Y CUMPLIMIENTO  (Operaciones, Logística y Dirección)
   ===================================================================== */

-- P1. ¿Cuántos pedidos se recibieron por período, cliente y destino?
-- Esperado: 12 pedidos en total. Por cliente: Bayer 3, Roche 3, Pfizer 2, Bagó 2, Droguería del Sud 2.
SELECT YEAR(p.Fecha_Pedido)  AS Anio,
       MONTH(p.Fecha_Pedido) AS Mes,
       c.Razon_Social        AS Cliente,
       d.Nombre_Destino      AS Destino,
       COUNT(*)              AS Cantidad_Pedidos
FROM PEDIDO p
INNER JOIN CLIENTE c ON c.Id_Cliente = p.Id_Cliente
INNER JOIN DESTINO d ON d.Id_Destino = p.Id_Destino
GROUP BY YEAR(p.Fecha_Pedido), MONTH(p.Fecha_Pedido), c.Razon_Social, d.Nombre_Destino
ORDER BY Anio, Mes, Cliente, Destino;

-- P2. ¿Qué pedidos están pendientes y cuáles superaron la fecha solicitada sin entregarse completos?
-- Pendiente = ni Entregado ni Cancelado.
-- Esperado: 6 filas (pedidos 6, 7, 8, 10, 11 y 12). Atrasados: 12 (8 días) y 6 (3 días).
SELECT p.Id_Pedido,
       c.Razon_Social             AS Cliente,
       d.Nombre_Destino           AS Destino,
       p.Fecha_Entrega_Solicitada,
       p.Estado,
       CASE WHEN p.Fecha_Entrega_Solicitada < CAST(GETDATE() AS DATE)
            THEN 'Atrasado' ELSE 'En plazo' END AS Situacion,
       CASE WHEN p.Fecha_Entrega_Solicitada < CAST(GETDATE() AS DATE)
            THEN DATEDIFF(DAY, p.Fecha_Entrega_Solicitada, CAST(GETDATE() AS DATE))
            ELSE 0 END             AS Dias_Atraso
FROM PEDIDO p
INNER JOIN CLIENTE c ON c.Id_Cliente = p.Id_Cliente
INNER JOIN DESTINO d ON d.Id_Destino = p.Id_Destino
WHERE p.Estado NOT IN ('Entregado', 'Cancelado')
ORDER BY Dias_Atraso DESC, p.Fecha_Entrega_Solicitada;

-- P3 / KPI 1. ¿Qué porcentaje de pedidos se entregó completo dentro de la fecha comprometida?
-- Esperado: 7 evaluados, 4 a tiempo, 57.1
SELECT Pedidos_Evaluados, Pedidos_A_Tiempo, Porcentaje_A_Tiempo
FROM vw_Kpi_Entregas_A_Tiempo;

-- Detalle del KPI 1: qué pedido entra en cada grupo.
-- Esperado: 1, 2, 3 y 5 A tiempo | 4 Tarde | 6 y 12 No entregado
SELECT p.Id_Pedido,
       p.Fecha_Entrega_Solicitada,
       CAST(dbo.fn_Fecha_Entrega_Pedido(p.Id_Pedido) AS DATE) AS Fecha_Entrega_Real,
       CASE WHEN dbo.fn_Fecha_Entrega_Pedido(p.Id_Pedido) IS NULL THEN 'No entregado'
            WHEN CAST(dbo.fn_Fecha_Entrega_Pedido(p.Id_Pedido) AS DATE) <= p.Fecha_Entrega_Solicitada
                 THEN 'A tiempo'
            ELSE 'Tarde' END AS Resultado
FROM PEDIDO p
WHERE p.Estado <> 'Cancelado'
  AND p.Fecha_Entrega_Solicitada < CAST(GETDATE() AS DATE)
ORDER BY p.Id_Pedido;

/* =====================================================================
   PREPARACIÓN Y STOCK  (Depósito y Mejora Continua)
   ===================================================================== */

-- P4. ¿Qué productos se pidieron en un pedido y con qué lotes se preparó cada línea?
-- LEFT JOIN: muestra también las líneas de pedido todavía sin preparar.
-- Esperado (pedido 3): 4 filas. Vacuna VA-2403 6 Rechazada y 6 Validada;
--                     Atorvastatina AT-2311 10 y AT-2408 5 (una línea cubierta por dos lotes).
SELECT dp.Id_Detalle_Pedido,
       pr.Nombre               AS Producto,
       dp.Cantidad_Solicitada,
       dpk.Id_Detalle_Picking,
       l.Numero_Lote,
       l.Fecha_Vencimiento,
       dpk.Cantidad_Preparada,
       dpk.Estado_Validacion
FROM DETALLE_PEDIDO dp
INNER JOIN PRODUCTO pr       ON pr.Id_Producto = dp.Id_Producto
LEFT JOIN DETALLE_PICKING dpk ON dpk.Id_Detalle_Pedido = dp.Id_Detalle_Pedido
LEFT JOIN LOTE l             ON l.Id_Lote = dpk.Id_Lote
WHERE dp.Id_Pedido = 3                       -- pedido a consultar
ORDER BY dp.Id_Detalle_Pedido, dpk.Id_Detalle_Picking;

-- P5. ¿Qué pedidos se prepararon con cantidades distintas a las solicitadas?
-- Compara lo solicitado con lo validado, en pickings confirmados.
-- El CASE suma 0 para las líneas rechazadas y para las líneas sin preparar (LEFT JOIN).
-- Esperado: 0 filas. Todos los pickings confirmados quedaron completos;
-- el exceso lo impide RN03 (trigger) y el faltante se detectaría con esta consulta.
SELECT p.Id_Pedido,
       dp.Id_Detalle_Pedido,
       pr.Nombre AS Producto,
       dp.Cantidad_Solicitada,
       SUM(CASE WHEN dpk.Estado_Validacion = 'Validada'
                THEN dpk.Cantidad_Preparada ELSE 0 END) AS Cantidad_Preparada
FROM DETALLE_PEDIDO dp
INNER JOIN PEDIDO p           ON p.Id_Pedido = dp.Id_Pedido
INNER JOIN PICKING pk         ON pk.Id_Pedido = p.Id_Pedido
INNER JOIN PRODUCTO pr        ON pr.Id_Producto = dp.Id_Producto
LEFT JOIN DETALLE_PICKING dpk ON dpk.Id_Detalle_Pedido = dp.Id_Detalle_Pedido
WHERE pk.Estado = 'Confirmado'
GROUP BY p.Id_Pedido, dp.Id_Detalle_Pedido, pr.Nombre, dp.Cantidad_Solicitada
HAVING SUM(CASE WHEN dpk.Estado_Validacion = 'Validada'
                THEN dpk.Cantidad_Preparada ELSE 0 END) <> dp.Cantidad_Solicitada
ORDER BY p.Id_Pedido, dp.Id_Detalle_Pedido;

-- P6 / KPI 2. ¿Qué porcentaje de pickings tuvo líneas rechazadas y qué operarios concentran más rechazos?
-- Esperado: Martín 3/1/33.3 | Lucía 2/0/0.0 | Diego 2/2/100.0 | TOTAL 7/3/42.9 (TOTAL al final)
SELECT Operario, Pickings_Confirmados, Pickings_Con_Rechazo, Porcentaje_Errores
FROM vw_Kpi_Errores_Picking
ORDER BY CASE WHEN Id_Operario IS NULL THEN 1 ELSE 0 END, Id_Operario;

-- Detalle: líneas rechazadas por operario.
-- Esperado: Diego Ramírez 2 | Martín Gómez 1
SELECT o.Legajo,
       o.Nombre + N' ' + o.Apellido AS Operario,
       COUNT(*)                     AS Lineas_Rechazadas
FROM DETALLE_PICKING dpk
INNER JOIN PICKING pk  ON pk.Id_Picking = dpk.Id_Picking
INNER JOIN OPERARIO o  ON o.Id_Operario = pk.Id_Operario
WHERE dpk.Estado_Validacion = 'Rechazada'
GROUP BY o.Legajo, o.Nombre, o.Apellido
ORDER BY Lineas_Rechazadas DESC;

-- P7. ¿Qué lotes vencen en los próximos días y cuánto stock representan? ¿Hay stock de lotes vencidos?
-- Esperado: 6 filas. Vencidos: 1 (-30 días, 120 u.), 7 (-10, 150), 13 (-5, 50).
--           Próximos: 11 (35 días, 290 u.), 3 (45, 190), 5 (50, 35).
SELECT Id_Lote, Numero_Lote, Producto, Fecha_Vencimiento,
       Dias_Para_Vencer, Cantidad_Disponible, Situacion
FROM vw_Lotes_Proximos_Vencer
WHERE Situacion <> N'Vigente' --N para coherencia con la viste que admite otros valores especiales
ORDER BY Fecha_Vencimiento;

-- Resumen de stock por situación.
-- Esperado: Vencido 3 lotes / 320 u. | Próximo a vencer 3 / 515 | Vigente 13 / 5930
SELECT Situacion,
       COUNT(*)                 AS Lotes,
       SUM(Cantidad_Disponible) AS Unidades
FROM vw_Lotes_Proximos_Vencer
GROUP BY Situacion
ORDER BY MIN(Dias_Para_Vencer);

/* =====================================================================
   TRAZABILIDAD Y ENTREGA  (Calidad, Auditoría y Planeamiento)
   ===================================================================== */

-- P8. Ante un retiro sanitario, ¿quiénes recibieron unidades de un lote y cuáles fueron recibidas?
-- Recorrido completo del lote (consulta central del proyecto).
-- Esperado (lote 8): 2 filas. Pedido 2, caja 2, entrega 1, Recibida | pedido 7, caja 9, sin entrega, Pendiente
EXEC dbo.sp_Trazabilidad_Lote @Id_Lote = 8;

-- Resumen para el retiro: unidades del lote según su estado de recepción.
-- Esperado (lote 8): Recibida 12 u. | Pendiente 20 u.
SELECT Estado_Recepcion,
       COUNT(*)               AS Cajas,
       SUM(Cantidad_Encajada) AS Unidades
FROM vw_Trazabilidad_Lote
WHERE Id_Lote = 8                            -- lote a consultar
GROUP BY Estado_Recepcion;

-- P9 (a). ¿Qué productos y lotes contiene una caja?
-- Esperado (caja 4): 3 filas. Pedido 3 Atorvastatina AT-2311 10 y AT-2408 5 | pedido 4 Enalapril L-1001 25
SELECT dc.Id_Caja,
       pk.Id_Pedido,
       pr.Nombre       AS Producto,
       l.Numero_Lote,
       l.Fecha_Vencimiento,
       dc.Cantidad
FROM DETALLE_CAJA dc
INNER JOIN DETALLE_PICKING dpk ON dpk.Id_Detalle_Picking = dc.Id_Detalle_Picking
INNER JOIN PICKING pk          ON pk.Id_Picking = dpk.Id_Picking
INNER JOIN LOTE l              ON l.Id_Lote = dpk.Id_Lote
INNER JOIN PRODUCTO pr         ON pr.Id_Producto = l.Id_Producto
WHERE dc.Id_Caja = 4                         -- caja a consultar
ORDER BY pk.Id_Pedido, pr.Nombre;

-- P9 (b). ¿Qué cajas se enviaron a un destino?
-- Esperado (destino 5, Farmacia Palermo Salud): cajas 3 y 4, entrega 2, Recibidas
SELECT c.Id_Caja,
       c.Codigo_QR,
       c.Fecha_Consolidacion,
       c.Id_Entrega,
       e.Fecha_Hora_Entrega,
       c.Estado_Recepcion
FROM CAJA c
LEFT JOIN ENTREGA e ON e.Id_Entrega = c.Id_Entrega   -- LEFT: incluye cajas aún no despachadas
WHERE c.Id_Destino = 5                               -- destino a consultar
ORDER BY c.Id_Caja;

-- P10. ¿Qué cajas fueron rechazadas, en qué destinos y por qué motivo?
-- Esperado: 1 fila. Caja 7, Farmacia Cordobesa, entrega 4, "Embalaje dañado al momento de la recepción"
SELECT c.Id_Caja,
       c.Codigo_QR,
       d.Nombre_Destino AS Destino,
       c.Id_Entrega,
       e.Fecha_Hora_Entrega,
       c.Motivo_Rechazo
FROM CAJA c
INNER JOIN DESTINO d ON d.Id_Destino = c.Id_Destino
LEFT JOIN ENTREGA e  ON e.Id_Entrega = c.Id_Entrega
WHERE c.Estado_Recepcion = 'Rechazada'
ORDER BY e.Fecha_Hora_Entrega DESC;

-- P11 / KPI 3. ¿Cuántos pedidos distintos se consolidan en promedio por caja?
-- Esperado: 10 cajas, 1.40
SELECT Cajas_Consolidadas, Indice_Consolidacion
FROM vw_Kpi_Consolidacion;

-- Detalle del KPI 3: pedidos distintos por caja.
-- Esperado: cajas 1, 2, 3 y 4 = 2 pedidos | el resto = 1
SELECT dc.Id_Caja,
       c.Id_Destino,
       COUNT(DISTINCT pk.Id_Pedido) AS Pedidos_Distintos
FROM DETALLE_CAJA dc
INNER JOIN CAJA c              ON c.Id_Caja = dc.Id_Caja
INNER JOIN DETALLE_PICKING dpk ON dpk.Id_Detalle_Picking = dc.Id_Detalle_Picking
INNER JOIN PICKING pk          ON pk.Id_Picking = dpk.Id_Picking
GROUP BY dc.Id_Caja, c.Id_Destino
ORDER BY Pedidos_Distintos DESC, dc.Id_Caja;
GO