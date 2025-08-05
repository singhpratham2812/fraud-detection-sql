-- ============================================================
--
--   FRAUD DETECTION SQL CASE STUDY
--   Dataset : PaySim Synthetic Financial Transactions
--   Tool    : MySQL Workbench 8.0
--   Author  : Pratham Singh
--
--   WHAT IS THIS PROJECT?
--   ---------------------
--   We have 30,000 financial transactions — transfers, payments,
--   cash-outs, and more. 84 of them are fraudulent. The existing
--   rule-based system flagged ZERO of those 84 cases.
--
--   This file uses SQL to:
--   1. Understand the scale of fraud (Module 1)
--   2. Identify which accounts are high risk (Module 2)
--   3. Find behavioural patterns in fraud (Module 3)
--   4. Build a risk scoring model that catches what the system missed (Module 4)
--
-- ============================================================

CREATE DATABASE fraud_detection; 
USE fraud_detection;

-- ============================================================
-- QUICK LOOK AT THE DATA BEFORE WE START
-- ============================================================

SELECT * FROM transactions LIMIT 10;

-- You will see 11 columns:
-- step          = hour number when the transaction happened (1 = hour 1, 8 = hour 8)
-- type          = what kind of transaction (TRANSFER, CASH_OUT, PAYMENT, etc.)
-- amount        = how much money was moved
-- nameOrig      = the account that SENT the money
-- oldbalanceOrg = sender's balance BEFORE the transaction
-- newbalanceOrig= sender's balance AFTER the transaction
-- nameDest      = the account that RECEIVED the money
-- oldbalanceDest= receiver's balance BEFORE the transaction
-- newbalanceDest= receiver's balance AFTER the transaction
-- isFraud       = 1 means this transaction IS fraud, 0 means it is NOT
-- isFlaggedFraud= 1 means the system CAUGHT it as fraud, 0 means it MISSED it


-- ============================================================
-- MODULE 1: FRAUD OVERVIEW — WHAT IS THE BIG PICTURE?
-- ============================================================
-- Before we dive deep, we need to answer the basic question:
-- how much fraud exists and where is it concentrated?
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- QUERY 1: Overall fraud numbers
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Counting total transactions, how many are fraud, what % that is,
-- and how much money was lost to fraud vs the average legitimate transaction.
--
-- NEW SQL CONCEPT — AGGREGATE FUNCTIONS:
-- COUNT(*)          = counts all rows
-- SUM(column)       = adds up all values in that column
-- ROUND(number, 2)  = rounds to 2 decimal places
-- CASE WHEN ... THEN ... ELSE ... END = IF/ELSE logic inside SQL
--   Example: CASE WHEN isFraud = 1 THEN amount ELSE 0 END
--   means: "if this row is fraud, use the amount, otherwise use 0"
--   Then SUM() of that = total fraud amount only
-- ────────────────────────────────────────────────────────────

SELECT
    COUNT(*)                                                AS total_transactions,
    SUM(isFraud)                                            AS total_fraud_cases,
    ROUND(SUM(isFraud) / COUNT(*) * 100, 2)                AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN isFraud = 1 THEN amount ELSE 0 END), 2)
                                                            AS total_fraud_value,
    ROUND(AVG(CASE WHEN isFraud = 1 THEN amount END), 2)   AS avg_fraud_amount,
    ROUND(AVG(CASE WHEN isFraud = 0 THEN amount END), 2)   AS avg_legit_amount,
    MAX(CASE WHEN isFraud = 1 THEN amount END)              AS largest_fraud_amount
FROM transactions;

-- WHAT THIS MEANS:
-- fraud_rate_pct    = what % of all transactions are fraudulent
-- avg_fraud_amount  = the typical size of a fraud transaction
-- avg_legit_amount  = the typical size of a normal transaction
-- If avg_fraud_amount >> avg_legit_amount, fraudsters are going
-- after large transactions — which is a key insight for setting
-- monitoring thresholds.


-- ────────────────────────────────────────────────────────────
-- QUERY 2: Fraud by transaction type
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Breaking down fraud by transaction type. We expect fraud to be
-- concentrated in certain types, not spread evenly.
--
-- NEW SQL CONCEPT — GROUP BY:
-- GROUP BY type means: "run the COUNT/SUM separately for each
-- unique value of type". So instead of one total row, we get
-- one row per transaction type (TRANSFER, CASH_OUT, PAYMENT etc.)
-- ────────────────────────────────────────────────────────────

