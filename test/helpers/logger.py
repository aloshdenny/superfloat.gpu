"""
Logging Utilities for Atreides GPU Simulation

Provides file and console logging for execution traces.
"""

import os
from datetime import datetime
from .format import format_trace, format_memory_dump, format_cycle_header


class GPULogger:
    """
    Logger for GPU simulation traces.
    
    Writes execution traces to both console and log files.
    """
    
    def __init__(self, test_name: str, log_dir: str = "test/logs"):
        """
        Initialize the logger.
        
        Args:
            test_name: Name of the test (used for log file naming)
            log_dir: Directory for log files
        """
        self.test_name = test_name
        self.log_dir = log_dir
        self.log_file = None
        self.verbose = True
        
        # Create log directory if it doesn't exist
        os.makedirs(log_dir, exist_ok=True)
        
        # Create log file with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_path = os.path.join(log_dir, f"{test_name}_{timestamp}.log")
        self.log_file = open(log_path, 'w')
        
        # Also create a "latest" symlink/copy
        latest_path = os.path.join(log_dir, f"{test_name}_latest.log")
        if os.path.exists(latest_path):
            os.remove(latest_path)
        try:
            os.symlink(os.path.basename(log_path), latest_path)
        except OSError:
            # Symlinks might not work on all platforms
            pass
        
        self._write_header()
    
    def _write_header(self):
        """Write the log file header."""
        header = [
            "=" * 80,
            f"Atreides GPU Simulation Trace",
            f"Test: {self.test_name}",
            f"Time: {datetime.now().isoformat()}",
            "=" * 80,
            ""
        ]
        self._write("\n".join(header))
    
    def _write(self, text: str):
        """Write to log file and optionally console."""
        if self.log_file:
            self.log_file.write(text + "\n")
            self.log_file.flush()
        if self.verbose:
            print(text)
    
    def log_cycle(self, cycle: int, cores: list):
        """
        Log a complete cycle trace.
        
        Args:
            cycle: Current cycle number
            cores: List of core data with thread states
        """
        trace = format_trace(cycle, cores)
        self._write(trace)
    
    def log_memory(self, memory: dict, start_addr: int = 0, count: int = 32, title: str = "Memory"):
        """
        Log a memory dump.
        
        Args:
            memory: Dictionary of address -> value
            start_addr: Starting address
            count: Number of addresses to show
            title: Title for the dump
        """
        dump = format_memory_dump(memory, start_addr, count, title)
        self._write(dump)
    
    def log_message(self, message: str):
        """Log a general message."""
        self._write(message)
    
    def log_section(self, title: str):
        """Log a section header."""
        self._write("")
        self._write("=" * 80)
        self._write(f"  {title}")
        self._write("=" * 80)
        self._write("")
    
    def log_result(self, passed: bool, expected: list, actual: list):
        """
        Log test results.
        
        Args:
            passed: Whether the test passed
            expected: Expected values
            actual: Actual values
        """
        self._write("")
        self._write("=" * 80)
        if passed:
            self._write("  TEST PASSED ✓")
        else:
            self._write("  TEST FAILED ✗")
        self._write("=" * 80)
        self._write(f"Expected: {expected}")
        self._write(f"Actual:   {actual}")
        self._write("")
    
    def set_verbose(self, verbose: bool):
        """Enable or disable console output."""
        self.verbose = verbose
    
    def close(self):
        """Close the log file."""
        if self.log_file:
            self.log_file.close()
            self.log_file = None
    
    def __del__(self):
        """Ensure log file is closed on destruction."""
        self.close()

