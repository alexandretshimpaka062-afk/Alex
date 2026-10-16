// Kivuthèque — assistant bibliothécaire IA (Supabase Edge Function)
// L'élève pose une question ; ChatGPT (API OpenAI) répond avec des livres du catalogue de l'école uniquement.
// Secrets à créer dans Supabase › Edge Functions › Secrets :
//   OPENAI_API_KEY  (obligatoire) : la clé API OpenAI (sk-…)
//   OPENAI_MODEL    (facultatif)  : le modèle, gpt-5-mini par défaut
// SUPABASE_URL et la clé publique du projet sont fournis automatiquement par Supabase.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const KEY = Deno.env.get("OPENAI_API_KEY") || "";
// modèle choisi, puis modèles de secours si celui-ci n'existe pas (ou plus) sur le compte
const MODELS = [...new Set([Deno.env.get("OPENAI_MODEL") || "gpt-5-mini", "gpt-5-mini", "gpt-4o-mini"])];

const SCHEMA = {
  type: "object",
  properties: {
    reponse: { type: "string", description: "Réponse courte et chaleureuse à l'élève, en français, sans liste de livres." },
    livres: {
      type: "array",
      description: "De 0 à 4 livres du catalogue, du plus conseillé au moins conseillé.",
      items: {
        type: "object",
        properties: {
          id: { type: "string", description: "Le code exact du livre dans le catalogue." },
          pourquoi: { type: "string", description: "Une phrase : pourquoi ce livre lui plaira." },
        },
        required: ["id", "pourquoi"],
        additionalProperties: false,
      },
    },
  },
  required: ["reponse", "livres"],
  additionalProperties: false,
};

const SYSTEM_INTRO = `Tu es l'assistant de la bibliothèque de Kivu International School (Goma), dans l'application Kivuthèque.
Tu aides les élèves (de la 1re primaire aux humanités, environ 6 à 18 ans) et leurs enseignants à choisir un livre.

Règles :
- Tu ne proposes QUE des livres du catalogue ci-dessous, avec leur code exact. N'invente jamais de livre, d'auteur ou de résumé.
- Propose 1 à 4 livres, adaptés à l'âge et à la classe du lecteur. Préfère les livres disponibles maintenant ; si un livre conseillé est emprunté, dis qu'on peut le réserver.
- Évite les livres que le lecteur a déjà lus, sauf s'il le demande.
- Réponds en français simple, en tutoyant l'élève, en 2 à 4 phrases. Les livres s'affichent sous ta réponse : ne les liste pas dans le texte.
- Si la question n'a rien à voir avec la lecture, les livres ou la bibliothèque, réponds gentiment que tu ne parles que de livres, sans proposer de livre.
- Si aucun livre du catalogue ne convient, dis-le honnêtement et propose de demander à la bibliothécaire.
- Ne demande jamais d'informations personnelles.`;

