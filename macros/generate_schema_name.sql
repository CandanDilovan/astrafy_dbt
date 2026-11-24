{#
    Overrides dbt's default schema naming.
    By default dbt concatenates the target dataset and the custom schema
    (staging + marts => "staging_marts"). Here the custom schema is used as is,
    so models land in the "staging" and "marts" datasets created by Terraform.
    Models without a custom schema fall back to the target dataset.
#}
{% macro generate_schema_name(custom_schema_name, node) %}
    {{ custom_schema_name | trim if custom_schema_name else target.schema }}
{% endmacro %}
