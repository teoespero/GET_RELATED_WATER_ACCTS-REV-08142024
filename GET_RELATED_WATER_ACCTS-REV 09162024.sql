----------------------------------------------------------------------------------------------------------------------------
-- NAME: GET_RELATED_WATER_ACCTS-REV 08142024.sql
-- AUTHOR:	TEO ESPERO
---			IT ADMINISTRATOR
--			MARINA COAST WATER DISTRICT
-- DATE:	08/14/2024
-- DESC:	THIS IS TO CREATE A LISTING OF ALL WATER ACCTS CONNECTED TO A SEWER ACCT USING THE SERVICE ADDRESS AS BASIS
-- REV HISTORY: 
--			08/14/2024 - BASE CODE
--			08/15/2024 - ADDED CODE TO DETERMINE IF THE ACCT IS SEWER-ONLY
--			08/27/2024 - ADDED CODE TO HANDLE ACCOUNTS THAT ARE THE SAME IN EVERYTHINg
--			09/12/2024 - ADDED CODE THAT PROVIDES EXCEPTIONS FOR SEWER ONLY ACCTS SINCE THEY WILL NOT
--						 HAVE ANY READS
--			09/16/2024 - ADDED VARS TO DEFINE CYCLES AND BILLING YEAR
--	CODE LIMITATION:	
--			1) VARIATIONS OF THE SAME ADDRESS
--			2) IF THE ACCOUNT HAS MULTIPLE SEWER ACCOUNTS, IT WILL GIVE THE SAME VALUE FOR EACH ONE
--			   CS WILL NEED TO WEED THIS OUT MANUALLY	
----------------------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------------------------
--	STEP 1
--	GET ALL THE SEWER ACCTS
----------------------------------------------------------------------------------------------------------------------------
DECLARE @mylist TABLE (Id int)
INSERT INTO @mylist
SELECT id FROM (VALUES (4),(5), (6)) AS tbl(id)

Declare @specified_date Date
set @specified_date = '09/01/2024'

DECLARE @Year int = YEAR(@specified_date)

SELECT 
	replicate('0', 6 - len(mast.cust_no)) + cast (mast.cust_no as varchar)+ '-'+replicate('0', 3 - len(mast.cust_sequence)) + cast (mast.cust_sequence as varchar) AS ACCTNUM,
	MAST.billing_cycle,
	RT.service_code,
	RTRIM(LTRIM(RTRIM(LTRIM(L.street_number)) + ' ' + RTRIM(LTRIM(l.street_directional)) + ' ' + RTRIM(LTRIM(L.street_name)))) AS SERV_ADDR,
	TRIM(RTRIM(LTRIM(L.city))) AS CITY,
	TRIM(RTRIM(LTRIM(L.[state]))) AS [STATE],
	TRIM(RTRIM(LTRIM(L.zip))) AS [ZIP],
	L.MISC_2
	INTO #SWR_ACCTS
FROM ub_master MAST
INNER JOIN
	ub_service_rate RT
	ON RT.cust_no=MAST.cust_no
	AND RT.cust_sequence=MAST.cust_sequence
INNER JOIN
	LOT L
	ON L.lot_no=MAST.lot_no
WHERE 
	------------------------------------------------------------------------------------------------------------
	-- FOR NOW WE ARE JUST LOOKING FOR ACTIVE ACCTS
	------------------------------------------------------------------------------------------------------------
	MAST.acct_status='ACTIVE'
	------------------------------------------------------------------------------------------------------------
	-- THE CYCLES NEEDS TO BE CHANGED
	------------------------------------------------------------------------------------------------------------
	AND MAST.billing_cycle IN (SELECT id FROM @mylist)
	------------------------------------------------------------------------------------------------------------
	-- THE FOLLOWING CODES ARE BASED ON THE SERVICE RATE PREFIX USED FOR BILLING
	------------------------------------------------------------------------------------------------------------
	AND (
		RT.service_code LIKE 'SB%' OR
		RT.service_code LIKE 'SF%' OR
		RT.service_code LIKE 'SW%')
	-- ONLY USE SERVICE RATES THAT ARE ACTIVE ON THE ACCT
	AND (RT.rate_final_date IS NULL)

