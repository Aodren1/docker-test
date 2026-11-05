#!/usr/bin/env bash
# Installe une boîte à outils de reverse engineering Android / Unity (IL2CPP).
# Usage : sudo ./tools/install-re-tools.sh [PREFIX]   (PREFIX par défaut : /opt/re-tools)
set -euo pipefail

PREFIX="${1:-/opt/re-tools}"
BIN="/usr/local/bin"
GH="https://github.com"

JADX_VER="1.5.3"
APKTOOL_VER="2.12.1"
IL2CPPDUMPER_VER="6.7.46"
CPP2IL_VER="2022.1.0-pre-release.20"
ASSETRIPPER_VER="1.3.4"
DEX2JAR_VER="2.4"
UBER_SIGNER_VER="1.3.0"
GHIDRA_VER="11.4.2"
GHIDRA_DATE="20250826"
RADARE2_VER="6.0.4"

mkdir -p "$PREFIX" "$BIN"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log() { printf '\n\033[1;32m[+] %s\033[0m\n' "$*"; }
dl()  { curl -fsSL --retry 4 --retry-delay 2 -o "$2" "$1"; }
wrap() { # wrap <nom> <commande...>
  local name="$1"; shift
  printf '#!/usr/bin/env bash\nexec %s "$@"\n' "$*" > "$BIN/$name"
  chmod +x "$BIN/$name"
}

log "Paquets système (JDK, .NET 8, adb, outils binaires)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  openjdk-21-jdk-headless dotnet-runtime-8.0 \
  unzip zip curl file binutils xxd p7zip-full \
  adb aapt zipalign apksigner \
  python3-pip python3-venv >/dev/null

log "jadx $JADX_VER (décompilateur DEX -> Java)"
dl "$GH/skylot/jadx/releases/download/v$JADX_VER/jadx-$JADX_VER.zip" "$TMP/jadx.zip"
rm -rf "$PREFIX/jadx" && unzip -q "$TMP/jadx.zip" -d "$PREFIX/jadx"
chmod +x "$PREFIX/jadx/bin/"*
ln -sf "$PREFIX/jadx/bin/jadx" "$BIN/jadx"
ln -sf "$PREFIX/jadx/bin/jadx-gui" "$BIN/jadx-gui"

log "Apktool $APKTOOL_VER (décodage / reconstruction d'APK)"
mkdir -p "$PREFIX/apktool"
dl "$GH/iBotPeaches/Apktool/releases/download/v$APKTOOL_VER/apktool_$APKTOOL_VER.jar" "$PREFIX/apktool/apktool.jar"
wrap apktool java -jar "$PREFIX/apktool/apktool.jar"

log "dex2jar $DEX2JAR_VER"
dl "$GH/pxb1988/dex2jar/releases/download/v$DEX2JAR_VER/dex-tools-v$DEX2JAR_VER.zip" "$TMP/d2j.zip"
rm -rf "$PREFIX/dex2jar" && unzip -q "$TMP/d2j.zip" -d "$TMP/d2j"
mv "$TMP"/d2j/dex-tools-* "$PREFIX/dex2jar"
chmod +x "$PREFIX/dex2jar/"*.sh
for s in "$PREFIX"/dex2jar/d2j-*.sh; do ln -sf "$s" "$BIN/$(basename "$s" .sh)"; done

log "uber-apk-signer $UBER_SIGNER_VER"
mkdir -p "$PREFIX/uber-apk-signer"
dl "$GH/patrickfav/uber-apk-signer/releases/download/v$UBER_SIGNER_VER/uber-apk-signer-$UBER_SIGNER_VER.jar" \
  "$PREFIX/uber-apk-signer/uber-apk-signer.jar"
wrap uber-apk-signer java -jar "$PREFIX/uber-apk-signer/uber-apk-signer.jar"

log "Il2CppDumper $IL2CPPDUMPER_VER (libil2cpp.so + global-metadata.dat -> dump.cs / scripts Ghidra/IDA)"
dl "$GH/Perfare/Il2CppDumper/releases/download/v$IL2CPPDUMPER_VER/Il2CppDumper-net6-v$IL2CPPDUMPER_VER.zip" "$TMP/il2cpp.zip"
rm -rf "$PREFIX/il2cppdumper" && unzip -q "$TMP/il2cpp.zip" -d "$PREFIX/il2cppdumper"
# Mode non interactif + pas d'attente de touche à la fin
if [ -f "$PREFIX/il2cppdumper/config.json" ]; then
  sed -i 's/"RequireAnyKey": *true/"RequireAnyKey": false/' "$PREFIX/il2cppdumper/config.json"
