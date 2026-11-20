-- Distâncias passam a ser em minutos de viagem (a partir da Horta), em vez de km.
update public.config set dados = (dados - 'vel') || jsonb_build_object(
  'unidade','min','anel',78,'desvio',9,
  'zonas', '[
    {"nome":"Horta (Matriz)","min":0,"via":"E"},{"nome":"Horta (Conceição)","min":2,"via":"E"},{"nome":"Horta (Angústias)","min":2,"via":"O"},
    {"nome":"Flamengos","min":6,"via":"I"},{"nome":"Praia do Almoxarife","min":9,"via":"E"},{"nome":"Pedro Miguel","min":14,"via":"E"},
    {"nome":"Ribeirinha","min":20,"via":"E"},{"nome":"Salão","min":26,"via":"E"},{"nome":"Cedros","min":32,"via":"E"},
    {"nome":"Praia do Norte","min":35,"via":"O"},{"nome":"Capelo","min":27,"via":"O"},{"nome":"Castelo Branco","min":15,"via":"O"},{"nome":"Feteira","min":8,"via":"O"}
  ]'::jsonb)
where id = 1 and coalesce(dados->>'unidade','') <> 'min';
