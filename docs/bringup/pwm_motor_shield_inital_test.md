
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
    `quit` exits Questa after the simulation completets. 
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