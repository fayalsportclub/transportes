// Função de administração: criar contas, mudar palavra-passe, suspender/reativar, mudar utilizador.
// Só responde a quem tem sessão iniciada como administrador ativo.
import { createClient } from "npm:@supabase/supabase-js@2";

const DOM = "transportes.fayalsportclub.pt";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const adm = createClient(url, key, { auth: { persistSession: false } });

    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: u } = await adm.auth.getUser(jwt);
    if (!u?.user) return resp({ erro: "Sessão inválida" }, 401);
    const { data: eu } = await adm.from("profiles").select("role,estado").eq("id", u.user.id).single();
    if (!eu || eu.role !== "admin" || eu.estado !== "ativo") return resp({ erro: "Sem permissão" }, 403);

    const b = await req.json();
    const user = String(b.username || "").trim().toLowerCase();
    const okUser = (s: string) => /^[a-z0-9._-]{3,40}$/.test(s);

    if (b.acao === "criar") {
      if (!okUser(user)) return resp({ erro: "Utilizador inválido (só letras, números, ponto e hífen)" }, 400);
      if (!b.password || String(b.password).length < 6) return resp({ erro: "Palavra-passe com menos de 6 caracteres" }, 400);
      const { data: ex } = await adm.from("profiles").select("id").eq("username", user).maybeSingle();
      if (ex) return resp({ erro: "Esse utilizador já existe" }, 400);
      const { data: c, error } = await adm.auth.admin.createUser({ email: `${user}@${DOM}`, password: b.password, email_confirm: true });
      if (error) return resp({ erro: error.message }, 400);
      const { error: e2 } = await adm.from("profiles").insert({
        id: c.user.id, nome: b.nome, username: user, tel: b.tel || "", freg: b.freg || null, morada: b.morada || "",
        role: ["gestor", "financeiro"].includes(b.role) ? b.role : "enc", estado: "ativo",
      });
      if (e2) { await adm.auth.admin.deleteUser(c.user.id); return resp({ erro: e2.message }, 400); }
      return resp({ id: c.user.id });
    }

    if (b.acao === "password") {
      if (!b.password || String(b.password).length < 6) return resp({ erro: "Palavra-passe com menos de 6 caracteres" }, 400);
      const { error } = await adm.auth.admin.updateUserById(b.id, { password: b.password });
      return error ? resp({ erro: error.message }, 400) : resp({ ok: true });
    }

    if (b.acao === "estado") {
      if (b.id === u.user.id) return resp({ erro: "Não pode suspender a própria conta" }, 400);
      const sus = b.estado === "suspenso";
      const { error } = await adm.auth.admin.updateUserById(b.id, { ban_duration: sus ? "876000h" : "none" });
      if (error) return resp({ erro: error.message }, 400);
      await adm.from("profiles").update({ estado: sus ? "suspenso" : "ativo" }).eq("id", b.id);
      return resp({ ok: true });
    }

    if (b.acao === "username") {
      if (!okUser(user)) return resp({ erro: "Utilizador inválido" }, 400);
      const { data: ex } = await adm.from("profiles").select("id").eq("username", user).maybeSingle();
      if (ex && ex.id !== b.id) return resp({ erro: "Esse utilizador já existe" }, 400);
      const { error } = await adm.auth.admin.updateUserById(b.id, { email: `${user}@${DOM}`, email_confirm: true });
      if (error) return resp({ erro: error.message }, 400);
      await adm.from("profiles").update({ username: user }).eq("id", b.id);
      return resp({ ok: true });
    }

    return resp({ erro: "Ação desconhecida" }, 400);
  } catch (e) {
    return resp({ erro: String((e as Error).message || e) }, 500);
  }
});
