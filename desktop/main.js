// Kivuthèque — application de bureau (Mac et Windows)
const { app, BrowserWindow, Menu, ipcMain, shell, dialog } = require("electron");
const fs = require("fs");
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

ipcMain.on("data:load", e => { e.returnValue = readData(); });
ipcMain.on("data:save", (e, text) => {
  try { writeData(text); } catch (err) { dialog.showErrorBox("Enregistrement impossible", "Les données n'ont pas pu être enregistrées dans :\n" + DATA_FILE + "\n\n" + err.message); }
});
ipcMain.on("data:path", e => { e.returnValue = DATA_DIR; });
ipcMain.on("data:open", () => { ensureDirs(); shell.openPath(DATA_DIR); });

function createWindow() {
  win = new BrowserWindow({
    width: 1440, height: 920, minWidth: 380, minHeight: 600,
    title: "Kivuthèque", backgroundColor: "#EDF2F7", show: false,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: true },
  });
  win.loadFile(path.join(__dirname, "index.html"));
  if (SMOKE) return smokeTest();
  win.once("ready-to-show", () => win.show());
  // les liens externes s'ouvrent dans le navigateur
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^https?:/.test(url)) shell.openExternal(url); return { action: "deny" }; });
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
