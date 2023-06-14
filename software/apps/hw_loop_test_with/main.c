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
    printf("Core %3d says Hello!\n", core_id);
    asm volatile( "add %[j], x0, x0         \n\t"
                  "add %[i], x0, x0         \n\t"
                  "lp.count\tx1, %[N]       \n\t"
                  "lp.starti\tx1, start0    \n\t"
                  "lp.endi\tx1, end0        \n\t"
                  "lp.starti\tx0, startZ    \n\t"
                  "lp.endi\tx0, endZ        \n\t"
                  "start0:                  \n\t"
                  "  lp.count\tx0, %[N]     \n\t"
                  "  startZ:                \n\t"
                  "    addi %[j], %[j], 1   \n\t"
                  "  endZ:                  \n\t"
                  "  addi %[i], %[i], 1     \n\t"
                  "end0:                    \n\t" 
                  : [i] "+&r"(i), [j] "+&r"(j)  /* Outputs */
                  : [N] "r"(10)     /* Inputs */
                  : /* Clobber */);
    printf("i: %3d, j: %3d\n", i,j);
  }
  // wait until all cores have finished
  mempool_barrier(num_cores);
  return 0;
}
