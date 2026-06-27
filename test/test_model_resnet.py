"""
ResNet-20 Sub-Block Test on Atreides GPU

Simulates the core operations of a ResNet block on the GPU:
1. Im2Col Convolution (mapped to MatMul)
2. Residual Addition
3. ReLU Activation

This proves the hardware can execute the ResNet-20 data path.
"""

import cocotb
from cocotb.triggers import ClockCycles
import random
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_matmul, q115_add, q115_relu
from test_inference import build_matmul_kernel, build_relu_kernel
from helpers.memory import read_memory_range
from helpers.setup import setup_test, run_kernel

def build_add_bias_kernel(base_vec: int, base_bias: int, base_out: int, N: int) -> list:
    from helpers.memory import asm_mul, asm_add, asm_const, asm_ldr, asm_str, asm_act, asm_ret, R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, BLOCK_IDX, BLOCK_DIM, THREAD_IDX
    return [
        asm_mul(R0, BLOCK_IDX, BLOCK_DIM),
        asm_add(R0, R0, THREAD_IDX),
        asm_const(R3, base_vec),
        asm_const(R4, base_bias),
        asm_const(R5, base_out),
        asm_add(R6, R3, R0),
        asm_ldr(R6, R6),            
        asm_add(R7, R4, R0),
        asm_ldr(R7, R7),            
        # SF16 Addition using ACT instruction with func=0 (No activation, just bias add)
        # Rd is 0 (R0), Rs is R6, Rt is R7
        asm_act(8, R6, R7), # R8 = R6 + R7
        asm_add(R9, R5, R0),
        asm_str(R9, R8),
        asm_ret(),
    ]

@cocotb.test()
async def test_resnet_block_gpu(dut):
    """
    Simulates a ResNet BasicBlock forward pass: output = ReLU(Conv(x) + shortcut)
    We use a small 4x4 matrix representation to fit within simulation time.
    """
    N = 4 # 4x4 problem size
    
    # 1. Generate Input Data
    x_f = [random.uniform(-0.5, 0.5) for _ in range(N * N)]
    w_f = [random.uniform(-0.5, 0.5) for _ in range(N * N)]
    shortcut_f = [random.uniform(-0.5, 0.5) for _ in range(N * N)]
    
    x_q = [float_to_q115(v) for v in x_f]
    w_q = [float_to_q115(v) for v in w_f]
    shortcut_q = [float_to_q115(v) for v in shortcut_f]
    
    # Calculate Expected Python Output
    conv_expected = q115_matmul(x_q, w_q, N, N, N)
    add_expected = [q115_add(c, s) for c, s in zip(conv_expected, shortcut_q)]
    final_expected = [q115_relu(v) for v in add_expected]
    
    # Memory Map
    base_x = 0
    base_w = N * N
    base_conv_out = 2 * N * N
    base_shortcut = 3 * N * N
    base_final_out = 4 * N * N
    
    data = [0] * (5 * N * N)
    for i in range(N * N):
        data[base_x + i] = x_q[i]
        data[base_w + i] = w_q[i]
        data[base_shortcut + i] = shortcut_q[i]
        
    # --- STEP 1: CONVOLUTION (MATMUL) ---
    program_conv = build_matmul_kernel(N, base_x, base_w, base_conv_out)
    
    logger = await setup_test(
        dut,
        test_name="resnet_conv",
        program=program_conv,
        data=data,
        thread_count=((N * N + 3) // 4) * 4,
        verbose=False
    )
    
    await run_kernel(dut, logger, max_cycles=2000, trace_interval=0)
    await ClockCycles(dut.clk, 10)
    
    conv_out_raw = read_memory_range(dut, base_conv_out, N * N)
    assert conv_out_raw == conv_expected, "ResNet Conv (MatMul) failed!"
    logger.close()
    
    # --- STEP 2: RESIDUAL ADDITION ---
    # We load the conv_out back into 'data' so the testbench has updated memory
    for i in range(N * N):
        data[base_conv_out + i] = conv_out_raw[i]
        
    program_add = build_add_bias_kernel(base_conv_out, base_shortcut, base_conv_out, N * N)
    
    logger2 = await setup_test(
        dut,
        test_name="resnet_residual_add",
        program=program_add,
        data=data,
        thread_count=((N * N + 3) // 4) * 4,
        verbose=False
    )
    
    await run_kernel(dut, logger2, max_cycles=500, trace_interval=0)
    await ClockCycles(dut.clk, 10)
    
    add_out_raw = read_memory_range(dut, base_conv_out, N * N)
    assert add_out_raw == add_expected, "ResNet Residual Add failed!"
    logger2.close()
    
    # --- STEP 3: RELU ---
    for i in range(N * N):
        data[base_conv_out + i] = add_out_raw[i]
        
    program_relu = build_relu_kernel(base_conv_out, base_final_out, N * N)
    
    logger3 = await setup_test(
        dut,
        test_name="resnet_relu",
        program=program_relu,
        data=data,
        thread_count=((N * N + 3) // 4) * 4,
        verbose=False
    )
    
    await run_kernel(dut, logger3, max_cycles=500, trace_interval=0)
    await ClockCycles(dut.clk, 10)
    
    final_out_raw = read_memory_range(dut, base_final_out, N * N)
    assert final_out_raw == final_expected, "ResNet ReLU failed!"
    logger3.close()
    
    print("="*60)
    print("ResNet-20 Basic Block GPU Test: ALL PASSED")
    print("="*60)
