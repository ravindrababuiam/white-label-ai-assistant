#!/usr/bin/env python3
"""
Upload Handler for Open WebUI S3 Integration

This module provides upload handling functionality with chunked uploads,
progress tracking, and integration with the document processor.
"""

import os
import json
import logging
import asyncio
import aiohttp
import hashlib
from datetime import datetime
from typing import Dict, List, Optional, AsyncGenerator, Callable
from pathlib import Path
import tempfile

logger = logging.getLogger(__name__)

class UploadHandler:
    def __init__(self, config_path: str = "/app/config/s3_config.json"):
        """Initialize upload handler with configuration"""
        self.config = self._load_config(config_path)
        self.chunk_size = self.config['upload']['chunk_size']
        self.max_concurrent = self.config['upload']['max_concurrent_uploads']
        self.retry_attempts = self.config['upload']['retry_attempts']
        self.timeout = self.config['upload']['timeout_seconds']
        
        # Document processor endpoint
        self.processor_url = os.getenv('DOCUMENT_PROCESSOR_URL', 'http://localhost:8000')
        
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
    
    def calculate_file_hash(self, file_path: str) -> str:
        """Calculate SHA-256 hash of file"""
        sha256_hash = hashlib.sha256()
        
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                sha256_hash.update(chunk)
        
        return sha256_hash.hexdigest()
    
    async def validate_upload_request(self, 
                                    filename: str, 
                                    file_size: int, 
                                    content_type: str = None) -> Dict:
        """Validate upload request before processing"""
        try:
            # Check file size
            max_size = self.config['s3']['max_file_size']
            if file_size > max_size:
                return {
                    'valid': False,
                    'error': f'File size ({file_size}) exceeds maximum allowed size ({max_size})'
                }
            
            # Check file extension
            file_ext = Path(filename).suffix.lower()
            allowed_extensions = self.config['s3']['allowed_extensions']
            
            if file_ext not in allowed_extensions:
                return {
                    'valid': False,
                    'error': f'File extension "{file_ext}" not allowed'
                }
            
            # Check content type if provided
            if content_type and self.config['security']['content_type_validation']:
                import mimetypes
                expected_type = mimetypes.guess_type(filename)[0]
                
                if expected_type and not content_type.startswith(expected_type.split('/')[0]):
                    return {
                        'valid': False,
                        'error': f'Content type mismatch: got "{content_type}", expected "{expected_type}"'
                    }
            
            return {
                'valid': True,
                'message': 'Upload request validation passed'
            }
            
        except Exception as e:
            logger.error(f"Upload validation error: {e}")
            return {
                'valid': False,
                'error': f'Validation error: {str(e)}'
            }
    
    async def create_upload_session(self, 
                                  filename: str, 
                                  file_size: int, 
                                  user_id: str,
                                  metadata: Dict = None) -> Dict:
        """Create upload session for tracking progress"""
        try:
            import uuid
            
            session_id = str(uuid.uuid4())
            
            session_data = {
                'session_id': session_id,
                'filename': filename,
                'file_size': file_size,
                'user_id': user_id,
                'metadata': metadata or {},
                'status': 'initialized',
                'created_at': datetime.utcnow().isoformat(),
                'chunks_uploaded': 0,
                'total_chunks': (file_size + self.chunk_size - 1) // self.chunk_size,
                'bytes_uploaded': 0,
                'progress_percentage': 0.0
            }
            
            # Store session data (in production, this would be in a database)
            session_file = f"/tmp/upload_session_{session_id}.json"
            with open(session_file, 'w') as f:
                json.dump(session_data, f)
            
            logger.info(f"Created upload session: {session_id} for file: {filename}")
            
            return {
                'success': True,
                'session_id': session_id,
                'chunk_size': self.chunk_size,
                'total_chunks': session_data['total_chunks']
            }
            
        except Exception as e:
            logger.error(f"Failed to create upload session: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def get_upload_session(self, session_id: str) -> Dict:
        """Get upload session data"""
        try:
            session_file = f"/tmp/upload_session_{session_id}.json"
            
            if not os.path.exists(session_file):
                return {
                    'success': False,
                    'error': 'Upload session not found'
                }
            
            with open(session_file, 'r') as f:
                session_data = json.load(f)
            
            return {
                'success': True,
                'session': session_data
            }
            
        except Exception as e:
            logger.error(f"Failed to get upload session: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def update_upload_progress(self, 
                                   session_id: str, 
                                   chunk_number: int, 
                                   chunk_size: int) -> Dict:
        """Update upload progress for session"""
        try:
            session_result = await self.get_upload_session(session_id)
            
            if not session_result['success']:
                return session_result
            
            session_data = session_result['session']
            
            # Update progress
            session_data['chunks_uploaded'] = max(session_data['chunks_uploaded'], chunk_number)
            session_data['bytes_uploaded'] = session_data['chunks_uploaded'] * self.chunk_size
            session_data['progress_percentage'] = min(
                (session_data['bytes_uploaded'] / session_data['file_size']) * 100,
                100.0
            )
            session_data['last_updated'] = datetime.utcnow().isoformat()
            
            # Save updated session
            session_file = f"/tmp/upload_session_{session_id}.json"
            with open(session_file, 'w') as f:
                json.dump(session_data, f)
            
            return {
                'success': True,
                'progress': session_data['progress_percentage'],
                'bytes_uploaded': session_data['bytes_uploaded'],
                'chunks_uploaded': session_data['chunks_uploaded']
            }
            
        except Exception as e:
            logger.error(f"Failed to update upload progress: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def upload_chunk(self, 
                         session_id: str, 
                         chunk_number: int, 
                         chunk_data: bytes,
                         progress_callback: Callable = None) -> Dict:
        """Upload a single chunk"""
        try:
            # Get session data
            session_result = await self.get_upload_session(session_id)
            
            if not session_result['success']:
                return session_result
            
            session_data = session_result['session']
            
            # Store chunk temporarily
            chunk_file = f"/tmp/chunk_{session_id}_{chunk_number:06d}"
            
            with open(chunk_file, 'wb') as f:
                f.write(chunk_data)
            
            # Update progress
            progress_result = await self.update_upload_progress(
                session_id, 
                chunk_number, 
                len(chunk_data)
            )
            
            # Call progress callback if provided
            if progress_callback and progress_result['success']:
                await progress_callback(session_id, progress_result)
            
            logger.debug(f"Uploaded chunk {chunk_number} for session {session_id}")
            
            return {
                'success': True,
                'chunk_number': chunk_number,
                'chunk_size': len(chunk_data),
                'progress': progress_result.get('progress', 0)
            }
            
        except Exception as e:
            logger.error(f"Failed to upload chunk: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def finalize_upload(self, session_id: str) -> Dict:
        """Finalize upload by combining chunks and processing"""
        try:
            # Get session data
            session_result = await self.get_upload_session(session_id)
            
            if not session_result['success']:
                return session_result
            
            session_data = session_result['session']
            
            logger.info(f"Finalizing upload for session: {session_id}")
            
            # Combine chunks into final file
            temp_file_path = f"/tmp/upload_{session_id}_{session_data['filename']}"
            
            with open(temp_file_path, 'wb') as output_file:
                for chunk_num in range(session_data['total_chunks']):
                    chunk_file = f"/tmp/chunk_{session_id}_{chunk_num:06d}"
                    
                    if os.path.exists(chunk_file):
                        with open(chunk_file, 'rb') as chunk_f:
                            output_file.write(chunk_f.read())
                        
                        # Clean up chunk file
                        os.unlink(chunk_file)
                    else:
                        logger.warning(f"Missing chunk {chunk_num} for session {session_id}")
            
            # Verify file integrity
            actual_size = os.path.getsize(temp_file_path)
            expected_size = session_data['file_size']
            
            if actual_size != expected_size:
                return {
                    'success': False,
                    'error': f'File size mismatch: expected {expected_size}, got {actual_size}'
                }
            
            # Calculate file hash
            file_hash = self.calculate_file_hash(temp_file_path)
            
            # Send to document processor
            processing_result = await self.send_to_processor(
                temp_file_path,
                session_data['filename'],
                session_data['user_id'],
                session_data.get('metadata', {})
            )
            
            # Update session status
            session_data['status'] = 'completed' if processing_result['success'] else 'failed'
            session_data['completed_at'] = datetime.utcnow().isoformat()
            session_data['file_hash'] = file_hash
            session_data['processing_result'] = processing_result
            
            # Save final session data
            session_file = f"/tmp/upload_session_{session_id}.json"
            with open(session_file, 'w') as f:
                json.dump(session_data, f)
            
            # Clean up temporary file
            try:
                os.unlink(temp_file_path)
            except:
                pass
            
            logger.info(f"Upload finalized for session: {session_id}")
            
            return {
                'success': processing_result['success'],
                'session_id': session_id,
                'file_hash': file_hash,
                'processing_result': processing_result
            }
            
        except Exception as e:
            logger.error(f"Failed to finalize upload: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def send_to_processor(self, 
                              file_path: str, 
                              filename: str, 
                              user_id: str,
                              metadata: Dict) -> Dict:
        """Send file to document processor"""
        try:
            logger.info(f"Sending file to processor: {filename}")
            
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=self.timeout)) as session:
                
                # Prepare multipart form data
                data = aiohttp.FormData()
                
                # Add file
                with open(file_path, 'rb') as f:
                    data.add_field('file', f, filename=filename)
                
                # Add metadata
                data.add_field('user_id', user_id)
                data.add_field('document_type', metadata.get('document_type', 'document'))
                
                # Send request to processor
                async with session.post(f"{self.processor_url}/upload", data=data) as response:
                    
                    if response.status == 200:
                        result = await response.json()
                        logger.info(f"Document processor completed successfully for: {filename}")
                        return result
                    else:
                        error_text = await response.text()
                        logger.error(f"Document processor failed: HTTP {response.status} - {error_text}")
                        return {
                            'success': False,
                            'error': f'Processor error: HTTP {response.status}',
                            'details': error_text
                        }
            
        except asyncio.TimeoutError:
            logger.error(f"Document processor timeout for file: {filename}")
            return {
                'success': False,
                'error': 'Document processor timeout'
            }
        except Exception as e:
            logger.error(f"Failed to send file to processor: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def cancel_upload(self, session_id: str) -> Dict:
        """Cancel upload session"""
        try:
            # Get session data
            session_result = await self.get_upload_session(session_id)
            
            if not session_result['success']:
                return session_result
            
            session_data = session_result['session']
            
            # Clean up chunk files
            for chunk_num in range(session_data['total_chunks']):
                chunk_file = f"/tmp/chunk_{session_id}_{chunk_num:06d}"
                if os.path.exists(chunk_file):
                    os.unlink(chunk_file)
            
            # Update session status
            session_data['status'] = 'cancelled'
            session_data['cancelled_at'] = datetime.utcnow().isoformat()
            
            # Save session data
            session_file = f"/tmp/upload_session_{session_id}.json"
            with open(session_file, 'w') as f:
                json.dump(session_data, f)
            
            logger.info(f"Upload cancelled for session: {session_id}")
            
            return {
                'success': True,
                'session_id': session_id,
                'status': 'cancelled'
            }
            
        except Exception as e:
            logger.error(f"Failed to cancel upload: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def cleanup_old_sessions(self, max_age_hours: int = 24) -> Dict:
        """Clean up old upload sessions"""
        try:
            import glob
            from datetime import timedelta
            
            cutoff_time = datetime.utcnow() - timedelta(hours=max_age_hours)
            cleaned_count = 0
            
            # Find all session files
            session_files = glob.glob("/tmp/upload_session_*.json")
            
            for session_file in session_files:
                try:
                    # Check file age
                    file_mtime = datetime.fromtimestamp(os.path.getmtime(session_file))
                    
                    if file_mtime < cutoff_time:
                        # Load session data to clean up chunks
                        with open(session_file, 'r') as f:
                            session_data = json.load(f)
                        
                        session_id = session_data['session_id']
                        
                        # Clean up chunk files
                        chunk_files = glob.glob(f"/tmp/chunk_{session_id}_*")
                        for chunk_file in chunk_files:
                            os.unlink(chunk_file)
                        
                        # Remove session file
                        os.unlink(session_file)
                        cleaned_count += 1
                        
                        logger.debug(f"Cleaned up old session: {session_id}")
                        
                except Exception as e:
                    logger.warning(f"Failed to clean up session file {session_file}: {e}")
            
            logger.info(f"Cleaned up {cleaned_count} old upload sessions")
            
            return {
                'success': True,
                'cleaned_sessions': cleaned_count
            }
            
        except Exception as e:
            logger.error(f"Failed to cleanup old sessions: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def get_upload_stats(self) -> Dict:
        """Get upload statistics"""
        try:
            import glob
            
            # Count active sessions
            session_files = glob.glob("/tmp/upload_session_*.json")
            
            stats = {
                'active_sessions': 0,
                'completed_sessions': 0,
                'failed_sessions': 0,
                'cancelled_sessions': 0,
                'total_sessions': len(session_files)
            }
            
            for session_file in session_files:
                try:
                    with open(session_file, 'r') as f:
                        session_data = json.load(f)
                    
                    status = session_data.get('status', 'unknown')
                    
                    if status == 'completed':
                        stats['completed_sessions'] += 1
                    elif status == 'failed':
                        stats['failed_sessions'] += 1
                    elif status == 'cancelled':
                        stats['cancelled_sessions'] += 1
                    else:
                        stats['active_sessions'] += 1
                        
                except Exception as e:
                    logger.warning(f"Failed to read session file {session_file}: {e}")
            
            return {
                'success': True,
                'stats': stats,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Failed to get upload stats: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def health_check(self) -> Dict:
        """Perform health check on upload handler"""
        try:
            # Check configuration
            config_ok = bool(self.config and self.chunk_size > 0)
            
            # Check processor connectivity (basic check)
            processor_configured = bool(self.processor_url)
            
            # Check temporary directory
            temp_dir_ok = os.path.exists('/tmp') and os.access('/tmp', os.W_OK)
            
            overall_healthy = config_ok and processor_configured and temp_dir_ok
            
            return {
                'success': True,
                'healthy': overall_healthy,
                'checks': {
                    'configuration': config_ok,
                    'processor_configured': processor_configured,
                    'temp_directory': temp_dir_ok
                },
                'config': {
                    'chunk_size': self.chunk_size,
                    'max_concurrent': self.max_concurrent,
                    'retry_attempts': self.retry_attempts,
                    'timeout': self.timeout
                },
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Upload handler health check failed: {e}")
            return {
                'success': False,
                'error': str(e)
            }