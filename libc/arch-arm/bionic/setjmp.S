/*
 * Copyright (c) 1997 Mark Brinicombe
 * Copyright (C) 2010 The Android Open Source Project
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by Mark Brinicombe
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <private/bionic_asm.h>

// According to the ARM AAPCS document, we only need to save
// the following registers:
//
//  Core   r4-r11, sp, lr
//    AAPCS 5.1.1:
//      A subroutine must preserve the contents of the registers r4-r8, r10, r11
//      and SP (and r9 in PCS variants that designate r9 as v6).
//
//  VFP    d8-d15
//    AAPCS 5.1.2.1:
//      Registers s16-s31 (d8-d15, q4-q7) must be preserved across subroutine
//      calls; registers s0-s15 (d0-d7, q0-q3) do not need to be preserved
//      (and can be used for passing arguments or returning results in standard
//      procedure-call variants). Registers d16-d31 (q8-q15), if present, do
//      not need to be preserved.
//
//  FPSCR  saved because glibc does.

// The internal structure of a jmp_buf is totally private.
// Current layout (changes from release to release):
//
// word   name            description
// 0      sigflag/cookie  setjmp cookie in top 31 bits, signal mask flag in low bit
// 1      sigmask         64-bit signal mask (not used with _setjmp / _longjmp)
// 2      "               "
// 3      reserved        (unused to allow float_base to be maximally aligned)
// 4      float_base      base of float registers (d8 to d15)
// 20     float_state     floating-point status and control register
// 21     core_base       base of core registers (r4-r11, r13-r14)
// 31     checksum        checksum of all of the core registers, to give better error messages.
// 32     reserved        reserved entries (room to grow)
// 64
//
// NOTE: float_base must be at an even word index, since the
//       FP registers will be loaded/stored with instructions
//       that expect 8-byte alignment.

#define _JB_SIGFLAG     0
#define _JB_SIGMASK     (_JB_SIGFLAG + 1)
#define _JB_FLOAT_BASE  (_JB_SIGMASK + 3)
#define _JB_FLOAT_STATE (_JB_FLOAT_BASE + (15-8+1)*2)
#define _JB_CORE_BASE   (_JB_FLOAT_STATE+1)
#define _JB_CHECKSUM    (_JB_CORE_BASE+10)

ENTRY(setjmp)
__BIONIC_WEAK_ASM_FOR_NATIVE_BRIDGE(setjmp)
  mov r1, #1
  b sigsetjmp
END(setjmp)

ENTRY(_setjmp)
__BIONIC_WEAK_ASM_FOR_NATIVE_BRIDGE(_setjmp)
  mov r1, #0
  b sigsetjmp
END(_setjmp)

#define MANGLE_REGISTERS 1
#define USE_CHECKSUM 1

.macro m_mangle_registers reg
#if MANGLE_REGISTERS
  eor r4, r4, \reg
  eor r5, r5, \reg
  eor r6, r6, \reg
  eor r7, r7, \reg
  eor r8, r8, \reg
  eor r9, r9, \reg
  eor r10, r10, \reg
  eor r11, r11, \reg
  eor r13, r13, \reg
  eor r14, r14, \reg
#endif
.endm

.macro m_unmangle_registers reg
  m_mangle_registers \reg
.endm

.macro m_calculate_checksum dst, src, scratch
  mov \dst, #0
  .irp i,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28
    ldr \scratch, [\src, #(\i * 4)]
    eor \dst, \dst, \scratch
  .endr
.endm

// int sigsetjmp(sigjmp_buf env, int save_signal_mask);
ENTRY(sigsetjmp)
__BIONIC_WEAK_ASM_FOR_NATIVE_BRIDGE(sigsetjmp)
  stmfd sp!, {r0, lr}
  .cfi_def_cfa_offset 8
  .cfi_rel_offset r0, 0
  .cfi_rel_offset lr, 4

  mov r0, r1
  bl __bionic_setjmp_cookie_get
  mov r1, r0

  ldmfd sp, {r0}

  // Save the setjmp cookie for later.
  bic r2, r1, #1
  stmfd sp!, {r2}
  .cfi_adjust_cfa_offset 4

  // Record the setjmp cookie and whether or not we're saving the signal mask.
  str r1, [r0, #(_JB_SIGFLAG * 4)]

  // Do we need to save the signal mask?
  tst r1, #1
  beq 1f

  // Align the stack.
  sub sp, #4
  .cfi_adjust_cfa_offset 4

  // Save the current signal mask.
  add r2, r0, #(_JB_SIGMASK * 4)
  mov r0, #2 // SIG_SETMASK
  mov r1, #0
  bl sigprocmask64

  // Unalign the stack.
  add sp, #4
  .cfi_adjust_cfa_offset -4

1:
  ldmfd sp!, {r2}
  .cfi_adjust_cfa_offset -4
  ldmfd sp!, {r0, lr}
  .cfi_adjust_cfa_offset -8
  .cfi_restore r0
  .cfi_restore lr

  // Save core registers.
  add r1, r0, #(_JB_CORE_BASE * 4)
  m_mangle_registers r2

  // ARM deprecates using sp in the register list for stmia.
  stmia r1, {r4-r11, lr}
  str sp, [r1, #(9 * 4)]
  m_unmangle_registers r2

  // Save floating-point registers.
  add r1, r0, #(_JB_FLOAT_BASE * 4)
  vstmia  r1, {d8-d15}

  // Save floating-point state.
  fmrx r1, fpscr
  str r1, [r0, #(_JB_FLOAT_STATE * 4)]

#if USE_CHECKSUM
  // Calculate the checksum.
  m_calculate_checksum r12, r0, r2
  str r12, [r0, #(_JB_CHECKSUM * 4)]
#endif

  mov r0, #0
  bx lr
END(sigsetjmp)

// void siglongjmp(sigjmp_buf env, int value);
ENTRY(siglongjmp)
__BIONIC_WEAK_ASM_FOR_NATIVE_BRIDGE(siglongjmp)
  stmfd sp!, {r0, r1, lr}
  .cfi_def_cfa_offset 12
  .cfi_rel_offset r0, 0
  .cfi_rel_offset r1, 4
  .cfi_rel_offset lr, 8

#if USE_CHECKSUM
  // Check the checksum before doing anything.
  m_calculate_checksum r12, r0, r3
  ldr r2, [r0, #(_JB_CHECKSUM * 4)]

  teq r2, r12
  bne __bionic_setjmp_checksum_mismatch
#endif

  // Fetch the signal flag.
  ldr r1, [r0, #(_JB_SIGFLAG * 4)]

  // Do we need to restore the signal mask?
  ands r1, r1, #1
  beq 1f

  // Restore the signal mask.
  mov r2, #0
  add r1, r0, #(_JB_SIGMASK * 4)
  mov r0, #2 // SIG_SETMASK
  bl sigprocmask64

1:
  ldmfd sp!, {r0, r1, lr}
  .cfi_adjust_cfa_offset -12
  .cfi_restore r0
  .cfi_restore r1
  .cfi_restore lr

  // Restore floating-point registers.
  add r2, r0, #(_JB_FLOAT_BASE * 4)
  vldmia r2, {d8-d15}

  // Restore floating-point state.
  ldr r2, [r0, #(_JB_FLOAT_STATE * 4)]
  fmxr fpscr, r2

  // Load the cookie.
  ldr r3, [r0, #(_JB_SIGFLAG * 4)]
  bic r3, r3, #1

  // Restore core registers.
  add r2, r0, #(_JB_CORE_BASE * 4)

  // ARM deprecates using sp in the register list for ldmia.
  ldmia r2, {r4-r11, lr}
  ldr sp, [r2, #(9 * 4)]
  m_unmangle_registers r3

  // Save the return value/address and check the setjmp cookie.
  stmfd sp!, {r1, lr}
  .cfi_adjust_cfa_offset 8
  .cfi_rel_offset lr, 4
  mov r0, r3
  bl __bionic_setjmp_cookie_check

  // Restore return value/address.
  ldmfd sp!, {r0, lr}
  .cfi_adjust_cfa_offset -8
  .cfi_restore lr

  teq r0, #0
  moveq r0, #1
  bx lr
END(siglongjmp)

ALIAS_SYMBOL(longjmp, siglongjmp)
__BIONIC_WEAK_ASM_FOR_NATIVE_BRIDGE(longjmp)
ALIAS_SYMBOL(_longjmp, siglongjmp)
__BIONIC_WEAK_ASM_FOR_NATIVE_BRIDGE(_longjmp)
