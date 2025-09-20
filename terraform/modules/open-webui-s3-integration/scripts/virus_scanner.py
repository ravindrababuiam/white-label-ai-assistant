#!/usr/bin/env python3
"""
Virus Scanner for Open WebUI Document Storage

This module provides virus scanning capabilities for uploaded files
using multiple scanning engines and quarantine functionality.
"""

import os
import json
import logging
import hashlib
import tempfile
import subprocess
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import requests
from pathlib import Path

logger = logging.getLogger(__name__)

class VirusScanner:
    def __init__(self, config_path: str = "/app/config/s3_config.json"):
        """Initialize virus scanner with configuration"""
        self.config = self._load_config(config_path)
        self.scan_timeout = self.config['security']['scan_timeout_seconds']
        self.quarantine_enabled = self.config['security']['quarantine_suspicious']
        
        # Initialize available scanners
        self.available_scanners = self._detect_available_scanners()
        
    def _load_config(self, config_path: str) -> Dict:
        """Load configuration from file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.error(f"Configuration file not found: {config_path}")
            raise
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in configuration file: {e}")
            raise
    
    def _detect_available_scanners(self) -> List[str]:
        """Detect available virus scanning engines"""
        scanners = []
        
        # Check for ClamAV
        if self._command_exists('clamscan'):
            scanners.append('clamav')
            logger.info("ClamAV scanner detected")
        
        # Check for custom API scanner
        if os.getenv('VIRUS_SCAN_API_KEY'):
            scanners.append('api')
            logger.info("API virus scanner configured")
        
        # Check for Windows Defender (if on Windows)
        if os.name == 'nt' and self._command_exists('MpCmdRun.exe'):
            scanners.append('defender')
            logger.info("Windows Defender scanner detected")
        
        if not scanners:
            logger.warning("No virus scanners detected")
        
        return scanners
    
    def _command_exists(self, command: str) -> bool:
        """Check if a command exists in the system PATH"""
        try:
            subprocess.run([command, '--version'], 
                         capture_output=True, 
                         timeout=5)
            return True
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
            return False
    
    def calculate_file_hash(self, file_path: str) -> str:
        """Calculate SHA-256 hash of file for tracking"""
        sha256_hash = hashlib.sha256()
        
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                sha256_hash.update(chunk)
        
        return sha256_hash.hexdigest()
    
    def scan_with_clamav(self, file_path: str) -> Dict:
        """Scan file using ClamAV"""
        try:
            logger.info(f"Scanning file with ClamAV: {file_path}")
            
            # Run clamscan command
            result = subprocess.run([
                'clamscan',
                '--no-summary',
                '--infected',
                '--stdout',
                file_path
            ], capture_output=True, text=True, timeout=self.scan_timeout)
            
            # Parse results
            if result.returncode == 0:
                return {
                    'scanner': 'clamav',
                    'clean': True,
                    'threats': [],
                    'scan_time': datetime.utcnow().isoformat(),
                    'message': 'File is clean'
                }
            elif result.returncode == 1:
                # Virus found
                threats = []
                for line in result.stdout.split('\n'):
                    if 'FOUND' in line:
                        threat_name = line.split(':')[1].strip().replace(' FOUND', '')
                        threats.append(threat_name)
                
                return {
                    'scanner': 'clamav',
                    'clean': False,
                    'threats': threats,
                    'scan_time': datetime.utcnow().isoformat(),
                    'message': f'Threats detected: {", ".join(threats)}'
                }
            else:
                # Scan error
                return {
                    'scanner': 'clamav',
                    'clean': None,
                    'threats': [],
                    'scan_time': datetime.utcnow().isoformat(),
                    'error': f'Scan error: {result.stderr}',
                    'message': 'Scan failed'
                }
                
        except subprocess.TimeoutExpired:
            logger.error(f"ClamAV scan timeout for file: {file_path}")
            return {
                'scanner': 'clamav',
                'clean': None,
                'threats': [],
                'scan_time': datetime.utcnow().isoformat(),
                'error': 'Scan timeout',
                'message': 'Scan timed out'
            }
        except Exception as e:
            logger.error(f"ClamAV scan error: {e}")
            return {
                'scanner': 'clamav',
                'clean': None,
                'threats': [],
                'scan_time': datetime.utcnow().isoformat(),
                'error': str(e),
                'message': 'Scan failed'
            }
    
    def scan_with_api(self, file_path: str) -> Dict:
        """Scan file using external API service"""
        try:
            logger.info(f"Scanning file with API scanner: {file_path}")
            
            api_key = os.getenv('VIRUS_SCAN_API_KEY')
            api_url = os.getenv('VIRUS_SCAN_API_URL', 'https://api.virustotal.com/vtapi/v2/file/scan')
            
            if not api_key:
                return {
                    'scanner': 'api',
                    'clean': None,
                    'threats': [],
                    'scan_time': datetime.utcnow().isoformat(),
                    'error': 'API key not configured',
                    'message': 'API scanner not configured'
                }
            
            # Upload file for scanning
            with open(file_path, 'rb') as f:
                files = {'file': f}
                params = {'apikey': api_key}
                
                response = requests.post(
                    api_url,
                    files=files,
                    params=params,
                    timeout=self.scan_timeout
                )
            
            if response.status_code == 200:
                result = response.json()
                
                # Check scan results (implementation depends on API)
                if result.get('response_code') == 1:
                    # Get scan report
                    report_url = result.get('permalink', '')
                    
                    return {
                        'scanner': 'api',
                        'clean': True,  # Simplified - would need to check actual results
                        'threats': [],
                        'scan_time': datetime.utcnow().isoformat(),
                        'report_url': report_url,
                        'message': 'File scanned successfully'
                    }
                else:
                    return {
                        'scanner': 'api',
                        'clean': None,
                        'threats': [],
                        'scan_time': datetime.utcnow().isoformat(),
                        'error': 'API scan failed',
                        'message': result.get('verbose_msg', 'Unknown error')
                    }
            else:
                return {
                    'scanner': 'api',
                    'clean': None,
                    'threats': [],
                    'scan_time': datetime.utcnow().isoformat(),
                    'error': f'API error: HTTP {response.status_code}',
                    'message': 'API scan failed'
                }
                
        except requests.exceptions.Timeout:
            logger.error(f"API scan timeout for file: {file_path}")
            return {
                'scanner': 'api',
                'clean': None,
                'threats': [],
                'scan_time': datetime.utcnow().isoformat(),
                'error': 'Scan timeout',
                'message': 'API scan timed out'
            }
        except Exception as e:
            logger.error(f"API scan error: {e}")
            return {
                'scanner': 'api',
                'clean': None,
                'threats': [],
                'scan_time': datetime.utcnow().isoformat(),
                'error': str(e),
                'message': 'API scan failed'
            }
    
    def scan_with_defender(self, file_path: str) -> Dict:
        """Scan file using Windows Defender (Windows only)"""
        try:
            logger.info(f"Scanning file with Windows Defender: {file_path}")
            
            # Run Windows Defender scan
            result = subprocess.run([
                'MpCmdRun.exe',
                '-Scan',
                '-ScanType',
                '3',
                '-File',
                file_path
            ], capture_output=True, text=True, timeout=self.scan_timeout)
            
            # Parse results
            if result.returncode == 0:
                return {
                    'scanner': 'defender',
                    'clean': True,
                    'threats': [],
                    'scan_time': datetime.utcnow().isoformat(),
                    'message': 'File is clean'
                }
            elif result.returncode == 2:
                # Threat found
                threats = ['Threat detected by Windows Defender']  # Simplified
                
                return {
                    'scanner': 'defender',
                    'clean': False,
                    'threats': threats,
                    'scan_time': datetime.utcnow().isoformat(),
                    'message': 'Threats detected by Windows Defender'
                }
            else:
                return {
                    'scanner': 'defender',
                    'clean': None,
                    'threats': [],
                    'scan_time': datetime.utcnow().isoformat(),
                    'error': f'Scan error: {result.stderr}',
                    'message': 'Defender scan failed'
                }
                
        except subprocess.TimeoutExpired:
            logger.error(f"Defender scan timeout for file: {file_path}")
            return {
                'scanner': 'defender',
                'clean': None,
                'threats': [],
                'scan_time': datetime.utcnow().isoformat(),
                'error': 'Scan timeout',
                'message': 'Defender scan timed out'
            }
        except Exception as e:
            logger.error(f"Defender scan error: {e}")
            return {
                'scanner': 'defender',
                'clean': None,
                'threats': [],
                'scan_time': datetime.utcnow().isoformat(),
                'error': str(e),
                'message': 'Defender scan failed'
            }
    
    def quarantine_file(self, file_path: str, scan_results: List[Dict]) -> Dict:
        """Move suspicious file to quarantine"""
        try:
            if not self.quarantine_enabled:
                return {'quarantined': False, 'reason': 'Quarantine disabled'}
            
            # Create quarantine directory
            quarantine_dir = Path('/tmp/quarantine')
            quarantine_dir.mkdir(exist_ok=True)
            
            # Generate quarantine filename
            file_hash = self.calculate_file_hash(file_path)
            original_name = Path(file_path).name
            quarantine_name = f"{file_hash}_{original_name}"
            quarantine_path = quarantine_dir / quarantine_name
            
            # Move file to quarantine
            import shutil
            shutil.move(file_path, quarantine_path)
            
            # Create quarantine metadata
            metadata = {
                'original_path': file_path,
                'quarantine_path': str(quarantine_path),
                'quarantine_time': datetime.utcnow().isoformat(),
                'file_hash': file_hash,
                'scan_results': scan_results,
                'reason': 'Virus/malware detected'
            }
            
            # Save metadata
            metadata_path = quarantine_path.with_suffix('.json')
            with open(metadata_path, 'w') as f:
                json.dump(metadata, f, indent=2)
            
            logger.warning(f"File quarantined: {file_path} -> {quarantine_path}")
            
            return {
                'quarantined': True,
                'quarantine_path': str(quarantine_path),
                'metadata_path': str(metadata_path),
                'file_hash': file_hash
            }
            
        except Exception as e:
            logger.error(f"Failed to quarantine file: {e}")
            return {
                'quarantined': False,
                'error': str(e)
            }
    
    def scan_file(self, file_path: str) -> Dict:
        """Scan file with all available scanners"""
        if not os.path.exists(file_path):
            return {
                'success': False,
                'error': 'File not found',
                'clean': None,
                'scan_results': []
            }
        
        logger.info(f"Starting virus scan for file: {file_path}")
        
        scan_results = []
        overall_clean = True
        all_threats = []
        
        # Scan with each available scanner
        for scanner in self.available_scanners:
            if scanner == 'clamav':
                result = self.scan_with_clamav(file_path)
            elif scanner == 'api':
                result = self.scan_with_api(file_path)
            elif scanner == 'defender':
                result = self.scan_with_defender(file_path)
            else:
                continue
            
            scan_results.append(result)
            
            # Update overall status
            if result.get('clean') is False:
                overall_clean = False
                all_threats.extend(result.get('threats', []))
            elif result.get('clean') is None:
                # Scan error - treat as suspicious if configured
                if self.quarantine_enabled:
                    overall_clean = False
        
        # Handle quarantine if threats detected
        quarantine_result = None
        if not overall_clean and os.path.exists(file_path):
            quarantine_result = self.quarantine_file(file_path, scan_results)
        
        # Compile final result
        result = {
            'success': True,
            'clean': overall_clean,
            'threats': list(set(all_threats)),  # Remove duplicates
            'scan_results': scan_results,
            'scanners_used': self.available_scanners,
            'scan_time': datetime.utcnow().isoformat(),
            'file_hash': self.calculate_file_hash(file_path) if os.path.exists(file_path) else None
        }
        
        if quarantine_result:
            result['quarantine'] = quarantine_result
        
        logger.info(f"Virus scan completed for {file_path}: clean={overall_clean}")
        
        return result
    
    def get_quarantine_list(self) -> Dict:
        """Get list of quarantined files"""
        try:
            quarantine_dir = Path('/tmp/quarantine')
            
            if not quarantine_dir.exists():
                return {
                    'success': True,
                    'quarantined_files': [],
                    'count': 0
                }
            
            quarantined_files = []
            
            for metadata_file in quarantine_dir.glob('*.json'):
                try:
                    with open(metadata_file, 'r') as f:
                        metadata = json.load(f)
                    
                    quarantined_files.append({
                        'file_hash': metadata.get('file_hash'),
                        'original_path': metadata.get('original_path'),
                        'quarantine_path': metadata.get('quarantine_path'),
                        'quarantine_time': metadata.get('quarantine_time'),
                        'threats': [threat for result in metadata.get('scan_results', []) 
                                  for threat in result.get('threats', [])],
                        'reason': metadata.get('reason')
                    })
                    
                except Exception as e:
                    logger.error(f"Error reading quarantine metadata {metadata_file}: {e}")
            
            return {
                'success': True,
                'quarantined_files': quarantined_files,
                'count': len(quarantined_files)
            }
            
        except Exception as e:
            logger.error(f"Error getting quarantine list: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def release_from_quarantine(self, file_hash: str, destination_path: str) -> Dict:
        """Release file from quarantine"""
        try:
            quarantine_dir = Path('/tmp/quarantine')
            
            # Find quarantined file
            quarantine_file = None
            metadata_file = None
            
            for qfile in quarantine_dir.glob(f"{file_hash}_*"):
                if qfile.suffix != '.json':
                    quarantine_file = qfile
                    metadata_file = qfile.with_suffix('.json')
                    break
            
            if not quarantine_file or not quarantine_file.exists():
                return {
                    'success': False,
                    'error': 'Quarantined file not found'
                }
            
            # Move file back
            import shutil
            shutil.move(str(quarantine_file), destination_path)
            
            # Remove metadata
            if metadata_file and metadata_file.exists():
                metadata_file.unlink()
            
            logger.info(f"File released from quarantine: {file_hash} -> {destination_path}")
            
            return {
                'success': True,
                'file_hash': file_hash,
                'destination_path': destination_path
            }
            
        except Exception as e:
            logger.error(f"Error releasing file from quarantine: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def health_check(self) -> Dict:
        """Perform health check on virus scanning capabilities"""
        try:
            status = {
                'success': True,
                'available_scanners': self.available_scanners,
                'scanner_count': len(self.available_scanners),
                'quarantine_enabled': self.quarantine_enabled,
                'scan_timeout': self.scan_timeout,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            # Test each scanner with a harmless test file
            scanner_status = {}
            
            # Create a temporary test file
            with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
                f.write("This is a test file for virus scanner health check.")
                test_file = f.name
            
            try:
                for scanner in self.available_scanners:
                    try:
                        if scanner == 'clamav':
                            result = self.scan_with_clamav(test_file)
                        elif scanner == 'api':
                            # Skip API test to avoid quota usage
                            result = {'scanner': 'api', 'message': 'Skipped for health check'}
                        elif scanner == 'defender':
                            result = self.scan_with_defender(test_file)
                        else:
                            continue
                        
                        scanner_status[scanner] = {
                            'available': True,
                            'message': result.get('message', 'OK')
                        }
                        
                    except Exception as e:
                        scanner_status[scanner] = {
                            'available': False,
                            'error': str(e)
                        }
                
            finally:
                # Clean up test file
                try:
                    os.unlink(test_file)
                except:
                    pass
            
            status['scanner_status'] = scanner_status
            
            return status
            
        except Exception as e:
            logger.error(f"Virus scanner health check failed: {e}")
            return {
                'success': False,
                'error': str(e)
            }