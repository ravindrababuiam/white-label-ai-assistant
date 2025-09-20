#!/usr/bin/env python3
"""
Vector Search Service for Open WebUI Qdrant Integration

This service provides vector search functionality with support for hybrid search,
filtering, and result reranking.
"""

import os
import json
import logging
import asyncio
from typing import Dict, List, Optional, Any, Union
from datetime import datetime
import time

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field
import uvicorn
import requests

from qdrant_client import QdrantClient

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Pydantic models
class SearchRequest(BaseModel):
    query: str = Field(..., description="Search query text")
    limit: Optional[int] = Field(10, description="Maximum number of results to return")
    score_threshold: Optional[float] = Field(0.0, description="Minimum similarity score threshold")
    search_type: Optional[str] = Field("hybrid", description="Search type: vector, text, or hybrid")
    filters: Optional[Dict] = Field(None, description="Additional filters to apply")
    with_payload: Optional[bool] = Field(True, description="Include payload in results")
    with_vectors: Optional[bool] = Field(False, description="Include vectors in results")

class VectorSearchRequest(BaseModel):
    vector: List[float] = Field(..., description="Query vector for similarity search")
    limit: Optional[int] = Field(10, description="Maximum number of results to return")
    score_threshold: Optional[float] = Field(0.0, description="Minimum similarity score threshold")
    filters: Optional[Dict] = Field(None, description="Additional filters to apply")
    with_payload: Optional[bool] = Field(True, description="Include payload in results")
    with_vectors: Optional[bool] = Field(False, description="Include vectors in results")

class SearchResult(BaseModel):
    id: str = Field(..., description="Document ID")
    score: float = Field(..., description="Similarity score")
    payload: Optional[Dict] = Field(None, description="Document metadata and content")
    vector: Optional[List[float]] = Field(None, description="Document vector")

class SearchResponse(BaseModel):
    results: List[SearchResult] = Field(..., description="Search results")
    total_results: int = Field(..., description="Total number of results")
    search_type: str = Field(..., description="Type of search performed")
    processing_time: float = Field(..., description="Search processing time in seconds")
    query_info: Dict = Field(..., description="Information about the search query")

class HealthResponse(BaseModel):
    status: str = Field(..., description="Service health status")
    qdrant_connected: bool = Field(..., description="Whether Qdrant is connected")
    embedding_service_connected: bool = Field(..., description="Whether embedding service is connected")
    collection_exists: bool = Field(..., description="Whether the collection exists")
    collection_info: Optional[Dict] = Field(None, description="Collection information")

