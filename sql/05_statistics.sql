/* =====================================================================
   05_STATISTICS.SQL  -  STATİSTİKA (4 sorğu)
   Paylanma | Persentil | Korrelyasiya | Outlier
   Hər sorğunu seç + Ctrl+Enter.
   ===================================================================== */


-- ST1. Paylanma: orta, median, standart sapma, dəyişkənlik əmsalı
-- Orta median-dan xeyli böyükdürsə, paylanma sağa əyilib (az sayda çox böyük əməliyyat).
-- CV = std / orta: nə qədər böyükdürsə, məbləğlər bir o qədər dağınıqdır.
SELECT transaction_code,
       ROUND(AVG(amount))                     AS mean_amt,
       ROUND(MEDIAN(amount))                  AS median_amt,
       ROUND(STDDEV(amount))                  AS std_amt,
       ROUND(STDDEV(amount) / AVG(amount), 2) AS coef_variation
FROM   clean_account_transaction
WHERE  txn_category = 'CUSTOMER_ACTIVITY'
GROUP  BY transaction_code;
-- Nəticə və tövsiyə: Hər beş əməliyyat növündə orta medianın 1,8-2,2 mislidir və standart sapma ortadan böyükdür (CV 2,8-4,6).
--   Yəni paylanma sağa əyilib: tipik əməliyyat kiçikdir, az sayda iri əməliyyat ortanı yuxarı çəkir. Tövsiyə:
--   hesabatlarda ortanı median ilə birlikdə göstərmək.


-- ST2. Persentillər (PERCENTILE_CONT): P25, P50, P75, P95
SELECT transaction_code,
       ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY amount)) AS p25,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY amount)) AS p50,
       ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY amount)) AS p75,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY amount)) AS p95
FROM   clean_account_transaction
WHERE  txn_category = 'CUSTOMER_ACTIVITY'
GROUP  BY transaction_code;
-- Nəticə və tövsiyə: P95 medianın 4-6,5 mislidir. Ticarət ödənişləri ən dağınıqdır (P75/P25 = 5,0), nağd çıxarış ən
--   bircinslidir (2,8). Nağd məbləğlər yumru rəqəmlərdir (1 200, 1 800, 3 400). Tövsiyə: limit və nəzarət
--   hədlərini orta əvəzinə yüksək persentilə (P95-P99) görə təyin etmək.


-- ST3. Korrelyasiya (CORR): -1 ... +1. 0-a yaxın = əlaqə yoxdur.
-- Kredit məbləği ilə faiz və müddət arasında əlaqə varmı?
SELECT ROUND(CORR(loan_amount, interest_rate), 3) AS corr_amount_rate,
       ROUND(CORR(loan_amount, term_months), 3)   AS corr_amount_term
FROM   bank_accounts
WHERE  account_type = 'Loan';
-- Nəticə və tövsiyə: Kredit məbləği ilə faiz (r = -0,045) və müddət (r = -0,008) arasında xətti əlaqə yoxdur: bu portfeldə
--   faiz və müddət məbləğdən asılı deyil. Tövsiyə: faizin nəyə görə təyin olunduğunu başqa amillərlə
--   (gecikmə, açılış ili) araşdırmaq.


-- ST4. Outlier: IQR qaydası (Q3 + 1.5 * IQR-dən böyük əməliyyatlar)
-- Outlier avtomatik "səhv" deyil, yalnız yoxlanmalı namizəddir.
SELECT t.transaction_code, COUNT(*) AS outliers, MAX(t.amount) AS largest
FROM   clean_account_transaction t
JOIN  (SELECT transaction_code,
              PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY amount) AS q1,
              PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY amount) AS q3
       FROM   clean_account_transaction
       WHERE  txn_category = 'CUSTOMER_ACTIVITY'
       GROUP  BY transaction_code) q
       ON q.transaction_code = t.transaction_code
WHERE  t.amount > q.q3 + 1.5 * (q.q3 - q.q1)
GROUP  BY t.transaction_code;
-- Nəticə və tövsiyə: IQR qaydası müştəri əməliyyatlarının 7,7%-ni (179 780) outlier saydı, çünki paylanma sağa əyilib. Ən
--   böyük əməliyyatlar median məbləğdən yüzlərlə dəfə böyükdür (445-1 467 dəfə). Tövsiyə: IQR siqnalını
--   avtomatik 'şübhəli' saymamaq, sabit yüksək hədd (məsələn P99) götürüb ən böyük əməliyyatları ayrıca
--   yoxlamaq.
