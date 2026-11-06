# shellcheck shell=sh disable=SC2034
# Clave de firma del repositorio de Lázaro, para kernel/compilar.sh,
# repo/herramientas.sh y repo/indexar.sh (dentro de un contenedor Alpine,
# como root). Deja:
#   CASA     carpeta del usuario "constructor" (abuild no compila como root)
#   LLAVES   carpeta con la clave privada $NOMBRE y la pública $NOMBRE.pub
#   NOMBRE   lazaro.rsa (oficial) o lazaro-prueba.rsa
#   FIRMA    oficial o prueba
# La clave oficial viene en LAZARO_APK_KEY (el secreto de GitHub) y su
# mitad pública tiene que ser repo/lazaro.rsa.pub, la que llevan los
# equipos. Sin LAZARO_APK_KEY se firma con una clave de prueba, que sirve
# para probar pero nunca se publica.

apk add -q alpine-sdk openssl
id constructor >/dev/null 2>&1 || adduser -D -G abuild constructor
CASA=/home/constructor
LLAVES="$CASA/.llaves"
mkdir -p "$LLAVES"
if [ -n "${LAZARO_APK_KEY:-}" ]; then
	NOMBRE=lazaro.rsa
	printf '%s\n' "$LAZARO_APK_KEY" > "$LLAVES/$NOMBRE"
	openssl rsa -in "$LLAVES/$NOMBRE" -pubout -out "$LLAVES/$NOMBRE.pub" 2>/dev/null ||
		{ echo "ERROR: LAZARO_APK_KEY no es una clave RSA válida" >&2; exit 1; }
	if ! cmp -s "$LLAVES/$NOMBRE.pub" "$LAZARO_DIR/repo/lazaro.rsa.pub"; then
		echo "ERROR: LAZARO_APK_KEY no corresponde a repo/lazaro.rsa.pub: los equipos rechazarían los paquetes" >&2
		exit 1
	fi
	FIRMA=oficial
else
	NOMBRE=lazaro-prueba.rsa
	[ -f "$LLAVES/$NOMBRE" ] || openssl genrsa -out "$LLAVES/$NOMBRE" 2048 2>/dev/null
	openssl rsa -in "$LLAVES/$NOMBRE" -pubout -out "$LLAVES/$NOMBRE.pub" 2>/dev/null
	FIRMA=prueba
	echo "AVISO: sin LAZARO_APK_KEY; se firma con una clave de prueba (no se publica)."
fi
chmod 600 "$LLAVES/$NOMBRE"
for d in "$CASA/.abuild" "$CASA/.config/abuild"; do
	mkdir -p "$d"
	{
		echo "PACKAGER_PRIVKEY=\"$LLAVES/$NOMBRE\""
		echo "JOBS=$(nproc)"
		echo "MAKEFLAGS=-j$(nproc)"
	} > "$d/abuild.conf"
done
cp "$LLAVES/$NOMBRE.pub" /etc/apk/keys/
chown -R constructor:abuild "$CASA"

# firmar_indice DIR: arma DIR/APKINDEX.tar.gz con los .apk de DIR y lo firma.
firmar_indice() {
	(cd "$1" && apk index --quiet -o APKINDEX.tar.gz --rewrite-arch "$ALPINE_ARCH" \
		-d "Lázaro Linux para Alpine $ALPINE_BRANCH" ./*.apk)
	cp "$1/APKINDEX.tar.gz" "$CASA/APKINDEX.tar.gz"
	chown constructor:abuild "$CASA/APKINDEX.tar.gz"
	su constructor -c "abuild-sign -k $LLAVES/$NOMBRE $CASA/APKINDEX.tar.gz" >/dev/null
	cp "$CASA/APKINDEX.tar.gz" "$1/APKINDEX.tar.gz"
}
