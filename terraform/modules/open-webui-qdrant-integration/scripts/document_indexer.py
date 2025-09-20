#!/usr/bin/env python3
"""
Document Indexer for Open WebUI Qdrant Integration

This service handles document processing, text extraction, chunking, and indexing
into the Qdrant vector database.
"""

import os
import json
import logging
import asyncio
from typing import Dict, List, Optional, Any, Union, Tuple
from datetime import datetime
import hashlib
import uuid
import mimetypes
from pathlib import Path

import aiofiles
import requests
from fastapi import FastAPI, HTTPException, UploadFile, File, BackgroundTasks
from pydantic import BaseModel, Field
import uvicorn

from qdrant_client import QdrantClient

# Import text processor from the same module
import sys
import os
sys.path.append(os.path.dirname(__file__))
from text_processor import TextProcessor

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Pydantic models
class DocumentMetadata(BaseModel):
    document_id: str = Field(..., description="Unique document identifier")
    filename: str = Field(..., description="Original filename")
    content_type: str = Field(..., description="MIME type of the document")
    size_bytes: int = Field(..., description="Document size in bytes")
    upload_timestamp: str = Field(..., description="Upload timestamp")
    user_id: Optional[str] = Field(None, description="User who uploaded the document")
    tags: Optional[List[str]] = Field([], description="Document tags")
    title: Optional[str] = Field(None, description="Document title")
    description: Optional[str] = Field(None, description="Document description")

class IndexingRequest(BaseModel):
    document_id: str = Field(..., description="Document ID to index")
    s3_key: str = Field(..., description="S3 key for the document")
    metadata: DocumentMetadata = Field(..., description="Document metadata")
    force_reindex: Optional[bool] = Field(False, description="Force reindexing if document exists")

class IndexingResponse(BaseModel):
    success: bool = Field(..., description="Whether indexing was successful")
    document_id: str = Field(..., description="Document ID")
    chunks_created: int = Field(..., description="Number of text chunks created")
    vectors_stored: int = Field(..., description="Number of vectors stored in Qdrant")
    processing_time: float = Field(..., description="Processing time in seconds")
    message: str = Field(..., description="Status message")

class IndexingStatus(BaseModel):
    document_id: str = Field(..., description="Document ID")
    status: str = Field(..., description="Indexing status")
    progress: float = Field(..., description="Progress percentage (0-100)")
    chunks_processed: int = Field(..., description="Number of chunks processed")
    total_chunks: int = Field(..., description="Total number of chunks")
    error_message: Optional[str] = Field(None, description="Error message if failed")
    started_at: str = Field(..., description="Indexing start timestamp")
    completed_at: Optional[str] = Field(None, description="Indexing completion timestamp")

