// Signature « ad hoc » de l'application Mac (sans certificat payant), indispensable
// pour que macOS accepte de l'ouvrir sur les Mac à puce Apple.
const { execFileSync } = require("child_process");
const path = require("path");

exports.default = async function (context) {
  if (context.electronPlatformName !== "darwin" || process.platform !== "darwin") return;
  if (context.appOutDir.endsWith("-temp")) return; // parties x64/arm64 avant fusion universelle
  const app = path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`);
  console.log("  • signature ad hoc", app);
  execFileSync("codesign", ["--force", "--deep", "--sign", "-", app], { stdio: "inherit" });
  execFileSync("codesign", ["--verify", "--deep", "--strict", "--verbose=2", app], { stdio: "inherit" });
};
