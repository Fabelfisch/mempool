// Copyright 2021 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Author: Matheus Cavalcante, ETH Zurich

#include <stdint.h>
#include <string.h>

#include "encoding.h"
#include "printf.h"
#include "runtime.h"
#include "synchronization.h"

int main() {
  uint32_t core_id = mempool_get_core_id();
  uint32_t num_cores = mempool_get_core_count();
  // Initialize synchronization variables
  mempool_barrier_init(core_id);

  if(core_id == 0){
    volatile uint32_t i = 0;
    volatile uint32_t j = 0;
    volatile uint32_t a = 0;
    volatile uint32_t b = 0;
    printf("Core %3d says Hello!\n", core_id);
    asm volatile( "add %[j], x0, x0         \n\t"
                  "add %[i], x0, x0         \n\t"
                  "add %[a], x0, x0         \n\t"
                  "1:                       \n\t"
                  "  add %[b], x0, x0       \n\t"
                  "  2:                     \n\t"
                  "    addi %[j], %[j], 1   \n\t"
                  "    addi %[b], %[b], 1   \n\t"
                  "  bne %[b],%[N], 2b      \n\t"
                  "  addi %[i], %[i], 1     \n\t"
                  "  addi %[a], %[a], 1     \n\t"
                  "bne %[a],%[N], 1b        \n\t" 
                  : [i] "+&r"(i), [j] "+&r"(j), [a] "+&r"(a), [b] "+&r"(b)  /* Outputs */
                  : [N] "r"(10)     /* Inputs */
                  : /* Clobber */);
    printf("i: %3d, j: %3d\n", i,j);
  }
  else{
    asm volatile ("nop");
  }
  // wait until all cores have finished
  mempool_barrier(num_cores);
  return 0;
}
