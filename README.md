# Fraud Detection SQL Case Study

![SQL](https://img.shields.io/badge/Tool-MySQL%208.0-4479A1?style=flat&logo=mysql&logoColor=white)
![Dataset](https://img.shields.io/badge/Dataset-PaySim%20Financial%20Transactions-0C447C?style=flat)
![Domain](https://img.shields.io/badge/Domain-Risk%20%26%20Fraud%20Analytics-E24B4A?style=flat)
![Queries](https://img.shields.io/badge/SQL%20Queries-12-7F77DD?style=flat)
![Status](https://img.shields.io/badge/Status-Completed-639922?style=flat)

---

## Overview

Financial fraud is low in volume but high in value — and the hardest part is that it hides inside millions of legitimate transactions. In this dataset of 30,000 transactions, only 84 are fraudulent (0.28%). The existing rule-based system flagged **zero** of them.

This project uses SQL to investigate those 84 cases — finding what makes them different, which signals predict fraud, and building a risk scoring model that the existing system completely missed.

> **Real-world context:** This mirrors the fraud pattern investigation I conduct as a Risk Analyst at Noon — identifying suspicious transaction behaviour, flagging high-risk accounts, and building rule-based detection logic to reduce financial loss.

---

## The Problem

| Issue | Detail |
|-------|--------|
| Fraud volume | 84 confirmed fraud cases out of 29,999 transactions |
| System performance | `isFlaggedFraud = 0` for all 84 fraud cases — 100% miss rate |
| Business impact | Fraud concentrated in high-value transactions — small count, large financial exposure |
| Detection gap | No visibility into which account types, patterns, or thresholds carry highest risk |

---

## Dataset

| Attribute | Detail |
|-----------|--------|
| Name | PaySim — Synthetic Financial Dataset for Fraud Detection |
| Source | [Kaggle — ealaxi/paysim1](https://www.kaggle.com/datasets/ealaxi/paysim1) |
| Subset used | First 30,000 rows (trimmed from 6M row full dataset) |
| Tool | MySQL Workbench 8.0 |
| License | Public / Open |

### Columns

| Column | Type | Description |
|--------|------|-------------|
| `step` | INT | Hour of simulation (1 step = 1 hour) |
| `type` | VARCHAR | CASH_IN, CASH_OUT, DEBIT, PAYMENT, TRANSFER |
| `amount` | DECIMAL | Transaction amount |
| `nameOrig` | VARCHAR | Sender account ID |
| `oldbalanceOrg` | DECIMAL | Sender balance before transaction |
| `newbalanceOrig` | DECIMAL | Sender balance after transaction |
| `nameDest` | VARCHAR | Receiver account ID |
| `oldbalanceDest` | DECIMAL | Receiver balance before transaction |
| `newbalanceDest` | DECIMAL | Receiver balance after transaction |
| `isFraud` | TINYINT | **1 = confirmed fraud, 0 = legitimate** |
| `isFlaggedFraud` | TINYINT | 1 = flagged by existing rule system (caught 0 cases) |

---

## Analysis Structure

The project is organised into 4 modules, each answering a different fraud question:

### Module 1 — Fraud Overview (Queries 1–3)
- **Query 1:** Overall fraud rate, total fraud value, avg fraud vs legit transaction size
- **Query 2:** Fraud breakdown by transaction type — which types are safe vs risky
- **Query 3:** System effectiveness — confusion matrix showing all 84 cases were missed

### Module 2 — Customer Risk Profiling (Queries 4–6)
- **Query 4:** Top sender accounts by fraud value — the account watchlist
- **Query 5:** Balance drainage analysis — do fraudsters empty accounts completely?
- **Query 6:** Destination account profiling — identifying potential mule accounts

### Module 3 — Behavioural Signals (Queries 7–9)
- **Query 7:** Fraud rate by transaction hour — peak fraud windows
- **Query 8:** Fraud rate by amount band — at what size does fraud risk spike?
- **Query 9:** Destination balance anomaly — money sent but receiver balance unchanged

### Module 4 — Risk Scoring Model (Queries 10–12)
- **Query 10:** Fraud trend over time — is fraud growing or stable?
- **Query 11:** Multi-signal CTE scoring model — assigns Critical/High/Medium/Low tier to every transaction
- **Query 12:** Fraud watchlist — top 50 transactions ranked by risk score for investigator review

---

## Key Findings

### Finding 1 — Fraud is 100% concentrated in 2 transaction types

| Type | Transactions | Fraud Cases | Fraud Rate |
|------|-------------|-------------|------------|
| CASH_OUT | 6,528 | 43 | 0.66% |
| TRANSFER | 2,874 | 41 | 1.43% |
| PAYMENT | 14,537 | 0 | 0.00% |
| DEBIT | 530 | 0 | 0.00% |
| CASH_IN | 5,530 | 0 | 0.00% |

**Implication:** Monitoring can be focused exclusively on TRANSFER and CASH_OUT — reducing surveillance workload by ~68% while maintaining 100% fraud coverage.

---

### Finding 2 — The existing system caught zero fraud cases

```
True Positive  (caught correctly):        0
False Negative (fraud missed):           84
False Positive (wrongly flagged):         0
True Negative  (correctly ignored):  29,915
```

The `isFlaggedFraud` column is 0 for every single fraudulent transaction. This is the core justification for building a SQL-based detection model.

---

### Finding 3 — Account drainage is the strongest fraud signal

Fraudulent TRANSFER and CASH_OUT transactions drain the sender account to zero far more frequently than legitimate ones:

```sql
newbalanceOrig = 0
```

After a high-value transfer, this is a near-perfect fraud indicator.

---

### Finding 4 — Fraud skews to high-value transactions

Transactions above **200,000** show significantly higher fraud rates than lower amount bands. Fraudsters target large one-time transfers — not small repeated payments.

---

### Finding 5 — Destination balance anomaly reveals undetected laundering

Transactions where:

```sql
oldbalanceDest = 0 AND newbalanceDest = 0 AND amount > 0
```

suggest funds were immediately re-moved to another account — a laundering pattern not captured in the fraud labels.

---

## Risk Scoring Model

The CTE-based model in Query 11 scores every transaction using 5 signals:

| Signal | Points | Logic |
|--------|--------|-------|
| High-risk transaction type | +2 | `type IN ('TRANSFER', 'CASH_OUT')` |
| High-value transaction | +2 | `amount > 200,000` |
| Account fully drained | +2 | `newbalanceOrig = 0 AND oldbalanceOrg > 0` |
| Destination balance unchanged | +1 | `oldbalanceDest = 0 AND newbalanceDest = 0 AND amount > 0` |
| Large relative amount | +1 | `amount / oldbalanceOrg > 0.80` |

**Maximum score: 8 points**

### Risk Tiers

| Tier | Score | Action |
|------|-------|--------|
| Critical | 6–8 | Review immediately |
| High | 4–5 | Review within 1 hour |
| Medium | 2–3 | Review today |
| Low | 0–1 | Monitor only |

---

## SQL Concepts Used

| Concept | Usage |
|---------|-------|
| `GROUP BY` + aggregate functions | COUNT, SUM, AVG grouped by type, account, hour |
| `CASE WHEN` inside aggregates | Conditional sums — e.g. total fraud value only |
| `CASE WHEN` for banding | Grouping continuous values into ranges (amount bands, time periods) |
| `WHERE` + `IN` | Filtering to TRANSFER and CASH_OUT only |
| `HAVING` | Post-aggregation filtering for repeat offenders |
| CTE (`WITH ... AS`) | Multi-step risk scoring pipeline across two chained CTEs |
| `ORDER BY` + `LIMIT` | Producing ranked watchlists |

---

## Limitations

| Limitation | Impact |
|-----------|--------|
| 30K row subset of 6M row dataset | Fraud count is lower than full dataset — patterns still valid |
| No timestamp column | Cannot calculate transaction velocity |
| Synthetic data | Based on real patterns but not real transactions |
| Binary fraud label | Destination balance anomaly finds unlabelled suspicious activity |

---

## Learnings

- Writing CTEs to build multi-step SQL pipelines
- Using `CASE WHEN` inside aggregate functions for conditional metrics
- Detecting fraud signals beyond labelled data — the destination balance anomaly was discovered through exploration
- Structuring a SQL analysis as an investigation narrative: baseline → profiling → signals → scoring model → watchlist
- Understanding the difference between fraud rate (%) and fraud volume (count)

---

## Roadmap

| # | Project | Tools | Status |
|---|---------|-------|--------|
| 1 | E-Commerce Refund Abuse Tracker | Excel | ✅ Complete |
| 2 | Support Team KPI Dashboard | Excel | ✅ Complete |
| 3 | Fraud Detection SQL Case Study | MySQL | ✅ Complete |
| 4 | EdTech Cohort & Retention Analysis | Power BI + DAX | ✅ Complete |
| 5 | ATO Pattern Detection | Python + pandas | ✅ Complete |

---

## Author

**Pratham Singh** 

- Email: pratham.singh2800@gmail.com
- LinkedIn: [linkedin.com/in/prathamsingh9996](https://www.linkedin.com/in/prathamsingh9996/)
- Dataset: [Kaggle — PaySim Financial Dataset](https://www.kaggle.com/datasets/ealaxi/paysim1)
