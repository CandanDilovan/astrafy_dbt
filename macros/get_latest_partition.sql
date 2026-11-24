{#
    Returns the latest monthly partition (as a DATE) of a partitioned BigQuery table.
    relation: a dbt relation, e.g. source('crypto_bitcoin_cash', 'transactions') or ref('my_model').
    Reads INFORMATION_SCHEMA.PARTITIONS (metadata only, ~free) instead of scanning the table,
    so the result can be used as a literal date filter that enables partition pruning.
    Assumes monthly partitions (partition_id like '20240501').
#}
{% macro get_latest_partition(relation) %}
	{% set query %}
		select max(safe.parse_date('%Y%m%d', partition_id))
		from `{{ relation.database }}.{{ relation.schema }}.INFORMATION_SCHEMA.PARTITIONS`
		where table_name = '{{relation.identifier}}'
	{% endset %}

	{% if execute %}
		{{ return(run_query(query).columns[0].values()[0]) }}
	{% endif %}
{% endmacro %}