SELECT
    type                                                    AS transaction_type,
    COUNT(*)                                                AS total_transactions,
    SUM(isFraud)                                            AS fraud_cases,
    ROUND(SUM(isFraud) / COUNT(*) * 100, 2)                AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN isFraud = 1 THEN amount ELSE 0 END), 2)
                                                            AS total_fraud_value
FROM transactions
GROUP BY type
ORDER BY fraud_cases DESC;

-- WHAT THIS MEANS:
-- You will see that TRANSFER and CASH_OUT have ALL the fraud.
-- PAYMENT, DEBIT, and CASH_IN show zero fraud.
-- This tells us: we only need to monitor 2 out of 5 transaction
-- types — reducing the monitoring workload by 60%.


-- ────────────────────────────────────────────────────────────
-- QUERY 3: Did the existing system catch any fraud?
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Comparing isFraud (actual fraud) vs isFlaggedFraud (what the
-- system caught). This tells us how effective the current
-- rule-based system is.
--
-- NEW SQL CONCEPT — CASE WHEN for labelling:
-- We use CASE WHEN to create a human-readable label like
-- "True Positive" or "False Negative" instead of just 0s and 1s.
-- ────────────────────────────────────────────────────────────

SELECT
    CASE
        WHEN isFraud = 1 AND isFlaggedFraud = 1 THEN 'True Positive  — Caught correctly'
        WHEN isFraud = 1 AND isFlaggedFraud = 0 THEN 'False Negative — Fraud MISSED by system'
        WHEN isFraud = 0 AND isFlaggedFraud = 1 THEN 'False Positive — Wrongly flagged'
        WHEN isFraud = 0 AND isFlaggedFraud = 0 THEN 'True Negative  — Correctly ignored'
    END                                                     AS classification,
    COUNT(*)                                                AS transaction_count
FROM transactions
GROUP BY isFraud, isFlaggedFraud
ORDER BY isFraud DESC;

-- WHAT THIS MEANS:
-- You should see ALL 84 fraud cases are "False Negative" —
-- meaning the existing system missed 100% of fraud.
-- isFlaggedFraud = 0 for every single fraudulent transaction.
-- This is the business case for building a better detection model
-- which is exactly what Module 4 does.


-- ============================================================
-- MODULE 2: CUSTOMER RISK PROFILING — WHO IS HIGH RISK?
-- ============================================================
-- Now we know fraud is in TRANSFER and CASH_OUT. Next question:
-- which specific accounts are involved and what do they do?
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- QUERY 4: Which sender accounts appear in fraud transactions?
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Listing sender accounts (nameOrig) that appear in confirmed
-- fraud transactions, ranked by total fraud value.
-- This is the "watch list" for account restrictions.
--
-- NEW SQL CONCEPT — WHERE:
-- WHERE isFraud = 1 filters the data to only look at rows
-- where fraud actually happened before we group and count.
-- ────────────────────────────────────────────────────────────

SELECT
    nameOrig                                                AS sender_account,
    COUNT(*)                                                AS fraud_transactions,
    ROUND(SUM(amount), 2)                                   AS total_fraud_value,
    ROUND(AVG(amount), 2)                                   AS avg_fraud_amount,
    MIN(step)                                               AS first_seen_at_hour,
    MAX(step)                                               AS last_seen_at_hour
FROM transactions
WHERE isFraud = 1
GROUP BY nameOrig
ORDER BY total_fraud_value DESC
LIMIT 20;

-- WHAT THIS MEANS:
-- These are the top 20 sender accounts by total fraud value.
-- In a real company, this list goes straight to the fraud ops
-- team for account review and potential restriction.
-- first_seen and last_seen show how long an account was active
-- in fraud before being caught.


-- ────────────────────────────────────────────────────────────
-- QUERY 5: Do fraudsters drain accounts completely?
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Comparing how much money is left in the sender's account
-- after a fraud transaction vs a legitimate one.
-- A strong fraud signal is: account balance goes to exactly 0.
--
-- NEW SQL CONCEPT — Filtering with WHERE + IN:
-- WHERE type IN ('TRANSFER', 'CASH_OUT') means we only look
-- at those two types since we know fraud only happens there.
-- ────────────────────────────────────────────────────────────

