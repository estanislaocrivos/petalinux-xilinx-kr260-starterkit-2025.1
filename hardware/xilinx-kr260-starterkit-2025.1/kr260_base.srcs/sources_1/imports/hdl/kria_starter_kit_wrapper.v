//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.1 (lin64) Build 6140274 Wed May 21 22:58:25 MDT 2025
//Date        : Thu May 22 07:32:56 2025
//Host        : xcossw07 running 64-bit Ubuntu 22.04.4 LTS
//Command     : generate_target kria_starter_kit_wrapper.bd
//Design      : kria_starter_kit_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module kria_starter_kit_wrapper
   (fan_en_b);
  output [0:0]fan_en_b;

  wire [0:0]fan_en_b;

  kria_starter_kit kria_starter_kit_i
       (.fan_en_b(fan_en_b));
endmodule
