# Bluetooth Protocol

## Device Discovery

Only devices whose advertised name starts with `SENBALL#` and ends with an ASCII digit (`0-9`) should be displayed.

After the first successful connection, the app stores the peripheral identifier. On later launches it automatically scans for and reconnects to that device.

The device enters low-power mode after one minute without movement. Prompt users to hit the device once before scanning so Bluetooth wakes and becomes discoverable.

## Commands

| Action | Bytes |
| --- | --- |
| Gyroscope on | `C5 5C 04 01` |
| Gyroscope off | `C5 5C 04 00` |

Rules:

- After Bluetooth connection succeeds, send gyroscope off.
- After the training countdown completes, send gyroscope on.
- When training ends, stops, or fails, send gyroscope off.

## Telemetry

Packet header: `D5 5D 03`  
Packet length: 11 bytes

| Offset | Meaning |
| --- | --- |
| 0 | `D5` |
| 1 | `5D` |
| 2 | `03` |
| 3 | Packet index |
| 4 | Battery |
| 5 | Data2 / punch count |
| 7 | Data4 / peak |

Punch-count logic:

- Store the first data2 value as baseline.
- If data2 increases, add the delta to displayed punch count.
- If data2 wraps from high value to low value, treat as an 8-bit rollover.