SELECT
    isFraud,
    COUNT(*)                                                AS transactions,
    ROUND(AVG(oldbalanceOrg), 2)                            AS avg_balance_before,
    ROUND(AVG(newbalanceOrig), 2)                           AS avg_balance_after,
    COUNT(CASE WHEN newbalanceOrig = 0 THEN 1 END)          AS drained_to_zero_count,
    ROUND(
        COUNT(CASE WHEN newbalanceOrig = 0 THEN 1 END)
        / COUNT(*) * 100, 2
    )                                                       AS drained_to_zero_pct
FROM transactions
WHERE type IN ('TRANSFER', 'CASH_OUT')
GROUP BY isFraud;

-- WHAT THIS MEANS:
-- Compare drained_to_zero_pct for isFraud=1 vs isFraud=0.
-- If fraudulent transactions drain accounts to zero much more
-- often than legitimate ones, "newbalanceOrig = 0" becomes
-- an automatic fraud flag we can add to our scoring model.


-- ────────────────────────────────────────────────────────────
-- QUERY 6: Where does the fraud money go? (Mule accounts)
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Looking at the DESTINATION accounts that received fraudulent
-- transfers. Accounts receiving multiple fraud transfers are
-- likely "mule accounts" used to collect stolen money.
--
-- (No new SQL concepts — this builds on GROUP BY and WHERE
-- from the previous queries)
-- ────────────────────────────────────────────────────────────

SELECT
    nameDest                                                AS destination_account,
    COUNT(*)                                                AS fraud_receipts,
    ROUND(SUM(amount), 2)                                   AS total_received,
    ROUND(AVG(amount), 2)                                   AS avg_received_per_transaction,
    MIN(step)                                               AS first_seen_hour,
    MAX(step)                                               AS last_seen_hour
FROM transactions
WHERE isFraud = 1
GROUP BY nameDest
ORDER BY fraud_receipts DESC, total_received DESC
LIMIT 15;

-- WHAT THIS MEANS:
-- Destination accounts receiving multiple fraud transfers are
-- likely money mule accounts — used to collect then quickly
-- move stolen funds. In a real bank, these accounts would be
-- frozen and reported to financial intelligence units.


-- ============================================================
-- MODULE 3: BEHAVIOURAL SIGNALS — HOW DO FRAUDSTERS BEHAVE?
-- ============================================================
-- Pattern recognition: fraudsters behave differently from
-- regular customers. These queries find those differences.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- QUERY 7: Does fraud concentrate at specific hours?
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Grouping transactions by hour (step) to see if fraud happens
-- more at certain times. Real-world fraudsters often operate
-- at off-hours when monitoring teams are smaller.
-- ────────────────────────────────────────────────────────────

SELECT
    step                                                    AS hour,
    COUNT(*)                                                AS total_transactions,
    SUM(isFraud)                                            AS fraud_cases,
    ROUND(SUM(isFraud) / COUNT(*) * 100, 2)                AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN isFraud = 1 THEN amount ELSE 0 END), 2)
                                                            AS fraud_value
FROM transactions
GROUP BY step
ORDER BY fraud_rate_pct DESC;

-- WHAT THIS MEANS:
-- Hours with higher fraud_rate_pct = peak fraud windows.
-- A risk team would increase monitoring intensity during
-- those specific hours. This is called "time-based risk control".


-- ────────────────────────────────────────────────────────────
-- QUERY 8: At what transaction size does fraud spike?
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Grouping transactions into amount ranges (called "bands")
-- and checking which range has the highest fraud rate.
-- This tells us what transaction size should trigger extra checks.
--
-- NEW SQL CONCEPT — CASE WHEN for creating bands:
-- We create custom groups using CASE WHEN on a numeric column.
-- "WHEN amount < 10000 THEN 'Under 10K'" means: if the amount
-- is less than 10,000, label it as "Under 10K".
-- This is like creating a pivot table grouping in Excel.
-- ────────────────────────────────────────────────────────────

