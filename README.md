# Nightscout → LibreView

Upload your [Nightscout](https://nightscout.github.io/) CGM data to your **LibreView**
(Abbott) account, so your doctor keeps seeing the reports they know while you keep using
xDrip / Shuggah / whatever reads your sensor.

Fork of [creepymonster/nightscout-to-libreview](https://github.com/creepymonster/nightscout-to-libreview):
same protocol, made non-interactive and containerised, plus a weekly backfill script, a daily
sync for cron with alerts — and the gotchas written down, because **this API lies to you**.

**Status: working as of September 2026** — 6 months backfilled and syncing daily (Libre 2/2+ EU
read by xDrip4iOS → Nightscout → LibreView, Spanish account).

## How it works

It presents itself as the FreeStyle LibreLink app: logs in to `api-eu.libreview.io/lsl`
(`FSLibreLink.iOS` gateway) with your LibreView credentials and posts glucose readings as
`scheduledContinuousGlucoseEntries`. It sends every 3rd Nightscout reading (≈ every 15 min, the
Libre's native history cadence) and, like upstream, adds 8–10 "scans" a day taken from real
readings so LibreView's reports look like a scanned sensor. The device identity is a UUID kept in
`state/device.json`; it shows up in LibreView → *My devices* as "FreeStyle LibreLink".

## Read this before uploading anything

1. **`POST /lsl/api/measurements` always answers `status: 0` with `TotalCount: 0`**, even when it
   ingests every reading. Ingestion is asynchronous. Do not use the response to verify anything
   (Juggluco doesn't either). I lost an afternoon to this.
2. **Do not verify through the LibreLinkUp API** (`/llu/connections`, `/graph`, `/logbook`): it
   returns the patients your account *follows*, not your own data.
3. **Verify on libreview.com** (2FA): the *Glucose history* card shows average glucose, hypo events
   and % of days with data — compare them with Nightscout for the same range. They matched to the
   digit for me (128 mg/dL, 6 hypos, 36 % of days).
4. **Cloudflare rate-limits the API**: `error code: 1015` if you post faster than about one
   request every 4 s. `historico.sh` waits 30 s between chunks and retries. A 1015 never reaches
   Abbott, so retrying that chunk is safe.
5. `recordNumber` is deterministic (`1` + `YYYYMMDDhhmmss`), but whether LibreView de-duplicates a
   re-sent range is **unverified**. Do not re-send ranges you already uploaded.
6. Keep `state/device.json`. Deleting it creates another device in your account. Login uses
   `SetDevice: true` on purpose.
7. LibreView gets the values Nightscout has (in my case xDrip's), **not** Abbott's algorithm — for me
   they run ~20 mg/dL lower than the official app. Tell your doctor which numbers they are looking at.
8. **LibreView cannot delete data.** Dry-run first, then a short range, then look at the website.

Not needed in practice, but if `api-eu` does not work for your country: the official apps read
their base URL (`newYuUrl`) from
`https://fsll.freestyleserver.com/Payloads/Mobile/FSLibreLink/Android/Config/FSLibreLink_Android_2.10_<CC>_config.json`.
The full protocol (sensor registration, `sensorstart`, the `recordNumber` mask) is readable in
[Juggluco](https://github.com/j-kaltes/Juggluco)'s `Common/src/main/cpp/net/libreview/`.

## Requirements

- Docker (the scripts run `node:20-alpine`; no Node on the host needed)
- A Nightscout instance and a **read-only** token for it
- A LibreView account (the one your clinic is linked to)

## Setup

```bash
git clone https://github.com/jmbosque/nightscout-to-libreview
cd nightscout-to-libreview
docker run --rm -v "$PWD":/app -w /app node:20-alpine npm install --omit=dev
cp .env.example .env && chmod 600 .env     # then fill it in
```

Read-only Nightscout token (do not give the exporter your API_SECRET):

```bash
S=$(printf '%s' "$API_SECRET" | sha1sum | cut -d' ' -f1)
curl -X POST -H "api-secret: $S" -H 'Content-Type: application/json' \
  https://YOUR-NIGHTSCOUT/api/v2/authorization/subjects \
  -d '{"name":"libreview-export","roles":["readable"]}'
curl -H "api-secret: $S" https://YOUR-NIGHTSCOUT/api/v2/authorization/subjects   # shows accessToken
```

## Usage

Dates are `YYYY-MM-DD`, UTC, `[from, to)`.

```bash
DRY_RUN=true ./subir-a-libreview.sh 2026-09-01 2026-09-08   # read from Nightscout, upload nothing
./subir-a-libreview.sh 2026-09-01 2026-09-08                # upload one range
./historico.sh 2026-03-01 2026-09-01                        # backfill, one POST per week, rate-limit friendly
./sync-diario.sh                                            # upload what is new since state/ultimo.txt
```

Daily sync with cron — initialise the watermark once, then:

```bash
echo 2026-09-01T00:00:00Z > state/ultimo.txt
crontab -e   # 15 6 * * * /path/to/sync-diario.sh >> /path/to/logs/sync.log 2>&1
```

`sync-diario.sh` is silent when everything is fine. It e-mails you (`MAIL_*` in `.env`) when the
upload fails or when Nightscout had **no new readings** (your uploader stopped), and pings
[healthchecks.io](https://healthchecks.io) (`HC_PING_URL`: `/start`, ok, `/fail`) so you are also
told when the cron does not run at all — the one failure a script cannot report by itself.

Script comments and messages are in Spanish; they are short.

## Credits, license, disclaimer

- Original code: [creepymonster](https://github.com/creepymonster/nightscout-to-libreview), kept
  in `src/` (only the response logging was fixed). It carries no explicit license; this fork does
  not change that.
- Protocol cross-checked against [Juggluco](https://github.com/j-kaltes/Juggluco) (GPL-3.0);
  nothing was copied, only read.
- My additions (`run.js`, the shell scripts, this README, `.env.example`) are MIT.
- Not affiliated with Abbott. This uses an undocumented API by impersonating their app; it can
  stop working any day and it may be against their terms. Your data must keep living in Nightscout;
  LibreView is a view for your doctor, not a backup.
