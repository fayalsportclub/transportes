-- Gestor financeiro: regista pagamentos e indica sócios (encarregado sócio beneficia todos os filhos).
-- Não vê moradas, pedidos, viagens nem definições.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('admin','gestor','financeiro','enc'));
alter table public.profiles add column if not exists socio boolean not null default false;
alter table public.profiles add column if not exists n_socio text not null default '';
alter table public.atletas add column if not exists n_socio text not null default '';

create or replace function public.pode_financas() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('admin','financeiro') and estado = 'ativo');
$$;
grant execute on function public.pode_financas() to authenticated, service_role;

-- famílias sem moradas, para o gestor financeiro
create or replace function public.fin_familias()
returns table (id uuid, nome text, tel text, role text, estado text, socio boolean, n_socio text)
language sql stable security definer set search_path = public as $$
  select p.id, p.nome, p.tel, p.role, p.estado, p.socio, p.n_socio from public.profiles p
  where public.pode_financas() and (p.role = 'enc' or p.id = auth.uid());
$$;
grant execute on function public.fin_familias() to authenticated;

create or replace function public.fin_socio_enc(pid uuid, s boolean, n text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.pode_financas() then raise exception 'Sem permissão'; end if;
  update public.profiles set socio = s, n_socio = coalesce(n, '') where id = pid and role = 'enc';
end $$;
grant execute on function public.fin_socio_enc(uuid, boolean, text) to authenticated;

-- atletas: o financeiro lê e só pode mudar sócio / n.º de sócio
drop policy if exists atletas_ler on public.atletas;
create policy atletas_ler on public.atletas for select to authenticated
  using (enc_id = auth.uid() or public.pode_gerir() or public.pode_financas());
drop policy if exists atletas_fin on public.atletas;
create policy atletas_fin on public.atletas for update to authenticated using (public.pode_financas()) with check (public.pode_financas());

create or replace function public.limita_fin_atletas() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_admin() then return new; end if;
  new.id := old.id; new.enc_id := old.enc_id; new.nome := old.nome; new.escalao := old.escalao;
  new.transporte := old.transporte; new.inicio := old.inicio; new.autorizado := old.autorizado;
  new.isento := old.isento; new.decisao := old.decisao;
  return new;
end $$;
drop trigger if exists limita_fin_atletas on public.atletas;
create trigger limita_fin_atletas before update on public.atletas for each row execute function public.limita_fin_atletas();

-- pagamentos
drop policy if exists pag_ler on public.pagamentos;
create policy pag_ler on public.pagamentos for select to authenticated
  using (public.pode_gerir() or public.pode_financas() or atleta_id in (select id from public.atletas where enc_id = auth.uid()));
drop policy if exists pag_admin on public.pagamentos;
create policy pag_admin on public.pagamentos for all to authenticated using (public.pode_financas()) with check (public.pode_financas());
