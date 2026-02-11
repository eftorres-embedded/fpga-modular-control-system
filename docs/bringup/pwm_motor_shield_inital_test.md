
# Pre-work
I used Questa to run the testbenches, since I did it using Windows 11, I decided to run the CLI tools. 

I opened Windows Powershell on the project directory and created the 3 folders needed: work, logs and waves. All of them inside \build\sim\ directory. 

The command I used was: 

`PS D:\fpga_projects\fpga-modular-control-system> New-Item -ItemType Directory -Force -Path build\sim\work, build\sim\logs, build\sim\waves | Out-Null`

The first time I ran it, my `tb_pwm_timebase.sv` file only contained a "Hello World" simulation for sanity-check: verify vlog/vsim work and the lcok runs (make sure the installation was working and all directories were in order). 

# The Work
## Create the simulation directories
```powershell
New-Item -ItemType Directory -Force -Path build\sim\work, build\sim\logs, build\sim\waves | Out-Null
```
## Build the library and directory
```powershell
vlib build\sim\work
```
## Compile the SystemVerilog files
```powershell
vlog -work build\sim\work -sv .\rtl\peripherals\pwm\pwm_timebase.sv .\tb\unit\pwm\tb_pwm_timebase.sv
```
## Run the simulation
```powershell
vsim -c -work build\sim\work tb_pwm_timebase -do  "run -all; quit"
```

# Detailed explanation
## Build the library and directory
Then we initialize the folder `build\sim\work` to turn it into a Questa compilation library:

I did it by running `vlib build\sim\work` inside the project directory.

## Compile the SystemVerilog files
Then, I compiled the SystemVerilog files, I used vlog since it can read .v and .sv files to compile them. 
`vlog -work build\sim\work -sv .\rtl\peripherals\pwm\pwm_timebase.sv .\tb\unit\pwm\tb_pwm_timebase.sv`
 - `vlog` runs the questa compiler for Verilog/SystemVerilog. It reads the source files you list and compiles them into a simulation library. 
 - `-work build\sim\work` tells vlog where to put the compiled results
 - `-sv` enables SystemVerilog mode, so .sv constructs are legal
 - `\rtl\peripherals\pwm\pwm_timebase.sv` is the FIRST source file to compile, this is the DUT, this was required because the testbench instantiates it (TB instantiates DUT, so the DUT must be compiled before the TB so the simulator knows its definition). `.\tb\unit\pwm\tb_pwm_timebase.sv` is the second source file to compile, this is the testbench module. 
 In summary, It compiles the PWM timebase RTL and its unit testbench as SystemVerilog and stores the compiled modules in the build\sim\work library so the testbench can be run with `vsim`. 

 ## Run the simulation
 - Then we tell Questa to load the compiled testbench from the library and run it automatically, we do this with the command: `vsim -c -work build\sim\work tb_pwm_timebase -do  "run -all; quit"`
 - `vsim` launches the Questa simulator, for example, if `vlog` means "compile", `vsim` means "execute"
 - `-c` means "Console/batch mode.
   - No GUI windows
   - Output goes to the transcript/terminal ($display, errors, etc.)
 - `-work build\sim\work` tells `vsim` where to look for compiled modules
 - `build\sim\work`is the library created with `vlib`
 -  and compiled into with `vlog -work build\sim\work ...`
 - `tb_pwm_timebase` is the top-level module to simulate, it must match the module name inside the testbench file. In other words, until this point, it means "Start simulation at module `tb_pwm_timebase`. 
 - `-do "run -all; quit"`
   `-do` allows a mini script of simulator commands to run immediately
   `-run -all` Runs the simulation until it ends, for example, run until: 
      - The testbench calls `$finish`, or
      - The testbench calls `$fatal` or hits assertion failure, or
      - there are no more events.
    `quit` exits Questa after the simulation completes. 
So in summary `-do "run -all; quit"` means: Run the simulation to completion, then exit without requiring me to type anything