SELECT
    CASE
        WHEN amount < 10000             THEN '1. Under 10K'
        WHEN amount < 50000             THEN '2. 10K to 50K'
        WHEN amount < 100000            THEN '3. 50K to 100K'
        WHEN amount < 500000            THEN '4. 100K to 500K'
        WHEN amount < 1000000           THEN '5. 500K to 1M'
        ELSE                                 '6. Above 1M'
    END                                                     AS amount_band,
    COUNT(*)                                                AS total_transactions,
    SUM(isFraud)                                            AS fraud_cases,
    ROUND(SUM(isFraud) / COUNT(*) * 100, 2)                AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN isFraud = 1 THEN amount ELSE 0 END), 2)
                                                            AS fraud_value
FROM transactions
GROUP BY amount_band
ORDER BY amount_band;

-- WHAT THIS MEANS:
-- Look at which amount_band has the highest fraud_rate_pct.
-- That band is where you set your "enhanced review" threshold.
-- Example: if fraud rate jumps to 5% above 200K, then any
-- transaction above 200K should automatically get a second check.


-- ────────────────────────────────────────────────────────────
-- QUERY 9: Hidden fraud signal — destination balance unchanged
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Finding transactions where money was sent BUT the destination
-- account balance did not increase. This should be impossible
-- in a legitimate transaction — if you receive money, your
-- balance goes up. If it doesn't, the money was immediately
-- moved again — a laundering pattern.
--
-- NEW SQL CONCEPT — AND condition inside WHERE:
-- WHERE (oldbalanceDest = 0 AND newbalanceDest = 0 AND amount > 0)
-- means ALL three conditions must be true at the same time.
-- ────────────────────────────────────────────────────────────

SELECT
    type,
    COUNT(*)                                                AS total_transactions,
    SUM(isFraud)                                            AS actual_fraud,
    COUNT(
        CASE WHEN oldbalanceDest = 0
              AND newbalanceDest = 0
              AND amount > 0
        THEN 1 END
    )                                                       AS suspicious_dest_balance,
    ROUND(
        COUNT(
            CASE WHEN oldbalanceDest = 0
                  AND newbalanceDest = 0
                  AND amount > 0
            THEN 1 END
        ) / COUNT(*) * 100, 2
    )                                                       AS suspicious_pct
FROM transactions
WHERE type IN ('TRANSFER', 'CASH_OUT')
GROUP BY type;

-- WHAT THIS MEANS:
-- suspicious_dest_balance = transactions where money "disappeared"
-- into a destination account with no balance change.
-- Compare this number to actual_fraud — if suspicious_dest_balance
-- is much higher than actual_fraud, it means there is likely MORE
-- fraud in the dataset that hasn't been labelled yet.
-- This is a discovery finding — you found hidden risk.


-- ============================================================
-- MODULE 4: RISK SCORING MODEL — CAN WE CATCH WHAT THE SYSTEM MISSED?
-- ============================================================
-- The existing system caught 0 out of 84 fraud cases.
-- We will now build a simple scoring model using 5 signals
-- to see how many of those 84 we can catch.
--
-- NEW SQL CONCEPT — CTE (Common Table Expression):
-- A CTE is a temporary result that you create first (using WITH)
-- and then query from. Think of it like creating a new column
-- or a new summary tab in Excel, then doing more analysis on it.
--
-- Syntax:
--   WITH name_of_temp_table AS (
--       SELECT ... your query ...
--   )
--   SELECT * FROM name_of_temp_table WHERE ...
--
-- We use TWO CTEs chained together below.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- QUERY 10: Fraud trend over time
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Grouping hours into bands to see if fraud rises or falls
-- over the simulation period. Useful for spotting emerging
-- fraud waves vs stable background fraud.
-- ────────────────────────────────────────────────────────────

SELECT
    CASE
        WHEN step BETWEEN 1 AND 2   THEN 'Hours 1 to 2'
        WHEN step BETWEEN 3 AND 4   THEN 'Hours 3 to 4'
        WHEN step BETWEEN 5 AND 6   THEN 'Hours 5 to 6'
        ELSE                             'Hours 7 to 8'
    END                                                     AS time_period,
    COUNT(*)                                                AS total_transactions,
    SUM(isFraud)                                            AS fraud_cases,
    ROUND(SUM(isFraud) / COUNT(*) * 100, 2)                AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN isFraud = 1
                   THEN amount ELSE 0 END), 2)              AS fraud_value
