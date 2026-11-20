-- Perímetro vedado (cidade da Horta, Flamengos, Feteira, Praia do Almoxarife) e isenções por caso social.
-- Ambas as exceções exigem decisão da Comissão de Gestão e só o administrador as pode marcar.
alter table public.atletas add column if not exists autorizado boolean not null default false;
alter table public.atletas add column if not exists isento boolean not null default false;
alter table public.atletas add column if not exists decisao text not null default '';

update public.config set dados = jsonb_set(dados, '{zonas}', (
    select jsonb_agg(z || jsonb_build_object('restrita',
             (z->>'nome') in ('Horta (Matriz)','Horta (Conceição)','Horta (Angústias)','Flamengos','Feteira','Praia do Almoxarife')) order by ord)
    from jsonb_array_elements(dados->'zonas') with ordinality as t(z, ord)))
where id = 1;

-- atleta de zona vedada sem autorização?
create or replace function public.zona_vedada(aid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select not a.autorizado and exists (
      select 1 from public.config c, jsonb_array_elements(c.dados->'zonas') z
      where c.id = 1 and z->>'nome' = p.freg and coalesce((z->>'restrita')::boolean, false))
    from public.atletas a join public.profiles p on p.id = a.enc_id where a.id = aid), false);
$$;
grant execute on function public.zona_vedada(uuid) to authenticated, service_role;

-- isentos nunca ficam em atraso
create or replace function public.em_atraso(aid uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  hojed date := (now() at time zone 'Atlantic/Azores')::date;
  m text := to_char(hojed, 'YYYY-MM');
  ini text; isen boolean; lim int; mm text; i int;
begin
  select inicio, isento into ini, isen from public.atletas where id = aid;
  if isen then return false; end if;
  select coalesce((dados->>'diaLimite')::int, 10) into lim from public.config where id = 1;
  for i in reverse 2..0 loop
    mm := to_char(hojed - make_interval(months => i), 'YYYY-MM');
    if mm < ini or exists (select 1 from public.pagamentos where atleta_id = aid and mes = mm) then continue; end if;
    if mm < m then return true; end if;
    if extract(day from hojed) > lim then return true; end if;
  end loop;
  return false;
end $$;

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
    if public.zona_vedada(a.id) then raise exception 'Zona sem transporte: requer autorização da Comissão de Gestão'; end if;
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
