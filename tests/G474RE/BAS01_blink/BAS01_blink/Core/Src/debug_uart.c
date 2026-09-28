/*
 * debug_uart.c
 *
 *  Created on: Sep 28, 2026
 *      Author: Ruben
 */

#ifndef SRC_DEBUG_UART_C_
#define SRC_DEBUG_UART_C_

#include "debug_uart.h"
#include "config.h"
#include "main.h"
#include <stdarg.h>
#include <stdio.h>

/* Created by CubeMX in main.c. The name is set in config.h. */
extern UART_HandleTypeDef DEBUG_UART_HANDLE;

void Debug_Init(void)
{
    Debug_Printf("\r\n--- BAS02 UART debug ready ---\r\n");
}

void Debug_Printf(const char *format, ...)
{
    char buffer[DEBUG_UART_BUFFER_SIZE];
    va_list args;

    va_start(args, format);
    int length = vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    if (length <= 0)
    {
        return;
    }

    /* vsnprintf returns the length it WANTED; cut it to what fits. */
    if ((size_t)length >= sizeof(buffer))
    {
        length = (int)sizeof(buffer) - 1;
    }

    /* Blocking transmit: fine for tests. In the final G4 control loop we
     * will NOT print like this, because waiting breaks fixed timing. */
    HAL_UART_Transmit(&DEBUG_UART_HANDLE, (uint8_t *)buffer, (uint16_t)length,
                      DEBUG_UART_TIMEOUT_MS);
}

#endif /* SRC_DEBUG_UART_C_ */
