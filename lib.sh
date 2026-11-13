# shellcheck shell=sh
# Valores derivados de config.env. Lo cargan build.sh y las pruebas.
# Requiere que LAZARO_DIR apunte a la carpeta lazaro-linux.

. "$LAZARO_DIR/config.env"

case "$ALPINE_BRANCH" in
	edge)
		ALPINE_DOCKER_TAG="edge"
		APORTS_BRANCH="master"
		;;
	v[0-9]*.[0-9]*)
		ALPINE_DOCKER_TAG="${ALPINE_BRANCH#v}"
		APORTS_BRANCH="${ALPINE_BRANCH#v}-stable"
		;;
	*)
		echo "ALPINE_BRANCH no válido: '$ALPINE_BRANCH' (usa vX.Y o edge)" >&2
		exit 1
		;;
esac

case "$ALPINE_ARCH" in
	x86_64) ;;
	x86)
		if [ "$LAZARO_EDICION" != ligera ]; then
			echo "La ISO de 32 bits (ALPINE_ARCH=x86) solo existe como edición Ligera." >&2
			exit 1
		fi
		;;
	*)
		echo "ALPINE_ARCH no válida: '$ALPINE_ARCH' (usa x86_64 o x86)" >&2
		exit 1
		;;
esac

ALPINE_REPO_MAIN="$ALPINE_MIRROR/$ALPINE_BRANCH/main"
ALPINE_REPO_COMMUNITY="$ALPINE_MIRROR/$ALPINE_BRANCH/community"
case "$LAZARO_EDICION" in
	ligera) ISO_FILE="$ISO_NAME-$ISO_VERSION-$ALPINE_DOCKER_TAG-$ALPINE_ARCH.iso" ;;
	completa) ISO_FILE="$ISO_NAME-completa-$ISO_VERSION-$ALPINE_DOCKER_TAG-$ALPINE_ARCH.iso" ;;
	*)
		echo "LAZARO_EDICION no válida: '$LAZARO_EDICION' (usa ligera o completa)" >&2
		exit 1
		;;
esac

export ALPINE_BRANCH ALPINE_ARCH ALPINE_MIRROR CALAMARES_VERSION POSTINSTALL_URL ISO_NAME \
	ISO_VERSION ALPINE_DOCKER_TAG APORTS_BRANCH ALPINE_REPO_MAIN \
	ALPINE_REPO_COMMUNITY ISO_FILE LAZARO_EDICION
