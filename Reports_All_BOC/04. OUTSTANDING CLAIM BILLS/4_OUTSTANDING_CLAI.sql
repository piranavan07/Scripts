--CREATE OR REPLACE VIEW 4_OUTSTANDING_CLAIM_BILLS
--AS
  SELECT
    PROD.CODE      AS SUB_PRODUCT,
    MAS.MASTER_REF AS MASTER_REF,
    MAS.RELMSTRREF AS RELATED_MASTER_REFNO,
    PAD.ADDRESS1   AS OUR_CUTOMER,
    PAD.CUS_MNM    AS CIF,
--    PAD.CUS_SBB    AS CUST_SBB,
    (
      SELECT
        GFCTP1
      FROM
        GFPF
      WHERE
        GFCUS1 = MAS.PRICUSTMNM
    )             AS OWNERSHIP_CODE,
    EXTC.EMPLYECD AS RELATED_PARTY,
    EXT.CENSTRCT  AS PURPOSE_CODE,
    (
      SELECT
        FULLNAME
      FROM
        CAPF
      WHERE
        CABRNM = MAS.BHALF_BRN
    )              AS ON_BEHALFOF_BRANCH,
    BEV.START_DATE AS LOG_DATE,
    BEV.START_DATE AS INPUT_DATE,
    BEV.FINISHED   AS TRANSACTION_DATE,
    MAS.EXPIRY_DAT AS EXPIRY_DATE,
    CASE
      WHEN BEV.CREATNMTHD = 'G'
      THEN BEV.FINISHED
    END                                                        AS FCC_INPUT_DATE,
--    MAS.CCY                                                    AS TRANSAC_CURR,

    CAST( (MAS.AMOUNT /POWER(10,C8PF.C8CED)) AS DECIMAL(20,0)) AS  AMT_IN_TRANSAC_CURR,
    CAST((MAS.AMT_O_S/POWER(10,C8PF.C8CED)) AS DECIMAL(20,0)) AS    OUTSTANDING_AMOUNT,	
	CAST( MULTIPLY_ALT((MAS.AMOUNT /POWER(10,C8PF.C8CED)),NVL(SPOT.SPOTRATE,1)) AS DECIMAL(20,0)) AS AMOUNT_IN_BASE_CURRENCY,
    CAST( MULTIPLY_ALT((MAS.AMT_O_S/POWER(10,C8PF.C8CED)),NVL(SPOT.SPOTRATE,1)) AS DECIMAL(20,0)) AS OS_AMT_IN_BASE,
	
    PAD1.ADDRESS1 AS COUNTER_PARTY,
    PAD1.COUNTRY  AS COUNTER_PARTY_COUNTRY,
	PAD.SW_BANK  AS COUNTER_PARTY_BANK_SWIFT,
--    NULL          AS TERM_OF_TRANSACTION,-------------------TODO
    DECODE(LCM.AVAIL_BY,'A','Acceptance','D','Deferred Payment', 'M','Mixed Payment', 'N','Negotiation','S','Sight Payment','E','On Demand') AS  AVAILABILITY,
    DECODE(LCM.REVOLVING,'Y','Yes','N','No') AS REVOLVING,
	
    CASE PRD.SHORTN13
      WHEN 'Back/Back'
      THEN 'YES'
      ELSE 'NO'
    END                                     AS BACK_TO_BACK ,
	
    DECODE(LCM.TRANSFER,'Y','Yes','N','No') AS TRANSFER_LC,-------------------TODO