## What should we see at this point?
- The testbench prints messages via `$display`
- If it passes, the PASS message will be displayed and then it exits
- If it fails, the $fatal message will be displayed and then it exits with an error. 

# February 2, 2026
- The tb_pwm_timebase.sv was initially written with a basic "hello world!" test bench to make sure everything ran correctly. 
- The test bench has been re-written with a correct testbench and it needs to be rerun, since the directories exist and the library is already created. I only need to Recompile and re-run. So I just run the commands

```powershell
vlog -work build/sim/work -sv ./rtl/peripherals/pwm/pwm_timebase.sv ./tb/unit/pwm/tb_pwm_timebase.sv
```

and then...

```powershell
vsim -c -work build/sim/work tb_pwm_timebase -do "run -all; quit"
```
this time I used forward slashes and it worked, I'm still not sure which one is best.


--currently running into some errors, modified the testbench (changed `wait (period_end);` to `@(posedge period_end)`). I'm still running into issues, will Force a clean rebuild by using the following commands: 

```powershell
Remove-Item -Recurse -Force build\sim\work
vlib build/sim/work
vlog -work build/sim/work -sv ./rtl/peripherals/pwm/pwm_timebase.sv ./tb/unit/pwm/tb_pwm_timebase.sv
vsim -c -work build/sim/work tb_pwm_timebase -do "run -all; quit"
```

-- Force cleaning was not necessary, the issue was with raceconditions on the testbench.

# February 3, 2026
- After all the test have passed, I added a "demo" section that runs for a shorter time in order to see a better waveform.  Then I generated a waveform, through the command line by running the following command (being on the project root directory):
```powershell
vsim -c -work build/sim/work tb_pwm_timebase -voptargs=+acc -wlf build/sim/waves/tb_pwm_timebase.wlf -do "log -r /tb_pwm_timebase/*; log -r /tb_pwm_timebase/dut/*; run -all; quit"
```
- Then open the waveform database in the GUI with the following command
```powershell
vsim -view build/sim/waves/tb_pwm_timebase.wlf
```
- Once the waveform is successfully generated, the objects need to be added to the Wave window. I added the relevant signals by clicking on `DUT` and dragging the signals of interest.
- Once the signals are added, I changed the radix of some signals to make it more readable such as cnt -> Radix -> Decimal
- A command that can be run to automatically open, add and zoom is:
```powershell
vsim -view build/sim/waves/tb_pwm_timebase.wlf -do "add wave -r /tb_pwm_timebase/*; add wave -r /tb_pwm_timebase/dut/*; wave zoom full"
```


# February 10, 2026
## tb_pwm_compare.sv - Testbench simulation
- Now, I ran a test bench simulation for the pwm_compare. I am not including the pwm_timebase, I am creating the cnt signal directly in tb_pwm_compare. 
- Simulation is compiled and run by the following commands:
```powershell
vlog -work build/sim/work -sv ./rtl/peripherals/pwm/pwm_compare.sv ./tb/unit/pwm/tb_pwm_compare.sv
vsim -c -work build/sim/work tb_pwm_compare -do "run -all; quit"
```
## tb_pwm_compare.sv - Testbench log signals to create wave on tb_pwm_compare.wlf
- After fixing errors and having a simulation successfully run. I ran the following command to create the waveform and producing tb_pwm_compare.wlf. (we are keeing internal signal visibility so logging works)
```powershell
vsim -c -work build/sim/work tb_pwm_compare -voptargs=+acc -wlf build/sim/waves/tb_pwm_compare.wlf -do "log -r /tb_pwm_compare/*; log -r /tb_pwm_compare/dut/*; run -all; quit"
```
## tb_pwm_compare.sv - Open test bench in GUI and add signals to the wave window
-After Generating the wlf (batch), we can run the following command to open the wlf in the GUI and show the signals
```powershell
vsim -view build/sim/waves/tb_pwm_compare.wlf -do "add wave -r /tb_pwm_compare/*; add wave -r /tb_pwm_compare/dut/*; wave zoom full"
```

