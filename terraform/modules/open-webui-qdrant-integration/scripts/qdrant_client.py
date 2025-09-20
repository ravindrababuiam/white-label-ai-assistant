#!/usr/bin/env python3
"""
Qdrant Client for Open WebUI Integration

This module provides a comprehensive Qdrant client with connection management,
collection operations, and vector search functionality.
"""

import os
import json
import logging
import asyncio
from datetime import datetime
from typing import Dict, List, Optional, Any, Union, Tuple
import uuid

from qdrant_client import QdrantClient
from qdrant_client.http import models
from qdrant_client.http.models import (
    Distance, VectorParams, CreateCollection, PointStruct,
    Filter, FieldCondition, Match, SearchRequest, ScrollRequest,
    UpdateCollection, OptimizersConfigDiff, HnswConfigDiff
)
import numpy as np

logger = logging.getLogger(__name__)

class QdrantVectorClient:
    def __init__(self, config_path: str = "/app/config/qdrant_config.json"):
        """Initialize Qdrant client with configuration"""
        self.config = self._load_config(config_path)
        self.client = self._create_client()
        self.collection_name = self.config['qdrant']['collection_name']
        self.vector_size = self.config['qdrant']['vector_size']
        self.distance_metric = self.config['qdrant']['distance_metric']
        
    def _load_config(self, config_path: str) -> Dict:
        """Load Qdrant configuration from file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.error(f"Configuration file not found: {config_path}")
            raise
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in configuration file: {e}")
            raise
    
    def _create_client(self) -> QdrantClient:
        """Create Qdrant client with configuration"""
        qdrant_config = self.config['qdrant']
        
        # Parse URL to get host and port
        url = qdrant_config['url']
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
        
        # Get API key if provided
        api_key = os.getenv('QDRANT_API_KEY') or qdrant_config.get('api_key')
        
        # Create client
        client = QdrantClient(
            host=host,
            port=port,
            api_key=api_key,
            timeout=qdrant_config.get('timeout_seconds', 30),
            prefer_grpc=True
        )
        
        logger.info(f"Connected to Qdrant at {host}:{port}")
        return client
    
    def _get_distance_metric(self) -> Distance:
        """Convert string distance metric to Qdrant Distance enum"""
        distance_map = {
            'Cosine': Distance.COSINE,
            'Euclidean': Distance.EUCLID,
            'Dot': Distance.DOT
        }
        return distance_map.get(self.distance_metric, Distance.COSINE)
    
    async def ensure_collection_exists(self) -> Dict:
        """Ensure the collection exists, create if it doesn't"""
        try:
            # Check if collection exists
            collections = self.client.get_collections()
            collection_names = [col.name for col in collections.collections]
            
            if self.collection_name in collection_names:
                logger.info(f"Collection '{self.collection_name}' already exists")
                
                # Verify collection configuration
                collection_info = self.client.get_collection(self.collection_name)
                
                return {
                    'success': True,
                    'action': 'verified',
                    'collection_name': self.collection_name,
                    'points_count': collection_info.points_count,
                    'vectors_count': collection_info.vectors_count
                }
            
            # Create collection
            logger.info(f"Creating collection '{self.collection_name}'")
            
            self.client.create_collection(
                collection_name=self.collection_name,
                vectors_config=VectorParams(
                    size=self.vector_size,
                    distance=self._get_distance_metric()
                ),
                optimizers_config=models.OptimizersConfig(
                    default_segment_number=2,
                    max_segment_size=20000,
                    memmap_threshold=20000,
                    indexing_threshold=20000,
                    flush_interval_sec=5,
                    max_optimization_threads=1
                ),
                hnsw_config=models.HnswConfig(
                    m=16,
                    ef_construct=100,
                    full_scan_threshold=10000,
                    max_indexing_threads=0,
                    on_disk=False
                )
            )
            
            logger.info(f"Successfully created collection '{self.collection_name}'")
            
            return {
                'success': True,
                'action': 'created',
                'collection_name': self.collection_name,
                'vector_size': self.vector_size,
                'distance_metric': self.distance_metric
            }
            
        except Exception as e:
            logger.error(f"Failed to ensure collection exists: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def create_indexes(self) -> Dict:
        """Create payload indexes for efficient filtering"""
        try:
            logger.info(f"Creating indexes for collection '{self.collection_name}'")
            
            # Define indexes for common payload fields
            indexes = [
                ('document_id', 'keyword'),
                ('user_id', 'keyword'),
                ('filename', 'keyword'),
                ('content_type', 'keyword'),
                ('upload_timestamp', 'datetime'),
                ('chunk_index', 'integer'),
                ('tags', 'keyword')
            ]
            
            for field_name, field_type in indexes:
                try:
                    self.client.create_payload_index(
                        collection_name=self.collection_name,
                        field_name=field_name,
                        field_schema=field_type
                    )
                    logger.debug(f"Created index for field '{field_name}'")
                except Exception as e:
                    # Index might already exist
                    logger.debug(f"Index creation for '{field_name}' failed (might exist): {e}")
            
            return {
                'success': True,
                'indexes_created': len(indexes),
                'collection_name': self.collection_name
            }
            
        except Exception as e:
            logger.error(f"Failed to create indexes: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def upsert_points(self, points: List[Dict]) -> Dict:
        """Upsert points (vectors with payload) to the collection"""
        try:
            if not points:
                return {
                    'success': True,
                    'points_upserted': 0,
                    'message': 'No points to upsert'
                }
            
            # Convert points to Qdrant format
            qdrant_points = []
            
            for point in points:
                # Generate ID if not provided
                point_id = point.get('id', str(uuid.uuid4()))
                
                # Validate vector
                vector = point.get('vector')
                if not vector:
                    logger.warning(f"Point {point_id} has no vector, skipping")
                    continue
                
                if len(vector) != self.vector_size:
                    logger.warning(f"Point {point_id} vector size mismatch: {len(vector)} != {self.vector_size}")
                    continue
                
                # Prepare payload
                payload = point.get('payload', {})
                payload['indexed_at'] = datetime.utcnow().isoformat()
                
                qdrant_points.append(
                    PointStruct(
                        id=point_id,
                        vector=vector,
                        payload=payload
                    )
                )
            
            if not qdrant_points:
                return {
                    'success': False,
                    'error': 'No valid points to upsert'
                }
            
            # Upsert points in batches
            batch_size = self.config['qdrant'].get('batch_size', 100)
            total_upserted = 0
            
            for i in range(0, len(qdrant_points), batch_size):
                batch = qdrant_points[i:i + batch_size]
                
                self.client.upsert(
                    collection_name=self.collection_name,
                    points=batch
                )
                
                total_upserted += len(batch)
                logger.debug(f"Upserted batch of {len(batch)} points")
            
            logger.info(f"Successfully upserted {total_upserted} points to '{self.collection_name}'")
            
            return {
                'success': True,
                'points_upserted': total_upserted,
                'collection_name': self.collection_name
            }
            
        except Exception as e:
            logger.error(f"Failed to upsert points: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def search_vectors(self, 
                           query_vector: List[float], 
                           limit: int = 10,
                           score_threshold: float = 0.0,
                           filter_conditions: Dict = None,
                           with_payload: bool = True,
                           with_vectors: bool = False) -> Dict:
        """Search for similar vectors in the collection"""
        try:
            # Validate query vector
            if len(query_vector) != self.vector_size:
                return {
                    'success': False,
                    'error': f'Query vector size mismatch: {len(query_vector)} != {self.vector_size}'
                }
            
            # Build filter
            search_filter = None
            if filter_conditions:
                search_filter = self._build_filter(filter_conditions)
            
            # Perform search
            search_results = self.client.search(
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
                result_data = {
                    'id': result.id,
                    'score': result.score
                }
                
                if with_payload and result.payload:
                    result_data['payload'] = result.payload
                
                if with_vectors and result.vector:
                    result_data['vector'] = result.vector
                
                results.append(result_data)
            
            logger.info(f"Vector search returned {len(results)} results")
            
            return {
                'success': True,
                'results': results,
                'total_results': len(results),
                'collection_name': self.collection_name,
                'search_params': {
                    'limit': limit,
                    'score_threshold': score_threshold,
                    'with_payload': with_payload,
                    'with_vectors': with_vectors
                }
            }
            
        except Exception as e:
            logger.error(f"Vector search failed: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def hybrid_search(self,
                          query_vector: List[float],
                          text_query: str = None,
                          limit: int = 10,
                          score_threshold: float = 0.0,
                          filter_conditions: Dict = None,
                          alpha: float = 0.7) -> Dict:
        """Perform hybrid search combining vector and text search"""
        try:
            # Vector search
            vector_results = await self.search_vectors(
                query_vector=query_vector,
                limit=limit * 2,  # Get more results for reranking
                score_threshold=score_threshold,
                filter_conditions=filter_conditions,
                with_payload=True
            )
            
            if not vector_results['success']:
                return vector_results
            
            results = vector_results['results']
            
            # Text search (if query provided)
            if text_query and text_query.strip():
                text_results = await self.text_search(
                    query=text_query,
                    limit=limit * 2,
                    filter_conditions=filter_conditions
                )
                
                if text_results['success']:
                    # Combine and rerank results
                    results = self._combine_search_results(
                        vector_results['results'],
                        text_results['results'],
                        alpha=alpha
                    )
            
            # Limit final results
            results = results[:limit]
            
            logger.info(f"Hybrid search returned {len(results)} results")
            
            return {
                'success': True,
                'results': results,
                'total_results': len(results),
                'search_type': 'hybrid',
                'collection_name': self.collection_name
            }
            
        except Exception as e:
            logger.error(f"Hybrid search failed: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def text_search(self,
                        query: str,
                        limit: int = 10,
                        filter_conditions: Dict = None) -> Dict:
        """Perform text-based search using payload filtering"""
        try:
            # Build text search filter
            text_filter = {
                'should': [
                    {'key': 'content', 'match': {'text': query}},
                    {'key': 'title', 'match': {'text': query}},
                    {'key': 'filename', 'match': {'text': query}},
                    {'key': 'tags', 'match': {'any': query.split()}}
                ]
            }
            
            # Combine with additional filters
            if filter_conditions:
                combined_filter = {
                    'must': [
                        text_filter,
                        filter_conditions
                    ]
                }
            else:
                combined_filter = text_filter
            
            # Scroll through results (text search doesn't use vectors)
            scroll_result = self.client.scroll(
                collection_name=self.collection_name,
                scroll_filter=self._build_filter(combined_filter),
                limit=limit,
                with_payload=True,
                with_vectors=False
            )
            
            # Format results
            results = []
            for point in scroll_result[0]:  # scroll_result is (points, next_page_offset)
                results.append({
                    'id': point.id,
                    'score': 1.0,  # Text search doesn't provide similarity scores
                    'payload': point.payload
                })
            
            logger.info(f"Text search returned {len(results)} results")
            
            return {
                'success': True,
                'results': results,
                'total_results': len(results),
                'search_type': 'text',
                'collection_name': self.collection_name
            }
            
        except Exception as e:
            logger.error(f"Text search failed: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def _build_filter(self, conditions: Dict) -> Filter:
        """Build Qdrant filter from conditions dictionary"""
        try:
            # This is a simplified filter builder
            # In production, you'd want more comprehensive filter building
            
            if 'must' in conditions:
                must_conditions = []
                for condition in conditions['must']:
                    must_conditions.append(self._build_condition(condition))
                return Filter(must=must_conditions)
            
            elif 'should' in conditions:
                should_conditions = []
                for condition in conditions['should']:
                    should_conditions.append(self._build_condition(condition))
                return Filter(should=should_conditions)
            
            else:
                return Filter(must=[self._build_condition(conditions)])
                
        except Exception as e:
            logger.error(f"Failed to build filter: {e}")
            return None
    
    def _build_condition(self, condition: Dict):
        """Build individual filter condition"""
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
    
    def _combine_search_results(self, 
                              vector_results: List[Dict], 
                              text_results: List[Dict],
                              alpha: float = 0.7) -> List[Dict]:
        """Combine and rerank vector and text search results"""
        try:
            # Create combined results with weighted scores
            combined = {}
            
            # Add vector results
            for result in vector_results:
                result_id = result['id']
                combined[result_id] = {
                    **result,
                    'vector_score': result['score'],
                    'text_score': 0.0,
                    'combined_score': alpha * result['score']
                }
            
            # Add text results
            for result in text_results:
                result_id = result['id']
                text_score = result['score']
                
                if result_id in combined:
                    # Update existing result
                    combined[result_id]['text_score'] = text_score
                    combined[result_id]['combined_score'] = (
                        alpha * combined[result_id]['vector_score'] + 
                        (1 - alpha) * text_score
                    )
                else:
                    # Add new result
                    combined[result_id] = {
                        **result,
                        'vector_score': 0.0,
                        'text_score': text_score,
                        'combined_score': (1 - alpha) * text_score
                    }
            
            # Sort by combined score
            sorted_results = sorted(
                combined.values(),
                key=lambda x: x['combined_score'],
                reverse=True
            )
            
            return sorted_results
            
        except Exception as e:
            logger.error(f"Failed to combine search results: {e}")
            return vector_results  # Fallback to vector results
    
    async def delete_points(self, point_ids: List[str]) -> Dict:
        """Delete points from the collection"""
        try:
            self.client.delete(
                collection_name=self.collection_name,
                points_selector=models.PointIdsList(
                    points=point_ids
                )
            )
            
            logger.info(f"Deleted {len(point_ids)} points from '{self.collection_name}'")
            
            return {
                'success': True,
                'points_deleted': len(point_ids),
                'collection_name': self.collection_name
            }
            
        except Exception as e:
            logger.error(f"Failed to delete points: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def get_collection_info(self) -> Dict:
        """Get information about the collection"""
        try:
            collection_info = self.client.get_collection(self.collection_name)
            
            return {
                'success': True,
                'collection_name': self.collection_name,
                'points_count': collection_info.points_count,
                'vectors_count': collection_info.vectors_count,
                'indexed_vectors_count': collection_info.indexed_vectors_count,
                'status': collection_info.status,
                'optimizer_status': collection_info.optimizer_status,
                'config': {
                    'vector_size': self.vector_size,
                    'distance_metric': self.distance_metric
                }
            }
            
        except Exception as e:
            logger.error(f"Failed to get collection info: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def health_check(self) -> Dict:
        """Perform health check on Qdrant connection and collection"""
        try:
            # Check connection
            collections = self.client.get_collections()
            
            # Check collection exists
            collection_exists = any(
                col.name == self.collection_name 
                for col in collections.collections
            )
            
            collection_info = None
            if collection_exists:
                collection_info = await self.get_collection_info()
            
            return {
                'success': True,
                'connection_healthy': True,
                'collection_exists': collection_exists,
                'collection_info': collection_info,
                'total_collections': len(collections.collections),
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Qdrant health check failed: {e}")
            return {
                'success': False,
                'connection_healthy': False,
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }