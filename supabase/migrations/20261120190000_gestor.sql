-- Novo perfil: gestor de transportes (gere pedidos e viagens; sem acesso a mensalidades, utilizadores ou definições).
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('admin','gestor','enc'));

create or replace function public.pode_gerir() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('admin','gestor') and estado = 'ativo');
$$;
grant execute on function public.pode_gerir() to authenticated, service_role;

-- leitura dos dados necessários para gerir transportes
drop policy if exists perfis_ler on public.profiles;
create policy perfis_ler on public.profiles for select to authenticated using (id = auth.uid() or public.pode_gerir());
drop policy if exists atletas_ler on public.atletas;
create policy atletas_ler on public.atletas for select to authenticated using (enc_id = auth.uid() or public.pode_gerir());
drop policy if exists pag_ler on public.pagamentos;
create policy pag_ler on public.pagamentos for select to authenticated
  using (public.pode_gerir() or atleta_id in (select id from public.atletas where enc_id = auth.uid()));

-- viagens e pedidos: gestão completa
drop policy if exists viagens_admin on public.viagens;
create policy viagens_admin on public.viagens for all to authenticated using (public.pode_gerir()) with check (public.pode_gerir());
drop policy if exists pedidos_ler on public.pedidos;
create policy pedidos_ler on public.pedidos for select to authenticated
  using (public.pode_gerir() or atleta_id in (select id from public.atletas where enc_id = auth.uid()));
drop policy if exists pedidos_criar on public.pedidos;
create policy pedidos_criar on public.pedidos for insert to authenticated
  with check (public.pode_gerir() or atleta_id in (select id from public.atletas where enc_id = auth.uid()));
drop policy if exists pedidos_alterar on public.pedidos;
create policy pedidos_alterar on public.pedidos for update to authenticated
  using (public.pode_gerir() or atleta_id in (select id from public.atletas where enc_id = auth.uid()))
  with check (public.pode_gerir() or atleta_id in (select id from public.atletas where enc_id = auth.uid()));
drop policy if exists pedidos_apagar on public.pedidos;
create policy pedidos_apagar on public.pedidos for delete to authenticated using (public.pode_gerir());

-- o gestor regista pedidos telefónicos sem as limitações dos encarregados (como o administrador)
create or replace function public.valida_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cfg jsonb;
  agora timestamp := now() at time zone 'Atlantic/Azores';
  hojed date := (now() at time zone 'Atlantic/Azores')::date;
  a public.atletas%rowtype;
begin
  if public.pode_gerir() then return new; end if;
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