class VectorSearchService:
    def __init__(self):
        self.qdrant_url = os.getenv('QDRANT_URL', 'http://qdrant:6333')
        self.qdrant_api_key = os.getenv('QDRANT_API_KEY', '')
        self.collection_name = os.getenv('COLLECTION_NAME', 'documents')
        self.embedding_service_url = os.getenv('EMBEDDING_SERVICE_URL', 'http://embedding-service:8001')
        
        # Search configuration
        self.default_limit = int(os.getenv('DEFAULT_SEARCH_LIMIT', '10'))
        self.max_limit = int(os.getenv('MAX_SEARCH_LIMIT', '100'))
        self.score_threshold = float(os.getenv('SCORE_THRESHOLD', '0.0'))
        self.enable_hybrid_search = os.getenv('ENABLE_HYBRID_SEARCH', 'true').lower() == 'true'
        self.enable_reranking = os.getenv('ENABLE_RERANKING', 'false').lower() == 'true'
        
        # Initialize Qdrant client
        self.qdrant_client = self._create_qdrant_client()
        
    def _create_qdrant_client(self) -> QdrantClient:
        """Create Qdrant client"""
        try:
            # Parse URL
            url = self.qdrant_url
            if url.startswith('http://'):
                url = url[7:]
            elif url.startswith('https://'):
                url = url[8:]
            
            if ':' in url:
                host, port = url.split(':', 1)
                port = int(port)
            else:
                host = url
                port = 6333
            
            client = QdrantClient(
                host=host,
                port=port,
                api_key=self.qdrant_api_key if self.qdrant_api_key else None,
                timeout=30,
                prefer_grpc=True
            )
            
            logger.info(f"Connected to Qdrant at {host}:{port}")
            return client
            
        except Exception as e:
            logger.error(f"Failed to create Qdrant client: {e}")
            raise
    
    async def _get_embedding(self, text: str) -> List[float]:
        """Get embedding for text from embedding service"""
        try:
            payload = {
                "text": text,
                "normalize": True
            }
            
            response = await asyncio.to_thread(
                requests.post,
                f"{self.embedding_service_url}/embeddings",
                json=payload,
                timeout=30
            )
            response.raise_for_status()
            
            result = response.json()
            return result['embedding']
            
        except Exception as e:
            logger.error(f"Failed to get embedding: {e}")
            raise
    
    async def vector_search(self, 
                          query_vector: List[float],
                          limit: int = 10,
                          score_threshold: float = 0.0,
                          filters: Dict = None,
                          with_payload: bool = True,
                          with_vectors: bool = False) -> Dict:
        """Perform vector similarity search"""
        try:
            start_time = time.time()
            
            # Validate limit
            limit = min(limit, self.max_limit)
            
            # Build filter
            search_filter = None
            if filters:
                search_filter = self._build_qdrant_filter(filters)
            
            # Perform search
            search_results = await asyncio.to_thread(
                self.qdrant_client.search,
                collection_name=self.collection_name,
                query_vector=query_vector,
                limit=limit,
                score_threshold=score_threshold,
                query_filter=search_filter,
                with_payload=with_payload,
                with_vectors=with_vectors
            )
            
            # Format results
            results = []
            for result in search_results:
                result_data = SearchResult(
                    id=str(result.id),
                    score=result.score,
                    payload=result.payload if with_payload else None,
                    vector=result.vector if with_vectors else None
                )
                results.append(result_data)
            
            processing_time = time.time() - start_time
            
            logger.info(f"Vector search returned {len(results)} results in {processing_time:.3f}s")
            
            return {
                'results': results,
                'total_results': len(results),
                'search_type': 'vector',
                'processing_time': processing_time,
                'query_info': {
                    'vector_size': len(query_vector),
                    'limit': limit,
                    'score_threshold': score_threshold,
                    'filters_applied': filters is not None
                }
            }
            
        except Exception as e:
            logger.error(f"Vector search failed: {e}")
            raise
    
    async def text_search(self,
                        query: str,
                        limit: int = 10,
                        filters: Dict = None,
                        with_payload: bool = True) -> Dict:
        """Perform text-based search using payload filtering"""
        try:
            start_time = time.time()
            
            # Validate limit
            limit = min(limit, self.max_limit)
            
            # Build text search filter
            text_conditions = []
            
            # Search in various text fields
            query_words = query.lower().split()
            
            for word in query_words:
                text_conditions.extend([
                    {'key': 'content', 'match': {'text': word}},
                    {'key': 'title', 'match': {'text': word}},
                    {'key': 'filename', 'match': {'text': word}}
                ])
            
            # Add tag search
            text_conditions.append({
                'key': 'tags',
                'match': {'any': query_words}
            })
            
            text_filter = {'should': text_conditions}
            
            # Combine with additional filters
            if filters:
                combined_filter = {
                    'must': [text_filter, filters]
                }
            else:
                combined_filter = text_filter
            
            # Convert to Qdrant filter
            qdrant_filter = self._build_qdrant_filter(combined_filter)
            
            # Scroll through results
            scroll_result = await asyncio.to_thread(
                self.qdrant_client.scroll,
                collection_name=self.collection_name,
                scroll_filter=qdrant_filter,
                limit=limit,
                with_payload=with_payload,
                with_vectors=False
            )
            
            # Format results
            results = []
            for point in scroll_result[0]:  # scroll_result is (points, next_page_offset)
                result_data = SearchResult(
                    id=str(point.id),
                    score=1.0,  # Text search doesn't provide similarity scores
                    payload=point.payload if with_payload else None,
                    vector=None
                )
                results.append(result_data)
            
            processing_time = time.time() - start_time
            
            logger.info(f"Text search returned {len(results)} results in {processing_time:.3f}s")
            
            return {
                'results': results,
                'total_results': len(results),
                'search_type': 'text',
                'processing_time': processing_time,
                'query_info': {
                    'query': query,
                    'query_words': query_words,
                    'limit': limit,
                    'filters_applied': filters is not None
                }
            }
            
        except Exception as e:
            logger.error(f"Text search failed: {e}")
            raise
    
    async def hybrid_search(self,
                          query: str,
                          limit: int = 10,
                          score_threshold: float = 0.0,
                          filters: Dict = None,
                          with_payload: bool = True,
                          with_vectors: bool = False,
                          alpha: float = 0.7) -> Dict:
        """Perform hybrid search combining vector and text search"""
        try:
            start_time = time.time()
            
            # Get embedding for query
            query_vector = await self._get_embedding(query)
            
            # Perform vector search
            vector_results = await self.vector_search(
                query_vector=query_vector,
                limit=limit * 2,  # Get more results for reranking
                score_threshold=score_threshold,
                filters=filters,
                with_payload=with_payload,
                with_vectors=with_vectors
            )
            
            # Perform text search
            text_results = await self.text_search(
                query=query,
                limit=limit * 2,
                filters=filters,
                with_payload=with_payload
            )
            
            # Combine and rerank results
            combined_results = self._combine_search_results(
                vector_results['results'],
                text_results['results'],
                alpha=alpha
            )
            
            # Limit final results
            final_results = combined_results[:limit]
            
            processing_time = time.time() - start_time
            
            logger.info(f"Hybrid search returned {len(final_results)} results in {processing_time:.3f}s")
            
            return {
                'results': final_results,
                'total_results': len(final_results),
                'search_type': 'hybrid',
                'processing_time': processing_time,
                'query_info': {
                    'query': query,
                    'vector_size': len(query_vector),
                    'limit': limit,
                    'score_threshold': score_threshold,
                    'alpha': alpha,
                    'vector_results': len(vector_results['results']),
                    'text_results': len(text_results['results']),
                    'filters_applied': filters is not None
                }
            }
            
        except Exception as e:
            logger.error(f"Hybrid search failed: {e}")
            raise
    
    def _combine_search_results(self,
                              vector_results: List[SearchResult],
                              text_results: List[SearchResult],
                              alpha: float = 0.7) -> List[SearchResult]:
        """Combine and rerank vector and text search results"""
        try:
            # Create combined results with weighted scores
            combined = {}
            
            # Add vector results
            for result in vector_results:
                result_id = result.id
                combined[result_id] = SearchResult(
                    id=result.id,
                    score=alpha * result.score,  # Weighted vector score
                    payload=result.payload,
                    vector=result.vector
                )
            
            # Add text results and combine scores
            for result in text_results:
                result_id = result.id
                text_score = (1 - alpha) * result.score
                
                if result_id in combined:
                    # Update existing result with combined score
                    combined[result_id].score += text_score
                    # Merge payload if needed
                    if result.payload and not combined[result_id].payload:
                        combined[result_id].payload = result.payload
                else:
                    # Add new result
                    combined[result_id] = SearchResult(
                        id=result.id,
                        score=text_score,
                        payload=result.payload,
                        vector=result.vector
                    )
            
            # Sort by combined score
            sorted_results = sorted(
                combined.values(),
                key=lambda x: x.score,
                reverse=True
            )
            
            return sorted_results
            
        except Exception as e:
            logger.error(f"Failed to combine search results: {e}")
            return vector_results  # Fallback to vector results
    
    def _build_qdrant_filter(self, conditions: Dict):
        """Build Qdrant filter from conditions dictionary"""
        try:
            from qdrant_client.http.models import Filter, FieldCondition, Match
            
            if 'must' in conditions:
                must_conditions = []
                for condition in conditions['must']:
                    built_condition = self._build_qdrant_condition(condition)
                    if built_condition:
                        must_conditions.append(built_condition)
                return Filter(must=must_conditions) if must_conditions else None
            
            elif 'should' in conditions:
                should_conditions = []
                for condition in conditions['should']:
                    built_condition = self._build_qdrant_condition(condition)
                    if built_condition:
                        should_conditions.append(built_condition)
                return Filter(should=should_conditions) if should_conditions else None
            
            else:
                built_condition = self._build_qdrant_condition(conditions)
                return Filter(must=[built_condition]) if built_condition else None
                
        except Exception as e:
            logger.error(f"Failed to build Qdrant filter: {e}")
            return None
    
    def _build_qdrant_condition(self, condition: Dict):
        """Build individual Qdrant filter condition"""
        try:
            from qdrant_client.http.models import FieldCondition, Match
            
            if 'key' in condition and 'match' in condition:
                key = condition['key']
                match_value = condition['match']
                
                if isinstance(match_value, dict):
                    if 'text' in match_value:
                        return FieldCondition(key=key, match=Match(text=match_value['text']))
                    elif 'value' in match_value:
                        return FieldCondition(key=key, match=Match(value=match_value['value']))
                    elif 'any' in match_value:
                        return FieldCondition(key=key, match=Match(any=match_value['any']))
                else:
                    return FieldCondition(key=key, match=Match(value=match_value))
            
            return None
            
        except Exception as e:
            logger.error(f"Failed to build Qdrant condition: {e}")
            return None
    
    async def get_collection_info(self) -> Dict:
        """Get information about the Qdrant collection"""
        try:
            collection_info = await asyncio.to_thread(
                self.qdrant_client.get_collection,
                self.collection_name
            )
            
            return {
                'collection_name': self.collection_name,
                'points_count': collection_info.points_count,
                'vectors_count': collection_info.vectors_count,
                'indexed_vectors_count': collection_info.indexed_vectors_count,
                'status': collection_info.status,
                'optimizer_status': collection_info.optimizer_status
            }
            
        except Exception as e:
            logger.error(f"Failed to get collection info: {e}")
            return None
    
    async def health_check(self) -> Dict:
        """Perform comprehensive health check"""
        try:
            # Check Qdrant connection
            qdrant_connected = False
            collection_exists = False
            collection_info = None
            
            try:
                collections = await asyncio.to_thread(
                    self.qdrant_client.get_collections
                )
                qdrant_connected = True
                
                # Check if collection exists
                collection_names = [col.name for col in collections.collections]
                collection_exists = self.collection_name in collection_names
                
                if collection_exists:
                    collection_info = await self.get_collection_info()
                    
            except Exception as e:
                logger.error(f"Qdrant health check failed: {e}")
            
            # Check embedding service connection
            embedding_service_connected = False
            try:
                response = await asyncio.to_thread(
                    requests.get,
                    f"{self.embedding_service_url}/health",
                    timeout=10
                )
                embedding_service_connected = response.status_code == 200
            except Exception as e:
                logger.error(f"Embedding service health check failed: {e}")
            
            return {
                'status': 'healthy' if qdrant_connected and embedding_service_connected else 'unhealthy',
                'qdrant_connected': qdrant_connected,
                'embedding_service_connected': embedding_service_connected,
                'collection_exists': collection_exists,
                'collection_info': collection_info,
                'configuration': {
                    'collection_name': self.collection_name,
                    'default_limit': self.default_limit,
                    'max_limit': self.max_limit,
                    'score_threshold': self.score_threshold,
                    'hybrid_search_enabled': self.enable_hybrid_search,
                    'reranking_enabled': self.enable_reranking
                }
            }
            
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return {
                'status': 'unhealthy',
                'error': str(e)
            }

