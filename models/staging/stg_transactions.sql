

{#- Only the columns needed downstream: the BigQuery sandbox caps storage
    at 10 GB per project and the full table (~20 GB) does not fit. -#}

{% set latest_month = get_latest_partition(source('crypto_bitcoin_cash', 'transactions')) %}
{% set io_fields = {'addresses': 'array<string>', 'value': 'numeric'} %}

with source as (
    select *
    from {{ source('crypto_bitcoin_cash', 'transactions') }}
    -- literal date => BigQuery only scans the last monthly partitions
    where block_timestamp_month >= date_sub(date '{{ latest_month }}', interval 3 month)
)

select
    cast(`hash` as string)             as transaction_hash,
    cast(block_number as int64)        as block_number,
    cast(block_timestamp as timestamp) as block_timestamp,
    cast(is_coinbase as bool)          as is_coinbase,
    {{ unnest_struct('inputs', io_fields) }}  as inputs,
    {{ unnest_struct('outputs', io_fields) }} as outputs
from source
-- exact 3-month window, counted back from the latest transaction available
where block_timestamp >= (
    select timestamp(date_sub(date(max(block_timestamp)), interval 3 month))
    from source
)
