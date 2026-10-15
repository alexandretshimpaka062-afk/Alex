// Kivuthèque — application de bureau (Mac et Windows)
const { app, BrowserWindow, Menu, ipcMain, shell, dialog, net, nativeImage, systemPreferences } = require("electron");
const fs = require("fs");
const crypto = require("crypto");
const path = require("path");

const SMOKE = process.argv.includes("--smoke-test");
const OLD_DIR = path.join(app.getPath("documents"), "Bibliothèque KIS");
const DATA_DIR = process.env.KIV_DATA_DIR || path.join(app.getPath("documents"), "Kivuthèque");
const DATA_FILE = path.join(DATA_DIR, "donnees.json");
const BACKUP_DIR = path.join(DATA_DIR, "Sauvegardes automatiques");
const KEEP_BACKUPS = 30;

let win = null;

function ensureDirs() {
  // reprise des données d'une ancienne version (« Bibliothèque KIS »)
  try { if (!process.env.KIV_DATA_DIR && !fs.existsSync(DATA_DIR) && fs.existsSync(OLD_DIR)) fs.renameSync(OLD_DIR, DATA_DIR); } catch {}
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
}

function readData() {
  try { return JSON.parse(fs.readFileSync(DATA_FILE, "utf8")); } catch { return null; }
}

// écriture atomique : fichier temporaire puis renommage, et une sauvegarde par jour
function writeData(text) {
  ensureDirs();
  const tmp = DATA_FILE + ".tmp";
  fs.writeFileSync(tmp, text, "utf8");
  fs.renameSync(tmp, DATA_FILE);
  const day = new Date().toISOString().slice(0, 10);
  const daily = path.join(BACKUP_DIR, `donnees-${day}.json`);
  fs.copyFileSync(DATA_FILE, daily);
  const old = fs.readdirSync(BACKUP_DIR).filter(f => /^donnees-\d{4}-\d{2}-\d{2}\.json$/.test(f)).sort();
  old.slice(0, Math.max(0, old.length - KEEP_BACKUPS)).forEach(f => fs.rmSync(path.join(BACKUP_DIR, f), { force: true }));
}

/* ---------------------------------------------------------------- comptes locaux
   Fichier comptes.json (séparé des données) : mots de passe jamais stockés en clair,
   seulement une empreinte scrypt salée. La session ouverte est gardée ici, côté logiciel,
   et chaque enregistrement est vérifié selon le rôle de la personne connectée. */
const ACCOUNTS_FILE = path.join(DATA_DIR, "comptes.json");
const ROLES = ["admin", "bibliothecaire", "fournitures", "consultation"];
const WRITERS = { livres: ["admin", "bibliothecaire"], membres: ["admin", "bibliothecaire"], emprunts: ["admin", "bibliothecaire"],
  fournitures: ["admin", "fournitures"], mouvements: ["admin", "fournitures"], params: ["admin"] };
let session = null;            // { id, nom, login, role }
let lastSaved = null;          // dernière version enregistrée, pour comparer
const failures = new Map();    // tentatives de connexion ratées

