/*
 * debug_uart.h
 *
 *  Created on: Sep 28, 2026
 *      Author: Ruben
 */

#ifndef INC_DEBUG_UART_H_
#define INC_DEBUG_UART_H_

#ifndef DEBUG_UART_H
#define DEBUG_UART_H

/* Prints a start message. Call once after the UART is initialised. */
void Debug_Init(void);

/* Works like printf, but sends the text to the PC over the ST-LINK
 * virtual COM port. Note: %f (float) does not work yet, use integers. */
void Debug_Printf(const char *format, ...);

#endif /* DEBUG_UART_H */

#endif /* INC_DEBUG_UART_H_ */
