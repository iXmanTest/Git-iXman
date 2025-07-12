SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER proc [dbo].[iSplit_Tote]
as

    SET NOCOUNT ON;

    DECLARE @max_weight FLOAT = 22;
    DECLARE @max_volume FLOAT = 0.062000;
    DECLARE @batch_size INT = 10000; -- ขนาดของแต่ละกลุ่ม
    DECLARE @start_row INT = 1;
    DECLARE @end_row INT;

	IF OBJECT_ID('tbltemploc') IS NOT NULL
	DROP TABLE tbltemploc; 
	SELECT * 
	INTO tbltemploc
	FROM [iExta].[dbo].[tbltemploc] WITH (NOLOCK);

    IF OBJECT_ID('tempdb..#Orders') IS NOT NULL DROP TABLE #Orders;
    CREATE TABLE #Orders(
        iRow INT,
        OrderID INT,
        Weight FLOAT,
        Volume FLOAT,
        iSKU NVARCHAR(50),
        Quantity INT,
        iCat NVARCHAR(20),
        INDEX idx_Orders (OrderID, iSKU),
        INDEX idx_Orders_iCat (iCat));

    IF OBJECT_ID('tempdb..##TempOrders') IS NULL
    BEGIN
    CREATE TABLE ##TempOrders (
        iRow INT,
        OrderID INT,
        Weight FLOAT,
        Volume FLOAT,
        iSKU NVARCHAR(50),
        Quantity INT,
        BasketID INT,
        iCat NVARCHAR(20),
        INDEX IDX_TempOrders (iSKU, BasketID),
        INDEX IDX_TempOrders_OrderID (OrderID),
        INDEX IDX_TempOrders_iCat (iCat));
	END;

	INSERT INTO #Orders
	SELECT ROW_NUMBER() OVER (ORDER BY store_id, icat, CASE WHEN (b.iLOC = '1' OR b.iLOC IS NULL) THEN '1' ELSE b.iLOC END, ISNULL(b.iZone, 999), UNIT_WEIGHT DESC, pick_qty DESC) AS iRow,
		store_id,
		ROUND(cast(Unit_W as money) / 1000.0, 2),
		ROUND(iQueue, 7),
		product_code,
		pick_qty,
		iCat
	FROM ExtaNew..TmpToteNew a
		LEFT JOIN dbo.tbltemploc b ON TRY_CONVERT(NVARCHAR, a.PRODUCT_CODE) = b.iSKU
	WHERE NOT EXISTS (
		SELECT 1
		FROM ##TempOrders x
		WHERE a.store_id = x.OrderID AND a.product_code = x.iSKU
	);

    DECLARE @count INT;
    SELECT @count = COUNT(*)
    FROM #Orders WITH (NOLOCK)
    --OPTION (MAXDOP 6);

    WHILE @start_row <= @count
    BEGIN
    SET @end_row = @start_row + @batch_size - 1;

    -- สร้างตารางชั่วคราวสำหรับเก็บข้อมูลในกลุ่มย่อย
    IF OBJECT_ID('tempdb..#BatchOrders') IS NOT NULL DROP TABLE #BatchOrders;
    CREATE TABLE #BatchOrders (
        iRow INT,
        OrderID INT,
        Weight FLOAT,
        Volume FLOAT,
        iSKU NVARCHAR(50),
        Quantity INT,
        iCat NVARCHAR(20));

    INSERT INTO #BatchOrders
    SELECT *
    FROM #Orders
    WHERE iRow BETWEEN @start_row AND @end_row;

    DECLARE @i INT = @start_row;
    DECLARE @BasketID INT = 1;
    DECLARE @current_weight FLOAT = 0;
    DECLARE @current_volume FLOAT = 0;
    DECLARE @current_orderid INT = 0;
    DECLARE @current_iCat NVARCHAR(20) = '';

    WHILE @i <= @end_row AND @i <= @count
        BEGIN
        DECLARE @OrderID INT, @Weight FLOAT, @Volume FLOAT, @iSKU NVARCHAR(50), @Quantity INT, @iCat NVARCHAR(20);
        SELECT
            @OrderID = OrderID,
            @Weight = Weight,
            @Volume = Volume,
            @iSKU = iSKU,
            @Quantity = Quantity,
            @iCat = iCat
        FROM #BatchOrders
        WHERE iRow = @i;

        IF @OrderID != @current_orderid OR @iCat != @current_iCat
            BEGIN
            SET @BasketID = 1;
            SET @current_weight = 0;
            SET @current_volume = 0;
            SET @current_orderid = @OrderID;
            SET @current_iCat = @iCat;
        END

        WHILE @Quantity > 0
            BEGIN
            IF (@current_weight + @Weight <= @max_weight) AND (@current_volume + @Volume <= @max_volume)
                BEGIN
                MERGE ##TempOrders AS target
                    USING (SELECT @i AS iRow, @OrderID AS OrderID, @Weight AS Weight, @Volume AS Volume, @iSKU AS iSKU, 1 AS Quantity, @BasketID AS BasketID, @iCat AS iCat) AS source
                    ON (target.iSKU = source.iSKU AND target.BasketID = source.BasketID AND target.OrderID = source.OrderID AND target.iCat = source.iCat)
                    WHEN MATCHED THEN 
                        UPDATE SET target.Quantity = target.Quantity + 1
                    WHEN NOT MATCHED THEN
                        INSERT (iRow, OrderID, Weight, Volume, iSKU, Quantity, BasketID, iCat)
                        VALUES (source.iRow, source.OrderID, source.Weight, source.Volume, source.iSKU, source.Quantity, source.BasketID, source.iCat);

                SET @current_weight = @current_weight + @Weight;
                SET @current_volume = @current_volume + @Volume;
                SET @Quantity = @Quantity - 1;
            END
                ELSE
                BEGIN
                SET @BasketID = @BasketID + 1;
                SET @current_weight = 0;
                SET @current_volume = 0;
            END
        END;

        SET @i = @i + 1;
    END;

    SET @start_row = @end_row + 1;
