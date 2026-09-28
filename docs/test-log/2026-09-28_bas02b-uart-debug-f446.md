# 2026-09-28  BAS02b UART debug print on F446ZE
Goal: Send text from the F446ZE to the PC terminal (Tera Term) via the ST-LINK virtual COM port, using the same debug_uart module as on the G474RE (BAS02).
Board(s): NUCLEO-F446ZE
Wiring (pin -> pin, voltage levels): none, USB cable to ST-LINK only. USART3 on PD8/PD9 (internal to ST-LINK VCP).
CubeMX settings that matter (clock, peripheral mode, prescaler, baud rate): USART3 Asynchronous, 115200, 8N1, no flow control, TX+RX. Clock unchanged from blink project.
Code location (file names or git branch/commit): branch bas02b-uart-debug-f446; Core/Src/debug_uart.c, Core/Inc/debug_uart.h, Core/Inc/config.h (DEBUG_UART_HANDLE changed to the F446 handle), USER CODE blocks in Core/Src/main.c (LD1 / PB0)
Result: VERIFIED
What I measured or saw: Tera Term shows the start message and a Heartbeat line every second with counter and tick, same as on the G474RE.
Gotchas / what went wrong first: (1) The old blink code with HAL_Delay was still above the heartbeat code in the while loop. Result: about 3 s between lines (ticks 2014, 5018, 8022 ms), so about 2 s extra delay. Fixed by removing the old blink code; only one HAL_Delay (HEARTBEAT_PERIOD_MS) may stay in the loop. (2) The COM port has a different COM number than the G474RE; check Device Manager. (3) %f (float) does not print with the default printf.
Promoted into module: yes, same debug_uart.c/.h as BAS02 (Debug_Init, Debug_Printf); only the handle name in config.h differs per board.