--    LCM.LOADING                             AS PORT_OF_LOADING,
--    LCM.DISCHARGE                           AS PORT_OF_DISCHARGE,
--    LCM.INCOTERMS                           AS INCOTERM,
--    ' '                                     AS BILL_OF_LADING_NO,
--    EXT.SHIPLINE                            AS SHIPPING_LINE,
--    EXT.VESSEL                              AS VESSEL_NAME,
    PRD.CODE79                              AS PRODUCT_CODE,
    EXT.HSCODE                              AS HS_CODE,
    NULL                                    AS CBSL_GOODS_CODE,-------------------TODO
    (
      SELECT DISTINCT
        POS.BO_ACC_NO
      FROM
        RELITEM REL,
        POSTING POS
      WHERE
        BEV.KEY97        = REL.EVENT_KEY
      AND REL.KEY97      = POS.KEY97
      AND POS.POSTED_AS IS NOT NULL
      AND POS.ACC_TYPE  IN ('CA','SA','VOS','EEFC')-------------------TODO
      FETCH FIRST 1 ROWS ONLY
    )                                           AS ACCOUNT,
	
    CAST(NVL(CHG.SWIFT_CHG,0) AS  DECIMAL(20,0)) AS SWIFT_CHG,
    CAST(NVL(CHG.CHARGE_AMT,0) AS DECIMAL(20,0)) AS COMM_CHG,
    NULL                                         AS BEN_SHA_OUR-------------------TODO
  FROM
    MASTER MAS INNER JOIN BASEEVENT BEV ON MAS.KEY97 = BEV.MASTER_KEY
    LEFT OUTER JOIN PRODTYPE PROD ON MAS.PRODTYPE = PROD.KEY97
    INNER JOIN LCMASTER LCM ON MAS.KEY97 = LCM.KEY97
    LEFT OUTER JOIN PARTYDTLS PAD ON LCM.APP_PTY = PAD.KEY97
    LEFT OUTER JOIN PARTYDTLS PAD1 ON LCM.BEN_PTY = PAD1.KEY97
	LEFT OUTER JOIN EXTCUST EXTC ON PAD.CUS_MNM = EXTC.CUST
    INNER JOIN EXEMPL30 PRD ON MAS.EXEMPLAR = PRD.KEY97
    LEFT OUTER JOIN EXTEVENT EXT ON BEV.KEY97 = EXT.EVENT
    INNER JOIN C8PF C8PF ON MAS.CCY = C8PF.C8CCY
    LEFT OUTER JOIN SPOTRATE SPOT ON MAS.CCY = SPOT.CURRENCY
    LEFT OUTER JOIN (
      SELECT
        MASTER_KEY,
        SUM(SWIFT_CHG)  AS SWIFT_CHG,
        SUM(CHARGE_AMT) AS CHARGE_AMT,
        CHARGE_CCY
      FROM
        (
          SELECT
            BEV.MASTER_KEY AS MASTER_KEY,
            RLT.DESCR      AS DESCR,
            BAC.CHG_CCY    AS CHARGE_CCY,
            CASE
              WHEN RLT.DESCR LIKE '%Swift%'
              THEN SUM(BAC.CHG_DUE/
                (
                  SELECT
                    POWER(10,C8CED)
                  FROM
                    C8PF
                  WHERE
                    C8CCY = BAC.CHG_CCY
                )
                )
              ELSE 0
            END AS SWIFT_CHG,
            CASE
              WHEN RLT.DESCR NOT LIKE '%Swift%'
              THEN SUM(BAC.CHG_DUE/
                (
                  SELECT
                    POWER(10,C8CED)
                  FROM
                    C8PF
                  WHERE
                    C8CCY = BAC.CHG_CCY
                )
                )
              ELSE 0
            END AS CHARGE_AMT
          FROM
            BASEEVENT BEV,
            RELITEM REL,
            BASECHARGE BAC,
            EVENTCHG EVC,
            CHGSCHED CHG,
            RELTEMPLTE RLT
          WHERE
            BEV.KEY97      = REL.EVENT_KEY
          AND REL.KEY97    = BAC.KEY97
          AND BAC.KEY97    = EVC.KEY97
          AND EVC.CHG_SCH  = CHG.KEY97
          AND CHG.CHG_TYPE = RLT.KEY97
            --AND MAS.MASTER_REF = 'DSSL190001000174'
          AND BEV.STATUS      = 'c'
          AND BAC.STATUS NOT IN ('A','X')-------------------TODO
          AND BEV.ISPROVISEV  = 'N'-------------------TODO
          AND BAC.ACTION      = 'N'-------------------TODO
          GROUP BY
            BEV.MASTER_KEY,
            RLT.DESCR,
            BAC.CHG_CCY
        )
      GROUP BY
        MASTER_KEY,
        CHARGE_CCY
    ) CHG ON MAS.KEY97      = CHG.MASTER_KEY
	
  WHERE PRD.CODE79     = 'CRC' --CLAIM RECEVIVED-------------------TODO
  AND BEV.REFNO_PFIX = 'CRE'-------------------TODO
  AND SPOT.BRANCH = 'BOCD' -- NEED TO CHANGE BOCC FOR INDIA-------------------TODO
  AND BEV.STATUS IN 'c'-------------------TODO
  AND MAS.STATUS IN('LIV')-------------------TODO
  AND MAS.AMT_O_S >0;
  --SELECT  MAS.REFNO_PFIX,BEV.REFNO_PFIX FROM MASTER MAS INNER JOIN BASEEVENT BEV ON MAS.KEY97 = BEV.MASTER_KEY WHERE MAS.EXEMPLAR='3' AND BEV.REFNO_PFIX='ISS';
  --SELECT DISTINCT CODE79,SHORTN13,LONGNA85 FROM EXEMPL30;--CODE79='ÇRC' LONGNA85='CLAIM RECEVIVED'