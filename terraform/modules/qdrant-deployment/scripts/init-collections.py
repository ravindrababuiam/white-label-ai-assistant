#!/usr/bin/env python3
"""
Qdrant Collection Initialization Script

This script initializes Qdrant collections for document embeddings
based on the configuration provided in the ConfigMap.
"""

import json
import logging
import os
import sys
import time
from typing import Dict, List, Any
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class QdrantInitializer:
    def __init__(self, host: str = "localhost", port: int = 6333, api_key: str = None):
        self.host = host
        self.port = port
        self.api_key = api_key
        self.base_url = f"http://{host}:{port}"
        
        # Configure session with retries
        self.session = requests.Session()
        retry_strategy = Retry(
            total=5,
            backoff_factor=2,
            status_forcelist=[429, 500, 502, 503, 504],
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)
        
        # Set API key header if provided
        if self.api_key:
            self.session.headers.update({"api-key": self.api_key})

    def wait_for_qdrant(self, timeout: int = 300) -> bool:
        """Wait for Qdrant to be ready"""
        logger.info(f"Waiting for Qdrant at {self.base_url} to be ready...")
        
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                response = self.session.get(f"{self.base_url}/health", timeout=10)
                if response.status_code == 200:
                    logger.info("Qdrant is ready!")
                    return True
            except requests.exceptions.RequestException as e:
                logger.debug(f"Qdrant not ready yet: {e}")
            
            time.sleep(5)
        
        logger.error(f"Qdrant did not become ready within {timeout} seconds")
        return False

    def collection_exists(self, collection_name: str) -> bool:
        """Check if a collection exists"""
        try:
            response = self.session.get(f"{self.base_url}/collections/{collection_name}")
            return response.status_code == 200
        except requests.exceptions.RequestException:
            return False

    def create_collection(self, config: Dict[str, Any]) -> bool:
        """Create a Qdrant collection based on configuration"""
        collection_name = config["name"]
        
        if self.collection_exists(collection_name):
            logger.info(f"Collection '{collection_name}' already exists, skipping creation")
            return True
        
        logger.info(f"Creating collection '{collection_name}'...")
        
        # Prepare collection configuration
        collection_config = {
            "vectors": {
                "size": config["vector_size"],
                "distance": config["distance"]
            },
            "optimizers_config": {
                "default_segment_number": 2,
                "max_segment_size": 20000,
                "memmap_threshold": 20000,
                "indexing_threshold": 20000,
                "flush_interval_sec": 5,
                "max_optimization_threads": 1
            },
            "wal_config": {
                "wal_capacity_mb": 32,
                "wal_segments_ahead": 0
            },
            "hnsw_config": config.get("hnsw_config", {
                "m": 16,
                "ef_construct": 100,
                "full_scan_threshold": 20000
            }),
            "on_disk_payload": config.get("on_disk_payload", True)
        }
        
        try:
            response = self.session.put(
                f"{self.base_url}/collections/{collection_name}",
                json=collection_config,
                timeout=30
            )
            
            if response.status_code in [200, 201]:
                logger.info(f"Successfully created collection '{collection_name}'")
                return True
            else:
                logger.error(f"Failed to create collection '{collection_name}': {response.status_code} - {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Error creating collection '{collection_name}': {e}")
            return False

    def create_index(self, collection_name: str, field_name: str, field_type: str = "keyword") -> bool:
        """Create an index on a payload field"""
        logger.info(f"Creating index on field '{field_name}' in collection '{collection_name}'...")
        
        index_config = {
            "field_name": field_name,
            "field_schema": field_type
        }
        
        try:
            response = self.session.put(
                f"{self.base_url}/collections/{collection_name}/index",
                json=index_config,
                timeout=30
            )
            
            if response.status_code in [200, 201]:
                logger.info(f"Successfully created index on '{field_name}'")
                return True
            else:
                logger.error(f"Failed to create index: {response.status_code} - {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Error creating index: {e}")
            return False

    def setup_document_collection_indexes(self, collection_name: str) -> bool:
        """Set up standard indexes for document collection"""
        indexes = [
            ("document_id", "keyword"),
            ("filename", "keyword"),
            ("content_type", "keyword"),
            ("upload_timestamp", "datetime"),
            ("customer_id", "keyword"),
            ("tags", "keyword")
        ]
        
        success = True
        for field_name, field_type in indexes:
            if not self.create_index(collection_name, field_name, field_type):
                success = False
        
        return success

def load_collections_config() -> List[Dict[str, Any]]:
    """Load collections configuration from environment or default"""
    config_str = os.getenv("COLLECTIONS_CONFIG")
    
    if config_str:
        try:
            return json.loads(config_str)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse COLLECTIONS_CONFIG: {e}")
            sys.exit(1)
    
    # Default configuration
    return [
        {
            "name": "documents",
            "vector_size": 1536,  # OpenAI embedding size
            "distance": "Cosine",
            "on_disk_payload": True,
            "hnsw_config": {
                "m": 16,
                "ef_construct": 100,
                "full_scan_threshold": 20000
            }
        },
        {
            "name": "conversations",
            "vector_size": 1536,
            "distance": "Cosine",
            "on_disk_payload": True,
            "hnsw_config": {
                "m": 16,
                "ef_construct": 100,
                "full_scan_threshold": 10000
            }
        }
    ]

def main():
    """Main initialization function"""
    logger.info("Starting Qdrant collection initialization...")
    
    # Get configuration from environment
    host = os.getenv("QDRANT_HOST", "localhost")
    port = int(os.getenv("QDRANT_PORT", "6333"))
    api_key = os.getenv("QDRANT_API_KEY")
    
    # Initialize Qdrant client
    initializer = QdrantInitializer(host=host, port=port, api_key=api_key)
    
    # Wait for Qdrant to be ready
    if not initializer.wait_for_qdrant():
        logger.error("Qdrant is not ready, exiting...")
        sys.exit(1)
    
    # Load collections configuration
    collections_config = load_collections_config()
    logger.info(f"Loaded configuration for {len(collections_config)} collections")
    
    # Create collections
    success = True
    for config in collections_config:
        if not initializer.create_collection(config):
            success = False
        
        # Set up standard indexes for document collections
        if config["name"] == "documents":
            if not initializer.setup_document_collection_indexes(config["name"]):
                success = False
    
    if success:
        logger.info("All collections initialized successfully!")
        sys.exit(0)
    else:
        logger.error("Some collections failed to initialize")
        sys.exit(1)

if __name__ == "__main__":
    main()