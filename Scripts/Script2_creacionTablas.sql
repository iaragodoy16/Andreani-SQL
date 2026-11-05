/*
    Script 01 - Creación de tablas, claves y restricciones
    La Base de datos fue creada desde la vista grafica del SSMS
    Estan comentados algunos de los aspectos importantes sobre la 
    creacion de las tablas, tales como a que requerimiento pertenece o su cardinalidad
*/
USE Andreani;
GO

/* =====================================================================
   TABLAS CATALOGO
   ===================================================================== */

-- Tipos de cliente (laboratorio, droguería, distribuidor)
CREATE TABLE TIPO_CLIENTE (
    Id_Tipo_Cliente INT IDENTITY(1,1) CONSTRAINT pk_Tipo_Cliente PRIMARY KEY,
    Nombre NVARCHAR(40) NOT NULL UNIQUE
);

-- Tipos de destino (farmacia, clínica, hospital)
CREATE TABLE TIPO_DESTINO (
    Id_Tipo_Destino INT IDENTITY(1,1) CONSTRAINT pk_Tipo_Destino PRIMARY KEY,
    Nombre NVARCHAR(40) NOT NULL UNIQUE
);

-- Provincias
CREATE TABLE PROVINCIA (
    Id_Provincia INT IDENTITY(1,1) CONSTRAINT pk_Provincia PRIMARY KEY,
    Nombre NVARCHAR(40) NOT NULL UNIQUE
);

-- Localidades: el nombre se repite entre provincias, por eso la UNIQUE es compuesta
CREATE TABLE LOCALIDAD (
    Id_Localidad INT IDENTITY(1,1) CONSTRAINT pk_Localidad PRIMARY KEY,
    Nombre NVARCHAR(60) NOT NULL,
    Codigo_Postal VARCHAR(8) NOT NULL,
    Id_Provincia INT NOT NULL
        CONSTRAINT fk_Localidad_Provincia REFERENCES PROVINCIA(Id_Provincia),
    UNIQUE (Nombre, Id_Provincia)
);

-- Condiciones de conservación. El rango de temperatura es opcional
CREATE TABLE CONDICION_CONSERVACION (
    Id_Condicion INT IDENTITY(1,1) CONSTRAINT pk_Condicion PRIMARY KEY,
    Nombre VARCHAR(40) NOT NULL UNIQUE,
    Temp_Min DECIMAL(4,1) NULL,
    Temp_Max DECIMAL(4,1) NULL,
    CONSTRAINT chk_Condicion_Temp CHECK (
        (Temp_Min IS NULL AND Temp_Max IS NULL)
        OR (Temp_Min IS NOT NULL AND Temp_Max IS NOT NULL AND Temp_Min <= Temp_Max)
    )
);

/* =====================================================================
   TABLAS NEGOCIO 
   ===================================================================== */

-- Clientes: laboratorios, droguerías y distribuidores dueños de la mercadería
CREATE TABLE CLIENTE (
    Id_Cliente INT IDENTITY(1,1) CONSTRAINT pk_Cliente PRIMARY KEY,
    Razon_Social NVARCHAR(150) NOT NULL,
    -- RI02 (CUIT no repetido) y RI21 (once dígitos numéricos)
    Cuit CHAR(11) NOT NULL UNIQUE
        CONSTRAINT chk_Cliente_Cuit CHECK (LEN(Cuit) = 11 AND Cuit NOT LIKE '%[^0-9]%'),
    Id_Tipo_Cliente INT NOT NULL
        CONSTRAINT fk_Cliente_Tipo_Cliente REFERENCES TIPO_CLIENTE(Id_Tipo_Cliente),
    Activo BIT NOT NULL CONSTRAINT df_Cliente_Activo DEFAULT 1,
);

-- Destinos: farmacias, clínicas y hospitales que reciben las entregas
CREATE TABLE DESTINO (
    Id_Destino INT IDENTITY(1,1) CONSTRAINT pk_Destino PRIMARY KEY,
    Nombre_Destino NVARCHAR(150) NOT NULL,
    Direccion NVARCHAR(200) NOT NULL,
    Id_Localidad INT NOT NULL
        CONSTRAINT fk_Destino_Localidad REFERENCES LOCALIDAD(Id_Localidad),
    Id_Tipo_Destino INT NOT NULL
        CONSTRAINT fk_Destino_Tipo_Destino REFERENCES TIPO_DESTINO(Id_Tipo_Destino)
);

