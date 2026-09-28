<!--
HOW TO USE THIS FILE (human notes. Claude Code strips these comments before
reading, so they cost no context.)

1. Save this file as CLAUDE.md in the ROOT of your project folder (the folder
   that contains .git). The name must be exactly CLAUDE.md.
2. Also save docs/HARDWARE_STATUS.md (included). This file imports it, so
   Claude sees your test results at the start of every session.
3. Put your Fardriver PDF in docs/protocols/fardriver_can59.pdf.
4. Start Claude Code in that folder and type /context. CLAUDE.md should be
   listed under "Memory files". If it is not, Claude cannot see it.
5. Keep this file under ~200 lines. Short, concrete facts work best. Long
   logs belong in docs/, not here.
6. Update it whenever you have to tell Claude the same thing twice, or when
   a decision changes.
7. This file is guidance, not enforcement. Claude usually follows it, but
   it is not a lock. Safety rules for the real vehicle must also live in
   the firmware itself, never only in this file.
-->

# Hybrid cargo moped ("bakbrommer") firmware project

## Who you are working with
- I am a beginner with STM32, CAN and embedded C. I know Arduino and did
  some C for a game. I need full support with code.
- Always give COMPLETE, working files, not fragments. Say the exact file
  name and where it goes.
- For CubeMX steps, list every setting explicitly: pin, mode, clock,
  prescaler, baud rate. Explain briefly why.
- One small step at a time. Do not change things I did not ask about.
- Answer in the language I write in (Dutch or English). Code, identifiers
  and code comments are in English.

## The project in one paragraph
Three-wheel hybrid cargo moped. A 110 cc Lifan petrol engine drives the rear
wheel by chain. Each front wheel is driven by its own Fardriver ND74500
controller (CAN version), on a lithium pack of about 60 V nominal / 71.4 V
full. Final system: an STM32G4 is the control node (sensors, safety layer,
ESC commands over CAN). An STM32F446ze is the UI/logging node (screens,
SD logging, settings, Bluetooth). Planned drive modes: Eco, Normal, Sport,
Race.

## Current phase
PRACTICE PHASE. I am learning CubeMX/CubeIDE and CAN on Nucleo boards and
testing each part separately before merging. Nothing is connected to the
vehicle or to high voltage yet. Bench tests use USB or low voltage only.

## Hardware I own (keep this list updated)
- NUCLEO-G474RE: same family as the final control node (FDCAN peripheral,
  used in classic CAN 2.0 mode)
- NUCLEO-F446ZE: for the UI/logging node (bxCAN
  peripheral). 
- 2x ISO1050 CAN transceiver modules (2500 V isolated, 120 ohm jumper)
- CANable USB-CAN adapter (NOT isolated) for the PC side
- Hall-hoeksensor Contactloos 0-360 graden hoekig koppel Rotatiesensor 12bit verplaatsingssensor Positiesensor 0-5V P3022-hoeksensor ( voor de stuurhoek )
- 1PCS Hall sensor naderingsschakelaar  NJK-5002C  npn lijn magneet (achterwiel snelheid)
- Estardyn 3,5 inch TFT LCD-scherm, 320x480 SPI-moduleST7796S voor dashboard
- 1 stks GY-601N1 6-assige accelerometer-gyroscoopsensor BMI323, 6DOF Motion Tracking Module, I2C/SPI/UART
- lineair hall sensor in gashendel voor gaspositie
- 4682 Adafruit Micro SD-kaart Breakout Module - SPI/SDIO 3V Alleen Flash-geheugenuitbreidingskaart 
- 2,4-inch TFT-scherm met EC11 roterende encoder Combinatiemodule SPI-interface LCD-scherm includes potentiometer en knop
- M10 1,00 mm 1,25 mm hydraulische remlichtschakelaar  (geen Barsensor  puur schakelend door hydcaulishe druk)
- LM393P LM393N LM393 DIP-8 voor RPM vanuit pickup omschakeling
- SOCO 6043B battery packs. Planned test: read their CAN data on the PC.
  Protocol reference: GitHub stprograms/SuperSoco485Monitor

## Architecture principles (do not break these)
- The G4 control node is safety-critical: deterministic timing, fixed-period
  tasks, minimal work in interrupts, shared variables are `volatile`, no
  malloc after startup.
- The UI/logging node is never in the path of drive commands. Screens, SD
  card and Bluetooth only send REQUESTS. The G4 validates them.
- Limit hierarchy: ESC hardware limit (set once with the Fardriver host
  tool) is >= G4 software limit per drive mode, which is >= anything set
  from a screen or app. Settings only change at standstill.
- The mode switch is a physical switch wired to a G4 GPIO. A screen or app
  can only request a mode change.
- The safety layer runs in every mode and overrides mode logic. Dual
  sensors get plausibility checks. When in doubt: reduce torque, never
  increase it.
- Two ground domains (power ground and logic ground), joined only through
  the isolated DC-DC converter. Do not merge them in designs or wiring
  advice.

## Fardriver CAN protocol
moet nog toegevoegd


## Firmware conventions
- STM32CubeIDE with CubeMX, HAL drivers by default (LL only for a measured
  need).
- NEVER edit generated code outside `/* USER CODE BEGIN */` and
  `/* USER CODE END */`. Regenerating from the .ioc file must not destroy
  my work. Put own logic in separate module files and call them from the
  USER CODE sections.
- Module pattern per sensor or function: `Xxx_Init()`, `Xxx_Update()`,
  `Xxx_Get()`, returning a struct with a `valid` flag. Files are named
  `sensors_steering.c/.h`, `safety_layer.c/.h`, `can_interface.c/.h`, etc.
- No magic numbers. Constants and limits go in `config.h` / `limits.h`.
- Prefer clear over clever. Comment the WHY, not the obvious.
- Pin assignments and clock settings are decisions. Do not change them
  without telling me, and update docs/HARDWARE_STATUS.md when they change.

## Workflow: how tests become final code
1. One small test at a time, on a Nucleo, in its own folder or git branch.
2. When a test works, promote the code into a reusable module. Do not leave
   it as throwaway code in main.c.
3. Then update docs/HARDWARE_STATUS.md: status, date, board, pins, CubeMX
   settings, measured result, gotchas. Only mark VERIFIED after I confirm it
   worked on real hardware.
4. Rows that are NOT TESTED are assumptions. Say so when you rely on them.
5. Before writing code that depends on an earlier test, read that test's
   entry in docs/HARDWARE_STATUS.md.
6. After each verified step, remind me to commit to git.

## Do not
- Do not invent CAN IDs, pin numbers or register values. If unknown, say so
  and point to the datasheet or the PDF.
- Do not bypass the safety layer or raise limits "just for testing".
- Do not give advice that connects anything to the 60-71 V system before we
  have reviewed that step together.

## Current verified status
@docs/HARDWARE_STATUS.md
