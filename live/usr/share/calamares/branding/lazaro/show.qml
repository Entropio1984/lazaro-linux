/* Presentación que se ve mientras se instala Lázaro Linux. */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 12000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    /* Diapositiva con el logo arriba y el texto debajo. */
    component SlideLazaro: Slide {
        id: diapositiva
        property string titulo: ""
        property string texto: ""

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.85, 620)
            spacing: 18

            Image {
                source: "logo.png"
                fillMode: Image.PreserveAspectFit
                width: Math.min(diapositiva.height * 0.35, 150)
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: diapositiva.titulo
                visible: text !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 24
                font.bold: true
                color: "#0E2A42"
            }
            Text {
                text: diapositiva.texto
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                font.pixelSize: 17
                color: "#0E2A42"
            }
        }
    }

    Slide {
        Image {
            source: "bienvenida.png"
            fillMode: Image.PreserveAspectFit
            width: Math.min(parent.width * 0.9, parent.height * 0.9, 400)
            anchors.centerIn: parent
        }
    }
    SlideLazaro {
        titulo: "Tu hardware aún tiene pulso"
        texto: "Lázaro Linux le da una segunda vida a tu equipo: documentos, PDF, internet y YouTube, sin pedir un computador nuevo."
    }
    SlideLazaro {
        titulo: "Todo listo al terminar"
        texto: "Idioma, teclado, audio, impresoras, controladores de video y wifi se configuran solos."
    }
    SlideLazaro {
        titulo: "Más programas, desde la tienda"
        texto: "Para instalar otros programas, abre la tienda de aplicaciones desde el menú (Discover en Plasma y LXQt, GNOME Software en los demás escritorios). Con Flathub tienes miles de programas a un clic."
    }
    SlideLazaro {
        titulo: "Aplicaciones de Flathub"
        texto: "Las aplicaciones de Flathub que marcaste (OnlyOffice, Chrome, Brave) se instalan solas en segundo plano unos minutos después del primer arranque, cuando el equipo tenga internet."
    }
    SlideLazaro {
        titulo: "Mantén tu sistema al día"
        texto: "Cuando haya actualizaciones, un icono te avisará en la barra. Al hacer clic se abre <b>Actualizar el sistema</b>, que también está en el menú de aplicaciones. Solo pide tu contraseña."
    }
    SlideLazaro {
        titulo: "¿Sin internet ahora?"
        texto: "Si instalaste sin internet, la configuración final se completa sola la primera vez que el equipo se conecte a una red."
    }

    function onActivate() { presentation.currentSlide = 0; }
    function onLeave() { }
}
