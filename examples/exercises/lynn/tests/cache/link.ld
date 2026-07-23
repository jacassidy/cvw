OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

SECTIONS
{
  . = 0x80000000;
  .tohost : { *(.tohost) }
  . = ALIGN(0x1000);
  .text.init : { *(.text.init) }
  .text : { *(.text) *(.text.main) }
  . = ALIGN(0x1000);
  .rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) }
  . = ALIGN(16);
  .data : { *(.data) }
  .sdata : { *(.sdata .sdata.*) }
  .bss : { *(.bss) *(.sbss) *(.scommon) }
  . = ALIGN(16);
  _end = .;
}
