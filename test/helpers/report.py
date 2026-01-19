"""
Test Report Generator for Atreides GPU

Generates summary reports from test logs and VCD files.
"""

import os
import re
import json
from datetime import datetime
from pathlib import Path


class TestReportGenerator:
    """
    Generates HTML and text reports from test results.
    """
    
    def __init__(self, results_dir: str = "test/results", waves_dir: str = "build/waves"):
        self.results_dir = Path(results_dir)
        self.waves_dir = Path(waves_dir)
        self.test_results = {}
        
    def scan_logs(self):
        """Scan log files for test results."""
        if not self.results_dir.exists():
            return
            
        for log_file in self.results_dir.glob("*_latest.log"):
            test_name = log_file.stem.replace("_latest", "")
            result = self._parse_log(log_file)
            self.test_results[test_name] = result
    
    def _parse_log(self, log_path: Path) -> dict:
        """Parse a log file for test results."""
        result = {
            'name': log_path.stem,
            'timestamp': None,
            'passed': None,
            'tests': [],
            'log_path': str(log_path),
        }
        
        try:
            with open(log_path, 'r') as f:
                content = f.read()
                
            # Look for timestamp
            time_match = re.search(r'Time: (\d{4}-\d{2}-\d{2}T[\d:]+)', content)
            if time_match:
                result['timestamp'] = time_match.group(1)
            
            # Look for pass/fail
            if 'TEST PASSED' in content:
                result['passed'] = True
            elif 'TEST FAILED' in content:
                result['passed'] = False
                
            # Count individual test results
            pass_count = len(re.findall(r'\[PASS\]', content))
            fail_count = len(re.findall(r'\[FAIL\]', content))
            result['pass_count'] = pass_count
            result['fail_count'] = fail_count
                
        except Exception as e:
            result['error'] = str(e)
            
        return result
    
    def scan_vcd_files(self):
        """Scan for VCD waveform files."""
        if not self.waves_dir.exists():
            return {}
            
        vcd_files = {}
        for vcd_file in self.waves_dir.glob("*.vcd"):
            module_name = vcd_file.stem
            vcd_files[module_name] = {
                'path': str(vcd_file),
                'size': vcd_file.stat().st_size,
                'modified': datetime.fromtimestamp(vcd_file.stat().st_mtime).isoformat(),
            }
        return vcd_files
    
    def generate_text_report(self) -> str:
        """Generate a text summary report."""
        lines = [
            "=" * 80,
            "ATREIDES GPU TEST SUMMARY REPORT",
            f"Generated: {datetime.now().isoformat()}",
            "=" * 80,
            "",
        ]
        
        # Test Results Summary
        self.scan_logs()
        
        total_tests = len(self.test_results)
        passed_tests = sum(1 for r in self.test_results.values() if r.get('passed'))
        failed_tests = sum(1 for r in self.test_results.values() if r.get('passed') is False)
        unknown_tests = total_tests - passed_tests - failed_tests
        
        lines.append("TEST RESULTS SUMMARY")
        lines.append("-" * 40)
        lines.append(f"  Total Tests:  {total_tests}")
        lines.append(f"  Passed:       {passed_tests}")
        lines.append(f"  Failed:       {failed_tests}")
        lines.append(f"  Unknown:      {unknown_tests}")
        lines.append("")
        
        # Per-Module Results
        lines.append("PER-MODULE RESULTS")
        lines.append("-" * 40)
        
        for name, result in sorted(self.test_results.items()):
            status = "PASS" if result.get('passed') else "FAIL" if result.get('passed') is False else "????"
            pass_count = result.get('pass_count', 0)
            fail_count = result.get('fail_count', 0)
            lines.append(f"  {name:30} [{status}] ({pass_count} passed, {fail_count} failed)")
        
        lines.append("")
        
        # VCD Files
        vcd_files = self.scan_vcd_files()
        if vcd_files:
            lines.append("WAVEFORM FILES")
            lines.append("-" * 40)
            for name, info in sorted(vcd_files.items()):
                size_kb = info['size'] / 1024
                lines.append(f"  {name:20} {size_kb:8.1f} KB  {info['modified']}")
            lines.append("")
        
        lines.append("=" * 80)
        
        return "\n".join(lines)
    
    def generate_html_report(self) -> str:
        """Generate an HTML summary report."""
        self.scan_logs()
        vcd_files = self.scan_vcd_files()
        
        total_tests = len(self.test_results)
        passed_tests = sum(1 for r in self.test_results.values() if r.get('passed'))
        failed_tests = sum(1 for r in self.test_results.values() if r.get('passed') is False)
        
        html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Atreides GPU Test Report</title>
    <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; margin: 40px; background: #1a1a2e; color: #eee; }}
        h1 {{ color: #00d4ff; border-bottom: 2px solid #00d4ff; padding-bottom: 10px; }}
        h2 {{ color: #a0a0ff; margin-top: 30px; }}
        .summary {{ display: flex; gap: 20px; margin: 20px 0; }}
        .summary-card {{ background: #16213e; padding: 20px; border-radius: 8px; min-width: 150px; text-align: center; }}
        .summary-card.pass {{ border-left: 4px solid #00ff88; }}
        .summary-card.fail {{ border-left: 4px solid #ff4444; }}
        .summary-card.total {{ border-left: 4px solid #00d4ff; }}
        .summary-number {{ font-size: 36px; font-weight: bold; }}
        .summary-label {{ color: #888; }}
        table {{ border-collapse: collapse; width: 100%; margin: 20px 0; }}
        th, td {{ padding: 12px 15px; text-align: left; border-bottom: 1px solid #333; }}
        th {{ background: #16213e; color: #00d4ff; }}
        tr:hover {{ background: #1f2f4f; }}
        .pass {{ color: #00ff88; }}
        .fail {{ color: #ff4444; }}
        .badge {{ padding: 4px 12px; border-radius: 4px; font-weight: bold; }}
        .badge.pass {{ background: #003322; color: #00ff88; }}
        .badge.fail {{ background: #330000; color: #ff4444; }}
        .timestamp {{ color: #666; font-size: 14px; }}
    </style>
</head>
<body>
    <h1>Atreides GPU Test Report</h1>
    <p class="timestamp">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    
    <div class="summary">
        <div class="summary-card total">
            <div class="summary-number">{total_tests}</div>
            <div class="summary-label">Total Tests</div>
        </div>
        <div class="summary-card pass">
            <div class="summary-number">{passed_tests}</div>
            <div class="summary-label">Passed</div>
        </div>
        <div class="summary-card fail">
            <div class="summary-number">{failed_tests}</div>
            <div class="summary-label">Failed</div>
        </div>
    </div>
    
    <h2>Test Results</h2>
    <table>
        <tr>
            <th>Module</th>
            <th>Status</th>
            <th>Passed</th>
            <th>Failed</th>
            <th>Timestamp</th>
        </tr>
"""
        
        for name, result in sorted(self.test_results.items()):
            status = result.get('passed')
            status_class = 'pass' if status else 'fail' if status is False else ''
            status_text = 'PASS' if status else 'FAIL' if status is False else 'N/A'
            timestamp = result.get('timestamp', 'N/A')
            pass_count = result.get('pass_count', 0)
            fail_count = result.get('fail_count', 0)
            
            html += f"""        <tr>
            <td>{name}</td>
            <td><span class="badge {status_class}">{status_text}</span></td>
            <td class="pass">{pass_count}</td>
            <td class="fail">{fail_count}</td>
            <td>{timestamp}</td>
        </tr>
"""
        
        html += """    </table>
    
    <h2>Waveform Files</h2>
    <table>
        <tr>
            <th>Module</th>
            <th>File</th>
            <th>Size</th>
            <th>Modified</th>
        </tr>
"""
        
        for name, info in sorted(vcd_files.items()):
            size_kb = info['size'] / 1024
            html += f"""        <tr>
            <td>{name}</td>
            <td>{info['path']}</td>
            <td>{size_kb:.1f} KB</td>
            <td>{info['modified']}</td>
        </tr>
"""
        
        html += """    </table>
</body>
</html>
"""
        return html
    
    def save_reports(self, output_dir: str = "test/results"):
        """Save text and HTML reports."""
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        # Text report
        text_report = self.generate_text_report()
        with open(output_path / "test_summary.txt", 'w') as f:
            f.write(text_report)
        
        # HTML report
        html_report = self.generate_html_report()
        with open(output_path / "test_summary.html", 'w') as f:
            f.write(html_report)
        
        # JSON data
        json_data = {
            'generated': datetime.now().isoformat(),
            'results': self.test_results,
            'vcd_files': self.scan_vcd_files(),
        }
        with open(output_path / "test_results.json", 'w') as f:
            json.dump(json_data, f, indent=2)
        
        return text_report


def generate_report():
    """Generate test reports."""
    generator = TestReportGenerator()
    report = generator.save_reports()
    print(report)
    print(f"\nReports saved to test/results/")


if __name__ == "__main__":
    generate_report()