-- Productos: cada uno referencia a su cliente propietario 
-- y a su condición de conservación (el rango de temperatura vive en la condición, no en el producto)
CREATE TABLE PRODUCTO (
    Id_Producto INT IDENTITY(1,1) CONSTRAINT pk_Producto PRIMARY KEY,
    Codigo_Producto VARCHAR(30) NOT NULL UNIQUE,
    Nombre NVARCHAR(150) NOT NULL,
    Descripcion NVARCHAR(300) NULL,
    Id_Cliente_Propietario INT NOT NULL
        CONSTRAINT fk_Producto_Cliente REFERENCES CLIENTE(Id_Cliente),
    Id_Condicion INT NOT NULL
        CONSTRAINT fk_Producto_Condicion REFERENCES CONDICION_CONSERVACION(Id_Condicion)
);

-- Lotes: cada laboratorio numera sus lotes con su propio criterio, por eso el
-- número de lote es único solo dentro de un mismo producto (RI03).
-- El lote tiene además identificador propio (Id_Lote).
CREATE TABLE LOTE (
    Id_Lote INT IDENTITY(1,1) CONSTRAINT pk_Lote PRIMARY KEY,
    Id_Producto INT NOT NULL
        CONSTRAINT fk_Lote_Producto REFERENCES PRODUCTO(Id_Producto),
    Numero_Lote VARCHAR(30) NOT NULL,
    Fecha_Vencimiento DATE NOT NULL,
    UNIQUE (Id_Producto, Numero_Lote)
);

-- Stock: una única existencia por lote (relación 1:1, no se gestionan ubicaciones).
-- Se separa de LOTE porque número y vencimiento no cambian, mientras que la
-- existencia se actualiza con cada picking confirmado.
-- La clave primaria es a la vez clave foránea. RN04: el stock nunca es negativo (RI15).
CREATE TABLE STOCK (
    Id_Lote INT NOT NULL
        CONSTRAINT pk_Stock PRIMARY KEY
        CONSTRAINT fk_Stock_Lote REFERENCES LOTE(Id_Lote),
    Cantidad_Disponible INT NOT NULL
        CONSTRAINT df_Stock_Cantidad DEFAULT 0
        CONSTRAINT chk_Stock_Cantidad CHECK (Cantidad_Disponible >= 0)
);

-- Operarios de depósito que realizan los pickings
CREATE TABLE OPERARIO (
    Id_Operario INT IDENTITY(1,1) CONSTRAINT pk_Operario PRIMARY KEY,
    Legajo VARCHAR(15) NOT NULL UNIQUE,
    Nombre NVARCHAR(60) NOT NULL,
    Apellido NVARCHAR(60) NOT NULL,
    Activo BIT NOT NULL CONSTRAINT df_Operario_Activo DEFAULT 1
);

-- Vehículos de reparto; Refrigerado indica si sirve para cadena de frío
CREATE TABLE VEHICULO (
    Id_Vehiculo INT IDENTITY(1,1) CONSTRAINT pk_Vehiculo PRIMARY KEY,
    Patente VARCHAR(10) NOT NULL UNIQUE,
    Refrigerado BIT NOT NULL CONSTRAINT df_Vehiculo_Refrigerado DEFAULT 0
);

-- Conductores
CREATE TABLE CONDUCTOR (
    Id_Conductor INT IDENTITY(1,1) CONSTRAINT pk_Conductor PRIMARY KEY,
    Documento VARCHAR(15) NOT NULL UNIQUE,
    Nombre NVARCHAR(60) NOT NULL,
    Apellido NVARCHAR(60) NOT NULL
);

/* =====================================================================
   DATOS OPERATIVOS
   ===================================================================== */

-- Pedidos: la fecha de alta y el estado inicial se completan solos (RI24).
-- El estado se guarda como dato operativo para saber rápido en qué etapa está;
-- los procedimientos lo actualizan en cada transición.
-- La fecha real de entrega NO se almacena: se obtiene de las entregas de sus cajas.
CREATE TABLE PEDIDO (
    Id_Pedido INT IDENTITY(1,1) CONSTRAINT pk_Pedido PRIMARY KEY,
    Id_Cliente INT NOT NULL
        CONSTRAINT fk_Pedido_Cliente REFERENCES CLIENTE(Id_Cliente),
    Id_Destino INT NOT NULL
        CONSTRAINT fk_Pedido_Destino REFERENCES DESTINO(Id_Destino),
    Fecha_Pedido DATETIME2(0) NOT NULL
        CONSTRAINT df_Pedido_Fecha DEFAULT SYSDATETIME(),
    Fecha_Entrega_Solicitada DATE NOT NULL,
    Estado VARCHAR(20) NOT NULL
        CONSTRAINT df_Pedido_Estado DEFAULT 'Recibido'
        CONSTRAINT chk_Pedido_Estado CHECK (Estado IN('Recibido','En preparación','Preparado','Despachado','Entregado','Cancelado')),
    -- RI16: la fecha solicitada no puede ser anterior a la del pedido
    CONSTRAINT chk_Pedido_Fechas CHECK (Fecha_Entrega_Solicitada >= CAST(Fecha_Pedido AS DATE)),
    
);

