/* =====================================================================
   01_AUDIT.SQL  -  DATA AUDİTİ (8 blok)
   Cleaning yazmazdan əvvəl datanın vəziyyətini yoxlayırıq: hər cleaning
   qərarının arxasında sübut olsun. Fayl yalnız oxuyur (SELECT).
   Hər sorğunu seç + Ctrl+Enter.
   ===================================================================== */


-- 1. İmport yoxlaması: sətir sayları mənbə CSV ilə eyni olmalıdır.
-- Tapıntı: 2 377 169 / 3 553 / 1 000 / 15
SELECT 'ACCOUNT_TRANSACTION' AS tbl, COUNT(*) AS n FROM account_transaction
UNION ALL SELECT 'BANK_ACCOUNTS',    COUNT(*) FROM bank_accounts
UNION ALL SELECT 'CUSTOMER_PROFILE', COUNT(*) FROM customer_profile
UNION ALL SELECT 'TRANSACTION_CODE', COUNT(*) FROM transaction_code;


-- 2. Sütun tipləri: tarix DATE, məbləğ NUMBER olmalıdır.
-- Tapıntı: tiplər düzgündür -> TO_DATE / TO_NUMBER çevirməsi lazım deyil.
SELECT table_name, column_name, data_type
FROM   user_tab_columns
WHERE  table_name IN ('ACCOUNT_TRANSACTION','BANK_ACCOUNTS','CUSTOMER_PROFILE','TRANSACTION_CODE')
ORDER  BY table_name, column_id;


-- 3. Əməliyyat cədvəli: dublikat, NULL, mənfi məbləğ, tarix aralığı.
-- total_rows = distinct_ids -> dublikat yoxdur. null_ids = 0 -> ID boş deyil.
-- Tapıntı: hamısı təmiz; tarix 2020-01-02 ... 2025-12-31; linked_rows = 36 276.
SELECT COUNT(*)                                          AS total_rows,
       COUNT(DISTINCT transaction_id)                    AS distinct_ids,
       SUM(CASE WHEN transaction_id IS NULL OR account_id IS NULL THEN 1 ELSE 0 END) AS null_ids,
       SUM(CASE WHEN amount IS NULL THEN 1 ELSE 0 END)   AS null_amount,
       SUM(CASE WHEN amount <= 0    THEN 1 ELSE 0 END)   AS nonpositive_amount,
       COUNT(linked_transaction_id)                      AS linked_rows,
       MIN(created_time)                                 AS min_date,
       MAX(created_time)                                 AS max_date
FROM   account_transaction;


-- 4. Yetim sətirlər: əməliyyatın hesabı, hesabın müştərisi, əməliyyatın kodu mövcuddurmu?
-- Yoxdursa, JOIN zamanı sətirlər səssizcə itər.
-- Tapıntı: üçü də 0. (İndeks olmadığı üçün 1-2 dəqiqə çəkə bilər.)
SELECT 'transaction -> account' AS check_name, COUNT(*) AS orphans
FROM   account_transaction t
WHERE  NOT EXISTS (SELECT 1 FROM bank_accounts a WHERE a.account_id = t.account_id)
UNION ALL
SELECT 'account -> customer', COUNT(*)
FROM   bank_accounts a
WHERE  NOT EXISTS (SELECT 1 FROM customer_profile c WHERE c.customer_id = a.customer_id)
UNION ALL
SELECT 'transaction -> code', COUNT(*)
FROM   account_transaction t
WHERE  NOT EXISTS (SELECT 1 FROM transaction_code tc WHERE tc.transaction_code = t.transaction_code);


-- 5. Kateqoriyalar: yazılış fərqi (Debit / debit / DEBIT) varmı?
-- Tapıntı: transaction_type yalnız Debit və Credit; channel 6 təmiz dəyər.
SELECT 'transaction_type' AS col, transaction_type AS value, COUNT(*) AS n
FROM   account_transaction GROUP BY transaction_type
UNION ALL
SELECT 'channel', channel, COUNT(*)
FROM   account_transaction GROUP BY channel
ORDER  BY 1, 3 DESC;


