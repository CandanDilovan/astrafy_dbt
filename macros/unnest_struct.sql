{#
    Rebuilds an ARRAY<STRUCT> column keeping only the given fields, each cast to its type.
    fields: dict of {field_name: bigquery_type}, e.g. {'value': 'numeric'}
    Reading only the needed nested fields cuts the bytes scanned by BigQuery.
#}
{% macro unnest_struct(column, fields) %}
    array(
        select as struct
        {%- for name, type in fields.items() %}
            cast({{ name }} as {{ type }}) as {{ name }}{{ "," if not loop.last }}
        {%- endfor %}
        from unnest({{ column }})
    )
{% endmacro %}
