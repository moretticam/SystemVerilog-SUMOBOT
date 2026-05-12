# SystemVerilog-SUMOBOT
SystemVerilog code for our autonomus SUMO BOT. Participated and WON! :) the **2026 AESSBOT tournament at UPC (Universitat Politècnica de Catalunya)**. It was the only HDL-based design out of 16 participants.
This repository contains the RTL design that runs on the robot's FPGA, a legacy Cyclone I dev board. It includes sensor interfacing, motor control, and the high-level behavior FSM that decides when to charge, evade, or search for an opponent.

---
## Hardware

| Component | Part |
|-----------|------|
| FPGA board | Altera Cyclone I EP1C3T144C8N dev-board|
| Distance sensors | 3x HC-SR04 ultrasound sensors|
| Motor driver | TB6612FNG |
| Chassis | 3D-Designs-for-the-robot.3mf |
---

## Functionalities
- Control of two DC motors
  - in-FPGA fabric PWM signal generation
- Sequential reading of 3 ultrasound sensors
- Automatic selection of closest opponent
- Prioritized PANIC sequence when ring edge is detected
- On-board debug LEDs
- Integrated button debouncer & sequencer
- *boxes* mode: will make you look very cool when changing tires!

## NOTE
We are working on a proper README, as well as adding further explanations. Feel free to check out the already commented bits.