class DocumentIndexer:
    def __init__(self):
        # Configuration
        self.qdrant_url = os.getenv('QDRANT_URL', 'http://qdrant:6333')
        self.qdrant_api_key = os.getenv('QDRANT_API_KEY', '')
        self.collection_name = os.getenv('COLLECTION_NAME', 'documents')
        self.embedding_service_url = os.getenv('EMBEDDING_SERVICE_URL', 'http://embedding-service:8001')
        self.s3_endpoint = os.getenv('S3_ENDPOINT', '')
        self.s3_bucket = os.getenv('S3_BUCKET', '')
        
        # Indexing configuration
        self.auto_index = os.getenv('AUTO_INDEX_DOCUMENTS', 'true').lower() == 'true'
        self.batch_size = int(os.getenv('INDEX_BATCH_SIZE', '50'))
        self.index_timeout = int(os.getenv('INDEX_TIMEOUT', '300'))
        self.update_existing = os.getenv('UPDATE_EXISTING_DOCUMENTS', 'true').lower() == 'true'
        self.extract_keywords = os.getenv('EXTRACT_KEYWORDS', 'true').lower() == 'true'
        
        # Text processing
        self.chunk_size = int(os.getenv('TEXT_CHUNK_SIZE', '1000'))
        self.chunk_overlap = int(os.getenv('TEXT_CHUNK_OVERLAP', '200'))
        
        # Initialize components
        self.text_processor = TextProcessor()
        self.qdrant_client = self._create_qdrant_client()
        
        # Track indexing jobs
        self.indexing_jobs = {}
        
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
    
    async def _download_document(self, s3_key: str) -> bytes:
        """Download document from S3"""
        try:
            # This is a simplified implementation
            # In production, you'd use boto3 or similar S3 client
            url = f"{self.s3_endpoint}/{self.s3_bucket}/{s3_key}"
            
            response = await asyncio.to_thread(
                requests.get,
                url,
                timeout=60
            )
            response.raise_for_status()
            
            return response.content
            
        except Exception as e:
            logger.error(f"Failed to download document from S3: {e}")
            raise
    
    async def _get_embeddings(self, texts: List[str]) -> List[List[float]]:
        """Get embeddings for multiple texts"""
        try:
            payload = {
                "texts": texts,
                "normalize": True
            }
            
            response = await asyncio.to_thread(
                requests.post,
                f"{self.embedding_service_url}/embeddings/batch",
                json=payload,
                timeout=120
            )
            response.raise_for_status()
            
            result = response.json()
            return result['embeddings']
            
        except Exception as e:
            logger.error(f"Failed to get embeddings: {e}")
            raise
    
    async def _extract_text_from_document(self, content: bytes, content_type: str, filename: str) -> str:
        """Extract text from document content"""
        try:
            return await self.text_processor.extract_text(content, content_type, filename)
        except Exception as e:
            logger.error(f"Failed to extract text from document: {e}")
            raise
    
    async def _create_text_chunks(self, text: str, metadata: DocumentMetadata) -> List[Dict]:
        """Create text chunks with metadata"""
        try:
            chunks = await self.text_processor.chunk_text(
                text=text,
                chunk_size=self.chunk_size,
                overlap=self.chunk_overlap
            )
            
            # Extract keywords if enabled
            keywords = []
            if self.extract_keywords:
                keywords = await self.text_processor.extract_keywords(text)
            
            # Create chunk objects with metadata
            chunk_objects = []
            for i, chunk in enumerate(chunks):
                chunk_id = f"{metadata.document_id}_chunk_{i}"
                
                chunk_metadata = {
                    'document_id': metadata.document_id,
                    'chunk_id': chunk_id,
                    'chunk_index': i,
                    'total_chunks': len(chunks),
                    'filename': metadata.filename,
                    'content_type': metadata.content_type,
                    'upload_timestamp': metadata.upload_timestamp,
                    'user_id': metadata.user_id,
                    'tags': metadata.tags or [],
                    'title': metadata.title,
                    'description': metadata.description,
                    'content': chunk,
                    'keywords': keywords,
                    'chunk_size': len(chunk),
                    'indexed_at': datetime.utcnow().isoformat()
                }
                
                chunk_objects.append({
                    'id': chunk_id,
                    'text': chunk,
                    'metadata': chunk_metadata
                })
            
            return chunk_objects
            
        except Exception as e:
            logger.error(f"Failed to create text chunks: {e}")
            raise
    
    async def _store_vectors_in_qdrant(self, chunks: List[Dict], embeddings: List[List[float]]) -> int:
        """Store vectors in Qdrant collection"""
        try:
            from qdrant_client.http.models import PointStruct
            
            if len(chunks) != len(embeddings):
                raise ValueError(f"Chunks count ({len(chunks)}) doesn't match embeddings count ({len(embeddings)})")
            
            # Prepare points for Qdrant
            points = []
            for chunk, embedding in zip(chunks, embeddings):
                point = PointStruct(
                    id=chunk['id'],
                    vector=embedding,
                    payload=chunk['metadata']
                )
                points.append(point)
            
            # Store points in batches
            total_stored = 0
            for i in range(0, len(points), self.batch_size):
                batch = points[i:i + self.batch_size]
                
                await asyncio.to_thread(
                    self.qdrant_client.upsert,
                    collection_name=self.collection_name,
                    points=batch
                )
                
                total_stored += len(batch)
                logger.debug(f"Stored batch of {len(batch)} vectors in Qdrant")
            
            logger.info(f"Successfully stored {total_stored} vectors in Qdrant")
            return total_stored
            
        except Exception as e:
            logger.error(f"Failed to store vectors in Qdrant: {e}")
            raise
    
    async def _check_document_exists(self, document_id: str) -> bool:
        """Check if document is already indexed"""
        try:
            from qdrant_client.http.models import Filter, FieldCondition, Match
            
            # Search for any chunks with this document_id
            search_filter = Filter(
                must=[
                    FieldCondition(
                        key="document_id",
                        match=Match(value=document_id)
                    )
                ]
            )
            
            result = await asyncio.to_thread(
                self.qdrant_client.scroll,
                collection_name=self.collection_name,
                scroll_filter=search_filter,
                limit=1,
                with_payload=False,
                with_vectors=False
            )
            
            return len(result[0]) > 0
            
        except Exception as e:
            logger.error(f"Failed to check if document exists: {e}")
            return False
    
    async def _delete_existing_document(self, document_id: str) -> int:
        """Delete existing document chunks from Qdrant"""
        try:
            from qdrant_client.http.models import Filter, FieldCondition, Match
            
            # Find all chunks for this document
            search_filter = Filter(
                must=[
                    FieldCondition(
                        key="document_id",
                        match=Match(value=document_id)
                    )
                ]
            )
            
            # Scroll through all chunks
            all_points = []
            offset = None
            
            while True:
                result = await asyncio.to_thread(
                    self.qdrant_client.scroll,
                    collection_name=self.collection_name,
                    scroll_filter=search_filter,
                    limit=100,
                    offset=offset,
                    with_payload=False,
                    with_vectors=False
                )
                
                points, next_offset = result
                all_points.extend([point.id for point in points])
                
                if next_offset is None:
                    break
                offset = next_offset
            
            # Delete points
            if all_points:
                from qdrant_client.http.models import PointIdsList
                
                await asyncio.to_thread(
                    self.qdrant_client.delete,
                    collection_name=self.collection_name,
                    points_selector=PointIdsList(points=all_points)
                )
                
                logger.info(f"Deleted {len(all_points)} existing chunks for document {document_id}")
            
            return len(all_points)
            
        except Exception as e:
            logger.error(f"Failed to delete existing document: {e}")
            return 0
    
    async def index_document(self, request: IndexingRequest) -> IndexingResponse:
        """Index a document into the vector database"""
        start_time = datetime.utcnow()
        document_id = request.document_id
        
        try:
            # Update job status
            self.indexing_jobs[document_id] = IndexingStatus(
                document_id=document_id,
                status="processing",
                progress=0.0,
                chunks_processed=0,
                total_chunks=0,
                started_at=start_time.isoformat()
            )
            
            logger.info(f"Starting indexing for document {document_id}")
            
            # Check if document already exists
            if not request.force_reindex:
                exists = await self._check_document_exists(document_id)
                if exists and not self.update_existing:
                    self.indexing_jobs[document_id].status = "skipped"
                    self.indexing_jobs[document_id].progress = 100.0
                    self.indexing_jobs[document_id].completed_at = datetime.utcnow().isoformat()
                    
                    return IndexingResponse(
                        success=True,
                        document_id=document_id,
                        chunks_created=0,
                        vectors_stored=0,
                        processing_time=0.0,
                        message="Document already exists and update_existing is disabled"
                    )
            
            # Update progress
            self.indexing_jobs[document_id].progress = 10.0
            
            # Download document from S3
            logger.info(f"Downloading document {document_id} from S3")
            content = await self._download_document(request.s3_key)
            
            # Update progress
            self.indexing_jobs[document_id].progress = 20.0
            
            # Extract text from document
            logger.info(f"Extracting text from document {document_id}")
            text = await self._extract_text_from_document(
                content=content,
                content_type=request.metadata.content_type,
                filename=request.metadata.filename
            )
            
            if not text.strip():
                raise ValueError("No text could be extracted from the document")
            
            # Update progress
            self.indexing_jobs[document_id].progress = 40.0
            
            # Create text chunks
            logger.info(f"Creating text chunks for document {document_id}")
            chunks = await self._create_text_chunks(text, request.metadata)
            
            self.indexing_jobs[document_id].total_chunks = len(chunks)
            self.indexing_jobs[document_id].progress = 50.0
            
            # Generate embeddings for chunks
            logger.info(f"Generating embeddings for {len(chunks)} chunks")
            chunk_texts = [chunk['text'] for chunk in chunks]
            embeddings = await self._get_embeddings(chunk_texts)
            
            # Update progress
            self.indexing_jobs[document_id].progress = 70.0
            
            # Delete existing document if updating
            deleted_chunks = 0
            if request.force_reindex or self.update_existing:
                deleted_chunks = await self._delete_existing_document(document_id)
            
            # Update progress
            self.indexing_jobs[document_id].progress = 80.0
            
            # Store vectors in Qdrant
            logger.info(f"Storing {len(embeddings)} vectors in Qdrant")
            vectors_stored = await self._store_vectors_in_qdrant(chunks, embeddings)
            
            # Update final status
            end_time = datetime.utcnow()
            processing_time = (end_time - start_time).total_seconds()
            
            self.indexing_jobs[document_id].status = "completed"
            self.indexing_jobs[document_id].progress = 100.0
            self.indexing_jobs[document_id].chunks_processed = len(chunks)
            self.indexing_jobs[document_id].completed_at = end_time.isoformat()
            
            logger.info(f"Successfully indexed document {document_id} in {processing_time:.2f}s")
            
            return IndexingResponse(
                success=True,
                document_id=document_id,
                chunks_created=len(chunks),
                vectors_stored=vectors_stored,
                processing_time=processing_time,
                message=f"Document indexed successfully. Created {len(chunks)} chunks, stored {vectors_stored} vectors."
            )
            
        except Exception as e:
            # Update error status
            self.indexing_jobs[document_id].status = "failed"
            self.indexing_jobs[document_id].error_message = str(e)
            self.indexing_jobs[document_id].completed_at = datetime.utcnow().isoformat()
            
            logger.error(f"Failed to index document {document_id}: {e}")
            raise
    
    async def get_indexing_status(self, document_id: str) -> Optional[IndexingStatus]:
        """Get indexing status for a document"""
        return self.indexing_jobs.get(document_id)
    
    async def delete_document(self, document_id: str) -> Dict:
        """Delete a document and all its chunks from the index"""
        try:
            deleted_chunks = await self._delete_existing_document(document_id)
            
            # Remove from indexing jobs if present
            if document_id in self.indexing_jobs:
                del self.indexing_jobs[document_id]
            
            return {
                'success': True,
                'document_id': document_id,
                'chunks_deleted': deleted_chunks,
                'message': f"Deleted {deleted_chunks} chunks for document {document_id}"
            }
            
        except Exception as e:
            logger.error(f"Failed to delete document {document_id}: {e}")
            return {
                'success': False,
                'document_id': document_id,
                'error': str(e)
            }
    
    async def health_check(self) -> Dict:
        """Perform health check"""
        try:
            # Check Qdrant connection
            collections = await asyncio.to_thread(
                self.qdrant_client.get_collections
            )
            
            # Check if collection exists
            collection_names = [col.name for col in collections.collections]
            collection_exists = self.collection_name in collection_names
            
            # Check embedding service
            embedding_service_healthy = False
            try:
                response = await asyncio.to_thread(
                    requests.get,
                    f"{self.embedding_service_url}/health",
                    timeout=10
                )
                embedding_service_healthy = response.status_code == 200
            except:
                pass
            
            return {
                'status': 'healthy' if collection_exists and embedding_service_healthy else 'unhealthy',
                'qdrant_connected': True,
                'collection_exists': collection_exists,
                'embedding_service_connected': embedding_service_healthy,
                'active_indexing_jobs': len([job for job in self.indexing_jobs.values() if job.status == 'processing']),
                'total_jobs': len(self.indexing_jobs),
                'configuration': {
                    'collection_name': self.collection_name,
                    'auto_index': self.auto_index,
                    'batch_size': self.batch_size,
                    'chunk_size': self.chunk_size,
                    'chunk_overlap': self.chunk_overlap,
                    'update_existing': self.update_existing,
                    'extract_keywords': self.extract_keywords
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
    title="Document Indexer Service",
    description="Document indexing service for Open WebUI Qdrant integration",
    version="1.0.0"
)

# Initialize service
indexer_service = DocumentIndexer()

@app.post("/index", response_model=IndexingResponse)
async def index_document(request: IndexingRequest, background_tasks: BackgroundTasks):
    """Index a document into the vector database"""
    try:
        # For long-running indexing, we could run this in background
        # For now, run synchronously
        result = await indexer_service.index_document(request)
        return result
        
    except Exception as e:
        logger.error(f"Document indexing failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/status/{document_id}", response_model=IndexingStatus)
async def get_indexing_status(document_id: str):
    """Get indexing status for a document"""
    try:
        status = await indexer_service.get_indexing_status(document_id)
        if status:
            return status
        else:
            raise HTTPException(status_code=404, detail="Document not found in indexing jobs")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get indexing status: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/documents/{document_id}")
async def delete_document(document_id: str):
    """Delete a document from the index"""
    try:
        result = await indexer_service.delete_document(document_id)
        if result['success']:
            return result
        else:
            raise HTTPException(status_code=500, detail=result['error'])
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Document deletion failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/jobs")
async def list_indexing_jobs():
    """List all indexing jobs"""
    try:
        return {
            'jobs': list(indexer_service.indexing_jobs.values()),
            'total_jobs': len(indexer_service.indexing_jobs),
            'active_jobs': len([job for job in indexer_service.indexing_jobs.values() if job.status == 'processing'])
        }
    except Exception as e:
        logger.error(f"Failed to list indexing jobs: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        health_status = await indexer_service.health_check()
        return health_status
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/ready")
async def readiness_check():
    """Readiness check endpoint"""
    try:
        health_status = await indexer_service.health_check()
        if (health_status['status'] == 'healthy' and 
            health_status['qdrant_connected'] and 
            health_status['collection_exists'] and
            health_status['embedding_service_connected']):
            return {"status": "ready"}
        else:
            raise HTTPException(status_code=503, detail="Service not ready")
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(
        "document_indexer:app",
        host="0.0.0.0",
        port=8003,
        log_level="info"
    )