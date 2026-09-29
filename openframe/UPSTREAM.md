# Vendored ChipFoundry OpenFrame files

These files are copied unmodified from ChipFoundry. They are licensed under Apache-2.0 (see `LICENSE`).

| Source | Revision | Files |
|---|---|---|
| github.com/chipfoundry/openframe_user_project | `fef97d5c468623f2b9c8ab59c557c31ef16bd64b` (main, 2026-09-28) | `openlane/openframe_project_wrapper/**`, `gds|lef|mag/v{cc,ss}d1_connection.*`, `verilog/rtl/v{cc,ss}d1_connection.v`, `mag/openframe_project_wrapper_empty.mag`, `LICENSE` |
| github.com/chipfoundry/CF_gpio_config | tag `CF_gpio_config-v1.1.4` | `ip/CF_gpio_config/rtl/CF_gpio_config.v` |

- `openlane/openframe_project_wrapper/fixed_dont_change/` fixes the wrapper die, pin locations and pad-ring interface. Precheck compares the finished layout against it and against `mag/openframe_project_wrapper_empty.mag`, so these files must stay unchanged.
- The rest of `openlane/openframe_project_wrapper/` is ChipFoundry's reference flow for their example timer. It is kept as a reference; the Atreides chip-level harden lives in `librelane/openframe/`.
