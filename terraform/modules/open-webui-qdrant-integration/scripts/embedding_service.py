#!/usr/bin/env python3
"""
Embedding Service for Open WebUI Qdrant Integration

This service provides embedding generation capabilities for document processing
and vector search functionality.
"""

import os
import json
import logging
import asyncio
from typing import Dict, List, Optional, Any, Union
from datetime import datetime
import hashlib
import time

import numpy as np
from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel, Field
import uvicorn
import openai
import requests
from transformers import AutoTokenizer, AutoModel
import torch

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Pydantic models
class EmbeddingRequest(BaseModel):
    text: str = Field(..., description="Text to generate embeddings for")
    model: Optional[str] = Field(None, description="Override default embedding model")
    normalize: Optional[bool] = Field(True, description="Normalize embeddings to unit vectors")

class BatchEmbeddingRequest(BaseModel):
    texts: List[str] = Field(..., description="List of texts to generate embeddings for")
    model: Optional[str] = Field(None, description="Override default embedding model")
    normalize: Optional[bool] = Field(True, description="Normalize embeddings to unit vectors")

class EmbeddingResponse(BaseModel):
    embedding: List[float] = Field(..., description="Generated embedding vector")
    model: str = Field(..., description="Model used for embedding generation")
    text_length: int = Field(..., description="Length of input text")
    processing_time: float = Field(..., description="Processing time in seconds")

class BatchEmbeddingResponse(BaseModel):
    embeddings: List[List[float]] = Field(..., description="Generated embedding vectors")
    model: str = Field(..., description="Model used for embedding generation")
    total_texts: int = Field(..., description="Number of texts processed")
    processing_time: float = Field(..., description="Total processing time in seconds")

class HealthResponse(BaseModel):
    status: str = Field(..., description="Service health status")
    model_loaded: bool = Field(..., description="Whether embedding model is loaded")
    provider: str = Field(..., description="Embedding provider")
    model_name: str = Field(..., description="Current embedding model")
    cache_enabled: bool = Field(..., description="Whether caching is enabled")

