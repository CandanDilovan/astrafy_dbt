{#
    Exploration: one row per address with the list of is_coinbase flags
    of every transaction where it receives money (outputs).
    Outputs are enough: coinbase transactions have NO inputs in this dataset
    (the block reward is created from nothing), so miner addresses only
    appear on the outputs side.
#}

with flattened as (
    select address, t.is_coinbase
    from {{ ref('stg_transactions') }} as t,
        unnest(t.outputs) as o,
        unnest(o.addresses) as address
)

select
    address,
    array_agg(is_coinbase) as is_coinbase_flags,
    logical_or(is_coinbase) as has_coinbase
from flattened
group by address
