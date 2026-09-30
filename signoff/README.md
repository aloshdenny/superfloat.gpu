# Signed-off OpenFrame runs

This directory holds the final views and signoff reports of the runs behind the three signed-off OpenFrame chips: SF16, FP16 and BF16. Each format has its core tile and its chip. The signoff results and the flow that produced them are described in `docs/openframe.md` (Hardening, Signoff results).

## Contents

| Path | Run | Source |
|---|---|---|
| `sf16/tile/` | `RUN_2026-09-29_00-38-54_eco` | `librelane/core_tile/runs/` |
| `sf16/chip/` | `chip_20_eco2` | `librelane/openframe/runs/` |
| `fp16/tile/` | `fp16_10r_eco5_s` | `librelane/core_tile/runs/` |
| `fp16/chip/` | `chip_fp16_1_eco_s` | `librelane/openframe/runs/` |
| `bf16/tile/` | `bf16_4_eco_s` | `librelane/core_tile/runs/` |
| `bf16/chip/` | `chip_bf16_2_eco4_s` | `librelane/openframe/runs/` |

- **Signoff continuation runs:** a run ending in `_s` is a signoff continuation, resumed from the post-route STA state of the ECO run before it.
- **Post-route STA reports:** that ECO run's post-route STA reports are included under `reports/<ECO run>/`.

Each run directory has:

- **`final/`:** LibreLane's final views: GDS, LEF, DEF, OpenDB, netlists (`nl`, `pnl`), SPEF, SDF, Liberty per corner, Magic view, SPICE, Verilog header and `metrics.json`/`metrics.csv`.
  - Only `final/gds` is kept of the three identical layouts; `klayout_gds` and `mag_gds` are left out.
- **`reports/`:**
  - each step's reports and logs (STA per corner, DRC, LVS, manufacturability);
  - `resolved.json`, the complete configuration the run used, including its ECO buffers.

The tile directories also have `timing_model/`. It holds the tile's Liberty views regenerated with `model.sdc` (`librelane/core_tile/timing_model.sh`), which the chip was timed against.

Intermediate step databases are not included; the final views are enough to reproduce signoff.

## Files stored in parts

GitHub rejects files over 100 MB, so every file larger than 95 MB is stored as `<name>.part-000`, `<name>.part-001`, and so on. To rebuild them and check each against `SHA256SUMS`:

```bash
./join.sh
```

The rebuilt files are listed in `.gitignore`, so they stay out of git.

## Tools

| Tool | Version |
|---|---|
| LibreLane | `9552976` (2026-09-28), Classic flow |
| OpenROAD | `dcf36133` |
| Magic | 8.3.677 |
| PDK | sky130A `1689ac3f2dc763876eaf967227c7dfe831b031ae` |
