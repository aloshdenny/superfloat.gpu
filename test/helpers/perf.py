"""
Performance Measurement Utilities for Atreides GPU

Provides GFLOPS computation, latency profiling, and formatted
performance reporting for matrix operations.
"""


def compute_gflops(M: int, N: int, K: int, cycles: int,
                   clock_period_ns: float = 10.0) -> float:
    """
    Compute GFLOPS for a matrix multiplication C = A×B.
    
    FLOPs for matmul = 2 * M * N * K (one multiply + one add per element).
    
    Args:
        M, N, K: Matrix dimensions (A is M×K, B is K×N)
        cycles: Number of clock cycles consumed
        clock_period_ns: Clock period in nanoseconds (default 10ns = 100MHz)
        
    Returns:
        GFLOPS (giga floating-point operations per second)
    """
    flops = 2 * M * N * K
    time_ns = cycles * clock_period_ns
    time_s = time_ns * 1e-9
    return (flops / time_s) / 1e9 if time_s > 0 else 0.0


class PerformanceReport:
    """Collects and formats performance metrics for a single test."""
    
    def __init__(self, name: str, M: int, N: int, K: int,
                 clock_period_ns: float = 10.0):
        self.name = name
        self.M = M
        self.N = N
        self.K = K
        self.clock_period_ns = clock_period_ns
        self.cycles = 0
        self.elements = M * N
        self.flops = 2 * M * N * K
    
    def record(self, cycles: int):
        """Record the cycle count for this workload."""
        self.cycles = cycles
    
    @property
    def gflops(self) -> float:
        return compute_gflops(self.M, self.N, self.K, self.cycles,
                              self.clock_period_ns)
    
    @property
    def latency_ns(self) -> float:
        return self.cycles * self.clock_period_ns
    
    @property
    def latency_us(self) -> float:
        return self.latency_ns / 1000.0
    
    @property
    def throughput_elements_per_cycle(self) -> float:
        return self.elements / self.cycles if self.cycles > 0 else 0.0
    
    @property
    def throughput_flops_per_cycle(self) -> float:
        return self.flops / self.cycles if self.cycles > 0 else 0.0
    
    def summary(self) -> str:
        """Single-line performance summary."""
        return (
            f"{self.name}: {self.M}×{self.K}×{self.N} "
            f"| {self.cycles} cycles "
            f"| {self.latency_us:.1f} µs "
            f"| {self.gflops:.4f} GFLOPS "
            f"| {self.throughput_elements_per_cycle:.3f} elem/cyc"
        )


def format_perf_table(reports: list) -> str:
    """
    Format a list of PerformanceReports as a Markdown-style table.
    
    Args:
        reports: List of PerformanceReport instances
        
    Returns:
        Formatted table string
    """
    lines = [
        "╔═══════════════════════════╤═════════╤══════════╤═══════════╤══════════════╤═══════════╗",
        "║ Test                      │ Size    │ Cycles   │ Latency   │ GFLOPS       │ Elem/Cyc  ║",
        "╠═══════════════════════════╪═════════╪══════════╪═══════════╪══════════════╪═══════════╣",
    ]
    
    for r in reports:
        size_str = f"{r.M}×{r.K}×{r.N}"
        lines.append(
            f"║ {r.name:<25} │ {size_str:<7} │ {r.cycles:>8} │ "
            f"{r.latency_us:>7.1f}µs │ {r.gflops:>12.6f} │ {r.throughput_elements_per_cycle:>9.4f} ║"
        )
    
    lines.append(
        "╚═══════════════════════════╧═════════╧══════════╧═══════════╧══════════════╧═══════════╝"
    )
    
    # IEEE fp32 equivalent throughput for comparison context
    lines.append("")
    lines.append("Note: GFLOPS computed assuming Q1.15 FMA = 2 FLOPs (1 mul + 1 add)")
    if reports:
        lines.append(f"Clock period: {reports[0].clock_period_ns:.1f} ns "
                      f"({1e3 / reports[0].clock_period_ns:.0f} MHz)")
    
    return "\n".join(lines)
