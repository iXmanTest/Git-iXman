
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER proc [dbo].[Label_XDock] 
@iDate Date = NULL,
@AllowSplit BIT = 0
as
exec iMportGen..AutocalxDockByYos95New @AllowSplit , @iDate ;

-- ตัวแปรสำหรับกรอง Route
DECLARE @sRoute NVARCHAR(20) = '00000', @fRoute NVARCHAR(20) = '99999';

-- สร้างหรือตรวจสอบตาราง LogTable
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'LogTable' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE [SmartX-Dock].[dbo].[LogTable] (
        LogID INT IDENTITY(1,1),
        LogDate DATETIME,
        Action NVARCHAR(100),
        Message NVARCHAR(MAX)
    );
END
ELSE
BEGIN
    -- ตรวจสอบโครงสร้างตารางว่ามีคอลัมน์ที่ต้องการหรือไม่
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('[SmartX-Dock].[dbo].[LogTable]')
        AND name IN ('LogID', 'LogDate', 'Action', 'Message')
        GROUP BY object_id
        HAVING COUNT(*) = 4
    )
    BEGIN
        -- บันทึก Log ว่าตารางมีโครงสร้างไม่ถูกต้อง
        INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
        VALUES (GETDATE(), 'Error', 'LogTable exists but has incorrect structure.');
        THROW 50001, 'LogTable exists but does not have the required columns.', 1;
    END
END;