const short = (s: unknown, n: number) => { const t = String(s ?? "").replace(/\s+/g, " ").trim(); return t.length > n ? t.slice(0, n - 1) + "…" : t; };
const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ erreur: "Méthode non prise en charge." }, 405);
  if (!KEY) return json({ erreur: "L'assistant n'est pas encore configuré : la clé API OpenAI manque (INSTALLATION.md, étape 8)." }, 503);

  const auth = req.headers.get("Authorization") || "";
  // clé publique du projet : ancienne clé « anon », nouvelle clé « publishable », ou celle envoyée par l'application
  let pub = Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!pub) { try { const k = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}"); pub = k.default || Object.values(k)[0] as string || ""; } catch { /* rien */ } }
  pub = pub || req.headers.get("apikey") || "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, pub, { global: { headers: { Authorization: auth } } });

  let body: { question?: string; historique?: { role: string; texte: string }[] };
  try { body = await req.json(); } catch { return json({ erreur: "Demande illisible." }, 400); }
  const question = short(body.question, 500);
  if (question.length < 2) return json({ erreur: "Écris ta question." }, 400);

  // limite de questions par jour (et vérifie que la personne est connectée et validée)
  const quota = await sb.rpc("kiv_assistant_quota");
  if (quota.error) return json({ erreur: quota.error.message }, 429);

  const [cat, prof] = await Promise.all([sb.rpc("kiv_catalogue_public"), sb.rpc("kiv_assistant_profil")]);
  if (cat.error) return json({ erreur: "Le catalogue n'a pas pu être lu." }, 500);
  type Livre = { id: string; titre: string; auteur: string; categorie: string; annee: string; resume: string; ex: number; dispo: number };
  let livres = (cat.data || []) as Livre[];
  const profil = (prof.data || {}) as { prenom?: string; classe?: string; genres?: string[]; lus?: string[] };

  // grand catalogue : on garde les livres les plus proches de la question
  if (livres.length > 500) {
    const mots = norm(question).split(/[^a-z0-9]+/).filter((m) => m.length > 3);
    const genres = new Set(profil.genres || []);
    livres = livres.map((b) => {
      const t = norm(`${b.titre} ${b.auteur} ${b.categorie} ${b.resume}`);
      return { b, s: mots.filter((m) => t.includes(m)).length * 5 + (genres.has(b.categorie) ? 2 : 0) + (b.dispo > 0 ? 1 : 0) };
    }).sort((x, y) => y.s - x.s).slice(0, 500).map((x) => x.b).sort((x, y) => x.titre.localeCompare(y.titre, "fr"));
  }
  const ids = new Set(livres.map((b) => b.id));
  // partie stable (mise en cache) : les règles et le catalogue, sans la disponibilité qui change souvent
  const catalogue = livres.map((b) => [b.id, short(b.titre, 90), short(b.auteur, 50), b.categorie || "", b.annee || "", short(b.resume, 160)].join(" | ")).join("\n");
  const titreDe = new Map(livres.map((b) => [b.id, b.titre]));
  const dispo = livres.filter((b) => b.dispo > 0).map((b) => b.id);

  const contexte = `Lecteur : ${profil.prenom || "un élève"}${profil.classe ? `, classe ${profil.classe}` : ""}.
Genres préférés : ${(profil.genres || []).join(", ") || "non précisés"}.
Déjà lus : ${(profil.lus || []).map((id) => titreDe.get(id) || id).slice(0, 40).join(" ; ") || "aucun"}.
Disponibles en ce moment (codes) : ${dispo.join(", ") || "aucun"}.

Question : ${question}`;

  const historique = (Array.isArray(body.historique) ? body.historique : []).slice(-6)
    .filter((m) => m && (m.role === "user" || m.role === "assistant") && m.texte)
    .map((m) => ({ role: m.role as "user" | "assistant", content: short(m.texte, 800) }));
  while (historique.length && historique[0].role !== "user") historique.shift();

  const system = `${SYSTEM_INTRO}\n\nCatalogue (code | titre | auteur | genre | année | résumé) :\n${catalogue}`;
  let lastStatus = 0, lastMsg = "";
  for (const model of MODELS) {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Authorization": `Bearer ${KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        messages: [{ role: "system", content: system }, ...historique, { role: "user", content: contexte }],
        response_format: { type: "json_schema", json_schema: { name: "conseils_lecture", strict: true, schema: SCHEMA } },
        max_completion_tokens: 4000,
        ...(/^(gpt-5|o\d)/.test(model) ? { reasoning_effort: "low" } : {}),
      }),
    }).catch(() => null);
    if (!res) { lastStatus = 0; continue; }
    const j = await res.json().catch(() => ({}));
    if (!res.ok) {
      lastStatus = res.status; lastMsg = (j.error && j.error.message) || "";
      // modèle inconnu ou paramètre refusé par ce modèle : on essaie le suivant
      if ((res.status === 404 || res.status === 400) && /model|reasoning_effort|max_completion_tokens|response_format/i.test(lastMsg)) continue;
      break;
    }
    const choice = (j.choices || [])[0] || {}, text = (choice.message && choice.message.content) || "";
    if (choice.message && choice.message.refusal) return json({ reponse: "Je ne peux pas t'aider pour cette question. Demande à la bibliothécaire !", livres: [], restant: quota.data });
    let out: { reponse: string; livres: { id: string; pourquoi: string }[] };
    try { out = JSON.parse(text); } catch { return json({ erreur: "L'assistant n'a pas su répondre. Réessaie avec une autre question." }, 502); }
    return json({
      reponse: short(out.reponse, 1200),
      livres: (out.livres || []).filter((l) => ids.has(l.id)).slice(0, 4).map((l) => ({ id: l.id, pourquoi: short(l.pourquoi, 240) })),
      restant: quota.data,
    });
  }
  console.error("OpenAI", lastStatus, lastMsg);
  if (lastStatus === 401) return json({ erreur: "La clé API OpenAI n'est pas valide (Supabase › Edge Functions › Secrets)." }, 503);
  if (lastStatus === 429) return json({ erreur: /quota|billing|credit/i.test(lastMsg) ? "Le compte OpenAI n'a plus de crédit : l'administrateur doit en ajouter sur platform.openai.com." : "L'assistant est très demandé. Réessaie dans une minute." }, 503);
  return json({ erreur: `L'assistant est indisponible${lastStatus ? " (" + lastStatus + ")" : ""}. Réessaie plus tard.` }, 502);
});