-- Detalle de pedido: un producto aparece una sola vez por pedido (RI04)
CREATE TABLE DETALLE_PEDIDO (
    Id_Detalle_Pedido INT IDENTITY(1,1) CONSTRAINT pk_Detalle_Pedido PRIMARY KEY,
    Id_Pedido INT NOT NULL
        CONSTRAINT fk_Detalle_Pedido_Pedido REFERENCES PEDIDO(Id_Pedido),
    Id_Producto INT NOT NULL
        CONSTRAINT fk_Detalle_Pedido_Producto REFERENCES PRODUCTO(Id_Producto),
    Cantidad_Solicitada INT NOT NULL
        CONSTRAINT chk_Detalle_Pedido_Cantidad CHECK (Cantidad_Solicitada > 0),
    UNIQUE (Id_Pedido, Id_Producto)
);

-- Picking: cada pedido se prepara en un único picking (RI05, UNIQUE en Id_Pedido).
-- Fecha_Fin es nula mientras el picking está en curso.
CREATE TABLE PICKING (
    Id_Picking INT IDENTITY(1,1) CONSTRAINT pk_Picking PRIMARY KEY,
    Id_Pedido INT NOT NULL UNIQUE
        CONSTRAINT fk_Picking_Pedido REFERENCES PEDIDO(Id_Pedido),
    Id_Operario INT NOT NULL
        CONSTRAINT fk_Picking_Operario REFERENCES OPERARIO(Id_Operario),
    Fecha_Inicio DATETIME2(0) NOT NULL,
    Fecha_Fin DATETIME2(0) NULL,
    Estado VARCHAR(20) NOT NULL
        CONSTRAINT df_Picking_Estado DEFAULT 'En curso'
        CONSTRAINT chk_Picking_Estado CHECK (Estado IN ('En curso','Confirmado','Cancelado')),
    -- RI17: la finalización no puede ser anterior al inicio
    CONSTRAINT chk_Picking_Fechas CHECK (Fecha_Fin >= Fecha_Inicio)
);

-- Detalle de picking: lo solicitado y lo preparado se registran por separado.
-- Cada línea referencia la línea de pedido que prepara y el lote del que se extrajo.
-- La validación es un estado de la línea: las rechazadas no se borran, quedan como
-- evidencia del error (base del KPI 2). No guarda pedido ni producto para evitar
-- dependencias transitivas (se obtienen vía picking y detalle de pedido).
CREATE TABLE DETALLE_PICKING (
    Id_Detalle_Picking INT IDENTITY(1,1) CONSTRAINT pk_Detalle_Picking PRIMARY KEY,
    Id_Picking INT NOT NULL
        CONSTRAINT fk_Detalle_Picking_Picking REFERENCES PICKING(Id_Picking),
    Id_Detalle_Pedido INT NOT NULL
        CONSTRAINT fk_Detalle_Picking_Detalle_Pedido REFERENCES DETALLE_PEDIDO(Id_Detalle_Pedido),
    Id_Lote INT NOT NULL
        CONSTRAINT fk_Detalle_Picking_Lote REFERENCES LOTE(Id_Lote),
    Cantidad_Preparada INT NOT NULL
        CONSTRAINT chk_Detalle_Picking_Cantidad CHECK (Cantidad_Preparada > 0),
    Estado_Validacion VARCHAR(10) NOT NULL
        CONSTRAINT df_Detalle_Picking_Validacion DEFAULT 'Pendiente'
        CONSTRAINT chk_Detalle_Picking_Validacion CHECK (Estado_Validacion IN ('Pendiente','Validada','Rechazada')),
    Fecha_Hora_Validacion DATETIME2(0) NULL
);