END;

    -- Rebuild indexes to maintain performance
    ALTER INDEX idx_Orders ON #Orders REBUILD;
    ALTER INDEX IDX_TempOrders ON ##TempOrders REBUILD;

	--truncate table TblToteX

	declare @iDate date=(SELECT top(1) convert(date,Work_Date,103) FROM TmpToteNew);

	--declare @icat int=1;
	--;with cte as
	--(
	--select no1, store_id, product_code, icat, unit_q, pick_qty, vol, volsum, boxid, iDate, maxbox, convert(nvarchar(5),BasketID) + '/'+ convert(nvarchar(5),maxbox) as box2
	--,right('00'+convert(nvarchar,MONTH(@iDate)),2)+right('00'+convert(nvarchar,DAY(@iDate)),2)+right('0000'+convert(nvarchar,OrderID),5)+right('00'+convert(nvarchar,BasketID),2)+convert(nvarchar,icat) as iTote      
	--from (
	--SELECT iRow no1, OrderID store_id,iSKU product_code,Volume unit_q,Quantity pick_qty,Volume*Quantity vol,0 volsum,BasketID boxid,@iDate idate,*,max(BasketID) over (partition by OrderID,icat) as maxbox from ##TempOrders) tb
	--)
	--insert into TblToteX
	--select * from cte
	--where cte.store_id  not in(select b.store_id from TblToteX b with (nolock) where store_id =b.store_id and cte.iTote=b.iTote and cte.product_code =b.product_code );

	;WITH cte AS (
        SELECT
            iRow AS no1,
            OrderID AS store_id,
            iSKU AS product_code,
            icat,
            Volume AS unit_q,
            Quantity AS pick_qty,
            Volume * Quantity AS vol,
            SUM(Volume * Quantity) OVER (PARTITION BY RIGHT('00' + CONVERT(NVARCHAR, MONTH(@iDate)), 2) + 
												RIGHT('00' + CONVERT(NVARCHAR, DAY(@iDate)), 2) + 
												RIGHT('0000' + CONVERT(NVARCHAR, OrderID), 5) + 
												RIGHT('00' + CONVERT(NVARCHAR, BasketID), 2) + 
												CONVERT(NVARCHAR, icat)
										ORDER BY iRow
										ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS volsum,
            BasketID AS boxid,
            @iDate AS iDate,
            MAX(BasketID) OVER (PARTITION BY OrderID, icat) AS maxbox,
            CONVERT(NVARCHAR(5), BasketID) + '/' + CONVERT(NVARCHAR(5), MAX(BasketID) OVER (PARTITION BY OrderID, icat)) AS box2,
            RIGHT('00' + CONVERT(NVARCHAR, MONTH(@iDate)), 2) + 
		RIGHT('00' + CONVERT(NVARCHAR, DAY(@iDate)), 2) + 
		RIGHT('0000' + CONVERT(NVARCHAR, OrderID), 5) + 
		RIGHT('00' + CONVERT(NVARCHAR, BasketID), 2) + 
		CONVERT(NVARCHAR, icat) AS iTote
        FROM ##TempOrders )
    INSERT INTO TblToteX
    SELECT *
    FROM cte
    WHERE NOT EXISTS ( SELECT 1 FROM TblToteX b WITH (NOLOCK)
    WHERE cte.store_id = b.store_id
    AND cte.iTote = b.iTote
    AND cte.product_code = b.product_code);
	
	if OBJECT_ID('tempdb..#xtmptote') is not null
	drop table #xtmptote

	;with cte as (
        select a.pick_qty as QtyGen, a.iTote, a.box2, b.*
        from TblToteX a left join TmpToteNew b on a.iDate=convert(date,b.Work_Date,103)  and a.store_id=b.STORE_ID  and a.product_code=b.PRODUCT_CODE
        where a.pick_qty >0 and a.iTote is not null )
        select distinct Work_Date, SHIFT_NO, SHIFT_NAME, ROUTE_NO,
        case when Tote_Id is null then iTote else Tote_Id end as Tote_Id
        , box2 as Seq , NoPerTote, STORE_ID, STORE_NAME, DELIVERY_DATE
        , RIGHT(iTote,5) as [NO] , BIN_LOC, PRODUCT_CODE, PRODUCT_NAME, BarcodeNo, PRODUCT_SIZE, Unit_Q, UNIT_WEIGHT, UNIT_WIDTH, UNIT_LENGTH, UNIT_HEIGHT
        , case when PICK_QTY<>QtyGen then QtyGen else PICK_QTY end as PICK_QTY, ScanQty, [User_Id], Modify_Date, PickerId, StartPick, EndPick
        , case when PRODUCT_NAME is not null then 0 end as [Status]
        , case when zone_id is null then 0 else zone_id end as zone_id
        , ip_Form, iAddress, iPO, iCAT, PRODUCT_SIZE_OD, Unit_W, iQueue
    into #xtmptote
    from cte
    where PICK_QTY>0

	WAITFOR DELAY '00:00:02';
    
	truncate table TmpToteNew

	insert into TmpToteNew
    select distinct *
    from #xtmptote

--<======================== กำหนดค่าคำนวณลัง เริ่มต้น =======================>

	begin try
        declare @mastercube2 real ='0.062000'--มาตรฐานลัง
        UPDATE T
        SET  UNIT_WEIGHT = P.[Weight]
                ,UNIT_WIDTH = P.W
                ,UNIT_LENGTH = P.L
                ,UNIT_HEIGHT = p.H				
                ,BarcodeNo = P.barcode_No
                ,iQueue=(@mastercube2/p.iQtyPut)
                ,Unit_W=P.[Weight]	
                ,iCAT  =p.ZoneId
                ,BIN_LOC=p.SEQ
                ,SHIFT_NO='0'
                ,SHIFT_NAME='0'
                ,PRODUCT_NAME=(select top(1) PRODUCT_NAME from TmpToteNew b with(nolock) where b.PRODUCT_CODE=t.PRODUCT_CODE and b.PRODUCT_NAME is not null)
                ,STORE_NAME=isnull((select top(1)  b.STORE_NAME from TmpToteNew b with(nolock) where b.STORE_ID=t.STORE_ID and b.STORE_ID is not null),0)
        FROM TmpToteNew T , TblProduct P 
        Where  T.PRODUCT_CODE = P.product_Id

        update a
        set a.zone_id=b.ZoneId
        from TmpToteNew a, [dbo].[TblZone] b
        where a.BIN_LOC=b.[Location]

	end try
	begin catch
	end catch

--<======================== กำหนดค่าคำนวณลัง สิ้นสุด =======================>
	;with cte as(
        select row_number() over (partition  BY store_id  ORDER BY store_id,icat,product_code)  as iNo, store_id, icat, product_code
        from [ExtaNew]..[TmpToteNew] b
    )
	update a
	set a.NoPerTote=b.iNo
	from [ExtaNew]..[TmpToteNew] a, cte b
	where a.STORE_ID=b.STORE_ID and a.PRODUCT_CODE=b.PRODUCT_CODE

	--select * from TblToteX with (nolock)

	select sum(pick_qty) as TblToteX
    from TblToteX

	select sum(PICK_QTY) as TmpToteNew
    from TmpToteNew;

	--select * from TblToteX order by iTote , convert(int,left(box2,1))

	--select *  FROM ExtaNew..TmpToteNew a  order by Tote_Id , convert(int,left(Seq,1))

	--;WITH CTE AS (
 --       SELECT OrderID, iCat, BasketID,
 --       SUM(Quantity) AS CumulativeTotal,
 --       COUNT(DISTINCT iSKU) AS items,
 --       --ROUND(SUM([Weight] * Quantity), 2)  iWeight ,
 --       ROUND(SUM([Weight] * Quantity), 2) + ( select top 1 case when iDate = convert(date,getdate()) then 2 else 3 end from TblToteX where store_id = OrderID  ) AS [iWeight+basket],
 --       ROUND(SUM(Volume * Quantity), 2) AS iQueue
 --       FROM ##TempOrders
 --       GROUP BY OrderID, BasketID,iCat )
 --   SELECT *
 --   FROM CTE
	----where OrderID='19917'
 --   ORDER BY OrderID, BasketID;

	--select distinct Tote_Id  FROM ExtaNew..TmpToteNew a 

	--select * from TblToteX
	--select *  FROM ExtaNew..TmpToteNew a 
	--select * from ##TempOrders

	--select distinct Tote_Id  FROM ExtaNew..TmpToteNew a 

	BEGIN TRY
		UPDATE x
		SET x.Tote_Id = CASE 
						WHEN SUBSTRING(Tote_Id, 1, 2) = '12' THEN 'DC' + RIGHT(Tote_Id, 10)
						WHEN SUBSTRING(Tote_Id, 1, 2) = '11' THEN 'DB' + RIGHT(Tote_Id, 10)
						WHEN SUBSTRING(Tote_Id, 1, 2) = '10' THEN 'DA' + RIGHT(Tote_Id, 10)
						ELSE 'D' + RIGHT(Tote_Id, 11)
					END
		FROM TmpToteNew x;
	END TRY
	BEGIN CATCH
	--PRINT ERROR_MESSAGE();
	END CATCH;

	set @batch_size = 10000; -- ขนาดของแต่ละกลุ่ม
	set @start_row = 1;
	--set @end_row INT;
	DECLARE @total_rows INT;

	set nocount on;
	-- นับจำนวนแถวทั้งหมดใน TmpToteNew
	SELECT @total_rows = COUNT(*)
	FROM [dbo].TmpToteNew WITH (NOLOCK);

	-- ลูปเพื่อประมวลผลข้อมูลเป็นช่วง ๆ
	WHILE @start_row <= @total_rows
	BEGIN
		SET @end_row = @start_row + @batch_size - 1;

		-- ลบข้อมูลในช่วงที่กำหนด
		DELETE b
		FROM [dbo].AcmTmpToteNew b
		WHERE EXISTS (
			SELECT 1
			FROM (
				SELECT *, ROW_NUMBER() OVER (ORDER BY Work_Date, STORE_ID) AS RowNum
				FROM [dbo].TmpToteNew WITH (NOLOCK)
			) A
			WHERE A.RowNum BETWEEN @start_row AND @end_row
			AND A.Work_Date = b.Work_Date
			AND A.STORE_ID = b.STORE_ID
		);

		-- แทรกข้อมูลในช่วงที่กำหนด
		INSERT INTO [dbo].AcmTmpToteNew
		SELECT DISTINCT 
			Work_Date, SHIFT_NO, SHIFT_NAME, ROUTE_NO, Tote_Id, Seq, NoPerTote, STORE_ID, STORE_NAME, DELIVERY_DATE, [NO], BIN_LOC, PRODUCT_CODE, PRODUCT_NAME, BarcodeNo, PRODUCT_SIZE, Unit_Q, 
			UNIT_WEIGHT, UNIT_WIDTH, UNIT_LENGTH, UNIT_HEIGHT, PICK_QTY, ScanQty, [User_Id], Modify_Date, PickerId, StartPick, EndPick, [Status], zone_id, ip_Form, iAddress, iPO, iCAT, PRODUCT_SIZE_OD, Unit_W, iQueue
		FROM (
			SELECT *, ROW_NUMBER() OVER (ORDER BY Work_Date, STORE_ID) AS RowNum
			FROM [dbo].TmpToteNew WITH (NOLOCK)
		) A
		WHERE A.RowNum BETWEEN @start_row AND @end_row
		AND NOT EXISTS (
			SELECT 1
			FROM [dbo].AcmTmpToteNew B WITH (NOLOCK)
			WHERE B.Work_Date = A.Work_Date
			AND B.PRODUCT_CODE = A.PRODUCT_CODE
			AND B.Tote_Id = A.Tote_Id
		)
		AND A.Tote_Id IS NOT NULL;

		-- อัปเดตค่าเริ่มต้นของแถวสำหรับรอบถัดไป
		SET @start_row = @end_row + 1;
	END;

	PRINT 'Data processing completed successfully.';
GO