FROM transactions
GROUP BY time_period
ORDER BY time_period;

-- WHAT THIS MEANS:
-- If fraud_rate_pct grows across periods, fraud is escalating.
-- If it is random, there is no timing pattern.
-- Either way — this is a finding to include in your report.


-- ────────────────────────────────────────────────────────────
-- QUERY 11: Multi-signal risk scoring model (the main event)
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Scoring every transaction from 0 to 8 based on 5 risk signals.
-- Then grouping results by risk tier (Critical / High / Medium / Low)
-- and checking how much actual fraud we catch in each tier.
--
-- THE 5 RISK SIGNALS:
-- Signal 1 (+2 pts): Type is TRANSFER or CASH_OUT
--                    (we know fraud only happens in these types)
-- Signal 2 (+2 pts): Amount is over 200,000
--                    (fraud skews toward high-value transactions)
-- Signal 3 (+2 pts): Sender balance drained to zero after transaction
--                    (fraudsters empty the account completely)
-- Signal 4 (+1 pt):  Destination balance unchanged despite receiving funds
--                    (money immediately moved — laundering signal)
-- Signal 5 (+1 pt):  Amount is more than 80% of sender's starting balance
--                    (sending almost everything you have is unusual)
--
-- HOW CTE WORKS HERE:
-- Step 1 (risk_scored): Calculate all 5 signals and total score per transaction
-- Step 2 (risk_classified): Assign a tier label based on the score
-- Step 3 (final SELECT): Summarise by tier and compare against actual fraud
-- ────────────────────────────────────────────────────────────

WITH risk_scored AS (
    SELECT
        nameOrig,
        nameDest,
        type,
        amount,
        oldbalanceOrg,
        newbalanceOrig,
        oldbalanceDest,
        newbalanceDest,
        isFraud,
        step,

        -- Signal 1: High risk transaction type
        CASE WHEN type IN ('TRANSFER', 'CASH_OUT')
             THEN 2 ELSE 0 END                              AS signal_type,

        -- Signal 2: High value transaction
        CASE WHEN amount > 200000
             THEN 2 ELSE 0 END                              AS signal_high_value,

        -- Signal 3: Sender account fully drained
        CASE WHEN newbalanceOrig = 0 AND oldbalanceOrg > 0
             THEN 2 ELSE 0 END                              AS signal_drained,

        -- Signal 4: Destination balance unchanged
        CASE WHEN oldbalanceDest = 0 AND newbalanceDest = 0 AND amount > 0
             THEN 1 ELSE 0 END                              AS signal_dest_unchanged,

        -- Signal 5: Sending most of available balance
        CASE WHEN oldbalanceOrg > 0 AND (amount / oldbalanceOrg) > 0.8
             THEN 1 ELSE 0 END                              AS signal_large_relative,

        -- Total risk score (sum of all signals, max = 8)
        (CASE WHEN type IN ('TRANSFER','CASH_OUT')           THEN 2 ELSE 0 END +
         CASE WHEN amount > 200000                           THEN 2 ELSE 0 END +
         CASE WHEN newbalanceOrig = 0 AND oldbalanceOrg > 0 THEN 2 ELSE 0 END +
         CASE WHEN oldbalanceDest = 0 AND newbalanceDest = 0 AND amount > 0
                                                            THEN 1 ELSE 0 END +
         CASE WHEN oldbalanceOrg > 0 AND (amount / oldbalanceOrg) > 0.8
                                                            THEN 1 ELSE 0 END)
                                                            AS risk_score
    FROM transactions
),

risk_classified AS (
    SELECT *,
        CASE
            WHEN risk_score >= 6 THEN 'Critical'
            WHEN risk_score >= 4 THEN 'High'
            WHEN risk_score >= 2 THEN 'Medium'
            ELSE                      'Low'
        END                                                 AS risk_tier
    FROM risk_scored
)

