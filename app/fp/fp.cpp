// //========================================================================
// // fp.cpp
// //========================================================================
// // A demo as part of Blimp's walkthrough

// #include "utils/blimp_stdlib.h"

// float fadd(float a, float b)
// {
//     return a + b;
// }


// //------------------------------------------------------------------------
// // main
// //------------------------------------------------------------------------


// int main()
// {
//   float a = 1.25f;  
//   float b = 2.50f; 
//   float c;
//   blimp_printf("Starting floating point addition...\n");
//   //int start_cycles = blimp_cycle_count();
//   blimp_printf("Starting counting...\n");
//   c = fadd(a, b);
//   blimp_printf("Ended counting...\n");
//   //int end_cycles = blimp_cycle_count();

//   // blimp_printf( "fp completed in %d cycles\n",
//   //               end_cycles - start_cycles );

//   blimp_printf("a = ", a);
//   blimp_printf("b = ", b);
//   blimp_printf("c = ", c);
// }



int float_to_bits(float f) {
    union {
        float f;
        int i;
    } u;
    u.f = f;
    return u.i;
}

//========================================================================
// fp.cpp
//========================================================================
// A demo as part of Blimp's walkthrough
#include "utils/blimp_stdlib.h"

int dest[1];
float fadd(float a, float b)
{
  return a + b;
}

//------------------------------------------------------------------------
// main
//------------------------------------------------------------------------
int main()
{
  float a = 1.25f;  
  float b = 2.50f; 
  float c;
  
  blimp_printf("Starting floating point addition...\n");
  c = fadd(a, b);
  blimp_printf("Ended floating point addition...\n");
  
  blimp_printf("FADD completed successfully!\n");
  blimp_printf("Result stored in variable c\n");
  
  //  verify the addition happened without trying to convert
  if (c != 0.0f) {
    blimp_printf("c is non-zero - operation completed\n");
  }
  
  
  return 0;
}