BEGIN TRY
    -- ล้างข้อมูลใน TempLable
    TRUNCATE TABLE [SmartX-Dock].[dbo].[TempLable];
    
    -- ตรวจสอบและลบตารางชั่วคราว
    IF OBJECT_ID('tempdb..#tempcte') IS NOT NULL
        DROP TABLE #tempcte;

    -- สร้าง CTE สำหรับคำนวณข้อมูลพื้นฐาน
    ;WITH cte AS (
        SELECT DISTINCT d.*, 
            a.[Route],
            a.TruckId AS xtruck,
            a.Door,
            a.Station,
            MIN(a.iRow) OVER (PARTITION BY station, a.TruckID ORDER BY station, iRow) AS x_base,
            SUM(d.RecQtyCrate) OVER (PARTITION BY d.TruckID ORDER BY d.TruckID, PO_NO, CV_CODE) AS running_total,
            SUM(d.RecQtyCrate) OVER (PARTITION BY d.TruckID) AS total_recqty_per_truck
        FROM [iMportGen].[dbo].TblSplitDeliveries d
        LEFT JOIN [SmartX-Dock].[dbo].TblAssignDock a
            ON CAST(REPLACE(LEFT(RIGHT(d.TruckID, 5), 2), '_', '') AS INT) = RIGHT(a.[Route], 1)
            AND d.Area = a.whName
            AND CAST(RIGHT(LEFT(d.TruckID, 8), 2) AS INT) = a.TruckType
        WHERE a.iDate = CAST(GETDATE() AS DATE)
    )
    -- สร้างตารางชั่วคราว #tempcte
    SELECT DISTINCT ProductCode, RecQtyCrate, Area, TruckID, OriginalProductCode, PO_NO, CV_CODE, Route, xtruck,
        CASE 
            WHEN running_total <= total_recqty_per_truck / 2.0 THEN x_base
            WHEN station IN ('ST06', 'ST07') THEN x_base
            WHEN x_base IN ('D1', 'D2') THEN x_base
            ELSE 'R' + RIGHT('0' + CAST(CAST(RIGHT(x_base, 2) AS INT) + 1 AS VARCHAR(2)), 2)
        END AS x,
        Door,
        Station,
        DENSE_RANK() OVER (PARTITION BY TruckID ORDER BY FLOOR(CAST(running_total AS NVARCHAR) / 34)) AS pallet_number,
        running_total, total_recqty_per_truck
    INTO #tempcte
    FROM cte
    WHERE Route BETWEEN @sRoute AND @fRoute
    ORDER BY TruckID, PO_NO, CV_CODE;

    -- บันทึก Log สำหรับการสร้าง #tempcte
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Create #tempcte', 'Inserted ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' rows into #tempcte');

    -- รวมการแทรกข้อมูลลง TempLable
    INSERT INTO [SmartX-Dock].[dbo].[TempLable]
    SELECT --a.TruckID, a.PO_NO, a.CV_CODE, 
           DELIVERY_DATE AS iDate, a.PO_NO AS WH, b.CV_NAME AS Vender, a.CV_CODE, NULL AS SeqProduct, NULL AS CountProduct,
           a.ProductCode AS SKU, b.PRODUCT_NAME AS SKUname, b.RecQty AS QTY, b.TCC, b.TCO, a.RecQtyCrate AS TCA,
           CASE 
               WHEN b.TCC <> 0 AND b.TCO = 0 THEN 'FULL'
               WHEN b.TCC = 0 AND b.TCO <> 0 THEN 'OVER'
               WHEN b.TCC <> 0 AND b.TCO <> 0 THEN 'FULL'
           END AS [Status],
           CASE 
               WHEN b.TCC <> 0 AND b.TCO = 0 THEN '1/1'
               WHEN b.TCC = 0 AND b.TCO <> 0 THEN '1/1'
               WHEN b.TCC <> 0 AND b.TCO <> 0 THEN '1/2'
           END AS seq,
           b.VENDOR_CARTON AS CRATE, IIF(LEN(a.Door) < 2, 'XD0' + a.Door, 'XD' + a.Door) AS Door,
           a.Route, '' AS Zone, a.Station, a.x AS Row, '' AS iTote, a.xtruck AS TruckNo, a.pallet_number
    FROM #tempcte a
    LEFT JOIN [SmartX-Dock].[dbo].[WTS_ORR2223Data] b
        ON a.PO_NO = b.PO_NO AND a.ProductCode = b.PRODUCT_CODE AND a.CV_CODE = b.CV_CODE
    WHERE b.DELIVERY_DATE = CAST(GETDATE() AS DATE) AND a.Route BETWEEN @sRoute AND @fRoute
    UNION ALL
    SELECT --a.TruckID, a.PO_NO, a.CV_CODE, 
           DELIVERY_DATE AS iDate, a.PO_NO AS WH, b.CV_NAME AS Vender, a.CV_CODE, NULL AS SeqProduct, NULL AS CountProduct,
           a.ProductCode AS SKU, b.PRODUCT_NAME AS SKUname, b.RecQty AS QTY, b.TCC, b.TCO, a.RecQtyCrate AS TCA,
           'OVER' AS [Status], '2/2' AS seq,
           b.VENDOR_CARTON AS CRATE, IIF(LEN(a.Door) < 2, 'XD0' + a.Door, 'XD' + a.Door) AS Door,
           a.Route, '' AS Zone, a.Station, a.x AS Row, '' AS iTote, a.xtruck AS TruckNo, a.pallet_number
    FROM #tempcte a
    INNER JOIN [SmartX-Dock].[dbo].[WTS_ORR2223Data] b
        ON a.PO_NO = b.PO_NO AND a.ProductCode = b.PRODUCT_CODE AND a.CV_CODE = b.CV_CODE
    WHERE b.TCC <> 0 AND b.TCO <> 0 AND b.DELIVERY_DATE = CAST(GETDATE() AS DATE) AND a.Route BETWEEN @sRoute AND @fRoute
    ORDER BY a.PO_NO, a.CV_CODE;

    -- บันทึก Log สำหรับการแทรก TempLable
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Insert TempLable', 'Inserted ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' rows into TempLable');

    -- ลบข้อมูลซ้ำใน TempLable
    ;WITH DuplicateCTE AS (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY WH, CV_CODE, SKU, SKUname
                   ORDER BY QTY DESC
               ) AS row_num
        FROM [SmartX-Dock].[dbo].[TempLable]
        WHERE seq <> '2/2'
    )
    DELETE FROM DuplicateCTE
    WHERE row_num > 1;

    -- บันทึก Log สำหรับการลบข้อมูลซ้ำ
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Delete Duplicates', 'Deleted ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' duplicate rows from TempLable');

    -- อัปเดต iTote
    UPDATE T
    SET iTote = REPLACE(RIGHT('00' + CAST(DATEPART(MM, iDate) AS NVARCHAR(20)), 2) 
                      + CAST(DATEPART(DD, iDate) AS NVARCHAR(20)) 
                      + '0' + RIGHT(STUFF(REPLACE(WH, '-', ''), 3, 0, '0'), 3)  
                      + SKU 
                      + RIGHT(REPLICATE('0', 5) + CAST(QTY AS NVARCHAR(20)), 5)
                      + REPLACE(REPLACE(station, 'ST', ''), 'XD', '')
                      + REPLACE(REPLACE(Row, 'R', ''), 'D', '')
                      + Route, ' ', '')
    FROM [SmartX-Dock].[dbo].[TempLable] T
    WHERE Route BETWEEN @sRoute AND @fRoute;

    -- บันทึก Log สำหรับการอัปเดต iTote
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Update iTote', 'Updated ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' rows in TempLable for iTote');

    -- อัปเดต Zone
    UPDATE a
    SET a.Zone = b.Zone
    FROM [SmartX-Dock].[dbo].[TempLable] a
    INNER JOIN [SmartX-Dock].[dbo].[tblMasterStation] b
        ON a.Station = b.StationId
    WHERE a.Route BETWEEN @sRoute AND @fRoute;

    -- บันทึก Log สำหรับการอัปเดต Zone
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Update Zone', 'Updated ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' rows in TempLable for Zone');

    -- สร้างตารางชั่วคราว #temp สำหรับ SeqProduct และ CountProduct
    IF OBJECT_ID('tempdb..#temp') IS NOT NULL
        DROP TABLE #temp;

    SELECT 
        DELIVERY_DATE AS iDate,
        PO_NO AS WH,
        CV_CODE,
        PRODUCT_CODE AS SKU,
        ROW_NUMBER() OVER (PARTITION BY DELIVERY_DATE, PO_NO, CV_CODE ORDER BY PRODUCT_CODE) AS SeqProduct,
        (SELECT COUNT(DISTINCT PRODUCT_CODE) 
         FROM [SmartX-Dock].[dbo].[WTS_ORR2223Data] 
         WHERE PO_NO = x.PO_NO AND CV_CODE = x.CV_CODE) AS CountProduct
    INTO #temp 
    FROM [SmartX-Dock].[dbo].[WTS_ORR2223Data] x
    WHERE DELIVERY_DATE = CAST(GETDATE() AS DATE);

    -- บันทึก Log สำหรับการสร้าง #temp
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Create #temp', 'Inserted ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' rows into #temp');

    -- อัปเดต SeqProduct และ CountProduct
    UPDATE x
    SET x.CountProduct = y.CountProduct, 
        x.SeqProduct = y.SeqProduct
    FROM [SmartX-Dock].[dbo].[TempLable] x
    INNER JOIN #temp y
        ON y.iDate = x.iDate AND y.WH = x.WH AND y.CV_CODE = x.CV_CODE AND y.SKU = x.SKU
    WHERE x.Route BETWEEN @sRoute AND @fRoute;

    -- บันทึก Log สำหรับการอัปเดต SeqProduct และ CountProduct
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Update SeqProduct/CountProduct', 'Updated ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' rows in TempLable');

    -- เลือกข้อมูลผลลัพธ์
    SELECT [iDate], [WH], [Zone], [Station], [Row], [Status], [SeqProduct], [CountProduct], [Vender], 
           [CV_Code], [SKU], [SKUname], [QTY], [TCC], [TCO], [TCA], [Crate], [Door], [Route], [Seq], 
           [iTote], [TruckNo], 
           IIF(LEN(pallet_number) < 2, 'P0' + CAST(pallet_number AS NVARCHAR), 'P' + CAST(pallet_number AS NVARCHAR)) AS pallet_number
    FROM [SmartX-Dock].[dbo].[TempLable]
    WHERE [Route] BETWEEN @sRoute AND @fRoute AND Route IS NOT NULL
    ORDER BY WH, CV_CODE, Route, SKU,
        CASE 
            WHEN Status = 'FULL' AND seq = '1/2' THEN 1
            WHEN Status = 'OVER' AND seq = '2/2' THEN 2
            ELSE 0
        END;

    -- อัปเดต WTS_ORR2223
    UPDATE a
    SET a.EXP_DATE3 = b.Route,
        a.MFD_DATE3 = b.iTote,
        a.EXP_DATE2 = b.TruckNo,
        a.MFD_DATE2 = b.Station
    FROM [SmartX-Dock].[dbo].[WTS_ORR2223] a
    INNER JOIN [SmartX-Dock].[dbo].[TempLable] b
        ON a.PO_NO = b.WH AND a.PRODUCT_CODE = b.SKU AND a.DELIVERY_DATE = b.iDate
    WHERE b.Route BETWEEN @sRoute AND @fRoute;

    -- บันทึก Log สำหรับการอัปเดต WTS_ORR2223
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Update WTS_ORR2223', 'Updated ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' rows in WTS_ORR2223');

    -- แทรกข้อมูลลง TblStation
    INSERT INTO [SmartX-Dock].[dbo].[TblStation]
    SELECT *, NULL, NULL, NULL, NULL 
    FROM [SmartX-Dock].[dbo].[TempLable] a
    WHERE NOT EXISTS (
        SELECT 1 
        FROM [SmartX-Dock].[dbo].[TblStation] b
        WHERE b.iTote = a.iTote AND b.seq = a.seq
    ) AND a.Route BETWEEN @sRoute AND @fRoute;

    -- บันทึก Log สำหรับการแทรก TblStation
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Insert TblStation', 'Inserted ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' rows into TblStation');

END TRY
BEGIN CATCH
    -- บันทึกข้อผิดพลาดลง LogTable
    INSERT INTO [SmartX-Dock].[dbo].[LogTable] (LogDate, Action, Message)
    VALUES (GETDATE(), 'Error', 'Error: ' + ERROR_MESSAGE());
    
    -- แสดงข้อผิดพลาด
    SELECT ERROR_MESSAGE() AS ErrorMessage;
END CATCH;
GO


