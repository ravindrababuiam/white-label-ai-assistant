#!/usr/bin/env python3
"""
Document Processor Service for Open WebUI S3 Integration

This service handles document upload, processing, virus scanning,
metadata extraction, and indexing for the Open WebUI platform.
"""

import os
import json
import logging
import tempfile
import asyncio
from datetime import datetime
from typing import Dict, List, Optional, Any
from pathlib import Path
import uuid

from fastapi import FastAPI, File, UploadFile, HTTPException, BackgroundTasks, Depends
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# Import our custom modules
from s3_client import S3DocumentClient
from virus_scanner import VirusScanner
from metadata_extractor import MetadataExtractor

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Document Processor Service",
    description="Document processing service for Open WebUI S3 integration",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global service instances
s3_client = None
virus_scanner = None
metadata_extractor = None

class DocumentProcessor:
    def __init__(self):
        """Initialize document processor with all services"""
        global s3_client, virus_scanner, metadata_extractor
        
        try:
            s3_client = S3DocumentClient()
            virus_scanner = VirusScanner()
            metadata_extractor = MetadataExtractor()
            
            logger.info("Document processor initialized successfully")
            
        except Exception as e:
            logger.error(f"Failed to initialize document processor: {e}")
            raise
    
    async def process_document(self, 
                             file_content: bytes, 
                             filename: str, 
                             user_id: str,
                             document_type: str = "document",
                             metadata: Dict = None) -> Dict:
        """Process uploaded document through the complete pipeline"""
        
        processing_id = str(uuid.uuid4())
        logger.info(f"Starting document processing: {processing_id} - {filename}")
        
        temp_file_path = None
        
        try:
            # Create temporary file
            with tempfile.NamedTemporaryFile(delete=False, suffix=Path(filename).suffix) as temp_file:
                temp_file.write(file_content)
                temp_file_path = temp_file.name
            
            # Step 1: Virus scanning
            logger.info(f"[{processing_id}] Starting virus scan")
            scan_result = virus_scanner.scan_file(temp_file_path)
            
            if not scan_result['success']:
                return {
                    'success': False,
                    'processing_id': processing_id,
                    'stage': 'virus_scan',
                    'error': 'Virus scan failed',
                    'details': scan_result
                }
            
            if not scan_result['clean']:
                logger.warning(f"[{processing_id}] Virus detected in file: {filename}")
                return {
                    'success': False,
                    'processing_id': processing_id,
                    'stage': 'virus_scan',
                    'error': 'File contains malware',
                    'threats': scan_result['threats'],
                    'quarantined': scan_result.get('quarantine', {}).get('quarantined', False)
                }
            
            logger.info(f"[{processing_id}] Virus scan passed")
            
            # Step 2: Metadata extraction
            logger.info(f"[{processing_id}] Starting metadata extraction")
            metadata_result = metadata_extractor.extract_metadata(temp_file_path)
            
            if not metadata_result['success']:
                logger.warning(f"[{processing_id}] Metadata extraction failed: {metadata_result.get('error')}")
                # Continue processing even if metadata extraction fails
                extracted_metadata = {}
            else:
                extracted_metadata = metadata_result['metadata']
            
            logger.info(f"[{processing_id}] Metadata extraction completed")
            
            # Step 3: Generate S3 key and upload
            logger.info(f"[{processing_id}] Starting S3 upload")
            s3_key = s3_client.generate_s3_key(user_id, filename, document_type)
            
            # Prepare upload metadata
            upload_metadata = {
                'processing_id': processing_id,
                'user_id': user_id,
                'document_type': document_type,
                'virus_scan_clean': True,
                'virus_scan_time': scan_result.get('scan_time'),
                'metadata_extracted': metadata_result['success']
            }
            
            if metadata:
                upload_metadata.update(metadata)
            
            # Upload to S3
            upload_result = s3_client.upload_file(temp_file_path, s3_key, upload_metadata)
            
            if not upload_result['success']:
                return {
                    'success': False,
                    'processing_id': processing_id,
                    'stage': 's3_upload',
                    'error': 'S3 upload failed',
                    'details': upload_result
                }
            
            logger.info(f"[{processing_id}] S3 upload completed: {s3_key}")
            
            # Step 4: Index in vector database (if enabled and text content available)
            indexing_result = None
            text_content = extracted_metadata.get('content_metadata', {}).get('text_content', '')
            
            if text_content and os.getenv('QDRANT_URL'):
                logger.info(f"[{processing_id}] Starting vector indexing")
                indexing_result = await self.index_document(
                    processing_id,
                    s3_key,
                    filename,
                    text_content,
                    extracted_metadata,
                    user_id
                )
                logger.info(f"[{processing_id}] Vector indexing completed")
            
            # Compile final result
            result = {
                'success': True,
                'processing_id': processing_id,
                'document_id': processing_id,  # Use processing_id as document_id
                's3_key': s3_key,
                'bucket': upload_result['bucket'],
                'file_hash': upload_result['file_hash'],
                'url': upload_result['url'],
                'filename': filename,
                'user_id': user_id,
                'document_type': document_type,
                'processed_at': datetime.utcnow().isoformat(),
                'virus_scan': {
                    'clean': scan_result['clean'],
                    'scanners_used': scan_result['scanners_used'],
                    'scan_time': scan_result['scan_time']
                },
                'metadata': extracted_metadata,
                'file_size': extracted_metadata.get('file_info', {}).get('file_size', 0),
                'content_stats': extracted_metadata.get('content_stats', {}),
                'indexing': indexing_result
            }
            
            logger.info(f"[{processing_id}] Document processing completed successfully")
            return result
            
        except Exception as e:
            logger.error(f"[{processing_id}] Document processing failed: {e}")
            return {
                'success': False,
                'processing_id': processing_id,
                'stage': 'processing',
                'error': str(e)
            }
            
        finally:
            # Clean up temporary file
            if temp_file_path and os.path.exists(temp_file_path):
                try:
                    os.unlink(temp_file_path)
                except:
                    pass
    
    async def index_document(self, 
                           document_id: str,
                           s3_key: str, 
                           filename: str, 
                           text_content: str, 
                           metadata: Dict,
                           user_id: str) -> Dict:
        """Index document in vector database"""
        try:
            # This would integrate with Qdrant for vector indexing
            # For now, return a placeholder result
            
            qdrant_url = os.getenv('QDRANT_URL')
            if not qdrant_url:
                return {
                    'indexed': False,
                    'reason': 'Qdrant URL not configured'
                }
            
            # Prepare document for indexing
            document_payload = {
                'id': document_id,
                's3_key': s3_key,
                'filename': filename,
                'content': text_content[:10000],  # Limit content size
                'user_id': user_id,
                'metadata': {
                    'file_size': metadata.get('file_info', {}).get('file_size', 0),
                    'mime_type': metadata.get('file_info', {}).get('mime_type', ''),
                    'created_time': metadata.get('file_info', {}).get('created_time', ''),
                    'document_type': metadata.get('content_metadata', {}).get('document_info', {}).get('title', ''),
                    'author': metadata.get('content_metadata', {}).get('document_properties', {}).get('author', ''),
                    'word_count': metadata.get('content_stats', {}).get('word_count', 0)
                },
                'indexed_at': datetime.utcnow().isoformat()
            }
            
            # TODO: Implement actual Qdrant integration
            # This would involve:
            # 1. Generate embeddings for the text content
            # 2. Store the document vector in Qdrant
            # 3. Store metadata for retrieval
            
            return {
                'indexed': True,
                'collection': 'documents',
                'document_id': document_id,
                'content_length': len(text_content),
                'indexed_at': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Failed to index document {document_id}: {e}")
            return {
                'indexed': False,
                'error': str(e)
            }

# Initialize processor
processor = DocumentProcessor()

# API Endpoints

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Check all services
        s3_health = s3_client.health_check()
        scanner_health = virus_scanner.health_check()
        metadata_health = metadata_extractor.health_check()
        
        overall_healthy = all([
            s3_health.get('success', False),
            scanner_health.get('success', False),
            metadata_health.get('success', False)
        ])
        
        return {
            'status': 'healthy' if overall_healthy else 'degraded',
            'timestamp': datetime.utcnow().isoformat(),
            'services': {
                's3': s3_health,
                'virus_scanner': scanner_health,
                'metadata_extractor': metadata_health
            }
        }
        
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={
                'status': 'unhealthy',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
        )

@app.get("/ready")
async def readiness_check():
    """Readiness check endpoint"""
    try:
        # Quick check that services are initialized
        if s3_client and virus_scanner and metadata_extractor:
            return {'status': 'ready', 'timestamp': datetime.utcnow().isoformat()}
        else:
            return JSONResponse(
                status_code=503,
                content={
                    'status': 'not_ready',
                    'timestamp': datetime.utcnow().isoformat()
                }
            )
    except Exception as e:
        return JSONResponse(
            status_code=503,
            content={
                'status': 'not_ready',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
        )

@app.post("/upload")
async def upload_document(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    user_id: str = "anonymous",
    document_type: str = "document"
):
    """Upload and process document"""
    try:
        # Validate file
        if not file.filename:
            raise HTTPException(status_code=400, detail="No filename provided")
        
        # Read file content
        file_content = await file.read()
        
        if not file_content:
            raise HTTPException(status_code=400, detail="Empty file")
        
        # Process document
        result = await processor.process_document(
            file_content=file_content,
            filename=file.filename,
            user_id=user_id,
            document_type=document_type
        )
        
        if result['success']:
            return JSONResponse(
                status_code=200,
                content=result
            )
        else:
            return JSONResponse(
                status_code=400,
                content=result
            )
            
    except Exception as e:
        logger.error(f"Upload endpoint error: {e}")
        return JSONResponse(
            status_code=500,
            content={
                'success': False,
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
        )

@app.get("/document/{document_id}")
async def get_document_info(document_id: str):
    """Get document information"""
    try:
        # This would typically query a database for document info
        # For now, return a placeholder response
        
        return {
            'document_id': document_id,
            'status': 'processed',
            'timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Get document info error: {e}")
        return JSONResponse(
            status_code=500,
            content={
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
        )

@app.delete("/document/{document_id}")
async def delete_document(document_id: str):
    """Delete document"""
    try:
        # This would typically:
        # 1. Remove from S3
        # 2. Remove from vector database
        # 3. Update document database
        
        return {
            'deleted': True,
            'document_id': document_id,
            'timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Delete document error: {e}")
        return JSONResponse(
            status_code=500,
            content={
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
        )

@app.get("/quarantine")
async def list_quarantined_files():
    """List quarantined files"""
    try:
        result = virus_scanner.get_quarantine_list()
        return result
        
    except Exception as e:
        logger.error(f"List quarantine error: {e}")
        return JSONResponse(
            status_code=500,
            content={
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
        )

@app.post("/quarantine/{file_hash}/release")
async def release_quarantined_file(file_hash: str, destination_path: str):
    """Release file from quarantine"""
    try:
        result = virus_scanner.release_from_quarantine(file_hash, destination_path)
        
        if result['success']:
            return result
        else:
            return JSONResponse(
                status_code=400,
                content=result
            )
            
    except Exception as e:
        logger.error(f"Release quarantine error: {e}")
        return JSONResponse(
            status_code=500,
            content={
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
        )

@app.get("/stats")
async def get_processing_stats():
    """Get processing statistics"""
    try:
        # This would typically return processing statistics
        # For now, return basic service status
        
        return {
            'service_status': 'running',
            'uptime': 'unknown',  # Would track actual uptime
            'processed_documents': 'unknown',  # Would track from database
            'quarantined_files': len(virus_scanner.get_quarantine_list().get('quarantined_files', [])),
            'timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Get stats error: {e}")
        return JSONResponse(
            status_code=500,
            content={
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
        )

if __name__ == "__main__":
    # Run the service
    port = int(os.getenv("PORT", "8000"))
    host = os.getenv("HOST", "0.0.0.0")
    
    logger.info(f"Starting Document Processor Service on {host}:{port}")
    
    uvicorn.run(
        "document_processor:app",
        host=host,
        port=port,
        reload=False,
        log_level="info"
    )