function readAccounts() { try { return JSON.parse(fs.readFileSync(ACCOUNTS_FILE, "utf8")); } catch { return { users: [], recovery: null }; } }
function writeAccounts(a) { ensureDirs(); const tmp = ACCOUNTS_FILE + ".tmp"; fs.writeFileSync(tmp, JSON.stringify(a, null, 1), { encoding: "utf8", mode: 0o600 }); fs.renameSync(tmp, ACCOUNTS_FILE); }
function hashPw(pw, salt = crypto.randomBytes(16).toString("hex")) { return { salt, hash: crypto.scryptSync(String(pw), salt, 64, { N: 16384, r: 8, p: 1 }).toString("hex") }; }
function checkPw(pw, rec) { if (!rec) return false; const h = crypto.scryptSync(String(pw), rec.salt, 64, { N: 16384, r: 8, p: 1 }); return crypto.timingSafeEqual(h, Buffer.from(rec.hash, "hex")); }
const pub = u => ({ id: u.id, nom: u.nom, login: u.login, role: u.role, active: u.active !== false, created: u.created });
const norm = s => String(s || "").trim().toLowerCase();
function needAdmin() { if (!session || session.role !== "admin") throw new Error("Seul un administrateur peut gérer les comptes."); }
function validPw(pw) { if (String(pw || "").length < 6) throw new Error("Le mot de passe doit contenir au moins 6 caractères."); }
function recoveryCode() { const a = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; return Array.from({ length: 3 }, () => Array.from({ length: 4 }, () => a[crypto.randomInt(a.length)]).join("")).join("-"); }
const wrap = fn => async (_e, arg) => { try { return { ok: true, ...(await fn(arg || {})) }; } catch (err) { return { ok: false, error: err.message }; } };

