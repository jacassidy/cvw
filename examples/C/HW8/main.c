#include <stdio.h>
#include <stdint.h>

// Declare the external assembly function
extern void rvtest_entry_point(void);

// Function to read the result from the destination address
uint64_t read_result() {
    uint64_t *destination = (uint64_t *)0x0123456789ABCDEF;
    return *destination;
}

int main() {
    // Call the RISC-V assembly function
    rvtest_entry_point();

    // Read and print the result
    uint64_t result = read_result();
    printf("Result: 0x%016lx\n", result);

    return 0;
}