-- Até 2 moradas adicionais por encarregado (pais separados, avós...).
-- A regra da zona vedada passa a olhar para as casas usadas no pedido (ou a principal, se não usa nenhuma).
alter table public.profiles add column if not exists moradas jsonb not null default '[]'::jsonb;

create or replace function public.zona_vedada_pedido(aid uuid, origem text, destino text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  a public.atletas%rowtype; p public.profiles%rowtype; z jsonb; fregs text[] := '{}'; x text; idx int;
begin
  select * into a from public.atletas where id = aid;
  if a.id is null or a.autorizado then return false; end if;
  select * into p from public.profiles where id = a.enc_id;
  foreach x in array array[origem, destino] loop
    if x = 'Casa' then fregs := fregs || p.freg;
    elsif x ~ '^Casa:[12]$' then
      idx := substring(x from 6)::int - 1;
      fregs := fregs || (p.moradas->idx->>'freg');
    end if;
  end loop;
  if cardinality(fregs) = 0 then fregs := array[p.freg]; end if;
  select dados->'zonas' into z from public.config where id = 1;
  return exists (select 1 from jsonb_array_elements(z) e
                 where e->>'nome' = any(fregs) and coalesce((e->>'restrita')::boolean, false));
end $$;
grant execute on function public.zona_vedada_pedido(uuid, text, text) to authenticated, service_role;

create or replace function public.valida_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cfg jsonb;
  agora timestamp := now() at time zone 'Atlantic/Azores';
  hojed date := (now() at time zone 'Atlantic/Azores')::date;
  a public.atletas%rowtype;
begin
  if public.is_admin() then return new; end if;
  if tg_op = 'INSERT' then
    select * into a from public.atletas where id = new.atleta_id;
    if a.id is null or a.enc_id <> auth.uid() or not a.transporte then raise exception 'Atleta inválido'; end if;
    if (select estado from public.profiles where id = auth.uid()) <> 'ativo' then raise exception 'Conta suspensa'; end if;
    if public.zona_vedada_pedido(a.id, new.origem, new.destino) then raise exception 'Zona sem transporte: requer autorização da Comissão de Gestão'; end if;
    select dados into cfg from public.config where id = 1;
    if new.data < hojed then raise exception 'Não é possível pedir para dias passados'; end if;
    if new.data = hojed and to_char(agora, 'HH24:MI') > coalesce(cfg->>'prazo', '12:00') then
      raise exception 'O prazo para hoje terminou às %', coalesce(cfg->>'prazo', '12:00');
    end if;
    if public.em_atraso(a.id) then raise exception 'Mensalidade em atraso'; end if;
    new.estado := 'pendente'; new.viagem_id := null; new.por_admin := false;
    new.prev_sobe := null; new.prev_desce := null; new.motivo := '';
    return new;
  else
    if new.estado <> 'cancelado' or old.estado not in ('pendente', 'confirmado') then
      raise exception 'Só é possível cancelar o pedido';
    end if;
    new.atleta_id := old.atleta_id; new.data := old.data; new.hora := old.hora;
    new.origem := old.origem; new.destino := old.destino; new.obs := old.obs;
    new.viagem_id := old.viagem_id; new.motivo := old.motivo; new.por_admin := old.por_admin;
    new.prev_sobe := old.prev_sobe; new.prev_desce := old.prev_desce; new.criado_em := old.criado_em;
    return new;
  end if;
end $$;
