# Eagle Interface Preview

Aplicación de prueba separada para verificar la interfaz y los componentes de
datos locales que Eagle está separando de Lara. No sustituye Eagle público y no
es una versión completa ni una ampliación de compatibilidad de iOS.

## Por qué este paso

Permite probar juntos el catálogo, la validación de paquetes, los fotogramas y
la caché que ya pertenecen a Eagle, sin incluir el motor de acceso heredado.
Es una comprobación de integración acotada, no una demostración de independencia
total. Los cambios no llegan al Eagle instalado hasta que se instala una nueva
versión de esa aplicación.

## Alcance

- Identificador independiente: com.leonardobaptiste.eagle.interfacepreview.
- Nombre visible: Eagle Preview. Versión de prueba: 0.1.0 (1).
- Dos paquetes locales: uno estático y otro de 17 fotogramas. No descarga temas.
- Dock e isla son representaciones dentro de la aplicación; las flechas solo
  mueven esa representación. No cambian el Dock ni Dynamic Island de iOS.
- La preparación es una demostración visual. No ejecuta Prepare, no modifica
  el sistema, no accede a otros procesos y no cambia el soporte de dispositivos.
- Se reutiliza sin modificaciones el componente de notificaciones dentro de la
  ventana de Eagle. No se afirma haber corregido sus gestos o animaciones.
- El idioma y la apariencia tienen preferencias propias, separadas de Eagle.

## Instalación y prueba manual

La IPA no incluye una firma de distribución. Debe firmarse con el procedimiento
habitual del usuario; el proyecto no proporciona certificados ni perfiles.
Eagle Preview puede coexistir con Eagle. No debe reemplazarse su identificador
por el de Eagle para esta prueba.

Comprobar en este orden:

1. Inicio: demostrar la preparación y observar la transición a Listo. Verificar
   que el texto deja claro que no es acceso real al sistema.
2. Galería: probar Todos, Live, Static y Guardados; marcar y desmarcar favoritos.
3. Preparar el paquete local estático y el animado. Repetir para comprobar la
   caché, sin interpretar el resultado como un tema aplicado a iOS.
4. Cambiar Dock/Isla y mover con las flechas. Verificar que títulos, controles y
   filtros no se desplazan con la representación.
5. Revisar modos claro y oscuro e idiomas español e inglés.
6. Pruebas: repetir avisos de éxito y error, tocar, mantener pulsado y deslizar.
   Grabar cualquier fallo visual; estos gestos requieren validación manual.
7. Pasar a segundo plano y regresar. Confirmar que la aplicación sigue usable.

La prueba automática de simulador cubre datos locales y estado básico. No
sustituye estos gestos, una prueba física, ni la validación de Eagle completo.

## Construcción aislada

El constructor scripts/build_eagle_interface_preview.py compila exclusivamente
la lista de componentes benignos, dos archivos nuevos de presentación y las
notificaciones de la ventana de la app. Extrae solo los tres elementos visuales
de arcoíris necesarios; no compila el archivo mixto ni el proyecto de Eagle.

Las salidas incluyen una lista de entradas con sus hashes y un ZIP de las
fuentes correspondientes. Se conservan LICENSE y el aviso MIT del componente
de notificaciones. El motor nativo, código C y cabeceras puente no se incluyen.
En el manifiesto, unchanged_input distingue archivos completos copiados de
declaraciones extraídas; no significa igualdad con la versión pública.
