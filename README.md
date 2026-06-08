<div align="center">
  <h1>📍 Locate</h1>
  <p><strong>Localiza tus objetos vía GPS y Realidad Aumentada</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter&logoColor=white" alt="Flutter">
    <img src="https://img.shields.io/badge/Android-36-3DDC84?logo=android&logoColor=white" alt="Android">
    <img src="https://img.shields.io/badge/iOS-18-000000?logo=apple&logoColor=white" alt="iOS">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  </p>
  <br>
</div>

---

## ✨ Funcionalidades

- **📍 Registrar objetos** — Guarda la ubicación GPS de tu coche, moto, bici, casa, tienda y más
- **🥽 Realidad Aumentada** — Apunta con la cámara y ve la distancia a tus objetos
- **🗺️ Buscar en mapa** — Visualiza todos tus objetos en OpenStreetMap y añade nuevos tocando el mapa
- **📋 Gestionar objetos** — Renombra, activa/desactiva para RA o elimina objetos
- **🔍 Buscar lugares** — Encuentra cualquier sitio escribiendo su nombre

## 📸 Capturas

| Menú principal | Registrar objeto | Vista RA | Mapa |
|:---:|:---:|:---:|:---:|
| ![Menú](screenshots/menu.png) | ![Registrar](screenshots/register.png) | ![RA](screenshots/ar.png) | ![Mapa](screenshots/map.png) |

> *Las capturas son ilustrativas. Añade tus propias imágenes en `screenshots/`.*

## 🚀 Cómo empezar

### Requisitos

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.44+)
- Android Studio o Xcode (según plataforma)

### Instalación

```bash
# Clonar el repositorio
git clone https://github.com/tuusuario/locate.git
cd locate

# Instalar dependencias
flutter pub get

# Ejecutar en Android
flutter run

# Ejecutar en iOS (requiere Xcode)
flutter run -d ios
```

### Generar APK

```bash
flutter build apk --debug
```

El APK se genera en `build/app/outputs/flutter-apk/app-debug.apk`.

## 🧭 Cómo funciona

### Realidad Aumentada
La vista AR combina la cámara en vivo con un overlay que calcula la posición de los objetos usando:
- **Brújula** — Combina acelerómetro y magnetómetro para conocer hacia dónde apunta el dispositivo
- **GPS** — Obtiene tu posición actual
- **Cálculo de rumbo** — Determina el ángulo entre tu posición y cada objeto

Los objetos aparecen como marcadores flotantes con nombre y distancia. Solo se muestran los objetos marcados como **activos**.

### Mapa
Usa **OpenStreetMap** (sin necesidad de API key). Puedes:
- Ver todos tus objetos como marcadores con iconos identificativos
- Tocar cualquier punto del mapa para añadir un nuevo objeto
- Buscar lugares por nombre usando geocodificación

## 📦 Tipos de objetos

| Tipo | Icono | Tipo | Icono |
|:---:|:---:|:---:|:---:|
| 🚗 Coche | `directions_car` | 🏪 Tienda | `store` |
| 🏍️ Moto | `motorcycle` | 🏠 Casa | `home` |
| 🚲 Bici | `pedal_bike` | 💼 Trabajo | `work` |
| 🛒 Supermercado | `shopping_cart` | ⛽ Gasolinera | `local_gas_station` |
| 🍽️ Restaurante | `restaurant` | 🌳 Parque | `park` |
| 🏥 Hospital | `local_hospital` | 🏨 Hotel | `hotel` |

## 🛠️ Stack técnico

| Tecnología | Propósito |
|---|---|
| **Flutter** | Framework cross-platform |
| **flutter_map** | Mapas OpenStreetMap |
| **camera** | Captura de cámara para RA |
| **geolocator** | GPS y localización |
| **geocoding** | Búsqueda de lugares |
| **sensors_plus** | Brújula (acelerómetro + magnetómetro) |
| **sqflite** | Base de datos local |

## 📄 Licencia

```
MIT License

Copyright (c) 2024 Locate

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

<div align="center">
  <sub>Hecho con ❤️ para no volver a perder nada</sub>
</div>
