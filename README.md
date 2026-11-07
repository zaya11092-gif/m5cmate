# M5C Mate

An open-source companion app for the **AnkerMake M5C** 3D printer, built on the
community-reverse-engineered [AnkerMake M5 protocol](https://github.com/Ankermgmt/ankermake-m5-protocol).
Not affiliated with AnkerMake.

## Features

- **Live print status over the official cloud MQTT channel** — progress, remaining
  time, nozzle/bed temperatures, layer, file name.
- **Dynamic Island / Lock Screen Live Activity** — live progress while printing;
  **long-press the island** for the expanded view (progress bar, remaining time,
  temps, layer).
- **Local notifications** for print started / finished / paused / resumed / errors
  and **filament runout**.
- **Speed control up to 200%** — sends Marlin `M220 S<pct>` feed-rate override
  through the verified MQTT gcode channel. The official app stops at lower values;
  the firmware always has the final say (it may clamp). An experimental native
  `commandType 1006` path is available in Settings.
- **Pause / Resume / Stop** buttons (native print-control command).
- **GCode console** — send arbitrary GCode and watch raw MQTT traffic.

## Building

CI (GitHub Actions, `macos-14`) builds an **unsigned** IPA on every push to
`main` and uploads it as the artifact `M5CMate-unsigned-ipa`.

### Install on your iPhone (free Apple ID)

1. Download the IPA artifact from the latest Actions run.
2. Install [Sideloadly](https://sideloadly.io) (Windows/macOS), plug in your
   iPhone, drop in the IPA, sign with your Apple ID (it uses a free 7-day
   provisioning profile), and install.
   - AltStore works too.
3. On the phone: Settings → General → VPN & Device Management → trust your
   developer certificate.
4. Sign in with your AnkerMake account (region must match your account region),
   pick your printer, done.

Re-sign every 7 days (free accounts) or use a paid developer account for
year-long profiles.

### Building locally

```bash
brew install xcodegen
xcodegen generate
open M5CMate.xcodeproj   # set your team in both targets, then run
```

## How the protocol layer works

| Piece | Detail |
|---|---|
| Login | `POST /v2/passport/login` — password encrypted with ECDH-P256 against Anker's static key |
| Printers | `POST /v1/app/query_fdm_list` → serial, model, per-printer MQTT AES key |
| MQTT | `make-mqtt(.eu).ankermake.com:8789` over TLS, user `eufy_<user_id>`, password = account email |
| Framing | `'MA'` envelope, version byte 6 (`1` = M5C 24-byte header, `2` = M5 64-byte header), AES-256-CBC (fixed IV `3DPrintAnkerMake`), trailing XOR-checksum byte |
| Status | JSON list on `/phone/maker/<sn>/notice` (`commandType` 1001 schedule, 1003/1004 temps, 1006 speed, 1052 layer, 1000 events) |
| Commands | JSON on `/device/maker/<sn>/command` — gcode `1043 {cmdData, cmdLen}`, print control `1008` |

The M5C firmware changed the envelope (24-byte header, version byte 1) in
newer releases — this app supports both incoming formats and defaults to
M5C-style outgoing packets (switchable in Settings → Advanced protocol).

## Known limitations

- **Background updates**: iOS suspends apps; the Live Activity keeps its last
  state in the background and is refreshed when the app opens or a background
  refresh runs. True push-based updates would need a server component.
- **Speed >150%** can produce print-quality issues or be clamped by firmware —
  watch the console for the printer's reply.
- The pause/resume/stop `1008` value mapping is not officially documented; if
  buttons misbehave, adjust the mapping in Settings.

## Credits

- [Ankermgmt/ankermake-m5-protocol](https://github.com/Ankermgmt/ankermake-m5-protocol) — protocol documentation
- [treitmayr's M5C fixes](https://github.com/Ankermgmt/ankermake-m5-protocol/pull/145) — M5C envelope format
- [Django1982's fork](https://github.com/Django1982/ankermake-m5-protocol) — verified gcode command format
- [CocoaMQTT](https://github.com/emqx/CocoaMQTT)
