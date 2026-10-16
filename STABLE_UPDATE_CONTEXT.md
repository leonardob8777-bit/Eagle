# Eagle Stable Update Context

Historical stability context, predating 1.0.6. For current user-facing copy,
see [1.0.6 update notes](docs/stable-update-notes.md) and the
[published release notes](docs/releases/v1.0.6.md).

Use this as source context for the future Updates window. Do not treat this file
as UI code; it is only a note of the stability work that should replace the old
welcome/beta wording when the visual pass is ready.

## Spanish copy

Titulo sugerido: Actualizaciones

Resumen corto:
Eagle ahora prepara el dispositivo con mas validaciones internas, mejor
diagnostico y menos falsos positivos antes de activar cambios reales.

Puntos para mostrar:
- Prepare ahora verifica mejor si el dispositivo realmente esta listo antes de
  continuar.
- Se corrigieron rutas que podian causar cierre de la app o reinicio por memoria
  durante intentos repetidos.
- Los datos de offsets/cache ahora se atan al modelo y build de iOS para evitar
  reutilizar informacion vieja despues de una OTA.
- Los errores de RemoteCall/YouTube ya no se disparan solo por abrir Eagle.
- Iconos en vivo ahora usan una sesion fresca de SpringBoard y verifican que no
  haya reinicio/cambio de PID antes de marcar cambios como aplicados.
- Las escrituras VFS ahora solo cuentan como correctas cuando escriben todos los
  bytes esperados.
- Las llamadas a daemons se ejecutan una por una y no liberan la siguiente
  operacion hasta terminar y destruir la sesion anterior; los estados visibles
  se publican en el hilo principal.
- Los parsers y rutas de escritura validan tamanos, offsets, archivos de origen
  y escrituras completas antes de informar exito.
- Liquid Glass restaura realmente el archivo guardado y SpringBoard Customizer
  ya no interpreta un exito como una excepcion ni oculta fallos parciales.
- Las opciones avanzadas ya no muestran exito cuando VFS, sandbox o la sesion
  de SpringBoard no estan listos.
- iOS 16.1, 16.1.1 y 16.2 quedan bloqueados temporalmente hasta tener pruebas
  fisicas confiables.
- iOS 16.7.2 queda disponible como probado-limitado.
- iOS 26.6 queda bloqueado porque necesita otro motor, no solo ajustes visuales
  u offsets.

Nota honesta:
Dynamic Island y Dock se conservan como rutas principales. Las opciones que no
puedan verificarse correctamente deben desactivarse temporalmente hasta recibir
reportes claros de dispositivos reales.

## English copy

Suggested title: Updates

Short summary:
Eagle now prepares the device with stronger internal validation, better
diagnostics, and fewer false positives before applying real changes.

Display points:
- Prepare now checks more carefully that the device is truly ready before
  continuing.
- Fixed paths that could close the app or trigger memory pressure during
  repeated attempts.
- Offset/cache data is now tied to the iOS build and device model, preventing
  stale data after an OTA.
- RemoteCall/YouTube errors no longer fire just from opening Eagle.
- Live icons now use a fresh SpringBoard session and verify that SpringBoard did
  not restart or change PID before reporting changes as applied.
- VFS writes now count as successful only when every expected byte is written.
- Daemon RemoteCall work is serialized and does not release the next operation
  until the previous session has finished and been destroyed; visible state is
  published on the main thread.
- Parsers and write paths validate sizes, offsets, source files, and complete
  writes before reporting success.
- Liquid Glass now restores the saved file, and SpringBoard Customizer no
  longer treats success as an exception or hides partial failures.
- Advanced options no longer report success when VFS, sandbox access, or the
  SpringBoard session is not ready.
- iOS 16.1, 16.1.1, and 16.2 are temporarily blocked until reliable physical
  testing exists.
- iOS 16.7.2 remains available as limited-tested.
- iOS 26.6 remains blocked because it needs a different engine, not visual or
  offset-only adjustments.

Honest note:
Dynamic Island and Dock remain primary routes. Options that cannot be verified
correctly should be temporarily disabled until clear reports from real devices
are available.
