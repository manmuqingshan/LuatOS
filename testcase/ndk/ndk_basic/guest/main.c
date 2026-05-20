// Reconstructed source for testcase/ndk/ndk_basic/scripts/baremetal.bin
// 
// Based on mini-rv32ima upstream (https://github.com/cnlohr/mini-rv32ima)
// but simplified to match observed LuatOS NDK test behavior only.

#include <stdint.h>
#include <stddef.h>

// Control store address - linker provides as symbol
extern volatile uint32_t SYSCON;

// CSR-based logging functions (observed in LuatOS runtime)
static void lprint( const char * s )
{
	asm volatile( "csrrw x0, 0x138, %0" : : "r" (s));
}

static void pprint( intptr_t ptr )
{
	asm volatile( "csrrw x0, 0x137, %0" : : "r" (ptr));
}

static void nprint( intptr_t num )
{
	asm volatile( "csrrw x0, 0x136, %0" : : "r" (num));
}

int main()
{
	// Debug logging block - matches observed test output
	lprint("\n");
	lprint("main is at: ");
	pprint( (intptr_t)main );
	
	char buffer[32];
	lprint("\nBuffer is at: ");
	pprint( (intptr_t)buffer );
	lprint("\nStack top is at: ");
	pprint( (intptr_t)&buffer[sizeof(buffer)-1] );

	// String length test - matches observed log messages
	lprint("\nTesting strlen optimization:");
	const char * teststr1 = "Hello, world!";
	const char * teststr2 = "This is a longer test string to check the strlen function optimization.";
	size_t len1 = __builtin_strlen(teststr1);
	size_t len2 = __builtin_strlen(teststr2);
	lprint("Length of teststr1: ");
	nprint(len1);
	lprint("\nLength of teststr2: ");
	nprint(len2);
	lprint("\n");

	// Exit via control store
	// Observed runtime log: "Control Store: set val to 00005555"
	SYSCON = 0x5555;
	
	return 0;
}

// Assembly entry point - simplified for observed behavior
__asm__(
".section .text.init\n"
".global _start\n"
".align 4\n"
"_start:\n"
"	lui	sp, %hi(_sstack)\n"
"	addi	sp, sp, %lo(_sstack)\n"
"	# BSS zeroing omitted: no globals in current reconstruction\n"
"	call	main\n"
"	j	.\n"  // Should not return
);