# FastAPI application
app = FastAPI(
    title="Vector Search Service",
    description="Vector search service for Open WebUI Qdrant integration",
    version="1.0.0"
)

# Initialize service
search_service = VectorSearchService()

@app.post("/search", response_model=SearchResponse)
async def search_documents(request: SearchRequest):
    """Search documents using text query"""
    try:
        # Validate limit
        limit = min(request.limit or search_service.default_limit, search_service.max_limit)
        score_threshold = request.score_threshold or search_service.score_threshold
        
        if request.search_type == "vector":
            # Get embedding and perform vector search
            query_vector = await search_service._get_embedding(request.query)
            result = await search_service.vector_search(
                query_vector=query_vector,
                limit=limit,
                score_threshold=score_threshold,
                filters=request.filters,
                with_payload=request.with_payload,
                with_vectors=request.with_vectors
            )
        elif request.search_type == "text":
            # Perform text search
            result = await search_service.text_search(
                query=request.query,
                limit=limit,
                filters=request.filters,
                with_payload=request.with_payload
            )
        else:  # hybrid (default)
            # Perform hybrid search
            result = await search_service.hybrid_search(
                query=request.query,
                limit=limit,
                score_threshold=score_threshold,
                filters=request.filters,
                with_payload=request.with_payload,
                with_vectors=request.with_vectors
            )
        
        return SearchResponse(**result)
        
    except Exception as e:
        logger.error(f"Search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/search/vector", response_model=SearchResponse)
