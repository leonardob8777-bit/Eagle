# Eagle 1.0.6 (95)

Simplified Chinese, a new Eagle icon and opening, fixed Prepare/Apply bars,
31 new online Dock backgrounds, clearer light/dark controls and smoother feedback.

See [the complete 1.0.6 release notes](docs/releases/v1.0.6.md) for the download,
changes, verification, compatibility and known visual limitations.

Previous release: [Eagle 1.0.5](docs/RELEASE_1.0.5.md).

---

# Eagle 1.0.4 (80)

Eagle 1.0.4 is the stable release with the Island and Dock gallery work from 1.0.3, the visual refresh, and the stability fixes completed since the last public build.

## What changed

- Added **Island Gallery** with six calibrated styles: Starlight, Inferno, Horizon, Vortex, Bubblegum, and Traffic.
- Island Gallery now separates **Live**, **Static**, and **Saves**, includes the Island shadow meter, and exposes a clear Apply action.
- Added **Dock Gallery** with Bubblegum, Springfield, and Bikini Bottom artwork at the exact 382 × 106-point Dock frame, with Live/static themes, Saves, and adjustable glow.
- Added **Hide Dock + Island** as a dedicated screen. Hide Island uses the persistent system preference; Hide Dock applies verified material recipes, requires a respring, and must be reapplied after a full device restart.
- Aura Studio no longer carries a New badge. New badges across the other current entries now use a consistent black-and-white design in light and dark appearance.
- Updated the Updates window with the new galleries, controls, layout corrections, recovery behavior, and stability fixes.
- Improved Home navigation, action placement, Prepare/Apply visibility, adaptive light/dark surfaces, Passcode localization, wallpaper copy, and diagnostics.

## Stability and recovery

- Gallery and Scene Aura operations verify SpringBoard session ownership before reading session properties. Expired or replaced sessions are rejected without entering the native call.
- Repeated taps, cancellation, background transitions, and unfinished operations release their locks safely.
- Island, Dock, and Aura saved flags reject invalid integer values instead of trapping during conversion.
- Dock Gallery rejects non-finite glow values before native conversion and keeps the applied intensity consistent with the stored value.
- Dock preview capacity is bounded to the supported 4, 5, or 6 icon choices even if an invalid preference was saved.
- Hide Dock keeps verified originals, checks every write, and restores from recovery data when a partial write occurs.
- Passcode and Collections transactions retain originals and recover from incomplete changes.
- Prepare cleanup and existing TrollStore access handling remain from the public release and were regression-tested with the new gallery operations.

## Compatibility

- Limited testing: iOS 16.7.2.
- Supported Prepare range: iOS 17.0–18.7.1 and iOS 26.0–26.0.1.
- Primary physical reference: iPhone 16 Pro (`iPhone17,1`) on iOS 18.6.2 (`22G100`).
- TrollStore preparation was additionally validated on iPhone 14 Pro Max with iOS 17.0.
- Live Island and Dock art remains limited to verified iOS 17/18 SpringBoard routes.
- The IPA is unsigned and must be signed with the user's normal installation method.

## Español

Eagle 1.0.4 es la versión estable con las galerías Island y Dock de la versión 1.0.3, el nuevo acabado visual y las correcciones de estabilidad realizadas desde la última versión pública.

- **Galería Island:** seis estilos calibrados, filtros Live/Static/Saves, medidor de sombra y botón Aplicar.
- **Galería Dock:** tres temas al tamaño exacto del Dock, temas Live/estáticos, Saves y brillo ajustable.
- **Hide Dock + Island:** pantalla independiente. Hide Island conserva su estado después de reiniciar; Hide Dock requiere respring y debe volver a activarse después de un reinicio completo.
- Aura Studio ya no muestra New. Las etiquetas New restantes usan el mismo diseño blanco y negro en modo claro y oscuro.
- Se actualizaron las novedades, la visibilidad de Preparar/Aplicar, la recuperación de Hide Dock y la estabilidad al aplicar temas.
- Se corrigieron sesiones vencidas, toques repetidos, cancelaciones, ajustes inválidos, intensidades no finitas, capacidades fuera de rango y recuperaciones incompletas.

La IPA no está firmada. Debe firmarse con el método habitual de instalación personal.
