# Hardware & test status

Claude Code reads this file at the start of every session (imported from
CLAUDE.md). Keep it SHORT: one row per test, details in the log entries below
or in docs/test-log/.

Status values: NOT TESTED / IN PROGRESS / VERIFIED / FAILED (add why)

## Toolchain and basics
| CubeIDE project builds and flashes (blink LED) on G474RE | VERIFIED | 2026-09-28 | G474RE, PA5 (LD2) | Label LD2 must be set by hand in .ioc (BSP names differ) |
| Same project type on F446ZE | VERIFIED | 2026-09-28 | F446ZE, PB0 (LD1) | Blink works, same workflow as G474RE;

| Test | Status | Date | Board / pins | Notes |
|---|---|---|---|---|
| CubeIDE project builds and flashes (blink LED) on G474RE | NOT TESTED | | | |
| UART debug print to PC terminal | NOT TESTED | | | |
| Same project type on F446ZE | NOT TESTED | | | |

## CAN
| Test | Status | Date | Board / pins | Notes |
|---|---|---|---|---|
| G474RE FDCAN internal loopback (classic mode) | NOT TESTED | | | |
| F446ZE bxCAN internal loopback | NOT TESTED | | | |
| G4 <-> F446 over 2x ISO1050 at 250 kbit/s | NOT TESTED | | | Both ends 120 ohm? |
| CANable + PC tool sees the frames | NOT TESTED | | | |
| Read SOCO 6043B pack data on PC | NOT TESTED | | | |
| Fardriver ND74500 communication | NOT TESTED | | | Controllers not yet received |

## Sensors (each tested alone on a Nucleo first)
| Sensor | Part | Status | Date | Board / pins | Notes |
|---|---|---|---|---|---|
| Steering angle | P3022 Hall angle sensor, 0-360 deg, 12 bit, 0-5 V out | NOT TESTED | | | 0-5 V output: needs divider before a 3.3 V ADC pin |
| Throttle | Linear Hall sensor in throttle grip | NOT TESTED | | | Single channel so far; safety layer wants dual (see Decisions) |
| Brake switch | M10 x 1.00/1.25 hydraulic brake light switch | NOT TESTED | | | On/off only, no pressure value |
| Wheel speed (front) | none yet | NOT TESTED | | | Maybe from Fardriver status frames? To decide |
| Wheel speed (rear) | NJK-5002C Hall proximity switch, NPN, magnet | NOT TESTED | | | NPN output: pull-up to 3.3 V; check supply voltage in datasheet |
| IMU | GY-601N1 module, BMI323, 6DOF, I2C/SPI | NOT TESTED | | | |
| Engine RPM pickup circuit | LM393 comparator (DIP-8) | NOT TESTED | | | |

## UI / logging (F446 practice, F446ze final)
| Part | Status | Date | Board / pins | Notes |
|---|---|---|---|---|
| 3.5" TFT 320x480, ST7796S, SPI (dashboard) | NOT TESTED | | | |
| 2.4" TFT + EC11 rotary encoder + button, SPI | NOT TESTED | | | |
| Adafruit 4682 micro SD breakout, SPI/SDIO, 3 V | NOT TESTED | | | |

## Decisions made
(Write short lines, for example: "2026-10-05: CAN baud rate 250 kbit/s on all nodes.")

-

---

## Test log entry template
Copy this into docs/test-log/YYYY-MM-DD_short-name.md for every test.

```
# YYYY-MM-DD  Short name of the test
Goal:
Board(s):
Wiring (pin -> pin, voltage levels):
CubeMX settings that matter (clock, peripheral mode, prescaler, baud rate):
Code location (file names or git branch/commit):
Result: VERIFIED / FAILED / PARTIAL
What I measured or saw:
Gotchas / what went wrong first:
Promoted into module: (yes/no, which file)
```
