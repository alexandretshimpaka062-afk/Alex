// Pont sécurisé entre l'interface et le disque (fichier de données dans Documents)
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("desktop", {
  load: () => ipcRenderer.sendSync("data:load"),
  save: text => ipcRenderer.send("data:save", text),
  dataDir: () => ipcRenderer.sendSync("data:path"),
  openDataDir: () => ipcRenderer.send("data:open"),
  platform: process.platform,
});
