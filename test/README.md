# Atreides GPU Test Suite

Comprehensive unit tests for all RTL components using cocotb and Icarus Verilog.

## Overview

This test suite provides thorough verification of each GPU module with:
- Q1.15 fixed-point arithmetic verification
- VCD waveform generation for GTKWave
- Detailed logging and test reports
- Python reference implementations for comparison

## Directory Structure

```
test/
├── helpers/
│   ├── __init__.py
│   ├── format.py         # Output formatting utilities
│   ├── logger.py         # Test logging framework
│   ├── memory.py         # Memory init and assembly helpers
│   ├── q115.py           # Q1.15 reference implementations
│   ├── report.py         # Test report generator
│   └── setup.py          # Test setup utilities
├── gtkwave/              # GTKWave save files for each module
│   ├── fma.gtkw
│   ├── alu.gtkw
│   ├── activation.gtkw
│   ├── systolic_pe.gtkw
│   ├── systolic_array.gtkw
│   ├── cache.gtkw
│   ├── decoder.gtkw
│   └── lsu.gtkw
├── results/              # Test logs and reports (generated)
├── tb_fma.sv             # FMA unit testbench
├── tb_alu.sv             # ALU testbench
├── tb_activation.sv      # Activation unit testbench
├── tb_systolic_pe.sv     # Systolic PE testbench
├── tb_systolic_array.sv  # Systolic array testbench
├── tb_cache.sv           # Cache testbench
├── tb_decoder.sv         # Decoder testbench
├── tb_lsu.sv             # LSU testbench
├── tb_gpu.sv             # Full GPU testbench
├── test_fma_unit.py      # FMA tests
├── test_alu_unit.py      # ALU tests
├── test_activation_unit.py # Activation tests
├── test_systolic_pe_unit.py # Systolic PE tests
├── test_systolic_array_unit.py # Systolic array tests
├── test_cache_unit.py    # Cache tests
├── test_decoder_unit.py  # Decoder tests
├── test_lsu_unit.py      # LSU tests
├── test_matmul.py        # Matrix multiplication integration test
└── test_matadd.py        # Matrix addition integration test
```

## Running Tests

### Prerequisites

- Python 3.8+
- cocotb
- Icarus Verilog
- sv2v (SystemVerilog to Verilog converter)
- GTKWave (for waveform viewing)

### Individual Module Tests

```bash
# FMA Unit
make test_fma_unit

# ALU
make test_alu_unit

# Activation Unit
make test_activation_unit

# Systolic PE
make test_systolic_pe_unit

# Systolic Array
make test_systolic_array_unit

# Cache
make test_cache_unit

# Decoder
make test_decoder_unit

# LSU
make test_lsu_unit
```

### Run All Unit Tests

```bash
make test_all_units
```

### Integration Tests

```bash
# Matrix multiplication
make test_matmul

# Matrix addition
make test_matadd
```

## Viewing Waveforms

After running a test, VCD files are generated in `build/waves/`. View them with GTKWave:

```bash
# Using pre-configured save files
make waves_fma
make waves_alu
make waves_activation
make waves_systolic_pe
make waves_systolic_array
make waves_cache
make waves_decoder
make waves_lsu

# Or manually
gtkwave build/waves/fma.vcd test/gtkwave/fma.gtkw
```

## Test Reports

Generate summary reports:

```bash
python -m test.helpers.report
```

Reports are saved to:
- `test/results/test_summary.txt` - Text summary
- `test/results/test_summary.html` - HTML report
- `test/results/test_results.json` - JSON data

## Q1.15 Fixed-Point Format

All arithmetic tests use Q1.15 fixed-point format:
- 1 sign bit (bit 15)
- 15 fractional bits (bits 14:0)
- Range: [-1.0, +0.999969...]
- Resolution: 2^-15 ≈ 0.0000305

Python reference implementations in `helpers/q115.py`:
- `float_to_q115()` / `q115_to_float()` - Conversion
- `q115_add()` / `q115_sub()` - Addition/Subtraction
- `q115_mul()` - Multiplication
- `q115_fma()` - Fused multiply-add
- `q115_relu()` / `q115_leaky_relu()` / `q115_clipped_relu()` - Activations
- `q115_matmul()` / `q115_matmul_2d()` - Matrix multiplication

## Test Coverage

| Module | Tests | Description |
|--------|-------|-------------|
| FMA | 6 | Q1.15 multiply, accumulate, saturation, edge cases |
| ALU | 7 | ADD, SUB, MUL, DIV, CMP, indexing sequences |
| Activation | 7 | ReLU, Leaky ReLU, Clipped ReLU, bias, saturation |
| Systolic PE | 8 | Weight load, MAC, accumulation, passthrough, saturation |
| Systolic Array | 8 | 2x2, 4x4 matmul, identity, zeros, random |
| Cache | 7 | Hit, miss, replacement, sequential, random, timing |
| Decoder | 13 | All ISA opcodes, register addressing |
| LSU | 8 | Load, store, state machine, Q1.15 values, timing |

## Adding New Tests

1. Create a testbench wrapper in `test/tb_<module>.sv`
2. Create cocotb test file in `test/test_<module>_unit.py`
3. Add GTKWave save file in `test/gtkwave/<module>.gtkw`
4. Add Makefile targets for compilation and test execution

## Cleaning Up

```bash
# Remove generated files
make clean

# Remove only waveforms
make clean_waves
```

