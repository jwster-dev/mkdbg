# STM32F446RE — Reference Board Example

This directory is the **official reference implementation** of mkdbg running on a
Nucleo-F446RE board. It shows how to wire the `wire` crash-diagnostics agent and the
`seam` fault-event-ring agent into a real FreeRTOS MPU firmware, so you can use
`mkdbg attach` and `mkdbg seam analyze` against it with no GDB and no JTAG.

If you are porting mkdbg to a **different board**, read this directory as a template.
Everything STM32-specific is contained here; nothing outside this directory is
board-specific.

---

## What this example demonstrates

| Feature | File to look at | mkdbg command |
|---|---|---|
| Crash dump over UART (wire agent) | `bsp/wire_port.c` | `mkdbg attach --port /dev/ttyXXX --arch cortex-m` |
| Fault event ring (seam agent) | `bsp/seam_port.c` | `mkdbg seam analyze <capture.cfl>` |
| MPU fault containment | `src/fault.c`, `src/kdi.c` | — |
| Staged bringup with dependency graph | `src/bringup_phase.c` | — |
| VM32 sandboxed workloads | `src/vm32.c` | — |

---

## Prerequisites

```bash
arm-none-eabi-gcc   # arm cross-compiler
cmake >= 3.20
openocd             # for flashing (optional if you use ST-Link drag-and-drop)
python3 + pyserial  # for legacy Python tooling in scripts/
```

---

## Build

```bash
# from this directory
cmake -B build -DCMAKE_TOOLCHAIN_FILE=cmake/arm-none-eabi.cmake
cmake --build build -j4
# output: build/MicroKernel_MPU.elf, .hex, .bin
```

---

## Flash

```bash
bash scripts/flash.sh
# or drag-and-drop the .bin onto the Nucleo mass-storage drive
```

---

## Porting to your STM32F4 board

You only need to change two files:

| File | What to change |
|---|---|
| `bsp/board.c` + `bsp/board.h` | UART port number, clock config, GPIO pins for the VCP |
| `bsp/wire_port.c` | `wire_uart_send()` / `wire_uart_recv()` — map to your UART HAL |
| `bsp/seam_port.c` | `seam_uart_flush()` — map to your UART HAL |

Change `BOARD_UART_PORT` in `CMakeLists.txt` to match your UART (1, 2, or 3).

Everything else — `src/fault.c`, `src/kdi.c`, FreeRTOS, wire protocol, seam event
ring — is board-agnostic and does not need modification.

---

## Porting to a non-STM32 MCU

See [`docs/PORTING.md`](../../docs/PORTING.md) in the repo root for the full guide.
The short version:

1. Implement `wire_uart_send()` / `wire_uart_recv()` for your UART HAL (~20 lines)
2. Implement `seam_uart_flush()` for your UART HAL (~10 lines)
3. Call `wire_on_fault()` from your HardFault handler
4. Build the firmware, connect UART, run `mkdbg attach --port /dev/ttyXXX --arch cortex-m`

---

## Directory structure

```
stm32f446/
├── src/            firmware source (bringup, KDI, VM32, fault, seam, wire hooks)
├── bsp/            board support (UART, clock, MPU init) — the only board-specific files
├── freertos/       FreeRTOS kernel (MPU port for Cortex-M4)
├── cmsis/          ARM CMSIS headers for STM32F4xx
├── startup/        ARM startup assembly (startup_stm32f446xx.s)
├── linker/         linker script (STM32F446ZE_FLASH.ld)
├── include/        firmware header files
├── tests/          host-side unit tests (run on your laptop, no hardware needed)
├── scenarios/      VM32 fault scenarios (.asm + .vm files)
├── demo/           VM32 hello-world demo
├── configs/        bringup manifest YAML
├── scripts/        STM32-specific tooling (bringup_ui.py, vm32_asm.py, flash.sh, ...)
└── docs/           STM32-specific documentation (VM32 design, OVWATCH, telemetry)
```
