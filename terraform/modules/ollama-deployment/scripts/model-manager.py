#!/usr/bin/env python3
"""
Ollama Model Manager

This script manages Ollama models, including:
- Monitoring model usage and performance
- Automatic model loading/unloading based on usage patterns
- Model health checks and recovery
- Cleanup of unused models
"""

import json
import logging
import os
import sys
import time
import requests
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class OllamaModelManager:
    def __init__(self, host: str = "localhost:11434"):
        self.host = host
        self.base_url = f"http://{host}"
        self.check_interval = int(os.getenv("CHECK_INTERVAL", "300"))  # 5 minutes
        self.max_loaded_models = int(os.getenv("OLLAMA_MAX_LOADED_MODELS", "3"))
        
        # Configure session with retries
        self.session = requests.Session()
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        
        # Model usage tracking
        self.model_usage = {}
        self.model_last_used = {}
        self.model_load_times = {}

    def get_loaded_models(self) -> List[Dict[str, Any]]:
        """Get list of currently loaded models"""
        try:
            response = self.session.get(f"{self.base_url}/api/ps", timeout=10)
            if response.status_code == 200:
                data = response.json()
                return data.get("models", [])
            else:
                logger.error(f"Failed to get loaded models: {response.status_code}")
                return []
        except requests.exceptions.RequestException as e:
            logger.error(f"Error getting loaded models: {e}")
            return []

    def get_available_models(self) -> List[Dict[str, Any]]:
        """Get list of all available models"""
        try:
            response = self.session.get(f"{self.base_url}/api/tags", timeout=10)
            if response.status_code == 200:
                data = response.json()
                return data.get("models", [])
            else:
                logger.error(f"Failed to get available models: {response.status_code}")
                return []
        except requests.exceptions.RequestException as e:
            logger.error(f"Error getting available models: {e}")
            return []

    def load_model(self, model_name: str) -> bool:
        """Load a model into memory"""
        logger.info(f"Loading model: {model_name}")
        
        try:
            # Use a simple generate request to load the model
            payload = {
                "model": model_name,
                "prompt": "",
                "stream": False,
                "keep_alive": "5m"
            }
            
            response = self.session.post(
                f"{self.base_url}/api/generate",
                json=payload,
                timeout=60
            )
            
            if response.status_code == 200:
                logger.info(f"Successfully loaded model: {model_name}")
                self.model_load_times[model_name] = datetime.now()
                return True
            else:
                logger.error(f"Failed to load model {model_name}: {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Error loading model {model_name}: {e}")
            return False

    def unload_model(self, model_name: str) -> bool:
        """Unload a model from memory"""
        logger.info(f"Unloading model: {model_name}")
        
        try:
            # Use keep_alive=0 to unload the model
            payload = {
                "model": model_name,
                "keep_alive": 0
            }
            
            response = self.session.post(
                f"{self.base_url}/api/generate",
                json=payload,
                timeout=30
            )
            
            if response.status_code == 200:
                logger.info(f"Successfully unloaded model: {model_name}")
                if model_name in self.model_load_times:
                    del self.model_load_times[model_name]
                return True
            else:
                logger.error(f"Failed to unload model {model_name}: {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Error unloading model {model_name}: {e}")
            return False

    def get_model_info(self, model_name: str) -> Optional[Dict[str, Any]]:
        """Get detailed information about a model"""
        try:
            response = self.session.post(
                f"{self.base_url}/api/show",
                json={"name": model_name},
                timeout=10
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                logger.error(f"Failed to get model info for {model_name}: {response.status_code}")
                return None
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Error getting model info for {model_name}: {e}")
            return None

    def check_model_health(self, model_name: str) -> bool:
        """Check if a model is healthy and responding"""
        try:
            payload = {
                "model": model_name,
                "prompt": "test",
                "stream": False,
                "options": {"num_predict": 1}
            }
            
            response = self.session.post(
                f"{self.base_url}/api/generate",
                json=payload,
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                return "response" in data
            else:
                return False
                
        except requests.exceptions.RequestException:
            return False

    def manage_model_memory(self):
        """Manage model memory usage by loading/unloading models"""
        loaded_models = self.get_loaded_models()
        available_models = self.get_available_models()
        
        logger.info(f"Currently loaded models: {len(loaded_models)}")
        logger.info(f"Available models: {len(available_models)}")
        
        # If we have too many loaded models, unload the least recently used
        if len(loaded_models) > self.max_loaded_models:
            models_to_unload = len(loaded_models) - self.max_loaded_models
            logger.info(f"Need to unload {models_to_unload} models")
            
            # Sort by last used time (oldest first)
            sorted_models = sorted(
                loaded_models,
                key=lambda m: self.model_last_used.get(m["name"], datetime.min)
            )
            
            for i in range(models_to_unload):
                model_name = sorted_models[i]["name"]
                self.unload_model(model_name)

    def update_model_usage(self):
        """Update model usage statistics"""
        loaded_models = self.get_loaded_models()
        
        for model in loaded_models:
            model_name = model["name"]
            
            # Update usage count
            if model_name not in self.model_usage:
                self.model_usage[model_name] = 0
            
            # Update last used time (approximate based on being loaded)
            self.model_last_used[model_name] = datetime.now()

    def cleanup_old_models(self):
        """Clean up models that haven't been used in a while"""
        cutoff_time = datetime.now() - timedelta(hours=24)
        
        models_to_remove = []
        for model_name, last_used in self.model_last_used.items():
            if last_used < cutoff_time:
                models_to_remove.append(model_name)
        
        for model_name in models_to_remove:
            logger.info(f"Cleaning up unused model: {model_name}")
            self.unload_model(model_name)
            
            # Remove from tracking
            if model_name in self.model_usage:
                del self.model_usage[model_name]
            if model_name in self.model_last_used:
                del self.model_last_used[model_name]

    def health_check_models(self):
        """Perform health checks on loaded models"""
        loaded_models = self.get_loaded_models()
        
        for model in loaded_models:
            model_name = model["name"]
            
            if not self.check_model_health(model_name):
                logger.warning(f"Model {model_name} failed health check, attempting reload")
                
                # Try to reload the model
                if self.unload_model(model_name):
                    time.sleep(5)  # Wait a bit before reloading
                    self.load_model(model_name)

    def get_system_stats(self) -> Dict[str, Any]:
        """Get system statistics"""
        try:
            # Get memory info
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
            
            mem_total = 0
            mem_available = 0
            
            for line in meminfo.split('\n'):
                if line.startswith('MemTotal:'):
                    mem_total = int(line.split()[1]) * 1024  # Convert to bytes
                elif line.startswith('MemAvailable:'):
                    mem_available = int(line.split()[1]) * 1024  # Convert to bytes
            
            mem_used = mem_total - mem_available
            mem_usage_percent = (mem_used / mem_total * 100) if mem_total > 0 else 0
            
            # Get disk info
            import shutil
            disk_total, disk_used, disk_free = shutil.disk_usage('/models')
            disk_usage_percent = (disk_used / disk_total * 100) if disk_total > 0 else 0
            
            return {
                "memory": {
                    "total": mem_total,
                    "used": mem_used,
                    "available": mem_available,
                    "usage_percent": mem_usage_percent
                },
                "disk": {
                    "total": disk_total,
                    "used": disk_used,
                    "free": disk_free,
                    "usage_percent": disk_usage_percent
                }
            }
            
        except Exception as e:
            logger.error(f"Error getting system stats: {e}")
            return {}

    def log_status(self):
        """Log current status"""
        loaded_models = self.get_loaded_models()
        system_stats = self.get_system_stats()
        
        logger.info("=== Ollama Model Manager Status ===")
        logger.info(f"Loaded models: {len(loaded_models)}")
        
        for model in loaded_models:
            model_name = model["name"]
            size_gb = model.get("size", 0) / (1024**3)
            logger.info(f"  - {model_name}: {size_gb:.1f}GB")
        
        if system_stats:
            mem_stats = system_stats.get("memory", {})
            disk_stats = system_stats.get("disk", {})
            
            logger.info(f"Memory usage: {mem_stats.get('usage_percent', 0):.1f}%")
            logger.info(f"Disk usage: {disk_stats.get('usage_percent', 0):.1f}%")

    def run(self):
        """Main management loop"""
        logger.info("Starting Ollama Model Manager")
        
        while True:
            try:
                logger.debug("Running management cycle...")
                
                # Update usage statistics
                self.update_model_usage()
                
                # Manage memory usage
                self.manage_model_memory()
                
                # Health check models
                self.health_check_models()
                
                # Clean up old models (less frequently)
                if int(time.time()) % 3600 == 0:  # Every hour
                    self.cleanup_old_models()
                
                # Log status (less frequently)
                if int(time.time()) % 1800 == 0:  # Every 30 minutes
                    self.log_status()
                
                # Wait for next cycle
                time.sleep(self.check_interval)
                
            except KeyboardInterrupt:
                logger.info("Received interrupt signal, shutting down...")
                break
            except Exception as e:
                logger.error(f"Error in management cycle: {e}")
                time.sleep(60)  # Wait a minute before retrying

def main():
    """Main function"""
    host = os.getenv("OLLAMA_HOST", "localhost:11434")
    
    # Wait for Ollama to be ready
    manager = OllamaModelManager(host=host)
    
    logger.info("Waiting for Ollama to be ready...")
    max_attempts = 30
    for attempt in range(max_attempts):
        try:
            response = requests.get(f"http://{host}/api/tags", timeout=10)
            if response.status_code == 200:
                logger.info("Ollama is ready!")
                break
        except requests.exceptions.RequestException:
            pass
        
        if attempt == max_attempts - 1:
            logger.error("Ollama did not become ready, exiting...")
            sys.exit(1)
        
        time.sleep(10)
    
    # Start management
    manager.run()

if __name__ == "__main__":
    main()