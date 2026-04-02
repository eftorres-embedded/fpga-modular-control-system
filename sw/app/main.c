#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

#define	PWM_BASE	0x00030000

#define	REG_CTRL	(*(volatile uint32_t*)(PWM_BASE + 0x00))
#define	REG_PERIOD	(*(volatile uint32_t*)(PWM_BASE + 0x04))
#define	REG_DUTY	(*(volatile	uint32_t*)(PWM_BASE + 0x08))
#define REG_APPLY	(*(volatile uint32_t*)(PWM_BASE + 0x0C))
#define REG_STATUS	(*(volatile uint32_t*)(PWM_BASE + 0x10))
#define REG_CNT		(*(volatile uint32_t*)(PWM_BASE + 0x14))

//later to add gamma-corrected fade loop
int main(void)
{
    printf("\n\nstart\n");

    printf("Write period for blinking\n");
    REG_PERIOD = 25000000;
    printf("period ok\n\n");

    printf("Write duty for blinking\n");
    REG_DUTY = 12500000;
    printf("duty ok\n\n");
	
	printf("Write 1 to bit 0 (enable) in CTRL\n");
	REG_CTRL = (1u << 0);
	printf("bit 0 set to 1: done!\n\n");
	
	printf("write: 1 to apply\n");
	REG_APPLY = 1;
	printf("REG_APPLY set to 1: done!\n\n");
	
	printf("sleeping for 2 seconds\n");
	usleep(2000000);
	printf("sleeping done\n\n");
	
	printf("status = 0x%08lx\n", REG_STATUS);
	printf("ctrl reg = %lu\n", REG_CTRL);
    printf("cnt    = %lu\n", REG_CNT);
	printf("DUTY REG = %lu\n", REG_DUTY);
	printf("PERIOD REG = %lu\n", REG_PERIOD);
	
	printf("\n");
	
	printf("Write PERIOD for smooth LED intensity\n");
    REG_PERIOD = 50000;
	REG_DUTY	= 0;
    printf("PERIOD ok\n\n");
	
	printf("write: 1 to apply\n");
	REG_APPLY = 1;
	printf("REG_APPLY set to 1: done!\n\n");
	
	printf("status = 0x%08lx\n", REG_STATUS);
	printf("ctrl reg = %lu\n", REG_CTRL);
    printf("cnt    = %lu\n", REG_CNT);
	printf("DUTY REG = %lu\n", REG_DUTY);
	printf("PERIOD REG = %lu\n\n\n", REG_PERIOD);

	
    // -------------------------------------------------
    // 1. Variable test
    // -------------------------------------------------
    int a = 5;
    int b = 10;
    int sum = a + b;

    printf("Variable test: %d + %d = %d\n", a, b, sum);

    // -------------------------------------------------
    // 2. Loop test (for loop)
    // -------------------------------------------------
    printf("\nFor loop test:\n");

    for (int i = 0; i < 5; i++)
	{
        printf("  i = %d\n", i);
        usleep(200000); // 200 ms delay
    }

    // -------------------------------------------------
    // 3. While loop test
    // -------------------------------------------------
    printf("\nWhile loop test:\n");

    int counter = 3;
    while (counter > 0)
	{
        printf("  counter = %d\n", counter);
        counter--;
        usleep(300000); // 300 ms delay
    }

    // -------------------------------------------------
    // 4. Timing / delay test
    // -------------------------------------------------
    printf("\nDelay test (1 second total):\n");

    for (int i = 0; i < 5; i++)
	{
        printf("  tick %d\n", i);
        usleep(200000); // 5 × 200 ms = 1 second
    }

    // -------------------------------------------------
    // 5. Infinite loop (heartbeat)
    // -------------------------------------------------
    printf("\nEntering main loop...\n");

    uint32_t heartbeat = 0;
	while(1)
	{
		
		//ramp up
		for(int32_t d = 0; d <= 50000; d += 100)
		{
			REG_DUTY = d;
			REG_APPLY = 1;
			usleep(2000);
		}

		//ramp down
		for(int32_t d = 50000; d >= 100; d -= 100)
		{
			REG_DUTY = d;
			REG_APPLY = 1;
			usleep(2001);
		}
		
	

	}
	return 0;
}
	