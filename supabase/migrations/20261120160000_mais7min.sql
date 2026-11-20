-- +7 minutos em todas as freguesias fora da cidade da Horta; a volta completa aumenta 14 (7 por cada lado).
update public.config set dados = jsonb_set(jsonb_set(dados, '{zonas}', (
    select jsonb_agg(case when z->>'nome' like 'Horta%' then z
                          else jsonb_set(z, '{min}', to_jsonb((z->>'min')::int + 7)) end order by ord)
    from jsonb_array_elements(dados->'zonas') with ordinality as t(z, ord))),
  '{anel}', to_jsonb((dados->>'anel')::int + 14))
where id = 1;
