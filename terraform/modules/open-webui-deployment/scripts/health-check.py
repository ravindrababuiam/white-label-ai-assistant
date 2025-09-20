#!/usr/bin/env python3
"""
Open WebUI Health Check Script

This script performs comprehensive health checks for Open WebUI,
including API endpoints, database connectivity, and external service integration.
"""

import os
import sys
import time
import json
import logging
import requests
from urllib.parse import urlparse
import sqlite3
import psycopg2

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class HealthChecker:
    def __init__(self):
        self.base_url = os.getenv('WEBUI_URL', 'http://localhost:8080')
        self.database_url = os.getenv('DATABASE_URL', '')
        self.ollama_url = os.getenv('OLLAMA_BASE_URL', '')
        self.litellm_url = os.getenv('OPENAI_API_BASE_URL', '')
        self.qdrant_url = os.getenv('QDRANT_URL', '')
        self.s3_bucket = os.getenv('S3_BUCKET_NAME', '')
        
        self.session = requests.Session()
        self.session.timeout = 10
        
        # Health check results
        self.results = {
            'timestamp': time.time(),
            'overall_status': 'unknown',
            'checks': {}
        }

    def check_web_interface(self):
        """Check if the web interface is responding"""
        logger.info("Checking web interface...")
        
        try:
            # Check main health endpoint
            response = self.session.get(f"{self.base_url}/health")
            
            if response.status_code == 200:
                self.results['checks']['web_interface'] = {
                    'status': 'healthy',
                    'response_time': response.elapsed.total_seconds(),
                    'message': 'Web interface is responding'
                }
                logger.info("Web interface health check passed")
                return True
            else:
                self.results['checks']['web_interface'] = {
                    'status': 'unhealthy',
                    'response_time': response.elapsed.total_seconds(),
                    'message': f'HTTP {response.status_code}: {response.text[:100]}'
                }
                logger.error(f"Web interface health check failed: HTTP {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            self.results['checks']['web_interface'] = {
                'status': 'unhealthy',
                'message': f'Connection error: {str(e)}'
            }
            logger.error(f"Web interface health check failed: {e}")
            return False

    def check_api_endpoints(self):
        """Check critical API endpoints"""
        logger.info("Checking API endpoints...")
        
        endpoints = [
            ('/api/v1/auths', 'Authentication API'),
            ('/api/v1/models', 'Models API'),
            ('/api/v1/chats', 'Chats API'),
            ('/api/v1/documents', 'Documents API')
        ]
        
        healthy_endpoints = 0
        total_endpoints = len(endpoints)
        
        for endpoint, description in endpoints:
            try:
                response = self.session.get(f"{self.base_url}{endpoint}")
                
                if response.status_code in [200, 401, 403]:  # 401/403 are OK for auth-protected endpoints
                    healthy_endpoints += 1
                    logger.debug(f"{description} endpoint is responding")
                else:
                    logger.warning(f"{description} endpoint returned HTTP {response.status_code}")
                    
            except requests.exceptions.RequestException as e:
                logger.warning(f"{description} endpoint check failed: {e}")
        
        health_ratio = healthy_endpoints / total_endpoints
        
        if health_ratio >= 0.8:  # 80% of endpoints must be healthy
            self.results['checks']['api_endpoints'] = {
                'status': 'healthy',
                'healthy_endpoints': healthy_endpoints,
                'total_endpoints': total_endpoints,
                'message': f'{healthy_endpoints}/{total_endpoints} API endpoints are responding'
            }
            logger.info("API endpoints health check passed")
            return True
        else:
            self.results['checks']['api_endpoints'] = {
                'status': 'unhealthy',
                'healthy_endpoints': healthy_endpoints,
                'total_endpoints': total_endpoints,
                'message': f'Only {healthy_endpoints}/{total_endpoints} API endpoints are responding'
            }
            logger.error("API endpoints health check failed")
            return False

    def check_database_connectivity(self):
        """Check database connectivity"""
        logger.info("Checking database connectivity...")
        
        if not self.database_url:
            self.results['checks']['database'] = {
                'status': 'skipped',
                'message': 'Database URL not configured'
            }
            logger.warning("Database URL not configured, skipping check")
            return True
        
        try:
            parsed_url = urlparse(self.database_url)
            db_type = parsed_url.scheme
            
            if db_type == 'sqlite':
                return self._check_sqlite_database(parsed_url.path)
            elif db_type in ['postgresql', 'postgres']:
                return self._check_postgresql_database()
            else:
                self.results['checks']['database'] = {
                    'status': 'unhealthy',
                    'message': f'Unsupported database type: {db_type}'
                }
                logger.error(f"Unsupported database type: {db_type}")
                return False
                
        except Exception as e:
            self.results['checks']['database'] = {
                'status': 'unhealthy',
                'message': f'Database check error: {str(e)}'
            }
            logger.error(f"Database connectivity check failed: {e}")
            return False

    def _check_sqlite_database(self, db_path):
        """Check SQLite database"""
        try:
            conn = sqlite3.connect(db_path, timeout=5)
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.fetchone()
            cursor.close()
            conn.close()
            
            self.results['checks']['database'] = {
                'status': 'healthy',
                'type': 'sqlite',
                'message': 'SQLite database is accessible'
            }
            logger.info("SQLite database health check passed")
            return True
            
        except Exception as e:
            self.results['checks']['database'] = {
                'status': 'unhealthy',
                'type': 'sqlite',
                'message': f'SQLite error: {str(e)}'
            }
            logger.error(f"SQLite database check failed: {e}")
            return False

    def _check_postgresql_database(self):
        """Check PostgreSQL database"""
        try:
            parsed_url = urlparse(self.database_url)
            
            conn = psycopg2.connect(
                host=parsed_url.hostname,
                port=parsed_url.port or 5432,
                database=parsed_url.path.lstrip('/'),
                user=parsed_url.username,
                password=parsed_url.password,
                connect_timeout=5
            )
            
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.fetchone()
            cursor.close()
            conn.close()
            
            self.results['checks']['database'] = {
                'status': 'healthy',
                'type': 'postgresql',
                'message': 'PostgreSQL database is accessible'
            }
            logger.info("PostgreSQL database health check passed")
            return True
            
        except Exception as e:
            self.results['checks']['database'] = {
                'status': 'unhealthy',
                'type': 'postgresql',
                'message': f'PostgreSQL error: {str(e)}'
            }
            logger.error(f"PostgreSQL database check failed: {e}")
            return False

    def check_ollama_integration(self):
        """Check Ollama service integration"""
        logger.info("Checking Ollama integration...")
        
        if not self.ollama_url:
            self.results['checks']['ollama'] = {
                'status': 'skipped',
                'message': 'Ollama URL not configured'
            }
            logger.warning("Ollama URL not configured, skipping check")
            return True
        
        try:
            # Check Ollama health
            response = self.session.get(f"{self.ollama_url}/api/tags")
            
            if response.status_code == 200:
                data = response.json()
                models = data.get('models', [])
                
                self.results['checks']['ollama'] = {
                    'status': 'healthy',
                    'response_time': response.elapsed.total_seconds(),
                    'models_count': len(models),
                    'message': f'Ollama is accessible with {len(models)} models'
                }
                logger.info(f"Ollama health check passed - {len(models)} models available")
                return True
            else:
                self.results['checks']['ollama'] = {
                    'status': 'unhealthy',
                    'message': f'Ollama returned HTTP {response.status_code}'
                }
                logger.error(f"Ollama health check failed: HTTP {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            self.results['checks']['ollama'] = {
                'status': 'unhealthy',
                'message': f'Ollama connection error: {str(e)}'
            }
            logger.error(f"Ollama health check failed: {e}")
            return False

    def check_litellm_integration(self):
        """Check LiteLLM service integration"""
        logger.info("Checking LiteLLM integration...")
        
        if not self.litellm_url:
            self.results['checks']['litellm'] = {
                'status': 'skipped',
                'message': 'LiteLLM URL not configured'
            }
            logger.warning("LiteLLM URL not configured, skipping check")
            return True
        
        try:
            # Check LiteLLM health
            response = self.session.get(f"{self.litellm_url}/health")
            
            if response.status_code == 200:
                self.results['checks']['litellm'] = {
                    'status': 'healthy',
                    'response_time': response.elapsed.total_seconds(),
                    'message': 'LiteLLM is accessible'
                }
                logger.info("LiteLLM health check passed")
                return True
            else:
                self.results['checks']['litellm'] = {
                    'status': 'unhealthy',
                    'message': f'LiteLLM returned HTTP {response.status_code}'
                }
                logger.error(f"LiteLLM health check failed: HTTP {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            self.results['checks']['litellm'] = {
                'status': 'unhealthy',
                'message': f'LiteLLM connection error: {str(e)}'
            }
            logger.error(f"LiteLLM health check failed: {e}")
            return False

    def check_qdrant_integration(self):
        """Check Qdrant vector database integration"""
        logger.info("Checking Qdrant integration...")
        
        if not self.qdrant_url:
            self.results['checks']['qdrant'] = {
                'status': 'skipped',
                'message': 'Qdrant URL not configured'
            }
            logger.warning("Qdrant URL not configured, skipping check")
            return True
        
        try:
            # Check Qdrant health
            response = self.session.get(f"{self.qdrant_url}/health")
            
            if response.status_code == 200:
                # Check collections
                collections_response = self.session.get(f"{self.qdrant_url}/collections")
                
                if collections_response.status_code == 200:
                    collections_data = collections_response.json()
                    collections = collections_data.get('result', {}).get('collections', [])
                    
                    self.results['checks']['qdrant'] = {
                        'status': 'healthy',
                        'response_time': response.elapsed.total_seconds(),
                        'collections_count': len(collections),
                        'message': f'Qdrant is accessible with {len(collections)} collections'
                    }
                    logger.info(f"Qdrant health check passed - {len(collections)} collections available")
                    return True
                else:
                    self.results['checks']['qdrant'] = {
                        'status': 'degraded',
                        'message': 'Qdrant is accessible but collections endpoint failed'
                    }
                    logger.warning("Qdrant collections endpoint failed")
                    return False
            else:
                self.results['checks']['qdrant'] = {
                    'status': 'unhealthy',
                    'message': f'Qdrant returned HTTP {response.status_code}'
                }
                logger.error(f"Qdrant health check failed: HTTP {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            self.results['checks']['qdrant'] = {
                'status': 'unhealthy',
                'message': f'Qdrant connection error: {str(e)}'
            }
            logger.error(f"Qdrant health check failed: {e}")
            return False

    def check_s3_integration(self):
        """Check S3 storage integration"""
        logger.info("Checking S3 integration...")
        
        if not self.s3_bucket:
            self.results['checks']['s3'] = {
                'status': 'skipped',
                'message': 'S3 bucket not configured'
            }
            logger.warning("S3 bucket not configured, skipping check")
            return True
        
        try:
            import boto3
            from botocore.exceptions import ClientError, NoCredentialsError
            
            s3_client = boto3.client('s3')
            
            # Test bucket access
            s3_client.head_bucket(Bucket=self.s3_bucket)
            
            self.results['checks']['s3'] = {
                'status': 'healthy',
                'bucket': self.s3_bucket,
                'message': f'S3 bucket {self.s3_bucket} is accessible'
            }
            logger.info(f"S3 health check passed - bucket {self.s3_bucket} is accessible")
            return True
            
        except NoCredentialsError:
            self.results['checks']['s3'] = {
                'status': 'unhealthy',
                'message': 'AWS credentials not configured'
            }
            logger.error("S3 health check failed: AWS credentials not configured")
            return False
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            self.results['checks']['s3'] = {
                'status': 'unhealthy',
                'message': f'S3 error: {error_code}'
            }
            logger.error(f"S3 health check failed: {error_code}")
            return False
            
        except ImportError:
            self.results['checks']['s3'] = {
                'status': 'skipped',
                'message': 'boto3 not available'
            }
            logger.warning("boto3 not available, skipping S3 check")
            return True
            
        except Exception as e:
            self.results['checks']['s3'] = {
                'status': 'unhealthy',
                'message': f'S3 check error: {str(e)}'
            }
            logger.error(f"S3 health check failed: {e}")
            return False

    def check_system_resources(self):
        """Check system resource usage"""
        logger.info("Checking system resources...")
        
        try:
            import psutil
            
            # Get CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            
            # Get memory usage
            memory = psutil.virtual_memory()
            memory_percent = memory.percent
            
            # Get disk usage
            disk = psutil.disk_usage('/')
            disk_percent = (disk.used / disk.total) * 100
            
            # Determine status based on resource usage
            status = 'healthy'
            warnings = []
            
            if cpu_percent > 90:
                status = 'degraded'
                warnings.append(f'High CPU usage: {cpu_percent:.1f}%')
            
            if memory_percent > 90:
                status = 'degraded'
                warnings.append(f'High memory usage: {memory_percent:.1f}%')
            
            if disk_percent > 90:
                status = 'degraded'
                warnings.append(f'High disk usage: {disk_percent:.1f}%')
            
            self.results['checks']['system_resources'] = {
                'status': status,
                'cpu_percent': cpu_percent,
                'memory_percent': memory_percent,
                'disk_percent': disk_percent,
                'warnings': warnings,
                'message': f'CPU: {cpu_percent:.1f}%, Memory: {memory_percent:.1f}%, Disk: {disk_percent:.1f}%'
            }
            
            if status == 'healthy':
                logger.info("System resources health check passed")
            else:
                logger.warning(f"System resources check degraded: {', '.join(warnings)}")
            
            return status == 'healthy'
            
        except ImportError:
            self.results['checks']['system_resources'] = {
                'status': 'skipped',
                'message': 'psutil not available'
            }
            logger.warning("psutil not available, skipping system resources check")
            return True
            
        except Exception as e:
            self.results['checks']['system_resources'] = {
                'status': 'unhealthy',
                'message': f'System resources check error: {str(e)}'
            }
            logger.error(f"System resources health check failed: {e}")
            return False

    def determine_overall_status(self):
        """Determine overall health status based on individual checks"""
        healthy_checks = 0
        total_checks = 0
        critical_failures = 0
        
        critical_checks = ['web_interface', 'database']
        
        for check_name, check_result in self.results['checks'].items():
            if check_result['status'] == 'skipped':
                continue
                
            total_checks += 1
            
            if check_result['status'] == 'healthy':
                healthy_checks += 1
            elif check_name in critical_checks and check_result['status'] == 'unhealthy':
                critical_failures += 1
        
        # Determine overall status
        if critical_failures > 0:
            self.results['overall_status'] = 'unhealthy'
        elif total_checks == 0:
            self.results['overall_status'] = 'unknown'
        elif healthy_checks / total_checks >= 0.8:  # 80% of checks must pass
            self.results['overall_status'] = 'healthy'
        else:
            self.results['overall_status'] = 'degraded'
        
        self.results['summary'] = {
            'healthy_checks': healthy_checks,
            'total_checks': total_checks,
            'critical_failures': critical_failures,
            'health_ratio': healthy_checks / total_checks if total_checks > 0 else 0
        }

    def run_all_checks(self):
        """Run all health checks"""
        logger.info("Starting comprehensive health check...")
        
        checks = [
            self.check_web_interface,
            self.check_api_endpoints,
            self.check_database_connectivity,
            self.check_ollama_integration,
            self.check_litellm_integration,
            self.check_qdrant_integration,
            self.check_s3_integration,
            self.check_system_resources
        ]
        
        for check in checks:
            try:
                check()
            except Exception as e:
                logger.error(f"Health check failed with exception: {e}")
        
        self.determine_overall_status()
        
        logger.info(f"Health check completed - Overall status: {self.results['overall_status']}")
        return self.results

    def output_results(self, format='json'):
        """Output health check results"""
        if format == 'json':
            print(json.dumps(self.results, indent=2))
        elif format == 'summary':
            print(f"Overall Status: {self.results['overall_status'].upper()}")
            print(f"Healthy Checks: {self.results['summary']['healthy_checks']}/{self.results['summary']['total_checks']}")
            
            for check_name, check_result in self.results['checks'].items():
                status_icon = {
                    'healthy': '✓',
                    'unhealthy': '✗',
                    'degraded': '⚠',
                    'skipped': '-'
                }.get(check_result['status'], '?')
                
                print(f"  {status_icon} {check_name}: {check_result['message']}")

def main():
    """Main health check function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Open WebUI Health Check')
    parser.add_argument('--format', choices=['json', 'summary'], default='json',
                       help='Output format (default: json)')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Run health checks
    checker = HealthChecker()
    results = checker.run_all_checks()
    
    # Output results
    checker.output_results(format=args.format)
    
    # Exit with appropriate code
    if results['overall_status'] == 'healthy':
        sys.exit(0)
    elif results['overall_status'] == 'degraded':
        sys.exit(1)
    else:  # unhealthy or unknown
        sys.exit(2)

if __name__ == "__main__":
    main()