----------------------------------------------------------------------------------------------------------------------------
--	STEP 2
--	GET ALL THE WATER ACCTS
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	replicate('0', 6 - len(mast.cust_no)) + cast (mast.cust_no as varchar)+ '-'+replicate('0', 3 - len(mast.cust_sequence)) + cast (mast.cust_sequence as varchar) AS ACCTNUM,
	MAST.billing_cycle,
	RT.service_code,
	L.MISC_2,
	RTRIM(LTRIM(RTRIM(LTRIM(L.street_number)) + ' ' + RTRIM(LTRIM(l.street_directional)) + ' ' + RTRIM(LTRIM(L.street_name)))) AS SERV_ADDR,
	TRIM(RTRIM(LTRIM(L.city))) AS CITY,
	TRIM(RTRIM(LTRIM(L.[state]))) AS [STATE],
	TRIM(RTRIM(LTRIM(L.zip))) AS [ZIP]
	INTO #WTR_ACCTS
FROM ub_master MAST
INNER JOIN
	ub_service_rate RT
	ON RT.cust_no=MAST.cust_no
	AND RT.cust_sequence=MAST.cust_sequence
INNER JOIN
	LOT L
	ON L.lot_no=MAST.lot_no
WHERE 
	MAST.acct_status='ACTIVE'
	AND MAST.billing_cycle IN (SELECT ID FROM @mylist)
	AND (
		RT.service_code LIKE 'WF%' OR
		RT.service_code LIKE 'WB%' OR
		RT.service_code LIKE 'WA%' 
		)
	AND (RT.rate_final_date IS NULL)
	AND L.misc_16 NOT LIKE 'IRR%'

