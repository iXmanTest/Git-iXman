USE [iExta]
GO

/****** Object:  StoredProcedure [dbo].[NewUpdateScanBOM]    Script Date: 2025-07-08 16:01:11 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[NewUpdateScanBOM] 
	@iUser  NVARCHAR(25) = null,
	@iTote  NVARCHAR(25) = null,
	@iDate  NVARCHAR(10) = null,	
	@iBarcode NVARCHAR(25)='0' ,--= null,
	@iZone nvarchar(150)='0'
AS
	DECLARE
	@QTY  INT
	,@outOrderQty  INT
	,@lblUserName NVARCHAR(100)
	,@ChkPallet int
	,@iRecheck int
	,@ChkTote INT
	,@ChkStep int

	--DECLARE @iBarcode VARCHAR(50)
	--,@Action VARCHAR(50)
	--,@Client nvarchar(50)
	--select @Client =client_net_address FROM sys.dm_exec_connections where session_id=@@SPID

	SET NOCOUNT ON;
	select @lblUserName=UserName 
	from tblUser with (nolock)
	where UserID=@iUser

begin try

	if @lblUserName is null 
	   goto iQuit

	if @iZone = '0' --or @iZone=0
	set @iZone='%'

	declare @iTem nvarchar(20)
	select top(1) @iTem =iSKU from iExta..[tblProducts] with (nolock) where iBar=@iBarCode
	--select top(1) @ChkPallet = count(distinct CustomerID) from [dbo].TbliScan with (nolock) where right('0000'+CustomerID,5)=@iTote and iDate=convert(date,@iDate,103)

	--if @ChkPallet > 0 goto ChkPallet
  if @iTote like  'LISTSCAN%' goto LISTSCAN
  if @iTote like  'AssignDoor%' goto AssignDoor
  if @iTote like  'findTruck%' goto findTruck
  if @iTote like  'CheckRoute%' goto CheckRoute

  select top(1) @ChkTote = count(distinct iTote) from [dbo].TblPick with (nolock) where iTote=@iTote and iDate=convert(date,@iDate,103)

  if @ChkTote >0 goto ByTote

  ByTote:
	declare @iChkLoc int=0,@iNo int=0,@icount int,@iZoneChk int
	if OBJECT_ID('tempdb..#itemp') is not null
		drop table #itemp
	select row_number() over (partition by tote order by [Zone]) as iNo,[Location],BarcodeNo,OrderQty,Qty,[Zone],Tote into #itemp from [dbo].[tblBOM] with (nolock) where Tote=@iTote
	select top(1) @iChkLoc =iNo,@iZoneChk=[Zone] from #itemp with (nolock) where OrderQty <> qty order by iNo 
	SELECT TOP(1) @ChkStep = 1  FROM [#itemp] WITH (nolock) WHERE (Zone like @iZone) AND (Tote = @iTote) GROUP BY Tote, Zone HAVING (SUM(OrderQty) - SUM(qty) = 0)
	select top(1) @iNo =iNo from #itemp with (nolock) where OrderQty < qty  and  BarcodeNo = @iBarCode 
	select top(1) @icount=count(*) from #itemp where OrderQty <> qty

	--declare @myZoneChk int
	--select top (1) @myZoneChk=[Zone] from #itemp with (nolock)  where [Zone] = '26'
	--if @myZoneChk = 26 begin
	--		select TOP(1) @ChkStep = 1 from #itemp where ProductID = @iTem and OrderQty <> Qty and [Zone] = @myZoneChk
	--		if @ChkStep = 1 begin
	--			goto XUpdateZone26
	--		end
	--end

	--select top (1) @iTem=ProductID , @iBarCode=BarcodeNo , @iTote=Tote from #itemp where [Zone] = '26' 

	--if @iZone = '26' --or @iZone=0
	--set @iZone='26'
	--if @iZone ='26' goto StepCheck


	if @iZone ='%' goto StepCheck
	
	if @iZone != 0 or @iZone <>'0'
	BEGIN	
	Print 'Test By Zone No.' + convert(nvarchar,@iZone)		

	if isnull(@iNo,0) <= isnull(@iChkLoc,0)
	if @iZone < @iZoneChk
		begin
			if @ChkStep = 1 goto StepCheck
			select 'เริ่มจัดที่โซน '+ convert(nvarchar,@iZoneChk)   as [Location],@iZone as [Zone], 1 as OrderQty,'' as ProductDesc,0 as ScanQty
			goto iQuit
		end
	else if @icount >0 and @iNo=0 and @iZone <> @iZoneChk
		begin
			select 'โซน '+ convert(nvarchar,@iZoneChk)  +' ยังไม่เสร็จ จ้า' as [Location],@iZone as [Zone], 1 as OrderQty,'' as ProductDesc,0 as ScanQty
			goto iQuit
		end
	
	--if isnull(@iZone,0) <= isnull(@iZoneChk,0)
--XUpdateZone26:
	begin 
		print 'Check update scan By Tote'
		UPDATE top(1) a 
		SET iChkScan = (iChkScan + 1)
		from [dbo].TblPick a with (nolock) 
		where iTote = @iTote				
		AND iDate = convert(date,@iDate,103) 				
		AND ProductID = @iTem	
		AND iOrder = iScan
		AND convert(nvarchar,iZone) like @iZone;

		UPDATE top(1) a 
		SET  ORDERQTY = QTY
		,LASTMODIFY = GETDATE()
		,USERID = @iUser 
		from [dbo].[tblBOM] a with (nolock) 
		where Tote = @iTote				
		AND ACTIVITYDATE = @iDate 						
		AND ProductID = @iTem	
		AND ORDERQTY <> Qty	
		AND convert(nvarchar,Zone) like @iZone;

StepCheck:
		;with cte as (
			--SELECT  iZone AS [Location] ,iOrder as OrderQty,iLoc+' '+ Product_Name as  ProductDesc,iScan as ScanQty, PickBy as UserID,iTime as LastModify
			--,(case when iScan=0 then 2 when (iOrder - iScan) <>0 then 1 else 3 end) as WIP
			--,(select top(1) count(distinct iBarcode) from [dbo].TblPick b with (nolock) where ProductID = @iTem and iTote = @iTote) as iChkBar 
			--,iBarcode as iBar
			--,ProductID					
			--,(select top(1) RouteNo from TblPick b with(nolock) where b.StoreID=a.StoreID order by CONVERT(int,b.RouteNo) desc ) as iRoute
			--,iLoc,Stage
			--from [dbo].TblPick a with (nolock) 
			--where iTote = @iTote
			--AND convert(nvarchar,iZone) like @iZone
			--AND iDate = convert(date,@iDate,103)

			SELECT  iZone AS [Location] ,iOrder as OrderQty,iLoc+' '+ Product_Name as  ProductDesc,iScan as ScanQty, PickBy as UserID,iTime as LastModify
			,(case when iScan=0 then 2 when (iOrder - iScan) <>0 then 1 else 3 end) as WIP
			,(select top(1) count(distinct iBarcode) from [dbo].TblPick b with (nolock) where ProductID = @iTem and iTote = @iTote) as iChkBar 
			,iBarcode as iBar
			,ProductID					
			,(select top(1) RouteNo from TblPick b with(nolock) where b.StoreID=a.StoreID order by CONVERT(int,b.RouteNo) desc ) as iRoute
			,iLoc
			,case 
				When Stage is NULL Then ''
				When Stage = '' Then ''
				else Stage
			End as Stage
			,case 
				When Batch is NULL Then ''
				else Batch
			End as Batch
			from [dbo].TblPick a with (nolock) 
			where iTote = @iTote
			AND convert(nvarchar,iZone) like @iZone
			AND iDate = convert(date,@iDate,103)

			--SELECT  --iZone AS [Location] 
			--	case 
			--		when Stage is NULL then convert(nvarchar(2),iZone)
			--		when Stage = '' then convert(nvarchar(2),iZone)
			--		else  convert(nvarchar(2),iZone)+' Exp '+Stage --AS [Location] 
			--	end AS [Location] 
			--	,iOrder as OrderQty,iLoc+' '+ Product_Name as  ProductDesc,iScan as ScanQty, PickBy as UserID,iTime as LastModify
			--,(case when iScan=0 then 2 when (iOrder - iScan) <>0 then 1 else 3 end) as WIP
			--,(select top(1) count(distinct iBarcode) from [dbo].TblPick b with (nolock) where ProductID = @iTem and iTote = @iTote) as iChkBar 
			--,iBarcode as iBar
			--,ProductID					
			--,(select top(1) RouteNo from TblPick b with(nolock) where b.StoreID=a.StoreID order by CONVERT(int,b.RouteNo) desc ) as iRoute
			--,iLoc
			--from [dbo].TblPick a with (nolock) --left outer join tblIVS i on 
			--	--a.ProductID = i.iSku
			--where iTote = @iTote
			--AND convert(nvarchar,iZone) like @iZone
			--AND iDate = convert(date,@iDate,103)

		)
		select *			
		,iSNull((select top(1) (case when (iScan+iChkScan)>iOrder then 1 else 0 end)  from [dbo].TblPick a with (nolock)  where ProductID = @iTem and iTote = @iTote ),0) as ChkScan		
		,case when (@iTem = ProductID and @iBarCode!='0' and iChkBar !=0)  then @iBarCode else iBar end as BarcodeNo			
		from cte with (nolock)
		order by  WIP , LastModify desc, UserID,[Location],iLoc   

		goto iQuit

	end 

	--if @iZone > @iZoneChk
	--begin
	--	select 'Location ก่อนหน้ายังไม่เสร็จ' as [Location],0 as [Zone], 1 as OrderQty,'' as ProductDesc,0 as ScanQty
	--end
	--print 'ChkZone'
	goto iQuit	

	END

		
ChkPallet:

	begin try 
	
	begin try	
		print 'Check update scan'
		UPDATE top(1) a 
		SET iChkScan = (iChkScan + 1)
		from TbliScan a with (nolock)
		WHERE CustomerID  = @iTote		
		AND iDate = convert(date,@iDate,103)			
		AND iBarcode = @iBarcode
		--and LastUpdate is not null
		AND iOrder = iScan
		and LDStatus='LD'
	end try
	begin catch
	end catch
	begin try				
		UPDATE top(1) a 
		SET 
		iScan = iOrder,
		LastUpdate = GETDATE()
    ,[iStatus]='ByWEB'
		,iUser = (select UserName  from tblUser where  UserID= @iUser )
		,iTruck=@iZone
		from TbliScan a with (nolock)
		WHERE CustomerID  = @iTote 
		AND iDate = convert(date,@iDate,103)			
		AND iBarcode = @iBarcode				
		AND iOrder <> iScan
		and LDStatus='LD'
	end try
	begin catch
	end catch 

	begin try
		;with cte as 
		(
		SELECT (case when LDStatus='C' then convert(nvarchar,[CustomerID])+' ADR : '+[Location]+'-C' 
		when iStoreName like '%โกแลต%' then convert(nvarchar,[CustomerID])+' ADR : '+[Location]+'-CHOC'
    when iStoreName like '%ออนไลน์%' then convert(nvarchar,[CustomerID])+' ADR : '+[Location]+'-ONLINE'
		else convert(nvarchar,[CustomerID])+' ADR : '+[Location] end ) as  [Location]
		,iOrder as OrderQty,iBarcode as ProductDesc,iBarcode as BarcodeNo, (case when (LDStatus ='C' or iScan='' or iScan is null) then '0' else iscan end ) as ScanQty,iUser as UserID
    , LastUpdate as LastModify,cast (istop  as int) as iStop        
		,(case when (iScan=0 or iScan='' or iScan is null) then 2 when (iOrder - iScan) <>0  then 1 else 3 end) as WIP0
		,(select top(1) route from TbliScan b with(nolock) where b.CustomerID=a.CustomerID order by CONVERT(int,b.route) desc ) as iRoute
		--,LDStatus
		FROM TbliScan a with (nolock)
		WHERE CustomerID  = @iTote 
		AND iDate = convert(date,@iDate,103)
		)
		select *,(select top(1) count(distinct iBarcode) from TbliScan with (nolock) where iBarcode=@iBarcode  and CustomerID = @iTote and LDStatus='LD') as iChkBar 
		,iSNull((select top(1) (case when (iScan+iChkScan)>1 then 1 else 0 end)  from TbliScan with (nolock) where iBarcode=@iBarcode and CustomerID = @iTote ),0) as ChkScan
		,iSNull((select COUNT(LDStatus) from TbliScan b with(nolock) where [Route]  = @iTote and LDStatus='C' and iDate=convert(date,@iDate,103)),0)  as iCancle		
		,iSNull((select COUNT(iStoreName) from TbliScan b with(nolock) where [Route]  = @iTote and LDStatus='LD' and iDate=convert(date,@iDate,103) and iStoreName like '%โกแลต%'),0)  as iChoco
    ,iSNull((select COUNT(iStoreName) from TbliScan b with(nolock) where [Route]  = @iTote and LDStatus='LD' and iDate=convert(date,@iDate,103) and iStoreName like '%ออนไลน์%'),0)  as iOnline
    ,CONCAT((case when ScanQty=0 then 0 else 1 end),WIP0) as WIP
		from cte with (nolock)
		order by  WIP , LastModify desc, iStop,  UserID,[Location]

	end try
	begin catch
	end catch
	goto iQuit
	
	end try
	begin catch
	end catch

LISTSCAN:
  set @iDate =(select top(1) iDate from  TblPick  with(nolock) order by iDate desc)
	begin try
	set @iTote=REPLACE(@iTote,'LISTSCAN','')

  select iPO as [PO],iAddress as [Adr],iTote as [Tote],Product_Name,iOrder,StoreID,Store_Name,ProductID,iBarcode,PackSize,iWeight,iScan,RouteNo as [Route],iSeq
  from TblPick a with (nolock)
  where iOrder<>iScan
  --and a.iTote like '%9'
  order by right(iTote,1) desc,iPO,iSeq,RouteNo

		--if OBJECT_ID ('tempdb..#tmpRoute') is not null
		--	drop table #tmpRoute
		--select ToteDate, RouteNo, Store, COUNT(DISTINCT XTote) AS cTote
		--into  #tmpRoute
		--FROM   icdc.dbo.TblScanLoaddata  with(nolock)
		--where LDStatus='C' and ToteDate = @iDate
		--group by ToteDate, RouteNo, Store, SUBSTRING(Location, 3, 2)
		--ORDER BY RouteNo, SUBSTRING(Location, 3, 2)

		--if OBJECT_ID ('tempdb..#tmpScan') is not null
		--	drop table #tmpScan
		--select ToteDate, RouteNo, Store, COUNT(DISTINCT XTote) AS iScan
		--into  #tmpScan
		--FROM   icdc.dbo.TblScanLoaddata  with(nolock)
		--where LDStatus='LD' and ToteDate = @iDate 
		--group by ToteDate, RouteNo, Store, SUBSTRING(Location, 3, 2)
		--ORDER BY RouteNo, SUBSTRING(Location, 3, 2)

		--insert into iMportGen.dbo.TblStore
		--select distinct Store,ltrim(replace(replace(replace(iSToreName,'สาขา',''),'(ร้านจัดเรียง)',''),'(ร้านฝากส่ง)','')) from icdc.dbo.TblScanLoaddata a with(nolock)
		--where a.Store not in (select distinct Store from iMportGen.dbo.TblStore b with(nolock) where a.Store =b.iStore )
		--order by a.Store
 
		--SELECT right('0000'+convert(nvarchar,a.Store),5) as iStore,ltrim(replace(replace(replace(s.iSToreName,'สาขา',''),'(ร้านจัดเรียง)',''),'(ร้านฝากส่ง)','')) as iStoreName
  --  ,isnull(c.iScan,0) as iScan, isnull(b.cTote,0) as CC, COUNT(DISTINCT a.XTote) AS Total
		--FROM   icdc.dbo.TblScanLoaddata a with(nolock) left join  #tmpRoute b on  a.ToteDate =b.ToteDate and a.Store =b.Store left join #tmpScan c on a.ToteDate =c.ToteDate and a.Store =c.Store left join iMportGen.dbo.TblStore s with (nolock)  on a.Store =s.iStore 
		--where a.RouteNo =@iTote
		--and a.ToteDate = @iDate
		--GROUP BY a.ToteDate,a.RouteNo, a.Store, SUBSTRING(Location, 3, 2),b.cTote,c.iScan ,s.iStoreName
		--ORDER BY SUBSTRING(Location, 3, 2)

		--select (select count(*) from icdc.dbo.TblScanLoaddata with(nolock) where ToteDate = @iDate and RouteNo =@iTote  )  as iQty,
		--(select count(*) from icdc.dbo.TblScanLoaddata with(nolock) where ToteDate = @iDate and RouteNo =@iTote and LDStatus ='LD' and ScanTime is not null and LDStatus <>'C') as iScan,
		--(select count(*) from icdc.dbo.TblScanLoaddata with(nolock) where ToteDate = @iDate and RouteNo =@iTote and LDStatus ='C' ) as Cancel

		--insert into [iMportGen].[dbo].[TblStore]
		--SELECT   Store, LTRIM(REPLACE(iStoreName, 'สาขา', '')) AS iName
		--FROM     icdc.dbo.TblScanLoaddata a with (nolock)
		--where Store not in(select store from [iMportGen].[dbo].[TblStore] b where a.Store =b.iStore)
		--GROUP BY Store, LTRIM(REPLACE(iStoreName, 'สาขา', ''))


	goto iQuit
	end try
	begin catch
	end catch

AssignDoor:

	set @iTote=REPLACE(@iTote,'AssignDoor','')	

  exec iExta..[updDoor] @iRoute=@iTote,@iDoor=@iBarcode
  print 'Assign Door '+@iBarcode

  goto iQuit

findTruck:
  set @iTote=REPLACE(@iTote,'findTruck','')

  exec iExta..[findTruck] @TruckBar=@iTote
  print 'Truck Bar '+ @iTote

  goto iQuit

CheckRoute:
  set @iTote=REPLACE(@iTote,'CheckRoute','')

  ;with cte as
  (
    SELECT distinct
    ROUTE_NO,LICENSE_CODE,[VENDOR_NAME],ASSIGN_TIME    
    ,isnull(Temperature,'') as iTEMP ,c.LdStart
    ,BATCH
    FROM [DoubleCheckLoad].[dbo].[TblWTSDPR] a with(nolock)
    Left join [DoubleCheckLoad].[dbo].TblDoor b with(nolock) ON b.DoorNo = a.[DOOR_NUMBER] and b.[Group] ='X'
    Left join iCDC.dbo.TblScanLoadData c with(nolock) ON c.RouteNo = a.ROUTE_NO and c.ToteDate = CONVERT(date,DELIVERY_DATE)
    Left join [DoubleCheckLoad].[dbo].TblTruck d with(nolock) ON d.TruckNo = a.LICENSE_CODE
    where DELIVERY_DATE=(select top(1) CONVERT(date,DELIVERY_DATE) from [DoubleCheckLoad].[dbo].[TblWTSDPR] with(nolock) order by DELIVERY_DATE desc)  
    and DOOR_TIME is null
    and ASSIGN_TIME is not null  
    group by c.ToteDate,DELIVERY_DATE,ROUTE_NO,LICENSE_CODE,[VENDOR_NAME],a.[DOOR_NUMBER],DOOR_TIME,a.STATUS_DISPLAY,b.[Group],d.CVCode,d.TruckType,ASSIGN_TIME,Temperature,LdStart,BATCH
  )
  select BATCH as PO, ROUTE_NO as [สาย],iTEMP as N'?C',LICENSE_CODE as [ทะเบียน],VENDOR_NAME as [บริษัท],convert(nvarchar,ASSIGN_TIME,108) as [รับงาน]
  from cte  
  Order by ASSIGN_TIME 

  goto iQuit
  	SELECT top(1) 'not authorized to access this resource/api' as [Location],0 as OrderQty,'' as ProductDesc,'' as BarcodeNo,0 as ScanQty,'' as UserID,'' as LastModify,'' as CountBar          
	,'2' as WIP
	,'Not Aut'as iRoute
	--,(select top(1) route from TbliScanData b with(nolock) where b.CustomerID=a.CustomerID order by CONVERT(int,b.route) desc ) as iRoute
	--from TbliScanData a with (nolock)
	--where 1<>2
iQuit:
end try
begin catch
end catch
GO