fi
wrap il2cppdumper env DOTNET_ROLL_FORWARD=Major dotnet "$PREFIX/il2cppdumper/Il2CppDumper.dll"

log "Cpp2IL $CPP2IL_VER (IL2CPP -> assemblies .NET / DummyDLL pour ILSpy/dnSpy)"
mkdir -p "$PREFIX/cpp2il"
dl "$GH/SamboyCoding/Cpp2IL/releases/download/$CPP2IL_VER/Cpp2IL-$CPP2IL_VER-Linux" "$PREFIX/cpp2il/Cpp2IL"
chmod +x "$PREFIX/cpp2il/Cpp2IL"
ln -sf "$PREFIX/cpp2il/Cpp2IL" "$BIN/cpp2il"

log "AssetRipper $ASSETRIPPER_VER (extraction des assets Unity : textures, modèles, audio, scènes)"
dl "$GH/AssetRipper/AssetRipper/releases/download/$ASSETRIPPER_VER/AssetRipper_linux_x64.zip" "$TMP/ar.zip"
rm -rf "$PREFIX/assetripper" && unzip -q "$TMP/ar.zip" -d "$PREFIX/assetripper"
AR_BIN="$(find "$PREFIX/assetripper" -maxdepth 2 -type f -name 'AssetRipper*' ! -name '*.so' ! -name '*.txt' ! -name '*.dll' | head -1)"
chmod +x "$AR_BIN"
ln -sf "$AR_BIN" "$BIN/assetripper"

log "Ghidra $GHIDRA_VER (désassembleur / décompilateur natif ARM64)"
dl "$GH/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VER}_build/ghidra_${GHIDRA_VER}_PUBLIC_${GHIDRA_DATE}.zip" "$TMP/ghidra.zip"
rm -rf "$PREFIX/ghidra" && unzip -q "$TMP/ghidra.zip" -d "$TMP/ghidra"
mv "$TMP"/ghidra/ghidra_* "$PREFIX/ghidra"
ln -sf "$PREFIX/ghidra/ghidraRun" "$BIN/ghidra"
ln -sf "$PREFIX/ghidra/support/analyzeHeadless" "$BIN/ghidra-headless"

log "radare2 $RADARE2_VER"
dl "$GH/radareorg/radare2/releases/download/$RADARE2_VER/radare2_${RADARE2_VER}_amd64.deb" "$TMP/r2.deb"
apt-get install -y -qq "$TMP/r2.deb" >/dev/null

log "Outils Python : Frida, objection, androguard, apkleaks, UnityPy"
python3 -m venv "$PREFIX/pyenv"
"$PREFIX/pyenv/bin/pip" install -q --upgrade pip
"$PREFIX/pyenv/bin/pip" install -q frida-tools objection androguard apkleaks UnityPy
for t in frida frida-ps frida-trace frida-ls-devices frida-kill frida-discover objection androguard apkleaks; do
  [ -x "$PREFIX/pyenv/bin/$t" ] && ln -sf "$PREFIX/pyenv/bin/$t" "$BIN/$t"
done
ln -sf "$PREFIX/pyenv/bin/python" "$BIN/re-python"

log "frida-server Android (arm64) à pousser sur l'appareil rooté"
FRIDA_VER="$("$PREFIX/pyenv/bin/python" -c 'import frida; print(frida.__version__)')"
mkdir -p "$PREFIX/frida-server"
dl "$GH/frida/frida/releases/download/$FRIDA_VER/frida-server-$FRIDA_VER-android-arm64.xz" "$TMP/fs.xz"
xz -dc "$TMP/fs.xz" > "$PREFIX/frida-server/frida-server-android-arm64"
chmod +x "$PREFIX/frida-server/frida-server-android-arm64"

log "Terminé. Outils installés dans $PREFIX, commandes dans $BIN"
for c in jadx apktool d2j-dex2jar uber-apk-signer il2cppdumper cpp2il assetripper ghidra-headless r2 frida objection androguard apkleaks; do
  printf '  %-18s %s\n' "$c" "$(command -v "$c" >/dev/null && echo OK || echo MANQUANT)"
done
