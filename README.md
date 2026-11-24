# Bitcoin Cash analytics: dbt project

dbt-core project for the Astrafy Data Engineer take-home challenge (Part 2).
It transforms the public BigQuery dataset `bigquery-public-data.crypto_bitcoin_cash`
into a staging table and a data mart of address balances. A GitHub Actions
workflow runs the models on every pull request.

The infrastructure (GCP project, datasets, service account) is created by the
[Terraform repository](https://github.com/CandanDilovan/astrafy_terraform).

## Lineage

```
bigquery-public-data.crypto_bitcoin_cash.transactions     (source, ~180 GB)
        │  last 3 months of available data, 6 useful columns
        ▼
staging.stg_transactions                                   (table, ~6.5 M rows)
        │  received - spent per address, miners excluded
        ▼
marts.address_balances                                     (table, ~4.2 M rows)
```

## Models

### `staging.stg_transactions`

Transactions of the **last three months of available data**, with only the
columns needed downstream, each explicitly cast (types enforced by a
[dbt contract](https://docs.getdbt.com/docs/collaborate/govern/model-contracts)).

| Column | Type | Content |
|---|---|---|
| `transaction_hash` | string | Transaction ID |
| `block_number` | int64 | Block containing the transaction |
| `block_timestamp` | timestamp | Block time |
| `is_coinbase` | bool | True for the block reward paid to the miner |
| `inputs` | array<struct<addresses, value>> | Money spent (addresses debited) |
| `outputs` | array<struct<addresses, value>> | Money received (addresses credited) |

### `marts.address_balances`

Current balance of every address, **excluding addresses that had at least one
coinbase transaction**.

```
balance = total received (outputs) - total spent (inputs)
```

| Column | Type | Content |
|---|---|---|
| `address` | string | Bitcoin Cash address |
| `balance_satoshis` | numeric | Balance in satoshis |
| `balance_bch` | numeric | Balance in BCH (1 BCH = 100,000,000 satoshis) |

The model reads in four readable steps: `received` (outputs, with the coinbase
flag), `spent` (inputs), `balances` (full outer join, as an address can appear
on one side only), then the final filter.

## Design choices and findings

### "Last three months" = last three months of *available* data

The public dataset **stops in May 2024**. Filtering on `current_date` would
return an empty table, so the window is computed from the latest data instead.

### Partition pruning: ~4 GB scanned instead of ~180 GB

The source table is partitioned by month on `block_timestamp_month`. BigQuery
only skips partitions when the filter is a **constant**; a subquery such as
`where month >= (select max(...))` scans the whole table (~180 GB).

So the latest partition is fetched **at compile time** by the macro
`get_latest_partition`, which reads the table metadata
(`INFORMATION_SCHEMA.PARTITIONS`, almost free), and is written as a literal date
in the SQL sent to BigQuery:

```sql
where block_timestamp_month >= date_sub(date '2024-05-01', interval 3 month)
```

A second filter then cuts exactly three months back from the latest
transaction. Selecting only `addresses` and `value` inside the nested arrays
brings the scan down further (~20 GB for all columns, ~4 GB here).

| Approach | Bytes scanned |
|---|---|
| Subquery filter on the partition column | ~180 GB |
| Literal date, all columns | ~20 GB |
| Literal date, needed columns only (this project) | **~4 GB** |

### Reduced staging instead of a 1:1 copy

The usual convention is a staging model 1:1 with its source. It was tried, but
the full three months take ~17 GB and the BigQuery sandbox (no billing account)
caps storage at **10 GB per project**. The staging keeps the columns needed to
compute balances; most of the dropped volume is the raw script bytecode
(`script_asm`, `script_hex`), which has no analytical value.

### "Coinbase" = the coinbase transaction

The dataset has no information about exchanges, so *"transaction on Coinbase"*
is read as a **coinbase transaction** (`is_coinbase = true`): the first
transaction of each block, which creates the block reward paid to the miner.
These transactions have no inputs, so miner addresses are detected on the
outputs side.

### Balances over a three-month window

Only three months are read, so the balance is the **net flow over that window**,
not the all-time balance. Money received before the window is not seen: an
address that spends it shows a **negative balance** (~1 M addresses). Likewise,
a miner rewarded before the window is not excluded. Both limits come from the
window imposed by the challenge.

### Other choices

- **Non-standard outputs removed.** Outputs such as `OP_RETURN` (data written in
  the chain) get a placeholder address `nonstandard...` in the dataset; they are
  not wallets and are filtered out.
- **Amounts kept in satoshis** (exact integers), with a BCH column for
  readability.
- **One dataset per layer.** `generate_schema_name` is overridden so models land
  in the `staging` and `marts` datasets created by Terraform, instead of dbt's
  default `staging_marts`.

## Macros

| Macro | Role |
|---|---|
| `get_latest_partition(relation)` | Latest monthly partition of any partitioned table, from metadata |
| `unnest_struct(column, fields)` | Rebuilds an array of structs keeping only the given fields, cast to their type |
| `satoshis_to_bch(column)` | Converts satoshis to BCH |
| `generate_schema_name` | Uses the custom schema as the dataset name, as is |

## Continuous integration

`.github/workflows/dbt_run.yml` runs on every pull request (opened, new commit
pushed, reopened) and can be started by hand (*Actions > dbt run > Run workflow*).

1. Checkout the code.
2. Authenticate as the `dbt-runner` service account (key stored in the
   `GCP_SA_KEY` secret, created by Terraform).
3. Install uv and Python 3.12.
4. Install dbt at the exact versions of `uv.lock` (`uv sync --locked`).
5. `dbt run --target ci`.

`profiles.yml` contains no secret: both targets use Application Default
Credentials, i.e. your Google account locally and the service account in CI.

## Run locally

Prerequisites: [uv](https://docs.astral.sh/uv/) and the
[gcloud CLI](https://cloud.google.com/sdk/docs/install), with the infrastructure
deployed by the Terraform repository.

```bash
gcloud auth application-default login   # your Google account
uv sync                                 # install dbt
uv run dbt debug                        # check the connection
uv run dbt run                          # build staging then mart
```

To use another project, change `project` in `profiles.yml`.

## Project layout

```
.
├── .github/workflows/dbt_run.yml   # CI: dbt run on pull requests
├── analyses/                       # Exploration queries (compiled, never materialized)
├── macros/                         # Reusable Jinja macros
├── models/
│   ├── staging/                    # sources.yml, models.yml, stg_transactions.sql
│   └── marts/                      # models.yml, address_balances.sql
├── dbt_project.yml                 # Project config (folder -> dataset, materialization)
├── profiles.yml                    # Connection targets dev / ci (no secret)
├── pyproject.toml / uv.lock        # Python dependencies (dbt-core, dbt-bigquery)
```

## Going further

- Tests (`not_null`, `unique` on `address`) and `dbt build` in CI.
- CI writing to a temporary dataset per pull request, then cleaned up.
- Workload Identity Federation instead of a service account key.
- An incremental staging model, if the source received new data.
