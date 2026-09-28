# 2026-09-28  BAS02 UART debug print
Goal: Send text from the G474RE to the PC terminal (Tera Term) via the ST-LINK virtual COM port.
Board(s): NUCLEO-G474RE
Wiring (pin -> pin, voltage levels): none, USB cable to ST-LINK only. PA2 = USART2_TX, PA3 = USART2_RX (internal to ST-LINK VCP).
CubeMX settings that matter (clock, peripheral mode, prescaler, baud rate): USART2 Asynchronous, 115200, 8N1, no flow control, TX+RX. USART1 disabled. BSP COM1 disabled. Clock: HSI, PLL to 170 MHz (unchanged from blink project).
Code location (file names or git branch/commit): branch bas02-uart-debug; Core/Src/debug_uart.c, Core/Inc/debug_uart.h, Core/Inc/config.h, USER CODE blocks in Core/Src/main.c
Result: VERIFIED
What I measured or saw: Tera Term shows the start message and a Heartbeat line every second with counter and tick.
Gotchas / what went wrong first: (1) The UART on PA2/PA3 is USART2 in this CubeMX, not LPUART1. USART1 uses PC4/PC5 and does not reach the USB cable. (2) The BSP COM1 option generated a second BSP_COM_Init for USART2; it failed and Error_Handler froze the program after the start message. Fixed by disabling COM1 in the .ioc. (3) %f (float) does not print with the default printf.
Promoted into module: yes, debug_uart.c/.h (Debug_Init, Debug_Printf)
