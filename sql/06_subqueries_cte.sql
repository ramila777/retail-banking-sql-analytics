/* =====================================================================
   06_SUBQUERIES_CTE.SQL  -  SUBQUERY VƏ CTE (5 sorğu)
   Skalyar | NOT EXISTS | Korrelyasiyalı | Zəncirvari CTE | Təqvim
   Hər sorğunu seç + Ctrl+Enter.
   ===================================================================== */


-- S1. Skalyar subquery: orta savings balansından yüksək hesablar
SELECT account_id, customer_id, balance
FROM   bank_accounts
WHERE  account_type = 'Savings'
  AND  balance > (SELECT AVG(balance) FROM bank_accounts WHERE account_type = 'Savings')
ORDER  BY balance DESC;
-- Nəticə və tövsiyə: Orta savings balansından yüksək hesablar: ___ hesab (___%). Tövsiyə: ___.


-- S2. NOT EXISTS: krediti olmayan müştərilər
-- NOT IN əvəzinə NOT EXISTS: subquery-də NULL olsa NOT IN heç nə qaytarmaz (klassik tələ).
SELECT c.customer_id, c.city
FROM   customer_profile c
WHERE  NOT EXISTS (SELECT 1 FROM bank_accounts a
                   WHERE  a.customer_id = c.customer_id AND a.account_type = 'Loan');
-- Nəticə və tövsiyə: 1 000 müştərinin 334-ünün (33,4%) krediti yoxdur. Tövsiyə: onları, xüsusilə savings balansı yüksək
--   olanları (Step06), kredit təklifi üçün hədəf qrup kimi götürmək.


-- S3. Korrelyasiyalı subquery: öz müddət qrupunun ortasından böyük kreditlər
-- Subquery hər xarici sətir üçün yenidən hesablanır (l.term_months-a istinad edir).
SELECT l.account_id, l.term_months, l.loan_amount
FROM   bank_accounts l
WHERE  l.account_type = 'Loan'
  AND  l.loan_amount > (SELECT AVG(l2.loan_amount)
                        FROM   bank_accounts l2
                        WHERE  l2.account_type = 'Loan'
                          AND  l2.term_months = l.term_months)
ORDER  BY l.term_months, l.loan_amount DESC;
-- Nəticə və tövsiyə: 1 007 kreditin 162-si (16,1%) öz müddət qrupunun ortasından böyükdür. Ən böyük kreditlər bütün
--   müddətlərdə təxminən eyni səviyyədədir (72-80 mln), yəni müddət ilə məbləğ əlaqəli deyil. Tövsiyə: iri
--   kreditləri ayrıca limit və izləmə altında saxlamaq.


-- S4. İç-içə subquery (zəncir): müştəri xərci -> kvartil -> seqment. İçdən çölə oxunur.
SELECT segment, COUNT(*) AS customers, ROUND(AVG(spend)) AS avg_spend
FROM  (SELECT customer_id, spend,
              CASE quartile WHEN 1 THEN 'High' WHEN 4 THEN 'Low' ELSE 'Medium' END AS segment
       FROM  (SELECT customer_id, spend, NTILE(4) OVER (ORDER BY spend DESC) AS quartile
              FROM  (SELECT a.customer_id, SUM(t.amount) AS spend
                     FROM   clean_account_transaction t
                     JOIN   bank_accounts a ON a.account_id = t.account_id
                     WHERE  t.txn_category = 'CUSTOMER_ACTIVITY' AND t.transaction_type = 'Debit'
                     GROUP  BY a.customer_id)))
GROUP  BY segment
ORDER  BY avg_spend DESC;
-- Nəticə və tövsiyə: Müştərilərin ən çox xərcləyən 25%-i xərcin 61,3%-ni yaradır, ən az xərcləyən 25% isə yalnız 3,6%-ni.
--   Tövsiyə: High seqmentini saxlamağa (limit, loyallıq təklifi), Low seqmentdə isə fəallığı artırmağa
--   yönəlmək. Qeyd: seqmentlər müştərinin bank tarixçəsinin uzunluğunu nəzərə almır.


-- S5. Təqvim cədvəli (CONNECT BY LEVEL): əməliyyatsız aylar da 0 ilə görünsün
-- Təqvim olmasa, əməliyyatı olmayan ay nəticədən sadəcə itər.
SELECT cal.month_start, NVL(s.spend, 0) AS spend
FROM  (SELECT ADD_MONTHS(DATE '2020-01-01', LEVEL - 1) AS month_start
       FROM   dual
       CONNECT BY LEVEL <= 72) cal                -- 2020-01 ... 2025-12
LEFT   JOIN (SELECT TRUNC(txn_date, 'MM') AS month_start, SUM(amount) AS spend
             FROM   clean_account_transaction
             WHERE  txn_category = 'CUSTOMER_ACTIVITY' AND transaction_type = 'Debit'
             GROUP  BY TRUNC(txn_date, 'MM')) s
       ON s.month_start = cal.month_start
ORDER  BY cal.month_start;
-- Nəticə və tövsiyə: 72 ayın hamısında müştəri əməliyyatı var, aylıq seriyada boşluq yoxdur. Tövsiyə: zaman seriyası
--   sorğularında təqvim cədvəlindən istifadə etmək ki, əməliyyatsız aylar nəticədən itməsin.
