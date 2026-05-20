OUTPUT_ARCH(riscv)
ENTRY(main)

SECTIONS
{
  . = 0x80000000;
  .text : { *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
}