async def search_by_vector(request: VectorSearchRequest):
    """Search documents using vector similarity"""
    try:
        limit = min(request.limit or search_service.default_limit, search_service.max_limit)
        score_threshold = request.score_threshold or search_service.score_threshold
        
        result = await search_service.vector_search(
            query_vector=request.vector,
            limit=limit,
            score_threshold=score_threshold,
            filters=request.filters,
            with_payload=request.with_payload,
            with_vectors=request.with_vectors
        )
        
        return SearchResponse(**result)
        
    except Exception as e:
        logger.error(f"Vector search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/collection/info")
async def get_collection_info():
    """Get information about the Qdrant collection"""
    try:
        info = await search_service.get_collection_info()
        if info:
            return info
        else:
            raise HTTPException(status_code=404, detail="Collection not found")
    except Exception as e:
        logger.error(f"Failed to get collection info: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    try:
        health_status = await search_service.health_check()
        return HealthResponse(**health_status)
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/ready")
async def readiness_check():
    """Readiness check endpoint"""
    try:
        health_status = await search_service.health_check()
        if (health_status['status'] == 'healthy' and 
            health_status['qdrant_connected'] and 
            health_status['embedding_service_connected'] and
            health_status['collection_exists']):
            return {"status": "ready"}
        else:
            raise HTTPException(status_code=503, detail="Service not ready")
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail=str(e))

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    try:
        collection_info = await search_service.get_collection_info()
        points_count = collection_info['points_count'] if collection_info else 0
        
        metrics_text = f"""
# HELP vector_search_collection_points Total number of points in collection
# TYPE vector_search_collection_points gauge
vector_search_collection_points {points_count}

# HELP vector_search_service_info Vector search service information
# TYPE vector_search_service_info info
vector_search_service_info{{collection="{search_service.collection_name}",hybrid_enabled="{search_service.enable_hybrid_search}"}} 1
"""
        
        return metrics_text.strip()
        
    except Exception as e:
        logger.error(f"Metrics collection failed: {e}")
        return "# Metrics collection failed"

if __name__ == "__main__":
    uvicorn.run(
        "vector_search:app",
        host="0.0.0.0",
        port=8002,
        log_level="info"
    )