ipcMain.handle("auth:status", wrap(async () => { const a = readAccounts(); return { hasUsers: a.users.length > 0, current: session }; }));
ipcMain.handle("auth:setup", wrap(async ({ nom, login, password }) => {
  const a = readAccounts(); if (a.users.length) throw new Error("Un administrateur existe déjà.");
  if (!String(nom || "").trim() || !norm(login)) throw new Error("Indiquez un nom et un identifiant."); validPw(password);
  const code = recoveryCode();
  const u = { id: crypto.randomUUID(), nom: String(nom).trim(), login: norm(login), role: "admin", active: true, created: new Date().toISOString(), pw: hashPw(password) };
  a.users.push(u); a.recovery = hashPw(code.replace(/-/g, "")); writeAccounts(a);
  session = pub(u); return { user: session, recoveryCode: code };
}));
ipcMain.handle("auth:login", wrap(async ({ login, password }) => {
  const key = norm(login), f = failures.get(key) || { n: 0, until: 0 };
  if (Date.now() < f.until) throw new Error(`Trop de tentatives. Réessayez dans ${Math.ceil((f.until - Date.now()) / 1000)} secondes.`);
  const u = readAccounts().users.find(x => x.login === key);
  if (!u || !checkPw(password, u.pw)) { f.n++; if (f.n >= 5) { f.until = Date.now() + 30000; f.n = 0; } failures.set(key, f); throw new Error("Identifiant ou mot de passe incorrect."); }
  if (u.active === false) throw new Error("Ce compte est désactivé. Adressez-vous à l'administrateur.");
  failures.delete(key); session = pub(u); lastSaved = null; return { user: session };
}));
ipcMain.handle("auth:logout", wrap(async () => { session = null; lastSaved = null; return {}; }));
ipcMain.handle("auth:list", wrap(async () => { needAdmin(); return { users: readAccounts().users.map(pub) }; }));
ipcMain.handle("auth:create", wrap(async ({ nom, login, password, role }) => {
  needAdmin(); const a = readAccounts(); const l = norm(login);
  if (!String(nom || "").trim() || !l) throw new Error("Indiquez un nom et un identifiant.");
  if (!/^[a-z0-9._-]{2,30}$/.test(l)) throw new Error("Identifiant : lettres sans accent, chiffres, point ou tiret (2 à 30 caractères).");
  if (a.users.some(x => x.login === l)) throw new Error("Cet identifiant est déjà utilisé."); if (!ROLES.includes(role)) throw new Error("Rôle inconnu."); validPw(password);
  const u = { id: crypto.randomUUID(), nom: String(nom).trim(), login: l, role, active: true, created: new Date().toISOString(), pw: hashPw(password) };
  a.users.push(u); writeAccounts(a); return { user: pub(u) };
}));
ipcMain.handle("auth:update", wrap(async ({ id, role, active }) => {
  needAdmin(); const a = readAccounts(); const u = a.users.find(x => x.id === id); if (!u) throw new Error("Compte introuvable.");
  const next = { role: role ?? u.role, active: active ?? (u.active !== false) };
  if (!ROLES.includes(next.role)) throw new Error("Rôle inconnu.");
  const admins = a.users.filter(x => x.role === "admin" && x.active !== false && x.id !== id).length;
  if ((next.role !== "admin" || !next.active) && u.role === "admin" && !admins) throw new Error("Il faut garder au moins un administrateur actif.");
  Object.assign(u, next); writeAccounts(a); if (session && session.id === id) session = pub(u); return { user: pub(u) };
}));
ipcMain.handle("auth:reset", wrap(async ({ id, password }) => { needAdmin(); validPw(password); const a = readAccounts(); const u = a.users.find(x => x.id === id); if (!u) throw new Error("Compte introuvable."); u.pw = hashPw(password); writeAccounts(a); return {}; }));
ipcMain.handle("auth:change", wrap(async ({ old, password }) => {
  if (!session) throw new Error("Session expirée."); validPw(password); const a = readAccounts(); const u = a.users.find(x => x.id === session.id);
  if (!checkPw(old, u.pw)) throw new Error("Mot de passe actuel incorrect."); u.pw = hashPw(password); writeAccounts(a); return {};
}));
ipcMain.handle("auth:recover", wrap(async ({ code, login, password }) => {
  const a = readAccounts(); const c = String(code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (!a.recovery || !checkPw(c, a.recovery)) throw new Error("Code de secours incorrect.");
  const u = a.users.find(x => x.login === norm(login) && x.role === "admin"); if (!u) throw new Error("Aucun administrateur avec cet identifiant.");
  validPw(password); u.pw = hashPw(password); u.active = true; const nc = recoveryCode(); a.recovery = hashPw(nc.replace(/-/g, "")); writeAccounts(a);
  session = pub(u); return { user: session, recoveryCode: nc };
}));

ipcMain.on("data:load", e => { e.returnValue = session ? (lastSaved = readData()) : null; });
ipcMain.handle("data:save", wrap(async text => {
  if (!session) throw new Error("Session expirée : reconnectez-vous.");
  const next = JSON.parse(text), prev = lastSaved || readData() || {};
  for (const [k, roles] of Object.entries(WRITERS))
    if (JSON.stringify(next[k] ?? null) !== JSON.stringify(prev[k] ?? null) && !roles.includes(session.role))
      throw new Error("Votre rôle ne permet pas de modifier cette partie. La modification n'a pas été enregistrée.");
  try { writeData(text); } catch (err) { throw new Error("Enregistrement impossible dans " + DATA_FILE + " : " + err.message); }
  lastSaved = next; return {};
}));

/* ---------------------------------------------------------------- Internet : fiches et couvertures de livres */
const NET_HOSTS = /^https:\/\/(www\.googleapis\.com|openlibrary\.org|covers\.openlibrary\.org|books\.google\.com|books\.googleusercontent\.com)\//;
ipcMain.handle("net:json", wrap(async url => {
  if (!NET_HOSTS.test(url)) throw new Error("Adresse non autorisée.");
  const r = await net.fetch(url, { headers: { "User-Agent": "Kivutheque/1.2 (bibliotheque scolaire)" } });
  if (!r.ok) throw new Error("Service indisponible (" + r.status + ").");
  return { data: await r.json() };
}));
ipcMain.handle("net:image", wrap(async url => {
  url = String(url).replace(/^http:/, "https:");
  if (!NET_HOSTS.test(url)) throw new Error("Adresse non autorisée.");
  const r = await net.fetch(url); if (!r.ok) return { data: null };
  let img = nativeImage.createFromBuffer(Buffer.from(await r.arrayBuffer()));
  if (img.isEmpty() || img.getSize().width < 20) return { data: null };
  if (img.getSize().width > 180) img = img.resize({ width: 180, quality: "best" });
  return { data: "data:image/jpeg;base64," + img.toJPEG(78).toString("base64") };
}));
ipcMain.handle("camera:ask", wrap(async () => ({ granted: process.platform === "darwin" ? await systemPreferences.askForMediaAccess("camera") : true })));
ipcMain.on("data:path", e => { e.returnValue = DATA_DIR; });
ipcMain.on("data:open", () => { ensureDirs(); shell.openPath(DATA_DIR); });

function createWindow() {
  win = new BrowserWindow({
    width: 1440, height: 920, minWidth: 380, minHeight: 600,
    title: "Kivuthèque", backgroundColor: "#EDF2F7", show: false,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: true },
  });
  const ses = win.webContents.session;
  ses.setPermissionRequestHandler((_wc, perm, cb, details) => cb(perm === "media" && (details.mediaTypes || []).every(t => t === "video")));
  ses.setPermissionCheckHandler((_wc, perm) => perm === "media");
  win.loadFile(path.join(__dirname, "index.html"));
  if (SMOKE) return smokeTest();
  win.once("ready-to-show", () => win.show());
  // les liens externes s'ouvrent dans le navigateur
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^(https?|mailto):/.test(url)) shell.openExternal(url); return { action: "deny" }; });
  win.webContents.on("will-navigate", (e, url) => { if (!url.startsWith("file:")) { e.preventDefault(); if (/^https?:/.test(url)) shell.openExternal(url); } });
  // les fichiers exportés : boîte de dialogue « Enregistrer sous »
  win.webContents.session.on("will-download", (e, item) => {
    const p = dialog.showSaveDialogSync(win, { defaultPath: path.join(app.getPath("documents"), item.getFilename()) });
    if (p) item.setSavePath(p); else item.cancel();
  });
}

