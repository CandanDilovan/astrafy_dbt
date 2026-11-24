{#
    Converts an amount in satoshis to BCH (1 BCH = 100,000,000 satoshis).
    column: the column or expression holding the satoshi amount.
#}
{% macro satoshis_to_bch(column) %}
    (({{ column }}) / 100000000)
{% endmacro %}
