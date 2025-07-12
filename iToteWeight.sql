SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE proc [dbo].[iToteWeight]
as
set nocount on;
--begin
--	insert into ExtaNew..AcmTmpToteNew
--	select * 
--	FROM  ExtaNew..TmpToteNew  A with (nolock)
--	WHERE Work_Date not in (select top(1) Work_Date from ExtaNew..AcmTmpToteNew B with (nolock) where b.Work_Date =a.Work_Date and b.PRODUCT_CODE =a.PRODUCT_CODE and a.tote_id =b.Tote_Id   )
--	AND A.Tote_Id is not null
--end
begin

-- ใช้ CTE เพื่อคำนวณค่า SUM ทั้งหมดในขั้นตอนเดียวและกรองข้อมูลเบื้องต้น
WITH AggregatedData AS (
    SELECT
        a.Work_Date,
        a.ROUTE_NO,
        a.Tote_Id,
        a.Seq,
        a.STORE_ID,
        a.STORE_NAME,
        SUM(a.PICK_QTY) AS TotalPickQty,
        SUM(CAST(a.UNIT_W AS MONEY) * a.PICK_QTY) AS TotalWeightBase,
        SUM(a.iQueue * a.PICK_QTY) AS TotalQueueQty
    FROM
        ExtaNew..AcmTmpToteNew a WITH (NOLOCK)
    -- การกรองข้อมูลภายใน CTE จะช่วยเพิ่มประสิทธิภาพ
    WHERE
        CONVERT(DATE, a.Work_Date, 103) > GETDATE() - 7
    GROUP BY
        a.Tote_Id,
        a.Work_Date,
        a.STORE_ID,
        a.STORE_NAME,
        a.ROUTE_NO,
        a.Seq
)

-- Query หลักที่นำข้อมูลที่คำนวณแล้วมาจัดรูปแบบและสร้างเงื่อนไขสุดท้าย
SELECT
    FORMAT(CONVERT(DATE, ad.Work_Date, 103), 'yyyy-MM-dd') AS iDate,
    RIGHT('0000' + CAST(ad.ROUTE_NO AS NVARCHAR(10)), 4) AS iRoute,
    ad.Tote_Id AS Tote,
    ad.Seq,
    RIGHT('0000' + CAST(ad.STORE_ID AS NVARCHAR(20)), 5) AS iStore,
    ad.STORE_NAME AS iName,
    ad.TotalPickQty AS iQty, -- ใช้ค่าที่ SUM ไว้แล้วจาก CTE

    -- คำนวณ iWeight โดยใช้ค่าที่ SUM ไว้แล้วจาก CTE
    CASE
        WHEN RIGHT(ad.Tote_Id, 1) = '1' THEN FORMAT(ad.TotalWeightBase, 'n2')
        ELSE FORMAT(ad.TotalWeightBase + 3.100, 'n2')
    END AS iWeight,

    FORMAT(ad.TotalQueueQty, 'n3') AS iQueue, -- จัดรูปแบบค่าที่ SUM ไว้แล้วจาก CTE

    -- คอลัมน์ ToteType ที่รวม Logic ของ iType และ Comment (จากโจทย์ก่อนหน้า) เข้าด้วยกัน
    CASE
        -- 1. กฎสำคัญที่สุด: 'สินค้านอกลัง'
        WHEN RIGHT(ad.Tote_Id, 1) = '1' THEN 'สินค้านอกลัง'

        -- 2. กฎจาก TypeCrossdock (จากโจทย์ก่อนหน้า) ที่บังคับให้เป็น 'ลังใหญ่'
        WHEN r.TypeCrossdock IN ('CDC KK', 'CDC NR') THEN 'ลังใหญ่'

        -- 3. กฎจาก Route No ที่บังคับให้เป็น 'ลังใหญ่'
        WHEN LEFT(ad.ROUTE_NO, 1) IN ('7', '9') THEN 'ลังใหญ่'
        WHEN LEFT(ad.ROUTE_NO, 2) = '17' THEN 'ลังใหญ่'
        -- WHEN CAST(LEFT(ad.ROUTE_NO, 4) AS INT) BETWEEN 4000 AND 4999 THEN 'ลังใหญ่'

        -- 4. กฎตามขนาด (เปรียบเทียบค่าตัวเลขโดยตรงเพื่อประสิทธิภาพที่ดีกว่า)
        WHEN ad.TotalQueueQty <= 0.035 THEN 'ลังเล็ก'

        -- 5. กฎสำรองสุดท้ายสำหรับทุกกรณีที่ไม่เข้าพวก
        ELSE 'ลังใหญ่'
    END AS iType, -- เปลี่ยนชื่อจาก iType เป็นชื่อที่สื่อความหมายมากขึ้น

    r.TypeCrossdock AS รูปแบบการส่ง -- ยังคงคอลัมน์นี้ไว้เพื่อการตรวจสอบ

FROM
    AggregatedData ad
    LEFT JOIN ExtaNew..TblRoute r WITH (NOLOCK) ON ad.STORE_ID = r.Store_ID
ORDER BY
    iDate DESC,
    ad.ROUTE_NO,
    ad.Tote_Id;
end 