// Vérification automatique (utilisée avant chaque publication) : l'application doit
// démarrer, afficher l'accueil, charger des exemples, les enregistrer sur disque et générer un PDF.
function smokeTest() {
  const errors = [];
  const done = code => { console.log(code ? "SMOKE-TEST ÉCHEC\n" + errors.join("\n") : "SMOKE-TEST OK"); app.exit(code); };
  setTimeout(() => { errors.push("délai dépassé"); done(1); }, 60000);
  win.webContents.on("console-message", (_e, level, msg) => { if (level >= 3) errors.push("console : " + msg); });
  win.webContents.on("render-process-gone", (_e, d) => { errors.push("rendu arrêté : " + d.reason); done(1); });
  win.webContents.once("did-finish-load", async () => {
    try {
      const wait = ms => new Promise(r => setTimeout(r, ms));
      await wait(1500);
      const r = await win.webContents.executeJavaScript(`(async () => {
        const out = {};
        out.title = document.title;
        out.desktop = !!window.desktop;
        out.pdf = !!(window.jspdf && window.jspdf.jsPDF && window.jspdf.jsPDF.API.autoTable);
        out.zxing = !!(window.ZXing && window.ZXing.BrowserMultiFormatReader);
        const W = ms => new Promise(r => setTimeout(r, ms)), fill = (s, v) => { const el = document.querySelector(s); el.value = v; el.dispatchEvent(new Event("input", { bubbles: true })); };
        out.setupScreen = !!document.querySelector("#as-login");
        fill("#as-nom", "Direction"); fill("#as-login", "direction"); fill("#as-pass", "secret123"); fill("#as-pass2", "secret123");
        document.querySelector("#asSubmit").click(); await W(1500);
        out.recovery = (document.querySelector("#asCode") || {}).textContent || "";
        document.querySelector("#asContinue").click(); await W(1500);
        const bad = await window.desktop.auth.login({ login: "direction", password: "faux" }); out.badLoginRefused = !bad.ok;
        document.querySelector("#wSample").click();
        await new Promise(r => setTimeout(r, 2500));
        out.livres = S.livres.length;
        out.view = document.querySelector("#viewTitle").textContent;
        const { jsPDF } = window.jspdf; const d = new jsPDF(); d.autoTable({ head: [["Essai"]], body: [["Kivuthèque"]] });
        out.pdfBytes = d.output("arraybuffer").byteLength;
        return out;
      })()`);
      console.log("SMOKE", JSON.stringify(r));
      await wait(500);
      const saved = JSON.parse(fs.readFileSync(DATA_FILE, "utf8"));
      if (r.title !== "Kivuthèque") errors.push("titre inattendu : " + r.title);
      if (!r.desktop) errors.push("pont disque absent");
      if (!r.pdf || !(r.pdfBytes > 1000)) errors.push("module PDF absent");
      if (!r.zxing) errors.push("module de scan absent");
      if (!r.setupScreen || !/^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(r.recovery)) errors.push("création du compte administrateur en échec");
      if (!r.badLoginRefused) errors.push("mauvais mot de passe accepté");
      if (!fs.existsSync(ACCOUNTS_FILE) || /secret123/.test(fs.readFileSync(ACCOUNTS_FILE, "utf8"))) errors.push("fichier des comptes absent ou mot de passe en clair");
      if (!(r.livres > 0) || saved.livres.length !== r.livres) errors.push("données non enregistrées");
      if (!fs.readdirSync(BACKUP_DIR).length) errors.push("sauvegarde automatique absente");
      done(errors.length ? 1 : 0);
    } catch (e) { errors.push(String(e && e.stack || e)); done(1); }
  });
}

