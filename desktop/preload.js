// Pont sécurisé entre l'interface et le logiciel (données, comptes, Internet, caméra)
const { contextBridge, ipcRenderer } = require("electron");
const inv = (ch, a) => ipcRenderer.invoke(ch, a);
contextBridge.exposeInMainWorld("desktop", {
  load: () => ipcRenderer.sendSync("data:load"),
  save: text => inv("data:save", text),
  dataDir: () => ipcRenderer.sendSync("data:path"),
  openDataDir: () => ipcRenderer.send("data:open"),
  platform: process.platform,
  auth: {
    status: () => inv("auth:status"), setup: a => inv("auth:setup", a), login: a => inv("auth:login", a), logout: () => inv("auth:logout"),
    list: () => inv("auth:list"), create: a => inv("auth:create", a), update: a => inv("auth:update", a), reset: a => inv("auth:reset", a),
    change: a => inv("auth:change", a), recover: a => inv("auth:recover", a),
  },
  net: { json: url => inv("net:json", url), image: url => inv("net:image", url) },
  askCamera: () => inv("camera:ask"),
});
