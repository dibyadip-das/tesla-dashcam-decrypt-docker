# Tesla Dashcam Decryptor for UGREEN NAS (Docker Compose)

A Docker packaging of [XGxF3/tesla-dashcam-decrypt](https://github.com/XGxF3/tesla-dashcam-decrypt) that batch-decrypts Tesla 2026.20+ encrypted dashcam / Sentry clips on your NAS. Everything is configured in `docker-compose.yml`: the input folder, the output folder, and your Bearer token.

Your video never leaves the NAS. Only each clip's header metadata (UUID, VIN, wrapped key) is sent to Tesla's `dashcam.tesla.com` API to retrieve the per-file AES key, exactly as the browser does.

## Folder contents

```
tesla-dashcam-decrypt-docker/
├── docker-compose.yml      <- edit this: paths + token
├── Dockerfile
├── entrypoint.sh           <- maps compose settings to script arguments
├── app/
│   ├── tesla_dashcam_decrypt.py   (upstream, unmodified)
│   └── requirements.txt
├── .env.example            (optional alternative for the token)
└── NOTICE
```

## 1. Get your Bearer token

1. Open https://dashcam.tesla.com in a desktop browser and log in.
2. Open DevTools (F12) → **Network** tab.
3. Drop any encrypted clip onto the page.
4. Click any request to `/api/1/…` → **Headers** → copy the value after `Authorization: Bearer `.

Tokens expire periodically. If the log says *"Token expired or invalid"*, grab a new one, update the compose file and redeploy.

## 2. Edit `docker-compose.yml`

| Setting | Where | Meaning |
|---|---|---|
| Input path | `volumes:` first line, left side | NAS folder with the encrypted clips (e.g. your copied `TeslaCam` folder). Mounted read-only. |
| Output path | `volumes:` second line, left side | NAS folder for decrypted MP4s. Subfolder structure (`SentryClips/…`, `SavedClips/…`) is preserved. |
| `TESLA_TOKEN` | `environment:` | Your Bearer token (required). Pasting it with the `Bearer ` prefix also works. |
| `RUN_MODE` | `environment:` | `once` = decrypt then stop. `watch` = rescan every `SCAN_INTERVAL` seconds. |
| `SCAN_INTERVAL` | `environment:` | Seconds between scans in watch mode (default 3600). |
| `BATCH_SIZE` | `environment:` | Files per key request to Tesla (default 20). |
| `REMUX` | `environment:` | `true` runs a lossless ffmpeg remux with faststart, helpful if a player has trouble seeking. |
| `DRY_RUN` | `environment:` | `true` fetches keys only, writes nothing. Good first test of your token. |
| `PUID` / `PGID` | `environment:` | The NAS user/group that should own the output files. SSH in and run `id` to find yours. |
| `EXTRA_ARGS` | `environment:` | Anything else to pass straight to the script. |
| `mem_limit` | service level | RAM cap for the container (512m). Decryption streams 4 KB pages, so normal usage is far below this. |

Only change the **left** side of each volume line (`/volume1/...`). Keep `:/input:ro` and `:/output` as they are.

To find the real path of a shared folder on UGOS Pro, open **Files**, right-click the folder → **Properties**. Shared folders usually live under `/volume1/<FolderName>`. If you want to decrypt straight from a USB stick plugged into the NAS, its path is typically shown in the same Properties dialog (under the external-device mount), but copying clips to a shared folder first is more reliable.

## 3. Deploy on the UGREEN NAS

### Option A: UGOS Pro Docker app (no SSH)

1. Copy the whole `tesla-dashcam-decrypt-docker` folder to the NAS, e.g. `/volume1/docker/tesla-dashcam-decrypt-docker`.
2. Make sure the output folder exists (create `TeslaCam_Decrypted` in **Files**).
3. Open the **Docker** app → **Project** → **Create**.
4. Name it `tesla-dashcam-decrypt`, set the storage path to the folder from step 1. UGOS will pick up the existing `docker-compose.yml`. Edit the token and paths there if you haven't already.
5. Click **Deploy**. The image builds the first time (a few minutes), then runs.
6. Check progress under **Container** → `tesla-dashcam-decrypt` → **Log**.

To run again later in `once` mode, just start the container again. Already-decrypted files are skipped automatically.

### Option B: SSH

```bash
cd /volume1/docker/tesla-dashcam-decrypt-docker
sudo docker compose up --build            # run in foreground, see output live
# or
sudo docker compose up -d --build && sudo docker compose logs -f
```

After changing the token: `sudo docker compose up -d --force-recreate`.

## Continuous mode

To have the NAS pick up new clips automatically, set:

```yaml
restart: unless-stopped
environment:
  RUN_MODE: "watch"
  SCAN_INTERVAL: "3600"
```

Keep in mind the token expires, so watch mode will start logging 401 errors until you paste a fresh one. Also avoid scanning while you're still copying clips into the input folder, since a half-copied file would be decrypted incompletely; if that happens, delete that output file and it will be redone on the next pass.

## Keeping the token out of the compose file (optional)

Copy `.env.example` to `.env` in the same folder, put the token there, and change the compose line to `TESLA_TOKEN: "${TESLA_TOKEN}"`. Alternatively mount a file and set `TESLA_TOKEN_FILE: /run/secrets/tesla_token`.

## Notes

- Existing files in the output folder are always skipped (upstream behaviour). To re-decrypt a clip, delete its output file.
- Build a smaller image without ffmpeg by setting `INSTALL_FFMPEG: "false"` under `build.args` (then `REMUX` can't be used).
- The image is based on `python:3.12-slim` and works on both x86_64 and ARM NAS models.
- Credit: decryption logic by XGxF3 (MIT). See `NOTICE` and `app/UPSTREAM_README.md`.
