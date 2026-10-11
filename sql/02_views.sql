/* =====================================================================
   02_VIEWS.SQL  -  VIEW-LAR (3 view)
   A) clean_account_transaction : data cleaning (audit problemlərinin həlli)
   B) vw_customer_360           : hər müştəri bir sətir
   C) vw_monthly_activity       : aylıq aqreqat (dashboard üçün)

   Audit göstərdi ki, problem YALNIZ əməliyyat cədvəlindədir. bank_accounts,
   customer_profile və transaction_code təmiz çıxdı, ona görə onlara cleaning
   view-su yazmırıq. Raw cədvələ toxunmuruq: düzəlişlər view-dadır, səhv
   etsək view-u yenidən yaradırıq, data zədələnmir.

   İŞLƏTMƏ: hər CREATE blokunu seç və F5 bas.
   ===================================================================== */


/* ---------------------------------------------------------------------
   A) CLEAN_ACCOUNT_TRANSACTION
   Auditdə tapılan problemlər və həlləri:

   1) Kredit/depozit əməliyyatları iki sətirdə yazılır (cüt kodlar), ona görə
      SUM(amount) pulu iki dəfə sayır.
      -> txn_category:
           CUSTOMER_ACTIVITY : müştərinin real əməliyyatları
                               (MER_PAY, CSH_WDL, CSH_DEP, IBK_OUT, IBK_IN)
           FEE               : bank komissiyası (SYS_FEE)
           LOAN              : kredit əməliyyatları (LN_*, cüt)
           FIXED_DEPOSIT     : müddətli depozit əməliyyatları (FD_*, cüt)
         Real xərc üçün: WHERE txn_category = 'CUSTOMER_ACTIVITY'.
         (LIKE 'LN_%' yazmırıq, çünki _ LIKE-da "istənilən simvol" deməkdir.)

   2) Məbləğ həmişə müsbətdir, istiqaməti Debit/Credit göstərir.
      -> signed_amount: Credit +, Debit -. SUM(signed_amount) real pul axınını
         verir (savings müştəri əməliyyatları üçün mənalıdır).

   3) 534 depozit açılışının cütü yoxdur.
      -> is_unpaired_fd_open = 1 ilə işarələnir, SİLİNMİR.

   4) System kanalı müştərinin etmədiyi, bankın avtomatik yazdığı sətirlərdir.
      -> is_system = 1.

   5) Hər sorğuda il/ay çıxarmamaq üçün hazır sütunlar (txn_date, txn_year, txn_month).
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW clean_account_transaction AS
SELECT t.transaction_id,
       t.account_id,
       t.linked_transaction_id,
       t.created_time,
       TRUNC(t.created_time)              AS txn_date,
       EXTRACT(YEAR  FROM t.created_time) AS txn_year,
       EXTRACT(MONTH FROM t.created_time) AS txn_month,
       t.transaction_type,
       t.transaction_code,
       c.label,
       c.account_type                     AS code_account_type,
       CASE
           WHEN t.transaction_code IN ('MER_PAY','CSH_WDL','CSH_DEP','IBK_OUT','IBK_IN') THEN 'CUSTOMER_ACTIVITY'
           WHEN t.transaction_code = 'SYS_FEE'                                           THEN 'FEE'
           WHEN SUBSTR(t.transaction_code, 1, 3) = 'LN_'                                 THEN 'LOAN'
           WHEN SUBSTR(t.transaction_code, 1, 3) = 'FD_'                                 THEN 'FIXED_DEPOSIT'
       END                                AS txn_category,
       t.amount,
       CASE t.transaction_type WHEN 'Credit' THEN t.amount ELSE -t.amount END AS signed_amount,
       t.channel,
       CASE WHEN t.channel = 'System' THEN 1 ELSE 0 END                       AS is_system,
       CASE WHEN t.transaction_code = 'FD_OPEN'
             AND t.linked_transaction_id IS NULL THEN 1 ELSE 0 END            AS is_unpaired_fd_open
FROM   account_transaction t
JOIN   transaction_code c ON c.transaction_code = t.transaction_code;
-- INNER JOIN təhlükəsizdir: auditdə yetim kod tapılmadı, sətir itmir.

-- Yoxlama 1: sətir sayı raw ilə eyni olmalıdır (gözlənilən: 2377169)
SELECT COUNT(*) AS rows_in_view FROM clean_account_transaction;

-- Yoxlama 2: kateqoriya bölgüsü, NULL kateqoriya olmamalıdır
-- Gözlənilən: CUSTOMER_ACTIVITY 2321653 / LOAN 47836 / FIXED_DEPOSIT 4248 / FEE 3432
SELECT txn_category,
       COUNT(*)                 AS n,
       SUM(is_system)           AS system_rows,
       SUM(is_unpaired_fd_open) AS unpaired_fd_open
FROM   clean_account_transaction
GROUP  BY txn_category
ORDER  BY n DESC;


/* ---------------------------------------------------------------------
   B) VW_CUSTOMER_360: hər müştəri BİR sətir (müştəri ölçüsü)
   Niyə: müştəri -> hesablar JOIN-u sətirləri çoxaldır (fanout). Burada bir dəfə
   aqreqat edirik, sonra hər sorğuda hazır istifadə edirik.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_customer_360 AS
SELECT c.customer_id, c.city, c.state,
       TRUNC(MONTHS_BETWEEN(DATE '2025-12-31', c.birth_date) / 12) AS age_end_2025,
       MAX(CASE WHEN a.account_type = 'Savings' THEN a.balance END)                       AS savings_balance,
       SUM(CASE WHEN a.account_type = 'Loan' THEN 1 ELSE 0 END)                           AS loans,
       SUM(CASE WHEN a.account_type = 'Loan' THEN a.loan_amount ELSE 0 END)               AS total_loan_amount,
       SUM(CASE WHEN a.account_type = 'FixedDeposit' THEN 1 ELSE 0 END)                   AS fixed_deposits,
       SUM(CASE WHEN a.account_type = 'FixedDeposit' AND a.account_status = 'Active' THEN 1 ELSE 0 END) AS active_fixed_deposits
FROM   customer_profile c
JOIN   bank_accounts a ON a.customer_id = c.customer_id
GROUP  BY c.customer_id, c.city, c.state, c.birth_date;

-- Yoxlama: 1000 qaytarmalıdır
SELECT COUNT(*) AS must_be_1000 FROM vw_customer_360;


/* ---------------------------------------------------------------------
   C) VW_MONTHLY_ACTIVITY: ay x kanal x tip üzrə aqreqat (dashboard faktı)
   Niyə: 2.4 mln sətir əvəzinə təxminən 800 sətir. Yalnız CUSTOMER_ACTIVITY
   (kredit/depozit cütləri pulu iki dəfə saymasın). Power BI üçün idealdır.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_monthly_activity AS
SELECT TRUNC(txn_date, 'MM') AS month_start,
       txn_year, txn_month, channel, transaction_type,
       COUNT(*)           AS txn_count,
       SUM(amount)        AS total_amount,
       SUM(signed_amount) AS net_amount
FROM   clean_account_transaction
WHERE  txn_category = 'CUSTOMER_ACTIVITY'
GROUP  BY TRUNC(txn_date, 'MM'), txn_year, txn_month, channel, transaction_type;

-- Yoxlama: nəticə qaytarmalıdır
SELECT * FROM vw_monthly_activity WHERE ROWNUM <= 5;