function buildMenu() {
  const isMac = process.platform === "darwin";
  const template = [
    ...(isMac ? [{ label: "Kivuthèque", submenu: [
      { role: "about", label: "À propos de Kivuthèque" }, { type: "separator" },
      { role: "hide", label: "Masquer Kivuthèque" }, { role: "hideOthers", label: "Masquer les autres" }, { role: "unhide", label: "Tout afficher" },
      { type: "separator" }, { role: "quit", label: "Quitter Kivuthèque" }] }] : []),
    { label: "Fichier", submenu: [
      { label: "Ouvrir le dossier des données", click: () => { ensureDirs(); shell.openPath(DATA_DIR); } },
      { type: "separator" },
      { label: "Imprimer…", accelerator: "CmdOrCtrl+P", click: () => win && win.webContents.print({}) },
      { type: "separator" }, isMac ? { role: "close", label: "Fermer la fenêtre" } : { role: "quit", label: "Quitter" }] },
    { label: "Édition", submenu: [
      { role: "undo", label: "Annuler" }, { role: "redo", label: "Rétablir" }, { type: "separator" },
      { role: "cut", label: "Couper" }, { role: "copy", label: "Copier" }, { role: "paste", label: "Coller" }, { role: "selectAll", label: "Tout sélectionner" }] },
    { label: "Affichage", submenu: [
      { role: "reload", label: "Actualiser" }, { type: "separator" },
      { role: "resetZoom", label: "Taille réelle" }, { role: "zoomIn", label: "Agrandir" }, { role: "zoomOut", label: "Réduire" },
      { type: "separator" }, { role: "togglefullscreen", label: "Plein écran" }] },
    { label: "Fenêtre", submenu: [{ role: "minimize", label: "Réduire dans le Dock" }, { role: "zoom", label: "Zoom" }] },
    { label: "Aide", submenu: [{ label: "À propos", click: () => dialog.showMessageBox(win, {
      type: "info", title: "Kivuthèque", message: "Kivuthèque " + app.getVersion(),
      detail: "Logiciel de gestion de la bibliothèque de Kivu International School.\n\nDonnées enregistrées dans :\n" + DATA_DIR + "\n\nMade by Alexandre et Declaire" }) }] },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on("second-instance", () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });
  app.whenReady().then(() => { ensureDirs(); buildMenu(); createWindow(); });
  app.on("activate", () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
  app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });
}
