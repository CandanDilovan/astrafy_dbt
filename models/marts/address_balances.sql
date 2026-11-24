{#
    Current balance of every address, over the last 3 months of available data
    (window imposed by the staging table, so it is a net flow over that period
    and can be negative: money received before the window is not seen).

    balance = total received (outputs) - total spent (inputs)

    Excludes addresses that received at least one coinbase transaction
    (block reward paid to miners). Coinbase transactions have no inputs,
    so the flag only needs the outputs side.
#}

with received as (
    -- outputs: money received by each address
    select
        address,
        sum(o.value) as total_received,
        logical_or(t.is_coinbase) as has_coinbase
    from {{ ref('stg_transactions') }} as t,
        unnest(t.outputs) as o,
        unnest(o.addresses) as address
    group by address
),

spent as (
    -- inputs: money spent by each address
    select
        address,
        sum(i.value) as total_spent
    from {{ ref('stg_transactions') }} as t,
        unnest(t.inputs) as i,
        unnest(i.addresses) as address
    group by address
),

balances as (
    -- full outer join: an address can appear on one side only
    -- (only received, or only spent money received before the window)
    select
        address,
        coalesce(r.total_received, 0) - coalesce(s.total_spent, 0) as balance_satoshis,
        coalesce(r.has_coinbase, false) as has_coinbase
    from received as r
    full outer join spent as s using (address)
)

select
    address,
    balance_satoshis,
    {{ satoshis_to_bch('balance_satoshis') }} as balance_bch
from balances
where not has_coinbase
    -- "nonstandard..." are not wallets but special outputs (e.g. OP_RETURN data)
    and not starts_with(address, 'nonstandard')
