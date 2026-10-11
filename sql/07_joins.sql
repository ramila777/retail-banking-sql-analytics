/* =====================================================================
   07_JOINS.SQL  -  JOIN NÖVLƏRİ (4 sorğu)
   INNER | LEFT | FULL OUTER | CROSS

   Anti-join, SELF JOIN və fanout problemi 08_analytical_queries.sql-dədir
   (Step06, Step11, Step05), burada təkrar yazmırıq.

   Əlaqələr:
     customer_profile.customer_id      = bank_accounts.customer_id
     bank_accounts.account_id          = account_transaction.account_id
     transaction_code.transaction_code = account_transaction.transaction_code
   Hər sorğunu seç + Ctrl+Enter.
   ===================================================================== */


-- J1. INNER JOIN (3 cədvəl): ştat üzrə müştəri xərci
-- INNER yalnız hər iki tərəfdə qarşılığı olan sətirləri saxlayır.
SELECT c.state,
       COUNT(DISTINCT c.customer_id) AS customers,
       SUM(t.amount)                 AS total_spend
FROM   customer_profile c
JOIN   bank_accounts a             ON a.customer_id = c.customer_id
JOIN   clean_account_transaction t ON t.account_id  = a.account_id
WHERE  t.txn_category = 'CUSTOMER_ACTIVITY' AND t.transaction_type = 'Debit'
GROUP  BY c.state
ORDER  BY total_spend DESC;
-- Nəticə və tövsiyə: 1 000 müştəri 20 ştatdadır. Xərcin 55,6%-i ilk dörd ştatın (California, Texas, Florida, New York) payına
--   düşür, bu da müştərilərin 53,5%-ni təşkil edir. Müştəri başına xərc çox ştatda 50-60 mln-dur, Florida (71
--   mln) yüksək, Arizona və Virginia (37 mln) aşağıdır. Tövsiyə: kiçik ştatlarda (məsələn Indiana, 3 müştəri)
--   nəticəyə ehtiyatla yanaşmaq.


-- J2. LEFT JOIN: bütün müştərilər, krediti olmayanlar da 0 ilə görünür
-- Loan şərti ON-dadır. WHERE-ə yazsaydıq, LEFT JOIN praktikada INNER JOIN-a çevrilərdi.
SELECT c.customer_id,
       COUNT(l.account_id)        AS loans,
       NVL(SUM(l.loan_amount), 0) AS total_loan
FROM   customer_profile c
LEFT   JOIN bank_accounts l ON l.customer_id = c.customer_id AND l.account_type = 'Loan'
GROUP  BY c.customer_id
ORDER  BY loans DESC;
-- Nəticə və tövsiyə: Hər müştəri bir sətirdə görünür (1 000), krediti olmayan 334 müştəri isə 0 kredit ilə nəticədədir. INNER
--   JOIN yalnız kreditli müştəriləri (666) qaytarardı. Tövsiyə: 'olmayanı' tapmaq lazım olan analizlərdə LEFT
--   JOIN seçmək.


-- J3. FULL OUTER JOIN: kod cədvəli ilə faktiki istifadə uyğundurmu?
-- Hər iki tərəfdə sətir itmirsə, data bütövdür (auditə uyğun: yetim kod yoxdur).
SELECT NVL(c.transaction_code, u.transaction_code) AS code,
       c.label,
       NVL(u.n, 0) AS times_used
FROM   transaction_code c
FULL   OUTER JOIN (SELECT transaction_code, COUNT(*) AS n
                   FROM   account_transaction
                   GROUP  BY transaction_code) u
       ON u.transaction_code = c.transaction_code
ORDER  BY times_used DESC;
-- Nəticə və tövsiyə: 15 kodun hamısı əməliyyatlarda istifadə olunur və hər əməliyyatın kodu cədvəldə var (cəmi 2 377 169
--   sətir). Kod cədvəli ilə əməliyyatlar arasında yetim yoxdur. Tövsiyə: yeni data yüklənəndə bu yoxlamanı
--   təkrarlamaq.


-- J4. CROSS JOIN + LEFT JOIN: bütün il x kanal kombinasiyaları (boş olanlar 0 ilə)
-- CROSS JOIN hər sətri hər sətirlə birləşdirir (6 il x 6 kanal = 36 kombinasiya).
-- System kanalında müştəri əməliyyatı yoxdur, ona görə həmin 6 sətir 0 görünür.
SELECT y.txn_year, c.channel, NVL(cnt.n, 0) AS txn_count
FROM  (SELECT 2019 + LEVEL AS txn_year FROM dual CONNECT BY LEVEL <= 6) y
CROSS  JOIN (SELECT 'ATM' AS channel FROM dual
             UNION ALL SELECT 'Branch' FROM dual
             UNION ALL SELECT 'InterbankPortal' FROM dual
             UNION ALL SELECT 'MobileApp' FROM dual
             UNION ALL SELECT 'OnlineBanking' FROM dual
             UNION ALL SELECT 'System' FROM dual) c
LEFT   JOIN (SELECT txn_year, channel, COUNT(*) AS n
             FROM   clean_account_transaction
             WHERE  txn_category = 'CUSTOMER_ACTIVITY'
             GROUP  BY txn_year, channel) cnt
       ON cnt.txn_year = y.txn_year AND cnt.channel = c.channel
ORDER  BY y.txn_year, c.channel;
-- Nəticə və tövsiyə: Tam il x kanal cədvəlində 36 kombinasiya var. System kanalında müştəri əməliyyatı olmadığı üçün həmin 6
--   sətir 0 görünür. Tövsiyə: hesabatlarda boş kombinasiyaları göstərmək lazımdırsa CROSS JOIN + LEFT JOIN
--   işlətmək.
