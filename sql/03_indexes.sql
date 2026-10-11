/* =====================================================================
   03_INDEXES.SQL  -  İNDEKSLƏR VƏ PERFORMANS ÖLÇMƏSİ (4 addım)

   account_transaction 2.4 mln sətirdir. İndeks olmasa, hər filtr bütün
   cədvəli oxuyur (FULL TABLE SCAN). Plan: əvvəl ölç, indeks yarat, yenidən ölç.
   Addım 1 və 4-də planı və sorğunun vaxtını (nəticə pəncərəsinin üstündə
   "Fetched ... in X seconds") qeyd et. Əvvəl/sonra müqayisəsi README-də
   ən güclü sübutlardan biridir.
   ===================================================================== */


-- ADDIM 1: İNDEKSDƏN ƏVVƏL. Planda "TABLE ACCESS FULL" görməlisən.
EXPLAIN PLAN SET STATEMENT_ID = 'before_idx' FOR
SELECT SUM(amount), COUNT(*)
FROM   account_transaction
WHERE  account_id = (SELECT MIN(account_id) FROM bank_accounts WHERE account_type = 'Savings');

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'before_idx'));

-- Real vaxtı ölçmək üçün sorğunu özünü də işlət:
SELECT SUM(amount), COUNT(*)
FROM   account_transaction
WHERE  account_id = (SELECT MIN(account_id) FROM bank_accounts WHERE account_type = 'Savings');


-- ADDIM 2: PRIMARY KEY-lər və indekslər (hər biri 1-2 dəqiqə çəkə bilər)
-- PRIMARY KEY unikallığı məcbur edir və avtomatik unikal indeks yaradır.
-- Auditdə üç cədvəlin ID-ləri unikal və boş olmayan çıxdı.
ALTER TABLE account_transaction ADD CONSTRAINT pk_account_transaction PRIMARY KEY (transaction_id);
ALTER TABLE bank_accounts       ADD CONSTRAINT pk_bank_accounts       PRIMARY KEY (account_id);
ALTER TABLE customer_profile    ADD CONSTRAINT pk_customer_profile    PRIMARY KEY (customer_id);

-- İkinci dərəcəli indekslər: yalnız JOIN/WHERE-də işlənən sütunlara.
CREATE INDEX idx_txn_account   ON account_transaction (account_id);                      -- əməliyyat -> hesab JOIN
CREATE INDEX idx_txn_code_date ON account_transaction (transaction_code, created_time); -- kod + tarix filtri
CREATE INDEX idx_txn_linked    ON account_transaction (linked_transaction_id);           -- bağlı cütlər (SELF JOIN)
CREATE INDEX idx_acc_customer  ON bank_accounts (customer_id);                           -- hesab -> müştəri JOIN
-- channel və transaction_type-a indeks YAZMIRIQ: 6 və 2 unikal dəyər, B-tree faydasızdır.
-- Kompromis: hər indeks yer tutur və INSERT/UPDATE-i yavaşladır, ona görə yalnız lazım olanlar.


-- ADDIM 3: Statistikanı yenilə (optimizer yeni indeksləri tanısın)
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'ACCOUNT_TRANSACTION', cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'BANK_ACCOUNTS',       cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'CUSTOMER_PROFILE',    cascade => TRUE);
END;
/


-- ADDIM 4: İNDEKSDƏN SONRA. Eyni sorğu. Planda indi "INDEX RANGE SCAN" görməlisən.
EXPLAIN PLAN SET STATEMENT_ID = 'after_idx' FOR
SELECT SUM(amount), COUNT(*)
FROM   account_transaction
WHERE  account_id = (SELECT MIN(account_id) FROM bank_accounts WHERE account_type = 'Savings');

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'after_idx'));

SELECT SUM(amount), COUNT(*)
FROM   account_transaction
WHERE  account_id = (SELECT MIN(account_id) FROM bank_accounts WHERE account_type = 'Savings');

/* README üçün cədvəl (öz nəticələrinlə doldur):
   | Sorğu                      | İndeksdən əvvəl | İndeksdən sonra |
   | Hesab üzrə əməliyyat cəmi  | ___ san (FULL)  | ___ san (RANGE) |  */
