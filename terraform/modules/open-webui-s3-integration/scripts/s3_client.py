#!/usr/bin/env python3
"""
S3 Client for Open WebUI Document Storage

This module provides a secure S3 client with encryption, validation,
and comprehensive error handling for document storage operations.
"""

import os
import json
import logging
import hashlib
import mimetypes
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, BinaryIO
from urllib.parse import urlparse
import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from botocore.config import Config
import magic

logger = logging.getLogger(__name__)

class S3DocumentClient:
    def __init__(self, config_path: str = "/app/config/s3_config.json"):
        """Initialize S3 client with configuration"""
        self.config = self._load_config(config_path)
        self.s3_client = self._create_s3_client()
        self.bucket_name = self.config['s3']['bucket_name']
        
        # Initialize file type detector
        self.mime_detector = magic.Magic(mime=True)
        
    def _load_config(self, config_path: str) -> Dict:
        """Load S3 configuration from file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.error(f"Configuration file not found: {config_path}")
            raise
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in configuration file: {e}")
            raise
    
    def _create_s3_client(self):
        """Create configured S3 client"""
        s3_config = self.config['s3']
        
        # Configure boto3 client
        config = Config(
            region_name=s3_config['region'],
            retries={'max_attempts': 3, 'mode': 'adaptive'},
            max_pool_connections=50
        )
        
        # Create client with optional endpoint
        client_kwargs = {'config': config}
        
        if s3_config.get('endpoint'):
            client_kwargs['endpoint_url'] = s3_config['endpoint']
            
        # Use IRSA if available, otherwise use credentials
        if not os.getenv('AWS_ROLE_ARN'):
            client_kwargs.update({
                'aws_access_key_id': os.getenv('AWS_ACCESS_KEY_ID'),
                'aws_secret_access_key': os.getenv('AWS_SECRET_ACCESS_KEY')
            })
        
        return boto3.client('s3', **client_kwargs)
    
    def validate_file(self, file_path: str, filename: str) -> Tuple[bool, str]:
        """Validate file before upload"""
        try:
            # Check file size
            file_size = os.path.getsize(file_path)
            max_size = self.config['s3']['max_file_size']
            
            if file_size > max_size:
                return False, f"File size ({file_size}) exceeds maximum allowed size ({max_size})"
            
            # Check file extension
            file_ext = os.path.splitext(filename)[1].lower()
            allowed_extensions = self.config['s3']['allowed_extensions']
            
            if file_ext not in allowed_extensions:
                return False, f"File extension '{file_ext}' not allowed"
            
            # Validate content type if enabled
            if self.config['security']['content_type_validation']:
                detected_mime = self.mime_detector.from_file(file_path)
                expected_mime = mimetypes.guess_type(filename)[0]
                
                if expected_mime and not self._is_mime_type_compatible(detected_mime, expected_mime):
                    return False, f"File content type mismatch: detected '{detected_mime}', expected '{expected_mime}'"
            
            return True, "File validation passed"
            
        except Exception as e:
            logger.error(f"File validation error: {e}")
            return False, f"Validation error: {str(e)}"
    
    def _is_mime_type_compatible(self, detected: str, expected: str) -> bool:
        """Check if detected MIME type is compatible with expected"""
        # Handle common MIME type variations
        mime_mappings = {
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'application/msword': 'application/msword',
            'application/vnd.ms-excel': 'application/vnd.ms-excel',
            'application/vnd.ms-powerpoint': 'application/vnd.ms-powerpoint',
            'text/plain': 'text/plain',
            'application/pdf': 'application/pdf',
            'image/jpeg': 'image/jpeg',
            'image/png': 'image/png',
            'image/gif': 'image/gif'
        }
        
        # Direct match
        if detected == expected:
            return True
            
        # Check mappings
        if detected in mime_mappings and mime_mappings[detected] == expected:
            return True
            
        # Check generic types
        detected_type = detected.split('/')[0]
        expected_type = expected.split('/')[0] if expected else ''
        
        return detected_type == expected_type
    
    def sanitize_filename(self, filename: str) -> str:
        """Sanitize filename for safe storage"""
        if not self.config['security']['filename_sanitization']:
            return filename
        
        # Remove or replace dangerous characters
        import re
        
        # Keep only alphanumeric, dots, hyphens, underscores
        sanitized = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)
        
        # Ensure filename doesn't start with dot or dash
        sanitized = re.sub(r'^[.-]', '_', sanitized)
        
        # Limit length
        if len(sanitized) > 255:
            name, ext = os.path.splitext(sanitized)
            sanitized = name[:255-len(ext)] + ext
        
        return sanitized
    
    def generate_s3_key(self, user_id: str, filename: str, document_type: str = "document") -> str:
        """Generate S3 key for document storage"""
        sanitized_filename = self.sanitize_filename(filename)
        timestamp = datetime.utcnow().strftime("%Y/%m/%d")
        
        # Create unique key with timestamp and user ID
        key = f"{document_type}/{user_id}/{timestamp}/{sanitized_filename}"
        
        return key
    
    def calculate_file_hash(self, file_path: str) -> str:
        """Calculate SHA-256 hash of file"""
        sha256_hash = hashlib.sha256()
        
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                sha256_hash.update(chunk)
        
        return sha256_hash.hexdigest()
    
    def upload_file(self, file_path: str, s3_key: str, metadata: Dict = None) -> Dict:
        """Upload file to S3 with metadata"""
        try:
            # Validate file
            filename = os.path.basename(file_path)
            is_valid, validation_message = self.validate_file(file_path, filename)
            
            if not is_valid:
                raise ValueError(validation_message)
            
            # Calculate file hash
            file_hash = self.calculate_file_hash(file_path)
            
            # Prepare metadata
            upload_metadata = {
                'uploaded_at': datetime.utcnow().isoformat(),
                'file_hash': file_hash,
                'original_filename': filename,
                'file_size': str(os.path.getsize(file_path)),
                'content_type': mimetypes.guess_type(filename)[0] or 'application/octet-stream'
            }
            
            if metadata:
                upload_metadata.update(metadata)
            
            # Prepare upload parameters
            upload_params = {
                'Bucket': self.bucket_name,
                'Key': s3_key,
                'Metadata': upload_metadata,
                'ContentType': upload_metadata['content_type']
            }
            
            # Add server-side encryption if configured
            if self.config['s3'].get('server_side_encryption'):
                upload_params['ServerSideEncryption'] = 'AES256'
            
            # Upload file
            with open(file_path, 'rb') as f:
                self.s3_client.upload_fileobj(f, **upload_params)
            
            logger.info(f"Successfully uploaded file to S3: {s3_key}")
            
            return {
                'success': True,
                's3_key': s3_key,
                'bucket': self.bucket_name,
                'file_hash': file_hash,
                'metadata': upload_metadata,
                'url': f"s3://{self.bucket_name}/{s3_key}"
            }
            
        except Exception as e:
            logger.error(f"Failed to upload file to S3: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def download_file(self, s3_key: str, local_path: str) -> Dict:
        """Download file from S3"""
        try:
            self.s3_client.download_file(self.bucket_name, s3_key, local_path)
            
            logger.info(f"Successfully downloaded file from S3: {s3_key}")
            
            return {
                'success': True,
                's3_key': s3_key,
                'local_path': local_path
            }
            
        except Exception as e:
            logger.error(f"Failed to download file from S3: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def get_file_metadata(self, s3_key: str) -> Dict:
        """Get file metadata from S3"""
        try:
            response = self.s3_client.head_object(Bucket=self.bucket_name, Key=s3_key)
            
            return {
                'success': True,
                'metadata': response.get('Metadata', {}),
                'content_type': response.get('ContentType'),
                'content_length': response.get('ContentLength'),
                'last_modified': response.get('LastModified'),
                'etag': response.get('ETag')
            }
            
        except Exception as e:
            logger.error(f"Failed to get file metadata from S3: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def delete_file(self, s3_key: str) -> Dict:
        """Delete file from S3"""
        try:
            self.s3_client.delete_object(Bucket=self.bucket_name, Key=s3_key)
            
            logger.info(f"Successfully deleted file from S3: {s3_key}")
            
            return {
                'success': True,
                's3_key': s3_key
            }
            
        except Exception as e:
            logger.error(f"Failed to delete file from S3: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def list_files(self, prefix: str = "", max_keys: int = 1000) -> Dict:
        """List files in S3 bucket"""
        try:
            response = self.s3_client.list_objects_v2(
                Bucket=self.bucket_name,
                Prefix=prefix,
                MaxKeys=max_keys
            )
            
            files = []
            for obj in response.get('Contents', []):
                files.append({
                    'key': obj['Key'],
                    'size': obj['Size'],
                    'last_modified': obj['LastModified'],
                    'etag': obj['ETag']
                })
            
            return {
                'success': True,
                'files': files,
                'count': len(files),
                'is_truncated': response.get('IsTruncated', False)
            }
            
        except Exception as e:
            logger.error(f"Failed to list files from S3: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def generate_presigned_url(self, s3_key: str, expiration: int = None) -> Dict:
        """Generate presigned URL for file access"""
        try:
            if expiration is None:
                expiration = self.config['s3']['presigned_url_expiry']
            
            url = self.s3_client.generate_presigned_url(
                'get_object',
                Params={'Bucket': self.bucket_name, 'Key': s3_key},
                ExpiresIn=expiration
            )
            
            return {
                'success': True,
                'url': url,
                'expires_in': expiration,
                'expires_at': (datetime.utcnow() + timedelta(seconds=expiration)).isoformat()
            }
            
        except Exception as e:
            logger.error(f"Failed to generate presigned URL: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def copy_file(self, source_key: str, destination_key: str) -> Dict:
        """Copy file within S3 bucket"""
        try:
            copy_source = {'Bucket': self.bucket_name, 'Key': source_key}
            
            self.s3_client.copy_object(
                CopySource=copy_source,
                Bucket=self.bucket_name,
                Key=destination_key
            )
            
            logger.info(f"Successfully copied file in S3: {source_key} -> {destination_key}")
            
            return {
                'success': True,
                'source_key': source_key,
                'destination_key': destination_key
            }
            
        except Exception as e:
            logger.error(f"Failed to copy file in S3: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def get_bucket_info(self) -> Dict:
        """Get bucket information and statistics"""
        try:
            # Get bucket location
            location_response = self.s3_client.get_bucket_location(Bucket=self.bucket_name)
            location = location_response.get('LocationConstraint') or 'us-east-1'
            
            # Get bucket policy (if accessible)
            try:
                policy_response = self.s3_client.get_bucket_policy(Bucket=self.bucket_name)
                has_policy = True
            except ClientError:
                has_policy = False
            
            # Get bucket encryption (if accessible)
            try:
                encryption_response = self.s3_client.get_bucket_encryption(Bucket=self.bucket_name)
                has_encryption = True
            except ClientError:
                has_encryption = False
            
            return {
                'success': True,
                'bucket_name': self.bucket_name,
                'region': location,
                'has_policy': has_policy,
                'has_encryption': has_encryption
            }
            
        except Exception as e:
            logger.error(f"Failed to get bucket info: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def health_check(self) -> Dict:
        """Perform health check on S3 connectivity"""
        try:
            # Test bucket access
            self.s3_client.head_bucket(Bucket=self.bucket_name)
            
            # Test list operation
            self.s3_client.list_objects_v2(Bucket=self.bucket_name, MaxKeys=1)
            
            return {
                'success': True,
                'message': 'S3 connectivity healthy',
                'bucket': self.bucket_name,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except NoCredentialsError:
            return {
                'success': False,
                'error': 'AWS credentials not configured'
            }
        except ClientError as e:
            error_code = e.response['Error']['Code']
            return {
                'success': False,
                'error': f'S3 error: {error_code}'
            }
        except Exception as e:
            return {
                'success': False,
                'error': f'S3 health check failed: {str(e)}'
            }