class EmbeddingService:
    def __init__(self):
        self.config = self._load_config()
        self.provider = os.getenv('EMBEDDING_PROVIDER', 'openai')
        self.model_name = os.getenv('EMBEDDING_MODEL', 'text-embedding-ada-002')
        self.api_url = os.getenv('EMBEDDING_API_URL', '')
        self.vector_size = int(os.getenv('VECTOR_SIZE', '1536'))
        self.max_tokens = int(os.getenv('MAX_TOKENS', '8192'))
        self.normalize_embeddings = os.getenv('NORMALIZE_EMBEDDINGS', 'true').lower() == 'true'
        
        # Cache configuration
        self.cache_enabled = os.getenv('ENABLE_CACHE', 'true').lower() == 'true'
        self.cache_ttl = int(os.getenv('CACHE_TTL', '3600'))
        self.cache = {} if self.cache_enabled else None
        
        # Initialize provider
        self.model = None
        self.tokenizer = None
        self._initialize_provider()
        
    def _load_config(self) -> Dict:
        """Load configuration from file"""
        try:
            config_path = "/app/config/qdrant_config.json"
            with open(config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.warning("Configuration file not found, using environment variables")
            return {}
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in configuration file: {e}")
            return {}
    
    def _initialize_provider(self):
        """Initialize the embedding provider"""
        try:
            if self.provider == 'openai':
                self._initialize_openai()
            elif self.provider == 'huggingface':
                self._initialize_huggingface()
            elif self.provider == 'local':
                self._initialize_local_model()
            elif self.provider == 'ollama':
                self._initialize_ollama()
            else:
                raise ValueError(f"Unsupported embedding provider: {self.provider}")
                
            logger.info(f"Initialized {self.provider} embedding provider with model {self.model_name}")
            
        except Exception as e:
            logger.error(f"Failed to initialize embedding provider: {e}")
            raise
    
    def _initialize_openai(self):
        """Initialize OpenAI embedding provider"""
        api_key = os.getenv('OPENAI_API_KEY')
        if not api_key:
            raise ValueError("OpenAI API key not provided")
        
        openai.api_key = api_key
        
        # Test connection
        try:
            openai.Model.list()
            logger.info("OpenAI API connection successful")
        except Exception as e:
            logger.error(f"OpenAI API connection failed: {e}")
            raise
    
    def _initialize_huggingface(self):
        """Initialize Hugging Face embedding provider"""
        try:
            from transformers import AutoTokenizer, AutoModel
            
            self.tokenizer = AutoTokenizer.from_pretrained(self.model_name)
            self.model = AutoModel.from_pretrained(self.model_name)
            
            # Move to GPU if available
            if torch.cuda.is_available():
                self.model = self.model.cuda()
                logger.info("Using GPU for Hugging Face model")
            
            logger.info(f"Loaded Hugging Face model: {self.model_name}")
            
        except Exception as e:
            logger.error(f"Failed to load Hugging Face model: {e}")
            raise
    
    def _initialize_local_model(self):
        """Initialize local embedding model"""
        # This would be implemented based on specific local model requirements
        logger.info("Local model provider initialized")
        pass
    
    def _initialize_ollama(self):
        """Initialize Ollama embedding provider"""
        if not self.api_url:
            self.api_url = "http://ollama:11434"
        
        # Test connection to Ollama
        try:
            response = requests.get(f"{self.api_url}/api/tags", timeout=10)
            response.raise_for_status()
            logger.info("Ollama API connection successful")
        except Exception as e:
            logger.error(f"Ollama API connection failed: {e}")
            raise
    
    def _get_cache_key(self, text: str, model: str) -> str:
        """Generate cache key for text and model"""
        content = f"{text}:{model}"
        return hashlib.md5(content.encode()).hexdigest()
    
    def _get_from_cache(self, cache_key: str) -> Optional[List[float]]:
        """Get embedding from cache if available and not expired"""
        if not self.cache_enabled or not self.cache:
            return None
        
        if cache_key in self.cache:
            cached_data = self.cache[cache_key]
            if time.time() - cached_data['timestamp'] < self.cache_ttl:
                return cached_data['embedding']
            else:
                # Remove expired entry
                del self.cache[cache_key]
        
        return None
    
    def _store_in_cache(self, cache_key: str, embedding: List[float]):
        """Store embedding in cache"""
        if not self.cache_enabled or not self.cache:
            return
        
        self.cache[cache_key] = {
            'embedding': embedding,
            'timestamp': time.time()
        }
        
        # Simple cache size management
        if len(self.cache) > 10000:  # Max 10k cached embeddings
            # Remove oldest 20% of entries
            sorted_items = sorted(
                self.cache.items(),
                key=lambda x: x[1]['timestamp']
            )
            for key, _ in sorted_items[:2000]:
                del self.cache[key]
    
    async def generate_embedding(self, text: str, model: Optional[str] = None) -> List[float]:
        """Generate embedding for a single text"""
        start_time = time.time()
        
        # Use provided model or default
        embedding_model = model or self.model_name
        
        # Check cache first
        cache_key = self._get_cache_key(text, embedding_model)
        cached_embedding = self._get_from_cache(cache_key)
        if cached_embedding:
            logger.debug(f"Retrieved embedding from cache for text length {len(text)}")
            return cached_embedding
        
        # Truncate text if too long
        if len(text) > self.max_tokens:
            text = text[:self.max_tokens]
            logger.warning(f"Text truncated to {self.max_tokens} characters")
        
        try:
            if self.provider == 'openai':
                embedding = await self._generate_openai_embedding(text, embedding_model)
            elif self.provider == 'huggingface':
                embedding = await self._generate_huggingface_embedding(text, embedding_model)
            elif self.provider == 'local':
                embedding = await self._generate_local_embedding(text, embedding_model)
            elif self.provider == 'ollama':
                embedding = await self._generate_ollama_embedding(text, embedding_model)
            else:
                raise ValueError(f"Unsupported provider: {self.provider}")
            
            # Normalize if requested
            if self.normalize_embeddings:
                embedding = self._normalize_vector(embedding)
            
            # Store in cache
            self._store_in_cache(cache_key, embedding)
            
            processing_time = time.time() - start_time
            logger.debug(f"Generated embedding in {processing_time:.3f}s for text length {len(text)}")
            
            return embedding
            
        except Exception as e:
            logger.error(f"Failed to generate embedding: {e}")
            raise
    
    async def _generate_openai_embedding(self, text: str, model: str) -> List[float]:
        """Generate embedding using OpenAI API"""
        try:
            response = await asyncio.to_thread(
                openai.Embedding.create,
                input=text,
                model=model
            )
            return response['data'][0]['embedding']
        except Exception as e:
            logger.error(f"OpenAI embedding generation failed: {e}")
            raise
    
    async def _generate_huggingface_embedding(self, text: str, model: str) -> List[float]:
        """Generate embedding using Hugging Face model"""
        try:
            # Tokenize
            inputs = self.tokenizer(
                text,
                return_tensors='pt',
                truncation=True,
                padding=True,
                max_length=512
            )
            
            # Move to GPU if available
            if torch.cuda.is_available():
                inputs = {k: v.cuda() for k, v in inputs.items()}
            
            # Generate embedding
            with torch.no_grad():
                outputs = self.model(**inputs)
                # Use mean pooling of last hidden states
                embedding = outputs.last_hidden_state.mean(dim=1).squeeze()
            
            # Convert to list
            if torch.cuda.is_available():
                embedding = embedding.cpu()
            
            return embedding.numpy().tolist()
            
        except Exception as e:
            logger.error(f"Hugging Face embedding generation failed: {e}")
            raise
    
    async def _generate_local_embedding(self, text: str, model: str) -> List[float]:
        """Generate embedding using local model"""
        # Placeholder for local model implementation
        # Return dummy embedding for now
        return [0.0] * self.vector_size
    
    async def _generate_ollama_embedding(self, text: str, model: str) -> List[float]:
        """Generate embedding using Ollama API"""
        try:
            payload = {
                "model": model,
                "prompt": text
            }
            
            response = await asyncio.to_thread(
                requests.post,
                f"{self.api_url}/api/embeddings",
                json=payload,
                timeout=30
            )
            response.raise_for_status()
            
            result = response.json()
            return result.get('embedding', [])
            
        except Exception as e:
            logger.error(f"Ollama embedding generation failed: {e}")
            raise
    
    def _normalize_vector(self, vector: List[float]) -> List[float]:
        """Normalize vector to unit length"""
        try:
            np_vector = np.array(vector)
            norm = np.linalg.norm(np_vector)
            if norm == 0:
                return vector
            return (np_vector / norm).tolist()
        except Exception as e:
            logger.error(f"Vector normalization failed: {e}")
            return vector
    
    async def generate_batch_embeddings(self, texts: List[str], model: Optional[str] = None) -> List[List[float]]:
        """Generate embeddings for multiple texts"""
        embeddings = []
        
        for text in texts:
            embedding = await self.generate_embedding(text, model)
            embeddings.append(embedding)
        
        return embeddings
    
    def get_health_status(self) -> Dict:
        """Get service health status"""
        return {
            'status': 'healthy',
            'model_loaded': self.model is not None or self.provider in ['openai', 'ollama'],
            'provider': self.provider,
            'model_name': self.model_name,
            'cache_enabled': self.cache_enabled,
            'vector_size': self.vector_size,
            'max_tokens': self.max_tokens,
            'normalize_embeddings': self.normalize_embeddings
        }

# FastAPI application
app = FastAPI(
    title="Embedding Service",
    description="Embedding generation service for Open WebUI Qdrant integration",
    version="1.0.0"
)

# Initialize service
embedding_service = EmbeddingService()

@app.post("/embeddings", response_model=EmbeddingResponse)
async def create_embedding(request: EmbeddingRequest):
    """Generate embedding for a single text"""
    try:
        start_time = time.time()
        
        embedding = await embedding_service.generate_embedding(
            text=request.text,
            model=request.model
        )
        
        processing_time = time.time() - start_time
        
        return EmbeddingResponse(
            embedding=embedding,
            model=request.model or embedding_service.model_name,
            text_length=len(request.text),
            processing_time=processing_time
        )
        
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/embeddings/batch", response_model=BatchEmbeddingResponse)
async def create_batch_embeddings(request: BatchEmbeddingRequest):
    """Generate embeddings for multiple texts"""
    try:
        start_time = time.time()
        
        embeddings = await embedding_service.generate_batch_embeddings(
            texts=request.texts,
            model=request.model
        )
        
        processing_time = time.time() - start_time
        
        return BatchEmbeddingResponse(
            embeddings=embeddings,
            model=request.model or embedding_service.model_name,
            total_texts=len(request.texts),
            processing_time=processing_time
        )
        
    except Exception as e:
        logger.error(f"Batch embedding generation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    try:
        health_status = embedding_service.get_health_status()
        return HealthResponse(**health_status)
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/ready")
async def readiness_check():
    """Readiness check endpoint"""
    try:
        health_status = embedding_service.get_health_status()
        if health_status['status'] == 'healthy' and health_status['model_loaded']:
            return {"status": "ready"}
        else:
            raise HTTPException(status_code=503, detail="Service not ready")
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail=str(e))

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    # Basic metrics - in production you'd use prometheus_client
    cache_size = len(embedding_service.cache) if embedding_service.cache else 0
    
    metrics_text = f"""
# HELP embedding_service_cache_size Number of cached embeddings
# TYPE embedding_service_cache_size gauge
embedding_service_cache_size {cache_size}

# HELP embedding_service_provider_info Embedding provider information
# TYPE embedding_service_provider_info info
embedding_service_provider_info{{provider="{embedding_service.provider}",model="{embedding_service.model_name}"}} 1
"""
    
    return metrics_text.strip()

if __name__ == "__main__":
    uvicorn.run(
        "embedding_service:app",
        host="0.0.0.0",
        port=8001,
        log_level="info"
    )