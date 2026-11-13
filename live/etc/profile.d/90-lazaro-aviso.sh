# Sesión live en modo texto: al entrar en una consola se repite el aviso
# de cómo instalar (lo deja /etc/init.d/lazaro-live cuando no hay
# escritorio).
if [ -r /run/lazaro/aviso-texto ]; then
	case "$(tty 2>/dev/null)" in
		/dev/tty[1-6]) cat /run/lazaro/aviso-texto ;;
	esac
fi
