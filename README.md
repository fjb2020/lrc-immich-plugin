# lrc-immich-plugin
[![Github All Releases](https://img.shields.io/github/downloads/bmachek/lrc-immich-plugin/total.svg)]()

Lightroom Classic plug‑in to upload and download photos between Lightroom Classic and an Immich server using the Immich API.  
Provides both **Export** and **Publish Services**, plus tools to **import assets from Immich back into Lightroom**.

---

## Features

- **Export to Immich**
  - Send selected photos from Lightroom Classic directly to your Immich server.
  - Uses the Immich API, so uploads go straight into your Immich library.

- **Publish Service integration**
  - Create a Lightroom Publish Service backed by Immich.
  - Keep Lightroom collections and Immich albums aligned via publish operations.
  - Optional post-publish metadata sync (description, GPS coordinates, tags).

- **Metadata sync tools**
  - Library menu command: Send metadata for selected published photos.
  - Reuses the same sync logic as optional post-publish metadata sync.

- **Import from Immich**
  - Download assets from Immich albums into a local folder.
  - Import those files into your Lightroom catalog for editing and management.

- **Safe upload handling**
  - Uses temporary files and cleans them up after uploads.
  - Skips failed renders and continues with the rest of the queue.

---

## Quick facts

- **Platform**: Lightroom Classic (macOS and Windows).
- **Target**: Any reachable Immich server.
- **Use cases**:
  - Keep Immich in sync as your off‑site library.
  - Publish curated albums from Lightroom to Immich.
  - Pull selected Immich albums back into Lightroom for editing.

---

## Documentation

All setup and usage details live in the **GitHub Wiki**:

- **Getting Started / Installation**
- **Configuration & API Key permissions**
- **Export & Publish workflows**
- **Import from Immich**
- **Advanced options (batch size, performance, etc.)**
- **Troubleshooting & FAQ**

You can find the Wiki from the repository home page under the **Wiki** tab.

---

## Metadata Sync Notes

- Description source:
  - Reads Lightroom formatted metadata keys in this order: `caption`, `title`, `headline`.
- GPS source:
  - Reads from `photo:getRawMetadata("gps")` only.
  - If GPS is not present on a photo, latitude/longitude are not sent for that photo.
- Tags source:
  - Uses assigned Lightroom keywords and maps hierarchy to Immich tags.
  - Missing tags are created as needed before assignment.
- Publish integration:
  - If enabled in publish settings, metadata sync runs after successful uploads.
  - Sync is best-effort; upload success is preserved even if metadata/tag operations later fail.

---

## Credits

- **All contributors** to this project.
- [Jeffrey Friedl for `JSON.lua`](http://regex.info/blog/lua/json)
- [Enrique García Cota for `inspect.lua`](https://github.com/kikito/inspect.lua)
- [Min Idzelis for giving ideas with his Immich Plug‑in](https://github.com/midzelis/mi.Immich.Publisher)

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=bmachek/lrc-immich-plugin&type=Date)](https://www.star-history.com/#bmachek/lrc-immich-plugin&Date)