----------------------------------------------------------------------------------------------------------------------------
--	STEP 3
--	USING BOTH TABLES GENERATED, CONCATENATE ALL WATER ACCTS USING THE SERVICE ADDRESS AS BASIS
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	SW.ACCTNUM,
	SW.billing_cycle AS CYCLE,
	SW.misc_2 AS ST_CATEGORY,
	SW.SERV_ADDR,
	SW.CITY,
	SW.STATE,
	SW.ZIP,
	SW.service_code AS SERV_CODE,
	------------------------------------------------------------------------------------------------------------
	-- THIS PART OF THE CODE CREATES A COMMA SEPARATED COLUMN OF ALL THE WATER ACCTS(EXC. IRRIGATION)
	-- THAT IS FOUND BY THE CODE USING THE SERVICE CODE AS BASIS
	-- A LIMITATION ON THE CODE IS WHEN A SERVICE ADDRESS HAS VARIANTS (E.G. BLVD. VS BLVD OR BOULEVARD)
	------------------------------------------------------------------------------------------------------------
	(
		CASE
			WHEN EXISTS(SELECT TOP 1 ACCTNUM FROM #WTR_ACCTS WHERE ACCTNUM = SW.ACCTNUM) THEN ACCTNUM
			ELSE  (
			LTRIM(RTRIM(STUFF((SELECT DISTINCT  ', ' + US.ACCTNUM 
			  FROM #WTR_ACCTS US
			  WHERE US.SERV_ADDR = SW.SERV_ADDR
			  FOR XML PATH('')), 1, 1, ''))) 
			)
		END
	) AS [LINKED WTR ACCTS]
	
	INTO #SWR_RELATIONS
FROM #SWR_ACCTS SW
--WHERE
--	SW.SERV_ADDR = '130  General Stilwell Drive'
ORDER BY
	SW.billing_cycle,
	SW.SERV_ADDR



--SELECT *
--FROM #WTR_ACCTS
--WHERE
--	ACCTNUM like '000056-017'

--SELECT *
--FROM #SWR_RELATIONS
--WHERE
--	ACCTNUM like '000056-017'

----------------------------------------------------------------------------------------------------------------------------
-- GET WINTER AVERAGE READS FOR THE WATER ACCTS 
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	WF.ACCTNUM,
	WF.SERV_ADDR,
	WV.winter_average,
	WV.effective_date
	INTO #WINTERS
FROM #WTR_ACCTS WF
INNER JOIN
	ub_winter_average WV
	ON replicate('0', 6 - len(WV.cust_no)) + cast (WV.cust_no as varchar)+ '-'+replicate('0', 3 - len(WV.cust_sequence)) + cast (WV.cust_sequence as varchar)=WF.ACCTNUM
-- DROP TABLE #WINTERS

--SELECT *
--FROM #WINTERS
--WHERE
--	ACCTNUM like '000056-017'

----------------------------------------------------------------------------------------------------------------------------
--	STEP 4
--	FOR DUPLICITY'S SAKE WE SHOULD CHECK IF THE SWR ACCOUNT IS INCLUDED IN THE LIST OF RELATED WTR ACCTS
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	SS.ACCTNUM,
	SS.CYCLE,
	SS.ST_CATEGORY,
	SS.SERV_ADDR,
	SS.CITY,
	SS.STATE,
	SS.ZIP,
	SS.SERV_CODE,
	[LINKED WTR ACCTS],
	------------------------------------------------------------------------------------------------------------
	-- IF THE SEWER ACCOUNT IS ALSO LISTED IN THE WATER ACCT (EXC. IRRIGATION) THEN
	-- IT IS CLASSIFIED AS NOT SEWER ONLY
	------------------------------------------------------------------------------------------------------------
	(SELECT TOP 1 WR.ACCTNUM FROM #WTR_ACCTS WR WHERE WR.ACCTNUM LIKE SS.ACCTNUM) AS SOLO
	INTO #SWR_RELATIONS2
FROM #SWR_RELATIONS SS

--SELECT *
--FROM #SWR_RELATIONS2
--WHERE
--	ACCTNUM like '000056-017'


----------------------------------------------------------------------------------------------------------------------------
--	STEP 5
--	DETERMINE IF THE ACCOUNT IS A SEWER-ONLY ACCT 
SELECT 
	SR2.ACCTNUM,
	SR2.CYCLE,
	SR2.ST_CATEGORY,
	SR2.SERV_ADDR,
	SR2.CITY,
	SR2.STATE,
	SR2.ZIP,
	SR2.SERV_CODE,
	[LINKED WTR ACCTS],
	SOLO,
	------------------------------------------------------------------------------------------------------------
	-- CREATES A FIELD THAT IDENTIFIES SEWER ONLY ACCOUNT
	------------------------------------------------------------------------------------------------------------
	(
		CASE WHEN SOLO IS NULL THEN 'Y' ELSE 'N' END
	) AS SWR_ONLY
	INTO #SWR_LIST
FROM #SWR_RELATIONS2 SR2
--WHERE
--	SR2.ACCTNUM = '003708-002'
ORDER BY
	SR2.ST_CATEGORY,
	SR2.CYCLE,
	SR2.SERV_ADDR

--SELECT *
--FROM #SWR_LIST
--WHERE
--	ACCTNUM like '000056-017'


----------------------------------------------------------------------------------------------------------------------------
--	STEP 6
--	DETERMINE RESIDENTIAL AND NON-RESIDENTIAL
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	ACCTNUM,
	CYCLE,
	ST_CATEGORY,
	SERV_ADDR,
	CITY,
	STATE,
	ZIP,
	SERV_CODE,
	(
		CASE 
			WHEN (
					ST_CATEGORY LIKE 'COM%' OR
					ST_CATEGORY LIKE 'IND%' OR
					ST_CATEGORY LIKE 'INS%' 
				) THEN 'NON-RESIDENTIAL'
			WHEN (
					ST_CATEGORY LIKE '%FAM%' 
				) THEN 'RESIDENTIAL'
			END
	) AS UNIT_TYPE,
	[LINKED WTR ACCTS],
	SOLO,
	SWR_ONLY
	INTO #SWR_LIST2
FROM #SWR_LIST
ORDER BY
	ST_CATEGORY,
	CYCLE,
	SWR_ONLY,
	SERV_ADDR

--SELECT *
--FROM #SWR_LIST2
--WHERE
--	ACCTNUM like '000056-017'

----------------------------------------------------------------------------------------------------------------------------
--	STEP 7
--	DETERMINE WHETHER THE BILLING TYPE IS MONTHLY FLOW (NON-RES) OR WINTER AVERAGE (RES)
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	distinct
	ACCTNUM,
	CYCLE,
	ST_CATEGORY,
	SERV_ADDR,
	CITY,
	STATE,
	ZIP,
	SERV_CODE,
	UNIT_TYPE,
	SOLO,
	SWR_ONLY,
	[LINKED WTR ACCTS],
	(
		CASE
			WHEN UNIT_TYPE LIKE 'RES%' THEN 'WINTER AVERAGE'
			WHEN UNIT_TYPE LIKE 'NON%' THEN 'MONTHLY FLOW'
		END
	) AS BILLING_TYPE
	INTO #SWR_LIST3
FROM #SWR_LIST2
ORDER BY
	ST_CATEGORY,
	CYCLE,
	UNIT_TYPE,
	SWR_ONLY,
	SERV_ADDR

--drop table #SWR_LIST3

--SELECT *
--FROM #SWR_LIST3
--WHERE
--	ACCTNUM like '000056-017'


----------------------------------------------------------------------------------------------------------------------------
--	STEP 8
--	DETERMINE THE WINTER AVE FOR RESIDENTIALS, ASSIGN A DEFAULT VALUE OF 5 FOR THOSE WITH 0 WINTER AVERAGE
----------------------------------------------------------------------------------------------------------------------------



--SELECT *
--FROM #WINTERS
--WHERE
--	ACCTNUM='023302-001'

SELECT 
	SL3.ACCTNUM,
	SL3.CYCLE,
	SL3.ST_CATEGORY,
	SL3.SERV_ADDR,
	SL3.CITY,
	SL3.STATE,
	SL3.ZIP,
	SL3.SERV_CODE,
	SL3.UNIT_TYPE,
	SL3.SOLO,
	SL3.SWR_ONLY,
	SL3.BILLING_TYPE,
	[LINKED WTR ACCTS],
	(
		CASE
			WHEN (SL3.BILLING_TYPE LIKE 'WIN%' AND SL3.SWR_ONLY = 'N') THEN AVE.winter_average
			WHEN (SL3.BILLING_TYPE LIKE 'WIN%' AND SL3.SWR_ONLY = 'N' AND AVE.winter_average = 0) THEN 5
			WHEN (SL3.BILLING_TYPE LIKE 'WIN%' AND SL3.SWR_ONLY = 'Y') THEN NULL
		END
	) AS WINTER_AVG
	INTO #SWR_LIST4
FROM #SWR_LIST3 SL3
LEFT JOIN
	#WINTERS AVE
	ON SL3.SERV_ADDR = AVE.SERV_ADDR
WHERE
	YEAR(AVE.effective_date)=@Year
	--AND MONTH(AVE.effective_date)=7
ORDER BY
	ST_CATEGORY,
	CYCLE,
	UNIT_TYPE,
	SWR_ONLY,
	SERV_ADDR

-- DROP TABLE #SWR_LIST4

----------------------------------------------------------------------------------------------------------------------------
-- THIS IS THE CODE THAT GOES THROUGH THE SEWER LIST AND INCLUDES THE ACCTS THAT DO NOT HAVE A WINTER AVER
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	NS3.ACCTNUM,
	NS3.CYCLE,
	NS3.ST_CATEGORY,
	NS3.SERV_ADDR,
	NS3.CITY,
	NS3.STATE,
	NS3.ZIP,
	NS3.SERV_CODE,
	NS3.UNIT_TYPE,
	NS3.SOLO,
	NS3.SWR_ONLY,
	NS3.BILLING_TYPE,
	NS3.[LINKED WTR ACCTS],
	NS4.WINTER_AVG
	INTO #S3S4COMBINED
FROM #SWR_LIST3 NS3
LEFT JOIN 
	#SWR_LIST4 NS4
	ON NS3.ACCTNUM=NS4.ACCTNUM

--SELECT *
--FROM #S3S4COMBINED
--WHERE
--	ACCTNUM like '000056-017'



----------------------------------------------------------------------------------------------------------------------------
--	STEP 9
--	CREATE A TEMP TABLE FOR MONTHLY FLOWS (NON-RES)
--	FOR NOW THE READ DATE HAS TO BE CHANGED
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	replicate('0', 6 - len(MH.cust_no)) + cast (MH.cust_no as varchar)+ '-'+replicate('0', 3 - len(MH.cust_sequence)) + cast (MH.cust_sequence as varchar) AS ACCTNUM,
	consumption,
	reading_period,
	reading_year,
	read_dt,
	mh.ub_meter_con_id
	INTO #MTR_RD
FROM ub_meter_hist MH
--WHERE
--	reading_period = 7
--	AND reading_year = 2024
ORDER BY 
	ACCTNUM,
	read_dt DESC

--drop table #MTR_RD


SELECT 
	RD2.ACCTNUM,
	RD2.consumption,
	RD2.reading_period,
	RD2.reading_year,
	read_dt,
	rd2.ub_meter_con_id,
	WAWA.SERV_ADDR
	INTO #MTR_RD2
FROM #MTR_RD RD2
INNER JOIN
	#WTR_ACCTS WAWA
	ON WAWA.ACCTNUM=RD2.ACCTNUM

--drop table #MTR_RD2

--SELECT 
--	distinct
--	*
--FROM #MTR_RD2
--WHERE
--	SERV_ADDR like'2200  Noche Buena%'

----------------------------------------------------------------------------------------------------------------------------
--	GETS THE LATEST NETER READ AVAILABLE FOR THE CURRENT YEAR
----------------------------------------------------------------------------------------------------------------------------
select 
	distinct
	t.ACCTNUM,
	t.consumption,
	t.reading_period,
	t.reading_year,
	t.read_dt,
	t.SERV_ADDR
	into #MTR_RD3
from #MTR_RD2 t
inner join (
	select ACCTNUM, 
	max(read_dt) as MaxTrans
    from #MTR_RD2
    group by ACCTNUM
) tm 
on 
	t.ACCTNUM = tm.ACCTNUM
	and t.read_dt=tm.MaxTrans
order by
	t.ACCTNUM,
	t.read_dt

--SELECT *
--FROM #MTR_RD3
--WHERE
--	SERV_ADDR like'130  General Stilwell Drive'

----------------------------------------------------------------------------------------------------------------------------
--	STEP 10
--	THIS IS TO TIE IN THE MONTHLY FLOW FOR 
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	DISTINCT
	S4.ACCTNUM,
	S4.CYCLE,
	S4.ST_CATEGORY,
	S4.SERV_ADDR,
	S4.CITY,
	S4.STATE,
	S4.ZIP,
	S4.SERV_CODE,
	S4.UNIT_TYPE,
	S4.SOLO,
	S4.SWR_ONLY,
	S4.BILLING_TYPE,
	S4.WINTER_AVG,
	S4.[LINKED WTR ACCTS],
	(
		CASE
			WHEN (S4.BILLING_TYPE LIKE 'MON%' AND S4.SWR_ONLY = 'N' AND S4.[LINKED WTR ACCTS] = S4.ACCTNUM) THEN MR.consumption
			WHEN (S4.BILLING_TYPE LIKE 'MON%' AND S4.SWR_ONLY = 'N' AND MR.consumption = 0) THEN 5
			WHEN (S4.BILLING_TYPE LIKE 'MON%' AND S4.SWR_ONLY = 'Y') THEN NULL
		END
	) AS CONS_TO_USE
	INTO #SWR_LIST5
FROM #S3S4COMBINED S4
left JOIN
	#MTR_RD3 MR
	ON MR.ACCTNUM=S4.ACCTNUM
--GROUP BY
--	S4.ACCTNUM,
--	S4.CYCLE,
--	S4.ST_CATEGORY,
--	S4.SERV_ADDR,
--	S4.CITY,
--	S4.STATE,
--	S4.ZIP,
--	S4.SERV_CODE,
--	S4.UNIT_TYPE,
--	S4.SOLO,
--	S4.SWR_ONLY,
--	S4.BILLING_TYPE,
--	S4.WINTER_AVG,
--	S4.[LINKED WTR ACCTS]
ORDER BY
	ST_CATEGORY,
	CYCLE,
	UNIT_TYPE,
	SWR_ONLY,
	SERV_ADDR

--DROP TABLE #SWR_LIST5
--SELECT *
--FROM #SWR_LIST5
--WHERE
--	ACCTNUM like '000056-017'


----------------------------------------------------------------------------------------------------------------------------
--	CREATE THE FINAL TABLE
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	distinct
	SL5.ACCTNUM,
	SL5.CYCLE,
	SL5.ST_CATEGORY,
	SL5.SERV_ADDR,
	SL5.CITY,
	SL5.STATE,
	SL5.ZIP,
	SL5.SERV_CODE,
	SL5.UNIT_TYPE,
	SL5.SOLO,
	SL5.SWR_ONLY,
	SL5.BILLING_TYPE,
	--SL5.WINTER_AVG,
	SL5.[LINKED WTR ACCTS],
	--SL5.CONS_TO_USE,
	(
	CASE
		WHEN (SL5.SWR_ONLY = 'Y' AND SL5.BILLING_TYPE LIKE 'MON%') THEN
			(
				SELECT SUM(RD.consumption) 
				FROM #WTR_ACCTS WA 
				INNER JOIN
					#MTR_RD3 RD
					ON RD.ACCTNUM=WA.ACCTNUM
				WHERE WA.SERV_ADDR=SL5.SERV_ADDR
			)
		WHEN (SL5.SWR_ONLY = 'Y' AND SL5.BILLING_TYPE LIKE 'WIN%') THEN
		(
			SELECT SUM(AA.winter_average) 
			FROM #WTR_ACCTS WA 
			INNER JOIN
				ub_winter_average AA
				ON replicate('0', 6 - len(AA.cust_no)) + cast (AA.cust_no as varchar)+ '-'+replicate('0', 3 - len(AA.cust_sequence)) + cast (AA.cust_sequence as varchar)=WA.ACCTNUM
			WHERE WA.SERV_ADDR=SL5.SERV_ADDR
		)
		WHEN (SL5.BILLING_TYPE LIKE 'WIN%' AND SL5.SWR_ONLY = 'N') THEN SL5.WINTER_AVG
		WHEN (SL5.BILLING_TYPE LIKE 'MON%' AND SL5.SWR_ONLY = 'N') THEN SL5.CONS_TO_USE
	END
	) AS [THE CONS]
	INTO #SEWER_LISTER
FROM #SWR_LIST5 SL5
WHERE
	SL5.SWR_ONLY='Y'
ORDER BY
	SL5.CYCLE,
	SL5.UNIT_TYPE,
	SL5.ACCTNUM


----------------------------------------------------------------------------------------------------------------------------
--	DISPLAY THE FINAL TABLE
----------------------------------------------------------------------------------------------------------------------------
SELECT 
	distinct
	SL6.ACCTNUM,
	SL6.CYCLE,
	SL6.ST_CATEGORY,
	SL6.SERV_ADDR,
	SL6.CITY,
	SL6.STATE,
	SL6.ZIP,
	SL6.SERV_CODE,
	SL6.UNIT_TYPE,
	SL6.SOLO,
	SL6.SWR_ONLY,
	SL6.BILLING_TYPE,
	--SL5.WINTER_AVG,
	SL6.[LINKED WTR ACCTS],
	--SL5.CONS_TO_USE,
	SL6.[THE CONS]
FROM #SEWER_LISTER SL6

--SELECT *
--FROM #WTR_ACCTS AX
--INNER JOIN
--	#MTR_RD3
	





----------------------------------------------------------------------------------------------------------------------------
--	STEP 7
--	GARBAGE COLLECTION
----------------------------------------------------------------------------------------------------------------------------

DROP TABLE #SWR_ACCTS
DROP TABLE #WTR_ACCTS
DROP TABLE #SWR_RELATIONS
DROP TABLE #SWR_RELATIONS2
DROP TABLE #SWR_LIST
DROP TABLE #SWR_LIST2
DROP TABLE #SWR_LIST3
DROP TABLE #SWR_LIST4
DROP TABLE #SWR_LIST5
DROP TABLE #MTR_RD
DROP TABLE #MTR_RD2
DROP TABLE #MTR_RD3
DROP TABLE #WINTERS
DROP TABLE #S3S4COMBINED
DROP TABLE #SEWER_LISTER

--SELECT compatibility_level  
--FROM sys.databases
--WHERE name = db_name();



--SELECT *
--FROM ub_meter_hist
--WHERE
--	cust_no=16847
--	AND cust_sequence=1
--	AND reading_period=7
--	AND reading_year=2024

--SELECT *
--FROM ub_winter_average
--WHERE 
--	cust_no=13858
--	AND cust_sequence=1


