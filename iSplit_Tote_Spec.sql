SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER       PROCEDURE [dbo].[iSplit_Tote_Spec]
@iSize NVARCHAR(1) = '1'
AS
BEGIN
    SET NOCOUNT ON;
    --BEGIN TRANSACTION; -- Start Transaction
		-- เริ่มการตรวจสอบและบันทึกเวลา
	DECLARE @start_time DATETIME = GETDATE();
	PRINT 'Start time: ' + CONVERT(NVARCHAR, @start_time, 120);

    BEGIN TRY
        DECLARE @max_weight FLOAT = 22.0;
        DECLARE @max_volume FLOAT = 0.062000;
        DECLARE @batch_size INT = 7000; -- Consider adjusting based on typical data size and server resources
        DECLARE @start_row_for_batching INT = 1;
        DECLARE @end_row_for_batching INT;

        SET @max_volume = CASE WHEN @iSize = '1' THEN 0.035000 ELSE @max_volume END;
        --SET @max_weight = CASE WHEN @iSize = '1' THEN 22.0 ELSE @max_weight END;

        -- Cleanup old temp tables
        IF OBJECT_ID('tempdb..#temp1_InitialData') IS NOT NULL DROP TABLE #temp1_InitialData;
        IF OBJECT_ID('tempdb..#OrdersForPacking') IS NOT NULL DROP TABLE #OrdersForPacking;
        IF OBJECT_ID('tempdb..#PackedItems') IS NOT NULL DROP TABLE #PackedItems;
        IF OBJECT_ID('tempdb..#BatchToPack') IS NOT NULL DROP TABLE #BatchToPack;
        IF OBJECT_ID('tempdb..#xtmptote_Final') IS NOT NULL DROP TABLE #xtmptote_Final;
        IF OBJECT_ID('tempdb..#tbltemploc_localcopy') IS NOT NULL DROP TABLE #tbltemploc_localcopy;
        IF OBJECT_ID('tempdb..#RouteShelfInfo') IS NOT NULL DROP TABLE #RouteShelfInfo;
        IF OBJECT_ID('tempdb..#StoreNames') IS NOT NULL DROP TABLE #StoreNames;

        TRUNCATE TABLE [ExtaNew].[dbo].[TmpToteNew];
        TRUNCATE TABLE ExtaNew..[TblToteX];

        -- Pre-fetch route shelf info for performance
        SELECT DISTINCT Store_ID, 'Y' AS OnSheltFlag
        INTO #RouteShelfInfo
        FROM [ExtaNew].[dbo].[TblRoute] WITH (NOLOCK) -- Consider NOLOCK implications
        WHERE [TypeStore] = 'On Shelf';
        CREATE UNIQUE INDEX IX_RouteShelfInfo_StoreID ON #RouteShelfInfo(Store_ID);

        -- 1. Initial data load into #temp1_InitialData
        PRINT 'Starting: Initial data load into #temp1_InitialData';
        ;WITH cte_raw AS (
            SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as OriginalRowID_Raw, a.*
            FROM [ExtaNew].[dbo].[TempText] a WITH (NOLOCK) -- Consider NOLOCK implications
            WHERE Col6 NOT LIKE '%DELIVERY_DATE%' AND Col6 IS NOT NULL -- Added IS NOT NULL for Col6 for safety
        ),
        cte_transformed AS (
            SELECT
                r.OriginalRowID_Raw,
                TRY_CONVERT(NVARCHAR(10),
                    DATEFROMPARTS(
                        TRY_CONVERT(INT, '20' + SUBSTRING(r.Col6, 7, 2)) - CASE WHEN TRY_CONVERT(INT, SUBSTRING(r.Col6, 7, 2)) >= 43 THEN 43 ELSE 0 END,
                        TRY_CONVERT(INT, SUBSTRING(r.Col6, 4, 2)),
                        TRY_CONVERT(INT, SUBSTRING(r.Col6, 1, 2))
                    ), 103) AS Work_Date,
                r.Col1 AS SHIFT_NO, r.Col2 AS SHIFT_NAME, r.Col3 AS ROUTE_NO,
                NULL AS Tote_Id, NULL AS Seq, NULL AS NoPerTote,
                r.Col4 AS STORE_ID, r.Col5 AS STORE_NAME, r.Col6 AS DELIVERY_DATE, r.Col7 AS [NO],
                r.Col7 AS BIN_LOC,
                r.Col9 AS PRODUCT_CODE, r.Col10 AS PRODUCT_NAME, NULL AS BarcodeNo,
                r.Col11 AS PRODUCT_SIZE, LTRIM(RTRIM(r.[Col12])) AS PRODUCT_SIZE_OD,
                TRY_CONVERT(DECIMAL(18,3), r.Col13) AS UNIT_WEIGHT,
                TRY_CONVERT(DECIMAL(18,2), r.Col14) AS UNIT_WIDTH,
                TRY_CONVERT(DECIMAL(18,2), r.Col15) AS UNIT_LENGTH,
                TRY_CONVERT(DECIMAL(18,2), r.Col16) AS UNIT_HEIGHT ,
                TRY_CONVERT(DECIMAL(18,2), r.Col17) AS PICK_QTY,
                NULL AS ScanQty, NULL AS [User_Id], NULL AS Modify_Date, NULL AS PickerId,
                NULL AS StartPick, NULL AS EndPick, NULL AS [Status],
                0 AS zone_id, NULL AS ip_Form, 0 AS iAddress, 0 AS iPO, 0 AS iCAT_Original,
                0 AS Unit_Q, 0 AS Unit_W, 0 AS iQueue_Original,
                rsi.OnSheltFlag AS OnShelt,
                IIF(LEFT(r.Col9, 2) = '18', 'Y', 'N') AS PMA
            FROM cte_raw r
            LEFT JOIN #RouteShelfInfo rsi ON TRY_CONVERT(VARCHAR(50), r.Col4) = TRY_CONVERT(VARCHAR(50), rsi.Store_ID)
        )
        SELECT * INTO #temp1_InitialData FROM cte_transformed
        WHERE ((OnShelt = 'Y' AND PMA = 'N') OR OnShelt IS NULL)
          AND PICK_QTY > 0 AND Work_Date IS NOT NULL;

        CREATE INDEX IX_temp1_InitialData_CompositeKey ON #temp1_InitialData (Work_Date, STORE_ID, PRODUCT_CODE, [NO], PICK_QTY, OriginalRowID_Raw);

        DECLARE @PrintSumDecimal DECIMAL(38,2); -- For sums of DECIMAL types
        DECLARE @PrintSumBigInt BIGINT;      -- For sums of INT types

        SELECT @PrintSumDecimal = SUM(PICK_QTY) FROM #temp1_InitialData;
        PRINT 'Sum PICK_QTY from #temp1_InitialData (initial load): ' + CAST(ISNULL(@PrintSumDecimal,0) AS VARCHAR(30));

        PRINT 'Starting: Initial insert into TmpToteNew';
        INSERT INTO [ExtaNew].[dbo].[TmpToteNew] (
            Work_Date, SHIFT_NO, SHIFT_NAME, ROUTE_NO, Tote_Id, Seq, NoPerTote, STORE_ID, STORE_NAME, DELIVERY_DATE, [NO],
            BIN_LOC, PRODUCT_CODE, PRODUCT_NAME, BarcodeNo, PRODUCT_SIZE, PRODUCT_SIZE_OD, UNIT_WEIGHT, UNIT_WIDTH,
            UNIT_LENGTH, UNIT_HEIGHT, PICK_QTY, ScanQty, [User_Id], Modify_Date, PickerId, StartPick, EndPick, [Status],
            zone_id, ip_Form, iAddress, iPO, iCAT, Unit_Q, Unit_W, iQueue
        ) SELECT
            Work_Date, SHIFT_NO, SHIFT_NAME, ROUTE_NO, Tote_Id, Seq, NoPerTote, STORE_ID, STORE_NAME, DELIVERY_DATE, [NO], BIN_LOC,
            PRODUCT_CODE, PRODUCT_NAME, BarcodeNo, PRODUCT_SIZE, PRODUCT_SIZE_OD, UNIT_WEIGHT, UNIT_WIDTH, UNIT_LENGTH, UNIT_HEIGHT,
            PICK_QTY, ScanQty, [User_Id], Modify_Date, PickerId, StartPick, EndPick, [Status], zone_id, ip_Form,
            iAddress, iPO, iCAT_Original, Unit_Q, Unit_W, iQueue_Original
        FROM #temp1_InitialData;

        PRINT 'Starting: Update TblProduct';
        INSERT INTO TblProduct (product_Id, product_Name, [Weight], barcode_No, iPO)
        SELECT DISTINCT ttn.PRODUCT_CODE, ttn.PRODUCT_NAME, ttn.UNIT_WEIGHT, ttn.BarcodeNo, 0
        FROM [ExtaNew].[dbo].[TmpToteNew] ttn
        WHERE ttn.PRODUCT_CODE IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM TblProduct tp WITH (NOLOCK) WHERE tp.product_Id = ttn.PRODUCT_CODE);

        PRINT 'Starting: Update iExta..TblZone';
        UPDATE z
        SET z.SKU = tt.Col9
        FROM iExta..[TblZone] z
        JOIN [ExtaNew].[dbo].[TempText] tt ON tt.Col8 = z.[Location]
        WHERE tt.Col6 NOT LIKE '%DELIVERY_DATE%';

        PRINT 'Starting: Update TmpToteNew from TblProduct';
        UPDATE T
        SET UNIT_WEIGHT = P.[Weight],
            UNIT_WIDTH = P.W,
            UNIT_LENGTH = P.L,
            UNIT_HEIGHT = P.H,
            BarcodeNo = P.barcode_No,
            iQueue = ROUND( @max_volume / NULLIF(CASE WHEN @iSize = '1' THEN ISNULL(P.QtySmall, 1.0) ELSE ISNULL(P.iQtyPut, 1.0) END, 0), 7),
            Unit_W = P.[Weight],
            iCAT = P.ZoneId
        FROM [ExtaNew].[dbo].[TmpToteNew] T
        JOIN TblProduct P ON T.PRODUCT_CODE = P.product_Id;

        PRINT 'Starting: Create #tbltemploc_localcopy';
        SELECT * INTO #tbltemploc_localcopy FROM [iExta].[dbo].[tbltemploc] WITH (NOLOCK);
        CREATE INDEX IX_tbltemploc_localcopy_iSKU ON #tbltemploc_localcopy(iSKU);

        PRINT 'Starting: Populate #OrdersForPacking';
        CREATE TABLE #OrdersForPacking (
            OrderLineID_Ref INT PRIMARY KEY,
            PackingSortOrder INT,
            OrderID INT,
            ItemWeight_Unit FLOAT,
            ItemVolumeFactor_Unit FLOAT,
            iSKU NVARCHAR(50),
            TotalQuantity INT,
            iCAT_FromProduct NVARCHAR(20)
        );
        CREATE UNIQUE INDEX idx_OrdersForPacking_PackingSortOrder ON #OrdersForPacking (PackingSortOrder);
        CREATE INDEX idx_OrdersForPacking_OrderLineID_Ref_Includes ON #OrdersForPacking (OrderLineID_Ref) INCLUDE (ItemVolumeFactor_Unit, ItemWeight_Unit);

        INSERT INTO #OrdersForPacking (OrderLineID_Ref, PackingSortOrder, OrderID, ItemWeight_Unit, ItemVolumeFactor_Unit, iSKU, TotalQuantity, iCAT_FromProduct)
        SELECT
            t1.OriginalRowID_Raw,
            ROW_NUMBER() OVER (
                ORDER BY
                    ttn.STORE_ID,
                    ttn.iCAT,
                    CASE WHEN (b.iLOC = '1' OR b.iLOC IS NULL) THEN '1' ELSE b.iLOC END,
                    ISNULL(b.iZone, 999),
                    ttn.UNIT_WEIGHT DESC,
                    ttn.PICK_QTY DESC
            ) AS PackingSortOrder,
            TRY_CONVERT(INT, ttn.STORE_ID) AS OrderID,
            ROUND(CAST(ttn.UNIT_WEIGHT AS FLOAT) / 1000.0, 3) AS ItemWeight_Unit,
            ttn.iQueue AS ItemVolumeFactor_Unit,
            ttn.PRODUCT_CODE,
            TRY_CONVERT(INT, ttn.PICK_QTY) AS TotalQuantity,
            ttn.iCAT AS iCAT_FromProduct
        FROM [ExtaNew].[dbo].[TmpToteNew] ttn WITH (NOLOCK)
        JOIN #temp1_InitialData t1 ON ttn.Work_Date = t1.Work_Date
                                    AND ttn.STORE_ID = t1.STORE_ID
                                    AND ttn.PRODUCT_CODE = t1.PRODUCT_CODE
                                    AND ttn.[NO] = t1.[NO]
                                    AND TRY_CONVERT(DECIMAL(18,2),ttn.PICK_QTY) = TRY_CONVERT(DECIMAL(18,2),t1.PICK_QTY)
        LEFT JOIN #tbltemploc_localcopy b ON TRY_CONVERT(NVARCHAR(50), ttn.PRODUCT_CODE) = b.iSKU
        WHERE TRY_CONVERT(INT, ttn.PICK_QTY) > 0
          AND ttn.iQueue IS NOT NULL AND ttn.iQueue > 0
          AND ttn.iCAT IS NOT NULL;

        SELECT @PrintSumBigInt = SUM(TotalQuantity) FROM #OrdersForPacking;
        PRINT 'Sum TotalQuantity from #OrdersForPacking: ' + CAST(ISNULL(@PrintSumBigInt,0) AS VARCHAR(30));

        PRINT 'Starting: Packing loop';
        IF OBJECT_ID('tempdb..#PackedItems') IS NOT NULL DROP TABLE #PackedItems;
        CREATE TABLE #PackedItems (
            OrderLineID_Ref INT,
            OrderID INT,
            ItemWeight_Unit FLOAT,
            ItemVolumeFactor_Unit FLOAT,
            iSKU NVARCHAR(50),
            QuantityInTote INT,
            BasketID INT,
            iCAT_UsedInPacking NVARCHAR(20)
        );
        CREATE CLUSTERED INDEX CIX_PackedItems ON #PackedItems (OrderID, iCAT_UsedInPacking, BasketID, OrderLineID_Ref, iSKU);

        DECLARE @count_orders_to_pack INT;
        SELECT @count_orders_to_pack = ISNULL(MAX(PackingSortOrder),0) FROM #OrdersForPacking;
        SET @start_row_for_batching = 1;

        WHILE @start_row_for_batching <= @count_orders_to_pack
        BEGIN
            SET @end_row_for_batching = @start_row_for_batching + @batch_size - 1;
            PRINT 'Processing batch: ' + CAST(@start_row_for_batching AS VARCHAR(10)) + ' to ' + CAST(@end_row_for_batching AS VARCHAR(10));

            IF OBJECT_ID('tempdb..#BatchToPack') IS NOT NULL DROP TABLE #BatchToPack;
            SELECT * INTO #BatchToPack
            FROM #OrdersForPacking
            WHERE PackingSortOrder BETWEEN @start_row_for_batching AND @end_row_for_batching;
            CREATE UNIQUE CLUSTERED INDEX CIX_BatchToPack_PackingSortOrder ON #BatchToPack(PackingSortOrder);

            DECLARE @current_packing_item_sort_order INT, @actual_batch_packing_end_row INT;
            SELECT @current_packing_item_sort_order = MIN(PackingSortOrder), @actual_batch_packing_end_row = MAX(PackingSortOrder)
            FROM #BatchToPack;

            DECLARE @BasketID INT = 0;
            DECLARE @current_tote_weight FLOAT = 0;
            DECLARE @current_tote_volume_factor_sum FLOAT = 0;
            DECLARE @current_processing_orderid INT = -1;
            DECLARE @current_processing_iCat NVARCHAR(20) = '###INITIAL_INVALID_CAT###';

            WHILE @current_packing_item_sort_order IS NOT NULL AND @current_packing_item_sort_order <= @actual_batch_packing_end_row
            BEGIN
                DECLARE @LoopOrderLineID_Ref INT, @LoopOrderID_Pack INT, @LoopItemUnitWeight FLOAT, @LoopItemUnitVolumeFactor FLOAT,
                        @LoopSKU_Pack NVARCHAR(50), @LoopItemLineTotalQuantity INT, @LoopItemPackingCat NVARCHAR(20);

                SELECT TOP 1
                       @LoopOrderLineID_Ref = OrderLineID_Ref, @LoopOrderID_Pack = OrderID, @LoopItemUnitWeight = ItemWeight_Unit,
                       @LoopItemUnitVolumeFactor = ItemVolumeFactor_Unit, @LoopSKU_Pack = iSKU,
                       @LoopItemLineTotalQuantity = TotalQuantity, @LoopItemPackingCat = iCAT_FromProduct
                FROM #BatchToPack WHERE PackingSortOrder = @current_packing_item_sort_order;

                IF @LoopOrderID_Pack IS NULL
                BEGIN
                    SELECT @current_packing_item_sort_order = MIN(PackingSortOrder)
                    FROM #BatchToPack WHERE PackingSortOrder > @current_packing_item_sort_order;
                    CONTINUE;
                END

                IF @LoopOrderID_Pack != @current_processing_orderid OR @LoopItemPackingCat != @current_processing_iCat
                BEGIN
                    SET @BasketID = 1;
                    SET @current_tote_weight = 0;
                    SET @current_tote_volume_factor_sum = 0;
                    SET @current_processing_orderid = @LoopOrderID_Pack;
                    SET @current_processing_iCat = @LoopItemPackingCat;
                END
                ELSE IF @BasketID = 0
                BEGIN
                     SET @BasketID = 1;
                END


                DECLARE @qty_remaining_for_this_line INT = @LoopItemLineTotalQuantity;
                WHILE @qty_remaining_for_this_line > 0
                BEGIN
                    IF (@current_tote_weight + @LoopItemUnitWeight <= @max_weight) AND
                       (@current_tote_volume_factor_sum + @LoopItemUnitVolumeFactor <= @max_volume)
                    BEGIN
                        MERGE #PackedItems AS target
                        USING (SELECT @LoopOrderLineID_Ref, @LoopOrderID_Pack, @LoopItemUnitWeight, @LoopItemUnitVolumeFactor, @LoopSKU_Pack, 1 AS Qty, @BasketID, @LoopItemPackingCat)
                            AS source (OrderLineID_Ref, OrderID, ItemWeight_Unit, ItemVolumeFactor_Unit, iSKU, QuantityInTote, BasketID, iCAT_UsedInPacking)
                        ON (target.OrderLineID_Ref = source.OrderLineID_Ref AND target.BasketID = source.BasketID AND target.iSKU = source.iSKU AND target.OrderID = source.OrderID AND target.iCAT_UsedInPacking = source.iCAT_UsedInPacking)
                        WHEN MATCHED THEN
                            UPDATE SET target.QuantityInTote = target.QuantityInTote + source.QuantityInTote
                        WHEN NOT MATCHED BY TARGET THEN
                            INSERT (OrderLineID_Ref, OrderID, ItemWeight_Unit, ItemVolumeFactor_Unit, iSKU, QuantityInTote, BasketID, iCAT_UsedInPacking)
                            VALUES (source.OrderLineID_Ref, source.OrderID, source.ItemWeight_Unit, source.ItemVolumeFactor_Unit, source.iSKU, source.QuantityInTote, source.BasketID, source.iCAT_UsedInPacking);

                        SET @current_tote_weight += @LoopItemUnitWeight;
                        SET @current_tote_volume_factor_sum += @LoopItemUnitVolumeFactor;
                        SET @qty_remaining_for_this_line -= 1;
                    END
                    ELSE
                    BEGIN
                        SET @BasketID += 1;
                        SET @current_tote_weight = 0;
                        SET @current_tote_volume_factor_sum = 0;

                        IF (@LoopItemUnitWeight <= @max_weight) AND (@LoopItemUnitVolumeFactor <= @max_volume)
                        BEGIN
                            MERGE #PackedItems AS target
                            USING (SELECT @LoopOrderLineID_Ref, @LoopOrderID_Pack, @LoopItemUnitWeight, @LoopItemUnitVolumeFactor, @LoopSKU_Pack, 1 AS Qty, @BasketID, @LoopItemPackingCat)
                                AS source (OrderLineID_Ref, OrderID, ItemWeight_Unit, ItemVolumeFactor_Unit, iSKU, QuantityInTote, BasketID, iCAT_UsedInPacking)
                            ON (target.OrderLineID_Ref = source.OrderLineID_Ref AND target.BasketID = source.BasketID AND target.iSKU = source.iSKU AND target.OrderID = source.OrderID AND target.iCAT_UsedInPacking = source.iCAT_UsedInPacking)
                            WHEN MATCHED THEN
                                UPDATE SET target.QuantityInTote = target.QuantityInTote + source.QuantityInTote
                            WHEN NOT MATCHED BY TARGET THEN
                                INSERT (OrderLineID_Ref, OrderID, ItemWeight_Unit, ItemVolumeFactor_Unit, iSKU, QuantityInTote, BasketID, iCAT_UsedInPacking)
                                VALUES (source.OrderLineID_Ref, source.OrderID, source.ItemWeight_Unit, source.ItemVolumeFactor_Unit, source.iSKU, source.QuantityInTote, source.BasketID, source.iCAT_UsedInPacking);

                            SET @current_tote_weight += @LoopItemUnitWeight;
                            SET @current_tote_volume_factor_sum += @LoopItemUnitVolumeFactor;
                            SET @qty_remaining_for_this_line -= 1;
                        END
                        ELSE
                        BEGIN
                            PRINT 'Warning: Item ' + ISNULL(@LoopSKU_Pack, 'UNKNOWN_SKU') +
                                  ' (Weight: ' + CAST(@LoopItemUnitWeight AS VARCHAR(20)) +
                                  ', VolFactor: ' + CAST(@LoopItemUnitVolumeFactor AS VARCHAR(20)) +
                                  ') exceeds max tote capacity (Weight: ' + CAST(@max_weight AS VARCHAR(20)) +
                                  ', VolFactor: ' + CAST(@max_volume AS VARCHAR(20)) + '). Forcing pack into its own tote.';

                            MERGE #PackedItems AS target
                            USING (SELECT @LoopOrderLineID_Ref, @LoopOrderID_Pack, @LoopItemUnitWeight, @LoopItemUnitVolumeFactor, @LoopSKU_Pack, 1 AS Qty, @BasketID, @LoopItemPackingCat)
                                AS source (OrderLineID_Ref, OrderID, ItemWeight_Unit, ItemVolumeFactor_Unit, iSKU, QuantityInTote, BasketID, iCAT_UsedInPacking)
                            ON (target.OrderLineID_Ref = source.OrderLineID_Ref AND target.BasketID = source.BasketID AND target.iSKU = source.iSKU AND target.OrderID = source.OrderID AND target.iCAT_UsedInPacking = source.iCAT_UsedInPacking)
                            WHEN MATCHED THEN
                                UPDATE SET target.QuantityInTote = target.QuantityInTote + source.QuantityInTote
                            WHEN NOT MATCHED BY TARGET THEN
                                INSERT (OrderLineID_Ref, OrderID, ItemWeight_Unit, ItemVolumeFactor_Unit, iSKU, QuantityInTote, BasketID, iCAT_UsedInPacking)
                                VALUES (source.OrderLineID_Ref, source.OrderID, source.ItemWeight_Unit, source.ItemVolumeFactor_Unit, source.iSKU, source.QuantityInTote, source.BasketID, source.iCAT_UsedInPacking);

                            SET @current_tote_weight += @LoopItemUnitWeight;
                            SET @current_tote_volume_factor_sum += @LoopItemUnitVolumeFactor;
                            SET @qty_remaining_for_this_line -= 1;
                        END
                    END
                END 

                SELECT @current_packing_item_sort_order = MIN(PackingSortOrder)
                FROM #BatchToPack WHERE PackingSortOrder > @current_packing_item_sort_order;

            END 
            SET @start_row_for_batching = @end_row_for_batching + 1;
            DROP TABLE #BatchToPack;
        END 

        SELECT @PrintSumBigInt = SUM(QuantityInTote) FROM #PackedItems;
        PRINT 'Sum QuantityInTote from #PackedItems: ' + CAST(ISNULL(@PrintSumBigInt,0) AS VARCHAR(30));

        PRINT 'Starting: Populate TblToteX';
        DECLARE @iDate DATE = (SELECT TOP (1) TRY_CONVERT(DATE, Work_Date, 103) FROM #temp1_InitialData WHERE Work_Date IS NOT NULL ORDER BY Work_Date);
        IF @iDate IS NULL SET @iDate = GETDATE();

        ;WITH CteToteX AS (
            SELECT
                pi.OrderLineID_Ref AS no1,
                pi.OrderID AS store_id,
                pi.iSKU AS product_code,
                pi.iCAT_UsedInPacking AS icat,
                pi.ItemVolumeFactor_Unit AS unit_q,
                pi.QuantityInTote AS pick_qty,
                pi.ItemVolumeFactor_Unit * pi.QuantityInTote AS vol,
                SUM(pi.ItemVolumeFactor_Unit * pi.QuantityInTote) OVER (
                    PARTITION BY pi.OrderID, pi.BasketID, pi.iCAT_UsedInPacking
                    ORDER BY pi.OrderLineID_Ref
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS volsum,
                pi.BasketID AS boxid,
                @iDate AS iDate,
                MAX(pi.BasketID) OVER (PARTITION BY pi.OrderID, pi.iCAT_UsedInPacking) AS maxbox,
                CONVERT(NVARCHAR(5), pi.BasketID) + N'/' + CONVERT(NVARCHAR(5), MAX(pi.BasketID) OVER (PARTITION BY pi.OrderID, pi.iCAT_UsedInPacking)) AS box2,
                RIGHT(N'00' + CONVERT(NVARCHAR(2), MONTH(@iDate)), 2) +
                RIGHT(N'00' + CONVERT(NVARCHAR(2), DAY(@iDate)), 2) +
                RIGHT(N'00000' + CONVERT(NVARCHAR(5), pi.OrderID), 5) +
                RIGHT(N'00' + CONVERT(NVARCHAR(2), pi.BasketID), 2) +
                CONVERT(NVARCHAR(20), pi.iCAT_UsedInPacking) AS iTote
            FROM #PackedItems pi
            WHERE pi.QuantityInTote > 0
        )
        INSERT INTO ExtaNew..TblToteX (no1, store_id, product_code, icat, unit_q, pick_qty, vol, volsum, boxid, iDate, maxbox, box2, iTote)
        SELECT no1, store_id, product_code, icat, unit_q, pick_qty, vol, volsum, boxid, iDate, maxbox, box2, iTote
        FROM CteToteX
        WHERE iTote IS NOT NULL;

        SELECT @PrintSumBigInt = SUM(pick_qty) FROM ExtaNew..TblToteX;
        PRINT 'Sum pick_qty from TblToteX: ' + CAST(ISNULL(@PrintSumBigInt,0) AS VARCHAR(30));

        PRINT 'Starting: Populate #xtmptote_Final';
        ;WITH CteJoinFinalTote AS (
            SELECT
                tX.pick_qty AS QtyInThisTote,
                tX.iTote,
                tX.box2,
                orig.Work_Date, orig.SHIFT_NO, orig.SHIFT_NAME, orig.ROUTE_NO,
                orig.STORE_ID, orig.STORE_NAME AS Original_STORE_NAME,
                orig.DELIVERY_DATE,
                orig.[NO] AS Original_LineNO_FromFile,
                orig.BIN_LOC AS Original_BIN_LOC,
                orig.PRODUCT_CODE,
                orig.PRODUCT_NAME AS Original_PRODUCT_NAME,
                orig.BarcodeNo AS Original_BarcodeNo,
                orig.PRODUCT_SIZE,
                op.ItemVolumeFactor_Unit,
                op.ItemWeight_Unit,
                orig.UNIT_WIDTH AS Original_UNIT_WIDTH,
                orig.UNIT_LENGTH AS Original_UNIT_LENGTH,
                orig.UNIT_HEIGHT AS Original_UNIT_HEIGHT,
                orig.PICK_QTY AS Original_LineTotalPICK_QTY,
                orig.ScanQty, orig.[User_Id], orig.Modify_Date, orig.PickerId, orig.StartPick, orig.EndPick,
                orig.[Status] AS Original_Status,
                orig.zone_id AS Original_ZoneID,
                orig.ip_Form, orig.iAddress, orig.iPO,
                tX.icat AS iCAT_InTote,
                orig.PRODUCT_SIZE_OD
            FROM ExtaNew..TblToteX tX
            JOIN #temp1_InitialData orig ON tX.no1 = orig.OriginalRowID_Raw
            LEFT JOIN #OrdersForPacking op ON orig.OriginalRowID_Raw = op.OrderLineID_Ref
            WHERE tX.pick_qty > 0 AND tX.iTote IS NOT NULL
        )
        SELECT DISTINCT
               Work_Date, SHIFT_NO, SHIFT_NAME, ROUTE_NO, iTote AS Tote_Id, box2 AS Seq,
               NULL AS NoPerTote,
               STORE_ID, Original_STORE_NAME AS STORE_NAME, DELIVERY_DATE,
               RIGHT(iTote, 7) AS [NO],
               Original_BIN_LOC AS BIN_LOC, PRODUCT_CODE, Original_PRODUCT_NAME AS PRODUCT_NAME, Original_BarcodeNo AS BarcodeNo,
               PRODUCT_SIZE,
               ItemVolumeFactor_Unit AS Unit_Q,
               ItemWeight_Unit AS UNIT_WEIGHT,
               Original_UNIT_WIDTH AS UNIT_WIDTH, Original_UNIT_LENGTH AS UNIT_LENGTH, Original_UNIT_HEIGHT AS UNIT_HEIGHT,
               QtyInThisTote AS PICK_QTY,
               ScanQty, [User_Id], Modify_Date, PickerId, StartPick, EndPick,
               CASE WHEN Original_PRODUCT_NAME IS NOT NULL THEN 0 ELSE Original_Status END AS [Status],
               COALESCE(Original_ZoneID, 0) AS zone_id,
               ip_Form, iAddress, iPO, iCAT_InTote AS iCAT, PRODUCT_SIZE_OD,
               ItemWeight_Unit AS Unit_W,
               ItemVolumeFactor_Unit AS iQueue
        INTO #xtmptote_Final
        FROM CteJoinFinalTote
        WHERE QtyInThisTote > 0;

        SELECT @PrintSumBigInt = SUM(PICK_QTY) FROM #xtmptote_Final;
        PRINT 'Sum PICK_QTY from #xtmptote_Final: ' + CAST(ISNULL(@PrintSumBigInt,0) AS VARCHAR(30));

        PRINT 'Starting: Final insert into TmpToteNew from #xtmptote_Final';
        TRUNCATE TABLE [ExtaNew].[dbo].[TmpToteNew];
        INSERT INTO [ExtaNew].[dbo].[TmpToteNew] (
            Work_Date, SHIFT_NO, SHIFT_NAME, ROUTE_NO, Tote_Id, Seq, NoPerTote,
            STORE_ID, STORE_NAME, DELIVERY_DATE, [NO], BIN_LOC, PRODUCT_CODE, PRODUCT_NAME,
            BarcodeNo, PRODUCT_SIZE, Unit_Q, UNIT_WEIGHT, UNIT_WIDTH, UNIT_LENGTH, UNIT_HEIGHT,
            PICK_QTY, ScanQty, [User_Id], Modify_Date, PickerId, StartPick, EndPick, [Status],
            zone_id, ip_Form, iAddress, iPO, iCAT, PRODUCT_SIZE_OD, Unit_W, iQueue
        )
        SELECT * FROM #xtmptote_Final;

        SELECT DISTINCT STORE_ID, STORE_NAME
        INTO #StoreNames
        FROM #temp1_InitialData
        WHERE STORE_ID IS NOT NULL AND STORE_NAME IS NOT NULL;
        CREATE UNIQUE INDEX IX_StoreNames_StoreID ON #StoreNames(STORE_ID);

        PRINT 'Starting: Final updates on TmpToteNew';
        UPDATE T
        SET T.UNIT_WEIGHT = COALESCE(T.UNIT_WEIGHT, P.[Weight]/1000.0),
            T.UNIT_WIDTH = COALESCE(T.UNIT_WIDTH, P.W),
            T.UNIT_LENGTH = COALESCE(T.UNIT_LENGTH, P.L),
            T.UNIT_HEIGHT = COALESCE(T.UNIT_HEIGHT, P.H),
            T.BarcodeNo = COALESCE(T.BarcodeNo, P.barcode_No),
            T.Unit_W = COALESCE(T.Unit_W, P.[Weight]/1000.0),
            T.iCAT = COALESCE(T.iCAT, P.ZoneId),
            T.BIN_LOC = COALESCE(T.BIN_LOC, P.SEQ),
            T.PRODUCT_NAME = COALESCE(T.PRODUCT_NAME, P.product_Name),
            T.STORE_NAME = COALESCE(T.STORE_NAME, sn.STORE_NAME)
        FROM [ExtaNew].[dbo].[TmpToteNew] T
        JOIN TblProduct P ON T.PRODUCT_CODE = P.product_Id
        LEFT JOIN #StoreNames sn ON T.STORE_ID = sn.STORE_ID;

        PRINT 'Starting: Calculate NoPerTote';
        ;WITH CteNoPerTote AS (
            SELECT
                ROW_NUMBER() OVER (PARTITION BY Tote_Id ORDER BY PRODUCT_CODE, PICK_QTY) AS iNo,
                STORE_ID, PRODUCT_CODE, Tote_Id, PICK_QTY
            FROM [ExtaNew].[dbo].[TmpToteNew]
        )
        UPDATE ttn
        SET ttn.NoPerTote = c.iNo
        FROM [ExtaNew].[dbo].[TmpToteNew] ttn
        JOIN CteNoPerTote c ON ttn.Tote_Id = c.Tote_Id
                           AND ttn.PRODUCT_CODE = c.PRODUCT_CODE
                           AND ttn.STORE_ID = c.STORE_ID
                           AND ttn.PICK_QTY = c.PICK_QTY;

        SELECT @PrintSumBigInt = SUM(pick_qty) FROM ExtaNew..TblToteX;
        PRINT 'FINAL Sum pick_qty from TblToteX: ' + CAST(ISNULL(@PrintSumBigInt,0) AS VARCHAR(30));

        SELECT @PrintSumBigInt = SUM(PICK_QTY) FROM [ExtaNew].[dbo].[TmpToteNew];
        PRINT 'FINAL Sum PICK_QTY from TmpToteNew: ' + CAST(ISNULL(@PrintSumBigInt,0) AS VARCHAR(30));

        PRINT 'Starting: Format Tote_Id';
        UPDATE [ExtaNew].[dbo].[TmpToteNew]
        SET Tote_Id = CASE
                        WHEN LEFT(Tote_Id,2)='12' THEN 'DC'+SUBSTRING(Tote_Id,3,LEN(Tote_Id)-2)
                        WHEN LEFT(Tote_Id,2)='11' THEN 'DB'+SUBSTRING(Tote_Id,3,LEN(Tote_Id)-2)
                        WHEN LEFT(Tote_Id,2)='10' THEN 'DA'+SUBSTRING(Tote_Id,3,LEN(Tote_Id)-2)
                        ELSE 'D'+Tote_Id
                      END
        WHERE Tote_Id IS NOT NULL;

        PRINT 'Data processing completed successfully.';
        --COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            --ROLLBACK TRANSACTION;

        PRINT 'An error occurred: ' + ERROR_MESSAGE();
        PRINT 'Error Line: ' + CAST(ERROR_LINE() AS VARCHAR(10));
        PRINT 'Error Severity: ' + CAST(ERROR_SEVERITY() AS VARCHAR(10));
        PRINT 'Error State: ' + CAST(ERROR_STATE() AS VARCHAR(10));
        THROW;
    END CATCH

    IF OBJECT_ID('tempdb..#temp1_InitialData') IS NOT NULL DROP TABLE #temp1_InitialData;
    IF OBJECT_ID('tempdb..#OrdersForPacking') IS NOT NULL DROP TABLE #OrdersForPacking;
    IF OBJECT_ID('tempdb..#PackedItems') IS NOT NULL DROP TABLE #PackedItems;
    IF OBJECT_ID('tempdb..#BatchToPack') IS NOT NULL DROP TABLE #BatchToPack;
    IF OBJECT_ID('tempdb..#xtmptote_Final') IS NOT NULL DROP TABLE #xtmptote_Final;
    IF OBJECT_ID('tempdb..#tbltemploc_localcopy') IS NOT NULL DROP TABLE #tbltemploc_localcopy;
    IF OBJECT_ID('tempdb..#RouteShelfInfo') IS NOT NULL DROP TABLE #RouteShelfInfo;
    IF OBJECT_ID('tempdb..#StoreNames') IS NOT NULL DROP TABLE #StoreNames;


	PRINT 'Processing completed. End time: ' + CONVERT(NVARCHAR, GETDATE(), 120);
	
	exec ExtaNew..UpToBOM;

END;
GO