-- Entrega = despacho: asocia un destino con el vehículo y el conductor responsable.
-- Se simplificó el transporte; las rutas con múltiples paradas quedan como evolución.
CREATE TABLE ENTREGA (
    Id_Entrega INT IDENTITY(1,1) CONSTRAINT pk_Entrega PRIMARY KEY,
    Id_Destino INT NOT NULL
        CONSTRAINT fk_Entrega_Destino REFERENCES DESTINO(Id_Destino),
    Id_Vehiculo INT NOT NULL
        CONSTRAINT fk_Entrega_Vehiculo REFERENCES VEHICULO(Id_Vehiculo),
    Id_Conductor INT NOT NULL
        CONSTRAINT fk_Entrega_Conductor REFERENCES CONDUCTOR(Id_Conductor),
    Fecha_Hora_Salida DATETIME2(0) NULL,
    Fecha_Hora_Entrega DATETIME2(0) NULL,
    Estado VARCHAR(20) NOT NULL
        CONSTRAINT df_Entrega_Estado DEFAULT 'Planificada'
        CONSTRAINT chk_Entrega_Estado CHECK (Estado IN ('Planificada','En viaje','Finalizada')),
    -- RI18: la llegada no puede ser anterior a la salida
    CONSTRAINT chk_Entrega_Fechas CHECK (Fecha_Hora_Entrega >= Fecha_Hora_Salida),
    -- No puede haber llegada sin salida
    CONSTRAINT chk_Entrega_Salida CHECK (Fecha_Hora_Entrega IS NULL OR Fecha_Hora_Salida IS NOT NULL)
);

-- Cajas: unidad física que se entrega. Se arma para un destino antes de existir la
-- entrega, por eso Id_Entrega admite NULL hasta el despacho (RI11).
-- La recepción se registra por caja, lo que distingue lo despachado de lo efectivamente recibido.
-- La coincidencia de destino caja-entrega se controla en el procedimiento (RN05).
CREATE TABLE CAJA (
    Id_Caja INT IDENTITY(1,1) CONSTRAINT pk_Caja PRIMARY KEY,
    Codigo_QR VARCHAR(50) NOT NULL UNIQUE,
    Codigo_Barras VARCHAR(50) NOT NULL UNIQUE,
    Id_Destino INT NOT NULL
        CONSTRAINT fk_Caja_Destino REFERENCES DESTINO(Id_Destino),
    Fecha_Consolidacion DATETIME2(0) NOT NULL,
    Id_Entrega INT NULL
        CONSTRAINT fk_Caja_Entrega REFERENCES ENTREGA(Id_Entrega),
    -- RI20: rango físico de la temperatura medida (opcional)
    Temperatura_Entrega DECIMAL(4,1) NULL
        CONSTRAINT chk_Caja_Temperatura CHECK (Temperatura_Entrega BETWEEN -30 AND 50),
    Estado_Recepcion VARCHAR(10) NOT NULL
        CONSTRAINT df_Caja_Estado_Recepcion DEFAULT 'Pendiente'
        CONSTRAINT chk_Caja_Estado_Recepcion CHECK
            (Estado_Recepcion IN ('Pendiente','Recibida','Rechazada')),
    Motivo_Rechazo NVARCHAR(200) NULL,
    -- RI22: una caja recibida o rechazada debe tener entrega asignada
    CONSTRAINT chk_Caja_Entrega CHECK (Estado_Recepcion = 'Pendiente' OR Id_Entrega IS NOT NULL),
    -- RI22: una caja rechazada debe tener motivo
    CONSTRAINT chk_Caja_Motivo CHECK (Estado_Recepcion <> 'Rechazada' OR Motivo_Rechazo IS NOT NULL)
);

-- Detalle de caja (N:M entre CAJA y DETALLE_PICKING).
-- Una caja consolida unidades de varios pedidos del mismo destino y un pedido puede
-- repartirse en varias cajas. Registrar el contenido por línea de picking permite saber
-- qué lote viajó en cada caja (trazabilidad). La PK compuesta cumple RI06.
CREATE TABLE DETALLE_CAJA (
    Id_Caja INT NOT NULL
        CONSTRAINT fk_Detalle_Caja_Caja REFERENCES CAJA(Id_Caja),
    Id_Detalle_Picking INT NOT NULL
        CONSTRAINT fk_Detalle_Caja_Detalle_Picking REFERENCES DETALLE_PICKING(Id_Detalle_Picking),
    Cantidad INT NOT NULL
        CONSTRAINT chk_Detalle_Caja_Cantidad CHECK (Cantidad > 0),
    CONSTRAINT pk_Detalle_Caja PRIMARY KEY (Id_Caja, Id_Detalle_Picking)
);
GO