//========================================================================
// blimp_stats.cpp
//========================================================================
// Utilities for reporting processor statistics

#include "utils/blimp_stats.h"

#ifdef _RISCV

uint32_t blimp_cycle_count()
{
  uint32_t* cycle_count_addr = (uint32_t*) 0xFFFFFF00;
  return *cycle_count_addr;
}

void blimp_stats_on()  { *(volatile uint32_t*) 0xFFFFFF04 = 1; }
void blimp_stats_off() { *(volatile uint32_t*) 0xFFFFFF04 = 0; }

#endif  // _RISCV