SELECT
    risk_tier,
    COUNT(*)                                                AS total_transactions,
    SUM(isFraud)                                            AS fraud_caught,
    ROUND(SUM(isFraud) / COUNT(*) * 100, 2)                AS fraud_rate_in_tier,
    ROUND(SUM(CASE WHEN isFraud = 1 THEN amount ELSE 0 END), 2)
                                                            AS fraud_value_caught,
    ROUND(AVG(amount), 2)                                   AS avg_transaction_size
FROM risk_classified
GROUP BY risk_tier
ORDER BY
    CASE risk_tier
        WHEN 'Critical' THEN 1
        WHEN 'High'     THEN 2
        WHEN 'Medium'   THEN 3
        ELSE                 4
    END;

-- WHAT THIS MEANS:
-- Critical tier should have a very high fraud_rate_in_tier
-- (maybe 20–50%) while containing only a small number of transactions.
-- That means: a risk analyst reviewing ONLY the Critical tier
-- transactions would catch most of the fraud while reviewing
-- far fewer transactions than reviewing everything.
-- This is the core value of a risk scoring model.


-- ────────────────────────────────────────────────────────────
-- QUERY 12: Final watchlist — top 50 cases to investigate
-- ────────────────────────────────────────────────────────────
--
-- WHAT WE ARE DOING:
-- Applying the same scoring logic one more time but this time
-- returning individual transactions (not summaries) so a fraud
-- analyst can see exactly WHICH transactions to look at first.
--
-- This is the operational output of the model —
-- a prioritised case list sorted by risk score then amount.
-- ────────────────────────────────────────────────────────────

WITH risk_scored AS (
    SELECT
        nameOrig                                            AS sender,
        nameDest                                            AS receiver,
        type,
        ROUND(amount, 2)                                    AS amount,
        ROUND(oldbalanceOrg, 2)                             AS balance_before_sending,
        ROUND(newbalanceOrig, 2)                            AS balance_after_sending,
        step                                                AS hour,
        isFraud                                             AS confirmed_fraud,
        (CASE WHEN type IN ('TRANSFER','CASH_OUT')           THEN 2 ELSE 0 END +
         CASE WHEN amount > 200000                           THEN 2 ELSE 0 END +
         CASE WHEN newbalanceOrig = 0 AND oldbalanceOrg > 0 THEN 2 ELSE 0 END +
         CASE WHEN oldbalanceDest = 0 AND newbalanceDest = 0 AND amount > 0
                                                            THEN 1 ELSE 0 END +
         CASE WHEN oldbalanceOrg > 0 AND (amount / oldbalanceOrg) > 0.8
                                                            THEN 1 ELSE 0 END)
                                                            AS risk_score
    FROM transactions
)
SELECT
    sender,
    receiver,
    type,
    amount,
    balance_before_sending,
    balance_after_sending,
    hour,
    risk_score,
    CASE
        WHEN risk_score >= 6 THEN 'CRITICAL — Review immediately'
        WHEN risk_score >= 4 THEN 'HIGH     — Review within 1 hour'
        ELSE                      'MEDIUM   — Review today'
    END                                                     AS recommended_action,
    confirmed_fraud
FROM risk_scored
WHERE risk_score >= 4
ORDER BY risk_score DESC, amount DESC
LIMIT 50;

-- WHAT THIS MEANS:
-- This is your fraud watchlist. The column "confirmed_fraud"
-- tells you which ones are actually fraud (1) vs ones the model
-- flagged but may not be fraud (0 — these are false positives).
-- A good model has mostly 1s at the top of this list.
-- Count how many confirmed_fraud = 1 appear in your top 50 —
-- that number divided by 84 (total fraud) = your model recall rate.
-- Example: if 60 out of 84 fraud cases appear in the top 50,
-- your model recall = 60/84 = 71% — much better than the system's 0%.


-- ============================================================
-- END OF ANALYSIS
-- ============================================================
-- Summary of what we found:
-- 1. Fraud rate is 0.28% — low by count, high by value
-- 2. 100% of fraud is in TRANSFER and CASH_OUT only
-- 3. The existing system caught 0 out of 84 fraud cases
-- 4. Key fraud signals: account drained, high value, dest unchanged
-- 5. Risk scoring model concentrates fraud in Critical/High tiers
--    allowing analysts to review far fewer transactions
--    while catching the majority of fraud value
-- ============================================================
