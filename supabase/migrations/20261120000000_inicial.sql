-- Transportes FSC — estrutura inicial
-- Todas as tabelas têm RLS: cada encarregado só vê os seus atletas, pedidos e pagamentos.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  username text not null unique,
  tel text default '',
  freg text,
  morada text default '',
  role text not null default 'enc' check (role in ('admin','enc')),
  estado text not null default 'ativo' check (estado in ('ativo','suspenso')),
  criado_em timestamptz not null default now()
);

create table if not exists public.atletas (
  id uuid primary key default gen_random_uuid(),
  enc_id uuid not null references public.profiles(id) on delete cascade,
  nome text not null,
  escalao text not null default '',
  socio boolean not null default false,
  transporte boolean not null default true,
  inicio text not null default to_char(now(),'YYYY-MM')
);
create index if not exists atletas_enc_idx on public.atletas(enc_id);

create table if not exists public.viagens (
  id uuid primary key default gen_random_uuid(),
  data date not null,
  hora text not null,
  nota text default ''
);
create index if not exists viagens_data_idx on public.viagens(data);

create table if not exists public.pedidos (
  id uuid primary key default gen_random_uuid(),
  atleta_id uuid not null references public.atletas(id) on delete cascade,
  data date not null,
  hora text not null,
  origem text not null,
  destino text not null,
  obs text default '',
  estado text not null default 'pendente' check (estado in ('pendente','confirmado','recusado','cancelado')),
  viagem_id uuid references public.viagens(id) on delete set null,
  motivo text default '',
  por_admin boolean not null default false,
  prev_sobe text,
  prev_desce text,
  criado_em timestamptz not null default now()
);
create index if not exists pedidos_data_idx on public.pedidos(data);
create index if not exists pedidos_atleta_idx on public.pedidos(atleta_id);

create table if not exists public.pagamentos (
  atleta_id uuid not null references public.atletas(id) on delete cascade,
  mes text not null,
  metodo text not null check (metodo in ('dinheiro','mbway')),
  data date not null default current_date,
  primary key (atleta_id, mes)
);

create table if not exists public.config (
  id int primary key default 1 check (id = 1),
  dados jsonb not null
);

insert into public.config (id, dados) values (1, '{
  "lugares": 8, "prazo": "12:00", "diaLimite": 10, "vSocio": 5, "vNaoSocio": 10,
  "anel": 52, "vel": 40, "paragem": 2, "maxEspera": 30, "maxCedo": 30, "desvio": 6, "base": "Horta (Matriz)",
  "zonas": [
    {"nome":"Horta (Matriz)","pos":0,"ramal":0},{"nome":"Horta (Conceição)","pos":1,"ramal":0},{"nome":"Horta (Angústias)","pos":51,"ramal":0},
    {"nome":"Flamengos","pos":0,"ramal":4},{"nome":"Praia do Almoxarife","pos":6,"ramal":0},{"nome":"Pedro Miguel","pos":9,"ramal":0},
    {"nome":"Ribeirinha","pos":13,"ramal":0},{"nome":"Salão","pos":17,"ramal":0},{"nome":"Cedros","pos":21,"ramal":0},
    {"nome":"Praia do Norte","pos":29,"ramal":0},{"nome":"Capelo","pos":34,"ramal":0},{"nome":"Castelo Branco","pos":42,"ramal":0},{"nome":"Feteira","pos":47,"ramal":0}
  ],
  "locais": [
    {"nome":"Estádio da Alagoa","freg":"Horta (Matriz)","base":true},
    {"nome":"Pavilhão Esc. Sec. Manuel de Arriaga","freg":"Horta (Matriz)","base":true},
    {"nome":"Escola Sec. Manuel de Arriaga","freg":"Horta (Matriz)","base":false},
    {"nome":"EBI da Horta","freg":"Horta (Matriz)","base":false}
  ]
}'::jsonb) on conflict (id) do nothing;

-- ---------- Funções auxiliares ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and estado = 'ativo');
$$;

