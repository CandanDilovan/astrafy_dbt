# Bitcoin Cash analytics: dbt project

dbt-core project of the Astrafy Data Engineer take-home challenge (Part 2).
The infrastructure (project, datasets, service account) comes from the
[Terraform repository](https://github.com/CandanDilovan/astrafy_terraform).

## What it does

```
bigquery-public-data.crypto_bitcoin_cash.transactions
        ▼
staging.stg_transactions     last 3 months of data
        ▼
marts.address_balances       balance per address, miners excluded
```

- **`stg_transactions`**: transactions of the last 3 months, with only the
  columns needed for the balances, cast to fixed types (dbt contract).
- **`address_balances`**: `balance = received (outputs) - spent (inputs)` per
  address, without the addresses that received a coinbase transaction
  (block reward paid to miners).

## Choices worth knowing

- **The data stops in May 2024**, so "last 3 months" means the last 3 months
  of available data, not from today.
- **Low cost**: the latest partition is read from the table metadata by the
  macro `get_latest_partition` and written as a fixed date in the query, so
  BigQuery only reads the last partitions: ~4 GB instead of ~180 GB.
- **Reduced staging**: the free BigQuery sandbox caps storage at 10 GB, too
  small for a full copy of the 3 months (~17 GB).
- **Balances over 3 months only**: money received before the window is not
  seen, so some balances are negative.
- **"Coinbase"** is read as the coinbase transaction (`is_coinbase`): the
  dataset has no information about the Coinbase exchange.

## CI

`.github/workflows/dbt_run.yml` runs `dbt run` on every pull request (and by
hand from the Actions tab): checkout, authentication with the Terraform service
account (`GCP_SA_KEY` secret), install with uv, `dbt run --target ci`.

## Run locally

```bash
gcloud auth application-default login
uv sync
uv run dbt run
```
