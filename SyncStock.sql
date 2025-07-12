
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER proc [dbo].[AsynchronousStock]
--@iDate nvarchar(12)
--@iRoute nvarchar(4)
as
begin
	begin try
	set nocount on;
	DECLARE @Object INT, @ResponseText VARCHAR(8000), @Body AS nvarchar(max)=NULL
	DECLARE @json AS TABLE (Json_Table NVARCHAR(MAX))
	DECLARE @iDate nvarchar(12)
	set @iDate=replace(convert(nvarchar,convert(date,getdate())),'-','')
	DECLARE @JSONText VARCHAR(MAX), @iHost NVARCHAR(100), @param NVARCHAR(100)
	SET @param = '{"WarehouseCode" : "FC01", "DeliveryDate": "'+ @iDate+ '"}'
	SET @iHost = 'http://192.168.101.241:2325/picked/pickingmonitordata'

	EXEC sp_OACreate 'MSXML2.XMLHTTP', @Object OUT;
	EXEC sp_OAMethod @Object, 'open', NULL, 'post',@iHost, 'false'
	--EXEC sp_OAMethod @Object, 'setRequestHeader',null, 'API_KEY','1234567890'
	EXEC sp_OAMethod @Object, 'setRequestHeader', null, 'Content-Type', 'application/json'
	EXEC sp_OAMethod @Object, 'send', null, @param

	Exec sp_OAMethod @Object, 'responseText', @ResponseText OUTPUT
	INSERT into @json (Json_Table) exec sp_OAGetProperty @Object, 'responseText'	
	select @JSONText = Json_Table  from @json
	--select * from @json


	truncate table [SmartX-Dock].[dbo].[TblAsynchronousStock]

	if OBJECT_ID('tempdb..#temp1') is not null 
		drop table #iTemp

	insert into [SmartX-Dock].[dbo].[TblAsynchronousStock]
--		SELECT * 
	SELECT *  
--	into #iTemp
	FROM OPENJSON(@JSONText, '$.detail')  
	WITH( 
	DeliveryDate nvarchar(100) '$.DeliveryDate',
	BatchNo nvarchar(100) '$.BatchNo',
	POGroup nvarchar(100) '$.POGroup',
	ProductCode nvarchar(100) '$.ProductCode',
	ProductName nvarchar(100) '$.ProductName',
	SupplierCode nvarchar(100) '$.SupplierCode',
	SupplierName nvarchar(100) '$.SupplierName',
	StoreID nvarchar(100) '$.StoreID',
	StoreName nvarchar(100) '$.StoreName',
	OrderQty nvarchar(100) '$.OrderQty',
	PickQTY nvarchar(100) '$.ReceiveQTY',
	ReceiveQTY nvarchar(100) '$.ReceiveQTY',
	SupNotShip nvarchar(100) '$.SupNotShip',
	NotPick nvarchar(100) '$.NotPick',
	NotReceive nvarchar(100) '$.NotReceive',
	WhNotShip nvarchar(100) '$.WhNotShip',
	WarehouseCode nvarchar(100) '$.WarehouseCode') --as iData
	--select * from #iTemp 


	--EXEC sp_OADestroy @Object
	--select Json_Table  from @json

	--end try 
	--begin catch
	--	select ERROR_MESSAGE();
	--end catch
	end try
	begin catch
	end catch
end 

begin try

		UPDATE a
		set a.batchno=right('00'+convert(nvarchar,(batchno)),2)
		From [SmartX-Dock].dbo.TblAsynchronousStock a

		UPDATE b
		SET b.DeliveryDate = convert(varchar, getdate(), 23)
		From [SmartX-Dock].dbo.TblAsynchronousStock b
		
	end try
		begin catch
		end catch


begin try

		UPDATE a
		set  a.PRODUCT_SIZE_OD='QtyOld '+convert(nvarchar,a.PICK_QTY)  
		FROM iMportGen..GenToteData a,[SmartX-Dock]..TblAsynchronousStock b
		where b.DeliveryDate=a.iDate
		and b.ProductCode=a.PRODUCT_CODE
		and b.BatchNo=a.iPO
		and b.StoreID=a.STORE_ID
		and a.PRODUCT_SIZE_OD=''
		--and b.ProductCode='0200007'
		--and b.BatchNo='04'

		--update a
		--set  a.PICK_QTY=b.PickQTY
		--FROM iMportGen..GenToteData a,[SmartX-Dock]..TblAsynchronousStock b
		--where b.DeliveryDate=a.iDate
		--and b.ProductCode=a.PRODUCT_CODE
		--and b.BatchNo=a.iPO
		--and b.StoreID=a.STORE_ID
		--and b.ProductCode='2100168'
		--and b.BatchNo='04'

		;WITH cte AS 
		(
		SELECT [PRODUCT_CODE],PICK_QTY,b.PickQTY,a.STORE_ID, ROW_NUMBER() OVER(PARTITION BY [PRODUCT_CODE],iPO,STORE_ID ORDER BY [PRODUCT_CODE] ASC) AS RowNo 
		FROM iMportGen..GenToteData a,[SmartX-Dock]..TblAsynchronousStock b
		where  b.DeliveryDate=a.iDate
		and b.ProductCode=a.PRODUCT_CODE
		and b.BatchNo=a.iPO
		and b.StoreID=a.STORE_ID
		--and b.ProductCode='0200007'
		--and b.BatchNo='04'
		)
		UPDATE a
		set  a.PICK_QTY=convert(int,PickQTY)
		FROM cte a WHERE RowNo = 1

		;WITH cte AS 
		(
		SELECT [PRODUCT_CODE],PICK_QTY,b.PickQTY,a.STORE_ID, ROW_NUMBER() OVER(PARTITION BY [PRODUCT_CODE],iPO,STORE_ID ORDER BY [PRODUCT_CODE] ASC) AS RowNo 
		FROM iMportGen..GenToteData a,[SmartX-Dock]..TblAsynchronousStock b
		where  b.DeliveryDate=a.iDate
		and b.ProductCode=a.PRODUCT_CODE
		and b.BatchNo=a.iPO
		and b.StoreID=a.STORE_ID
		--and b.ProductCode='0200007'
		--and b.BatchNo='04'
		)
		UPDATE a
		set  a.PICK_QTY=0
		FROM cte a WHERE RowNo = 2

		;WITH cte AS 
		(
		SELECT [PRODUCT_CODE],PICK_QTY,b.PickQTY,a.STORE_ID, ROW_NUMBER() OVER(PARTITION BY [PRODUCT_CODE],iPO,STORE_ID ORDER BY [PRODUCT_CODE] ASC) AS RowNo 
		FROM iMportGen..GenToteData a,[SmartX-Dock]..TblAsynchronousStock b
		where  b.DeliveryDate=a.iDate
		and b.ProductCode=a.PRODUCT_CODE
		and b.BatchNo=a.iPO
		and b.StoreID=a.STORE_ID
		--and b.ProductCode='0200007'
		--and b.BatchNo='04'
		)
		UPDATE a
		set  a.PICK_QTY=0
		FROM cte a WHERE RowNo = 3

		end try
		begin catch
		end catch
GO


