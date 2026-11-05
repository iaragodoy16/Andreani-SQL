/*
    Script 06 - Procedimientos almacenados
   
      - SET NOCOUNT ON: evita enviar el conteo de filas afectadas en cada sentencia.
      - SET XACT_ABORT ON: ante un error, SQL Server deshace la transacción completa.
      - THROW: devuelve el error a quien llamó al procedimiento y corta la ejecución
        (a diferencia de PRINT ERROR_MESSAGE(), que solo muestra el mensaje).
        Códigos propios desde 50001.
      - En los procedimientos con transacción, las validaciones van dnetro de la
        transacción, para que nadie cambie el estado entre el control y la modificación.
*/
USE Andreani;
GO

/* ---------------------------------------------------------------------
   sp_Validar_Linea_Picking
   Simula la lectura con el lector de códigos: recibe la línea de picking, el lote
   leído y la cantidad leída. Si coinciden con lo registrado, la línea queda
   'Validada'; si no, 'Rechazada'. La línea rechazada no se borra: queda como
   evidencia del error y alimenta el KPI 2. La corrección se registra como una
   línea nueva.
   Solo se valida una línea 'Pendiente' de un picking 'En curso'.
   Si el lote o la cantidad leídos llegan en NULL, la comparación no es verdadera
   y la línea queda 'Rechazada': una lectura vacía se rechaza.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_Validar_Linea_Picking
    @Id_Detalle_Picking INT,
    @Id_Lote_Leido      INT,
    @Cantidad_Leida     INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Vencimiento     DATE;    
    DECLARE @Id_Lote         INT;
    DECLARE @Cantidad        INT;
    DECLARE @Estado_Linea    VARCHAR(10);
    DECLARE @Estado_Picking  VARCHAR(20);
    DECLARE @Resultado       VARCHAR(10);

    SELECT @Id_Lote        = dpk.Id_Lote,
           @Cantidad       = dpk.Cantidad_Preparada,
           @Estado_Linea   = dpk.Estado_Validacion,
           @Estado_Picking = pk.Estado,
           @Vencimiento    = l.Fecha_Vencimiento
    FROM DETALLE_PICKING dpk
    INNER JOIN PICKING pk ON pk.Id_Picking = dpk.Id_Picking
    INNER JOIN LOTE l     ON l.Id_Lote = dpk.Id_Lote 
    WHERE dpk.Id_Detalle_Picking = @Id_Detalle_Picking;

    IF @Id_Lote IS NULL
        THROW 50001, N'La línea de picking indicada no existe.', 1;
    IF @Estado_Linea <> 'Pendiente'
        THROW 50002, N'La línea ya fue validada o rechazada.', 1;
    IF @Estado_Picking <> 'En curso'
        THROW 50003, N'El picking de la línea no está en curso.', 1;

    -- Coincide el lote y la cantidad leídos con lo registrado: Validada; si no, Rechazada
    SET @Resultado = CASE WHEN @Id_Lote_Leido = @Id_Lote AND @Cantidad_Leida = @Cantidad
                          AND @Vencimiento > CAST(GETDATE() AS DATE)
                          THEN 'Validada' ELSE 'Rechazada' END;

    UPDATE DETALLE_PICKING
    SET Estado_Validacion     = @Resultado,
        Fecha_Hora_Validacion = SYSDATETIME()
    WHERE Id_Detalle_Picking = @Id_Detalle_Picking;

    SELECT @Id_Detalle_Picking AS Id_Detalle_Picking, @Resultado AS Resultado;
END;
GO

/* ---------------------------------------------------------------------
   sp_Confirmar_Picking  (RN04)
   En una única transacción:
     1) verifica que el picking exista, esté 'En curso', no tenga líneas pendientes,
        tenga al menos una línea validada y que cada lote validado tenga registro de stock;
     2) descuenta el stock de cada lote por las líneas VALIDADAS (las rechazadas
        nunca descuentan);
     3) marca el picking como 'Confirmado' con su fecha de fin;
     4) marca el pedido como 'Preparado'.
   El stock nunca queda negativo: lo impide el CHECK de STOCK (RI15); si se
   violara, se deshace toda la confirmación.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_Confirmar_Picking
    @Id_Picking INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Estado_Picking VARCHAR(20);
    DECLARE @Id_Pedido      INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @Estado_Picking = Estado, @Id_Pedido = Id_Pedido
        FROM PICKING
        WHERE Id_Picking = @Id_Picking;

        IF @Estado_Picking IS NULL
            THROW 50010, N'El picking indicado no existe.', 1;
        IF @Estado_Picking <> 'En curso'
            THROW 50011, N'Solo se puede confirmar un picking en curso.', 1;
        IF EXISTS (SELECT 1 FROM DETALLE_PICKING
                   WHERE Id_Picking = @Id_Picking AND Estado_Validacion = 'Pendiente')
            THROW 50012, N'El picking tiene líneas pendientes de validación.', 1;
        IF NOT EXISTS (SELECT 1 FROM DETALLE_PICKING
                       WHERE Id_Picking = @Id_Picking AND Estado_Validacion = 'Validada')
            THROW 50013, N'El picking no tiene líneas validadas para confirmar.', 1;
        -- Un lote validado sin fila en STOCK no se descontaría nunca: se informa el error
        IF EXISTS (SELECT 1 FROM DETALLE_PICKING d
                   WHERE d.Id_Picking = @Id_Picking AND d.Estado_Validacion = 'Validada'
                     AND NOT EXISTS (SELECT 1 FROM STOCK s WHERE s.Id_Lote = d.Id_Lote))
            THROW 50014, N'Hay lotes validados sin registro de stock.', 1;

        -- Descuenta, por lote, la suma de lo preparado en las líneas validadas
        UPDATE STOCK
        SET Cantidad_Disponible = Cantidad_Disponible -
            (SELECT SUM(d.Cantidad_Preparada)
             FROM DETALLE_PICKING d
             WHERE d.Id_Lote = STOCK.Id_Lote
               AND d.Id_Picking = @Id_Picking
               AND d.Estado_Validacion = 'Validada')
        WHERE Id_Lote IN (SELECT Id_Lote FROM DETALLE_PICKING
                          WHERE Id_Picking = @Id_Picking AND Estado_Validacion = 'Validada');

        UPDATE PICKING
        SET Estado = 'Confirmado', Fecha_Fin = SYSDATETIME()
        WHERE Id_Picking = @Id_Picking;

        UPDATE PEDIDO
        SET Estado = 'Preparado'
        WHERE Id_Pedido = @Id_Pedido;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;   -- vuelve a lanzar el error original (por ejemplo, stock insuficiente)
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   sp_Asignar_Caja_Entrega  (RN05)
   Asigna una caja consolidada a una entrega. Controla que:
     - la caja y la entrega existan;
     - la caja todavía no tenga entrega;
     - la entrega esté 'Planificada' (todavía no salió);
     - el destino de la caja coincida con el de la entrega.
   El UPDATE vuelve a exigir Id_Entrega IS NULL: si dos usuarios asignaran la
   misma caja a la vez, solo uno modifica la fila y el otro recibe el error.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_Asignar_Caja_Entrega
    @Id_Caja    INT,
    @Id_Entrega INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Destino_Caja        INT;
    DECLARE @Entrega_Actual      INT;
    DECLARE @Destino_Entrega     INT;
    DECLARE @Estado_Entrega      VARCHAR(20);

    SELECT @Destino_Caja = Id_Destino, @Entrega_Actual = Id_Entrega
    FROM CAJA
    WHERE Id_Caja = @Id_Caja;

    SELECT @Destino_Entrega = Id_Destino, @Estado_Entrega = Estado
    FROM ENTREGA
    WHERE Id_Entrega = @Id_Entrega;

    IF @Destino_Caja IS NULL
        THROW 50020, N'La caja indicada no existe.', 1;
    IF @Destino_Entrega IS NULL
        THROW 50021, N'La entrega indicada no existe.', 1;
    IF @Entrega_Actual IS NOT NULL
        THROW 50022, N'La caja ya está asignada a una entrega.', 1;
    IF @Estado_Entrega <> 'Planificada'
        THROW 50023, N'Solo se pueden asignar cajas a una entrega planificada.', 1;
    IF @Destino_Caja <> @Destino_Entrega
        THROW 50024, N'El destino de la caja no coincide con el de la entrega.', 1;

    UPDATE CAJA
    SET Id_Entrega = @Id_Entrega
    WHERE Id_Caja = @Id_Caja AND Id_Entrega IS NULL;

    IF @@ROWCOUNT = 0
        THROW 50022, N'La caja ya está asignada a una entrega.', 1;

    SELECT @Id_Caja AS Id_Caja, @Id_Entrega AS Id_Entrega;
END;
GO

/* ---------------------------------------------------------------------
   sp_Registrar_Recepcion_Caja
   Registra en destino si la caja fue 'Recibida' o 'Rechazada', con el motivo del
   rechazo y, si corresponde, la temperatura medida. Luego, cada pedido que tiene
   líneas en esa caja pasa a 'Entregado' si todas sus cajas ya fueron recibidas
   (se usa fn_Fecha_Entrega_Pedido: distinta de NULL = entregado completo).
   Controla que la caja exista, que el estado indicado sea válido (un NULL también se
   rechaza), que esté pendiente, que tenga entrega y que esa entrega ya tenga registrada
   su llegada (la fecha de entrega del pedido sale de ahí).
   Los CHECK de CAJA validan además el motivo obligatorio y el rango de temperatura.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_Registrar_Recepcion_Caja
    @Id_Caja          INT,
    @Estado_Recepcion VARCHAR(10),
    @Motivo_Rechazo   NVARCHAR(200) = NULL,
    @Temperatura      DECIMAL(4,1) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Estado_Actual   VARCHAR(10);
    DECLARE @Id_Entrega      INT;
    DECLARE @Llegada_Entrega DATETIME2(0);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @Estado_Actual   = c.Estado_Recepcion,
               @Id_Entrega      = c.Id_Entrega,
               @Llegada_Entrega = e.Fecha_Hora_Entrega
        FROM CAJA c
        LEFT JOIN ENTREGA e ON e.Id_Entrega = c.Id_Entrega
        WHERE c.Id_Caja = @Id_Caja;

        IF @Estado_Actual IS NULL
            THROW 50030, N'La caja indicada no existe.', 1;
        -- Con el parámetro en NULL, NOT IN no da verdadero: por eso se pregunta IS NULL primero
        IF @Estado_Recepcion IS NULL OR @Estado_Recepcion NOT IN ('Recibida', 'Rechazada')
            THROW 50031, N'El estado de recepción debe ser Recibida o Rechazada.', 1;
        IF @Estado_Actual <> 'Pendiente'
            THROW 50032, N'La recepción de la caja ya fue registrada.', 1;
        IF @Id_Entrega IS NULL
            THROW 50033, N'La caja no está asignada a ninguna entrega.', 1;
        IF @Llegada_Entrega IS NULL
            THROW 50034, N'La entrega de la caja todavía no registra su llegada.', 1;

        UPDATE CAJA
        SET Estado_Recepcion    = @Estado_Recepcion,
            Motivo_Rechazo      = @Motivo_Rechazo,
            Temperatura_Entrega = @Temperatura
        WHERE Id_Caja = @Id_Caja;

        -- Pedidos con líneas en esta caja que ya tienen todas sus cajas recibidas
        UPDATE PEDIDO
        SET Estado = 'Entregado'
        WHERE Estado <> 'Entregado'
          AND dbo.fn_Fecha_Entrega_Pedido(Id_Pedido) IS NOT NULL
          AND Id_Pedido IN (
              SELECT pk.Id_Pedido
              FROM DETALLE_CAJA dc
              INNER JOIN DETALLE_PICKING dpk ON dpk.Id_Detalle_Picking = dc.Id_Detalle_Picking
              INNER JOIN PICKING pk          ON pk.Id_Picking = dpk.Id_Picking
              WHERE dc.Id_Caja = @Id_Caja
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   sp_Trazabilidad_Lote  (consulta central, RF13)
   Devuelve el recorrido completo de un lote consultando vw_Trazabilidad_Lote:
   producto, pedidos, clientes, cajas, entregas y estado de recepción.
   Ante un retiro sanitario responde: ¿a quién llegó este lote y fue recibido?
   Se listan las columnas de la vista
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_Trazabilidad_Lote
    @Id_Lote INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM LOTE WHERE Id_Lote = @Id_Lote)
        THROW 50040, N'El lote indicado no existe.', 1;

    SELECT Id_Lote, Numero_Lote, Fecha_Vencimiento,
           Codigo_Producto, Producto, Cliente_Propietario,
           Id_Pedido, Cliente_Pedido, Destino_Pedido,
           Id_Detalle_Picking, Cantidad_Preparada, Estado_Validacion,
           Id_Caja, Codigo_QR, Cantidad_Encajada, Estado_Recepcion, Motivo_Rechazo,
           Id_Entrega, Vehiculo, Conductor, Fecha_Hora_Salida, Fecha_Hora_Entrega
    FROM vw_Trazabilidad_Lote
    WHERE Id_Lote = @Id_Lote
    ORDER BY Id_Pedido, Id_Caja;
END;
GO