-- 6. Kod cədvəli + hər kod üzrə say və bağlı sətirlər (bir sorğuda).
-- Tapıntı: kredit və depozit kodları CÜTDÜR (eyni pul iki hesabda iki sətir):
--   LN_DISB<->LN_DISB_CR, LN_PMNT<->LN_PMNT_DR, FD_OPEN<->FD_OPEN_DR, FD_MAT_CHG<->FD_MAT_CR
--   -> SUM(amount) bütün sətirlərdə pulu İKİ DƏFƏ sayar.
-- Tapıntı: FD_OPEN 1 546 sətir, amma bağlı olanı 1 012 -> 534 depozit açılışının cütü yoxdur.
SELECT c.transaction_code, c.label, c.account_type, c.transaction_type,
       COUNT(t.transaction_id)       AS n,
       COUNT(t.linked_transaction_id) AS linked
FROM   transaction_code c
LEFT   JOIN account_transaction t ON t.transaction_code = c.transaction_code
GROUP  BY c.transaction_code, c.label, c.account_type, c.transaction_type
ORDER  BY n DESC;


-- 7. bank_accounts: keyfiyyət + hesab tipi və status.
-- Tapıntı: 3 553 hesab, dublikat yox, 1 000 müştəri, mənfi balans yox, 1 007 kreditli hesab.
SELECT COUNT(*)                                     AS total_rows,
       COUNT(DISTINCT account_id)                   AS distinct_accounts,
       COUNT(DISTINCT customer_id)                  AS distinct_customers,
       SUM(CASE WHEN account_id IS NULL OR customer_id IS NULL THEN 1 ELSE 0 END) AS null_ids,
       SUM(CASE WHEN balance < 0 THEN 1 ELSE 0 END) AS negative_balance,
       COUNT(loan_amount)                           AS rows_with_loan
FROM   bank_accounts;

-- Tapıntı: Savings 1 000 (Active); Loan 1 007 (783 Active, 224 Inactive);
--          FixedDeposit 1 546 (701 Active, 845 Inactive = bitmiş depozit).
SELECT account_type, account_status, COUNT(*) AS n
FROM   bank_accounts
GROUP  BY account_type, account_status
ORDER  BY account_type, n DESC;


-- 8. customer_profile: dublikat, boş ID, şəhər yazılışı, doğum tarixi.
-- distinct_national_ids < total_rows -> eyni şəxs iki dəfə yazılıb.
-- cities_raw <> cities_normalized    -> 'Baku' / 'baku ' kimi fərqlər.
-- oldest / youngest                  -> məntiqsiz doğum tarixi.
-- (Nəticə: dublikat, boş ID və yazılış fərqi yoxdur, bu cədvələ view lazım deyil.)
SELECT COUNT(*)                          AS total_rows,
       COUNT(DISTINCT customer_id)       AS distinct_ids,
       COUNT(DISTINCT national_id)       AS distinct_national_ids,
       SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_ids,
       COUNT(DISTINCT city)              AS cities_raw,
       COUNT(DISTINCT UPPER(TRIM(city))) AS cities_normalized,
       MIN(birth_date)                   AS oldest,
       MAX(birth_date)                   AS youngest
FROM   customer_profile;


/* =====================================================================
   AUDİTİN XÜLASƏSİ (README üçün)
   Problem YOXDUR: dublikat ID, boş/mənfi məbləğ, yetim sətir, yazılış fərqi.
   Problem VAR:
     1) Kredit/depozit əməliyyatları iki sətirdə yazılır -> SUM(amount) pulu iki dəfə sayır.
     2) Məbləğ həmişə müsbətdir, istiqaməti Debit/Credit göstərir.
     3) 534 depozit açılışının qarşı sətri yoxdur.
   Dərin yoxlama (cütlərin məbləği): 08_analytical_queries.sql, Step11.
   ===================================================================== */
