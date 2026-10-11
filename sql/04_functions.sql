/* =====================================================================
   04_FUNCTIONS.SQL  -  FUNKSİYALAR (5 sorğu)
   Aqreqat (F1-F2) | Tarix (F3) | Window (F4-F5)
   Hər sorğunu seç + Ctrl+Enter.
   ===================================================================== */


-- F1. Aqreqat + HAVING: kod üzrə say, cəm, orta.
-- WHERE qruplaşmadan ƏVVƏL satırları süzür, HAVING qruplaşmadan SONRA qrupları süzür.
SELECT transaction_code,
       COUNT(*)           AS txn_count,
       SUM(amount)        AS total_amount,
       ROUND(AVG(amount)) AS avg_amount
FROM   clean_account_transaction
WHERE  txn_category = 'CUSTOMER_ACTIVITY'
GROUP  BY transaction_code
HAVING COUNT(*) > 300000
ORDER  BY txn_count DESC;
-- Nəticə və tövsiyə: Müştəri əməliyyatlarının 42,4%-i ticarət ödənişləridir (MER_PAY, orta 11 841). Nağd çıxarış tez-tezdir,
--   amma kiçikdir (orta 3 198), nağd mədaxil isə daha seyrək və iridir (orta 8 712). Tövsiyə: ATM və filial
--   yükünü planlayanda çıxarışın tezliyini, mədaxilin isə məbləğini əsas götürmək.


-- F2. Şərti aqreqat (SUM + CASE): il üzrə Debit və Credit ayrı sütunlarda
SELECT txn_year,
       SUM(CASE WHEN transaction_type = 'Debit'  THEN amount ELSE 0 END) AS debit_total,
       SUM(CASE WHEN transaction_type = 'Credit' THEN amount ELSE 0 END) AS credit_total
FROM   clean_account_transaction
WHERE  txn_category = 'CUSTOMER_ACTIVITY'
GROUP  BY txn_year
ORDER  BY txn_year;
-- Nəticə və tövsiyə: Daxilolma hər il xərcdən böyükdür (6 ildə xalis +6,71 mlrd). Debit/Credit nisbəti 0,74-dən 0,92-yə
--   qalxıb, yəni müştərilər daxilolmanın getdikcə daha böyük hissəsini xərcləyir. Artımın böyük hissəsi hesab
--   sayının çoxalmasından gəlir (156 → 1 000 savings hesab). Tövsiyə: illər arası müqayisəni hesab başına
--   xərclə aparmaq.


-- F3. Tarix və NULL funksiyaları: TRUNC, ADD_MONTHS, MONTHS_BETWEEN, NULLIF
-- NULLIF 0-a bölmədən qoruyur (loan_amount NULL/0 olan hesablarda xəta çıxmasın).
SELECT creation_date,
       ADD_MONTHS(creation_date, term_months)                  AS planned_end_date,
       TRUNC(MONTHS_BETWEEN(DATE '2025-12-31', creation_date)) AS age_in_months,
       ROUND(balance / NULLIF(loan_amount, 0), 2)              AS balance_to_loan
FROM   bank_accounts
WHERE  account_type = 'Loan' AND ROWNUM <= 10;
-- Nəticə və tövsiyə: Kredit müddətləri 10-50 il arasındadır (120-600 ay), bu real bank üçün qeyri-adi uzundur və datanın
--   xüsusiyyətidir. Kreditin balance sütununun mənası aydın olmadığı üçün analizdə istifadə edilmir. Tövsiyə:
--   bu sütunun mənasını data mənbəyindən dəqiqləşdirmədən nəticə çıxarmamaq.


-- F4. RANK / DENSE_RANK / ROW_NUMBER: hər ildə kanalların xərc sırası (PARTITION BY il)
-- RANK bərabərlikdə nömrə atlayır, DENSE_RANK atlamır, ROW_NUMBER heç vaxt təkrarlamır.
SELECT txn_year, channel, total_spend,
       RANK()       OVER (PARTITION BY txn_year ORDER BY total_spend DESC) AS rnk,
       DENSE_RANK() OVER (PARTITION BY txn_year ORDER BY total_spend DESC) AS dense_rnk,
       ROW_NUMBER() OVER (PARTITION BY txn_year ORDER BY total_spend DESC) AS row_num
FROM  (SELECT txn_year, channel, SUM(amount) AS total_spend
       FROM   clean_account_transaction
       WHERE  txn_category = 'CUSTOMER_ACTIVITY' AND transaction_type = 'Debit'
       GROUP  BY txn_year, channel)
ORDER  BY txn_year, rnk;
-- Nəticə və tövsiyə: Xərcin təxminən 75-77%-i hər il bank-arası köçürmələrdən (InterbankPortal) keçir. 2025-də OnlineBanking
--   MobileApp-ı keçib (1,82 və 1,75 mlrd), ATM və Branch isə demək olar ki, bərabərdir. Tövsiyə: bank-arası
--   köçürmə limitlərinə və nəzarətinə xüsusi diqqət ayırmaq, mobil kanalın 2025-dəki geriləməsini yoxlamaq.


-- F5. LAG / LEAD: aylıq xərc, əvvəlki və sonrakı ay
SELECT month_start, spend,
       LAG(spend)  OVER (ORDER BY month_start) AS prev_month,
       LEAD(spend) OVER (ORDER BY month_start) AS next_month
FROM  (SELECT TRUNC(txn_date, 'MM') AS month_start, SUM(amount) AS spend
       FROM   clean_account_transaction
       WHERE  txn_category = 'CUSTOMER_ACTIVITY' AND transaction_type = 'Debit'
       GROUP  BY TRUNC(txn_date, 'MM'))
ORDER  BY month_start;
-- Nəticə və tövsiyə: Aylıq xərc 7 mln-dan (Yanvar 2020) təxminən 1,6 mlrd-a (2025) qalxıb, 2024-2025-də ay-ay dəyişmə təxminən
--   ±10%-dir. Sentyabr 6 ilin hamısında avqustdan aşağıdır (-1,1%-dən -6,9%-ə qədər). Tövsiyə: mövsümi təsiri
--   təsdiqləmək üçün hesab sayını nəzərə alan (hesab başına) xərclə yoxlamaq.