-- Mensalidade em atraso (mesma regra da aplicação): meses dos últimos 3 sem pagamento,
-- o mês corrente só conta depois do dia-limite.
create or replace function public.em_atraso(aid uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  hojed date := (now() at time zone 'Atlantic/Azores')::date;
  m text := to_char(hojed, 'YYYY-MM');
  ini text; lim int; mm text; i int;
begin
  select inicio into ini from public.atletas where id = aid;
  select coalesce((dados->>'diaLimite')::int, 10) into lim from public.config where id = 1;
  for i in reverse 2..0 loop
    mm := to_char(hojed - make_interval(months => i), 'YYYY-MM');
    if mm < ini or exists (select 1 from public.pagamentos where atleta_id = aid and mes = mm) then continue; end if;
    if mm < m then return true; end if;
    if extract(day from hojed) > lim then return true; end if;
  end loop;
  return false;
end $$;

-- Regras para pedidos feitos pelos encarregados (o administrador não tem estas limitações)
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

drop trigger if exists valida_pedido on public.pedidos;
create trigger valida_pedido before insert or update on public.pedidos
  for each row execute function public.valida_pedido();

-- Usado pela tarefa automática que impede o projeto de ser pausado
create or replace function public.ping() returns int language sql security definer set search_path = public as $$
  select count(*)::int from public.config;
$$;
grant execute on function public.ping() to anon, authenticated;

-- ---------- Segurança (RLS) ----------
alter table public.profiles enable row level security;
alter table public.atletas enable row level security;
alter table public.viagens enable row level security;
alter table public.pedidos enable row level security;
alter table public.pagamentos enable row level security;
alter table public.config enable row level security;

grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on public.profiles, public.atletas, public.viagens, public.pedidos, public.pagamentos, public.config to authenticated;
grant all on public.profiles, public.atletas, public.viagens, public.pedidos, public.pagamentos, public.config to service_role;
grant execute on function public.is_admin(), public.em_atraso(uuid) to authenticated, service_role;
revoke all on public.profiles, public.atletas, public.viagens, public.pedidos, public.pagamentos, public.config from anon;

drop policy if exists perfis_ler on public.profiles;
create policy perfis_ler on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists perfis_admin on public.profiles;
create policy perfis_admin on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists atletas_ler on public.atletas;
create policy atletas_ler on public.atletas for select to authenticated using (enc_id = auth.uid() or public.is_admin());
drop policy if exists atletas_admin on public.atletas;
create policy atletas_admin on public.atletas for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists viagens_admin on public.viagens;
create policy viagens_admin on public.viagens for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists pedidos_ler on public.pedidos;
create policy pedidos_ler on public.pedidos for select to authenticated
  using (public.is_admin() or atleta_id in (select id from public.atletas where enc_id = auth.uid()));
drop policy if exists pedidos_criar on public.pedidos;
create policy pedidos_criar on public.pedidos for insert to authenticated
  with check (public.is_admin() or atleta_id in (select id from public.atletas where enc_id = auth.uid()));
drop policy if exists pedidos_alterar on public.pedidos;
create policy pedidos_alterar on public.pedidos for update to authenticated
  using (public.is_admin() or atleta_id in (select id from public.atletas where enc_id = auth.uid()))
  with check (public.is_admin() or atleta_id in (select id from public.atletas where enc_id = auth.uid()));
drop policy if exists pedidos_apagar on public.pedidos;
create policy pedidos_apagar on public.pedidos for delete to authenticated using (public.is_admin());

drop policy if exists pag_ler on public.pagamentos;
create policy pag_ler on public.pagamentos for select to authenticated
  using (public.is_admin() or atleta_id in (select id from public.atletas where enc_id = auth.uid()));
drop policy if exists pag_admin on public.pagamentos;
create policy pag_admin on public.pagamentos for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists config_ler on public.config;
create policy config_ler on public.config for select to authenticated using (true);
drop policy if exists config_admin on public.config;
create policy config_admin on public.config for update to authenticated using (public.is_admin()) with check (public.is_admin());
