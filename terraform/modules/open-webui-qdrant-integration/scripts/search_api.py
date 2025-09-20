#!/usr/bin/env python3
"""
Search API for Open WebUI Qdrant Integration

This service provides a unified API for document search functionality,
integrating with the vector search service and providing Open WebUI compatible endpoints.
"""

import os
import json
import logging
import asyncio
from typing import Dict, List, Optional, Any, Union
from datetime import datetime
import time

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import uvicorn
import requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Pydantic models for Open WebUI compatibility
class ChatMessage(BaseModel):
    role: str = Field(..., description="Message role (user, assistant, system)")
    content: str = Field(..., description="Message content")

class SearchQuery(BaseModel):
    query: str = Field(..., description="Search query")
    limit: Optional[int] = Field(10, description="Maximum number of results")
    threshold: Optional[float] = Field(0.7, description="Similarity threshold")
    search_type: Optional[str] = Field("hybrid", description="Search type")
    filters: Optional[Dict] = Field(None, description="Additional filters")

class DocumentSearchResult(BaseModel):
    id: str = Field(..., description="Document chunk ID")
    document_id: str = Field(..., description="Original document ID")
    title: str = Field(..., description="Document title")
    content: str = Field(..., description="Relevant content snippet")
    score: float = Field(..., description="Relevance score")
    metadata: Dict = Field(..., description="Document metadata")
    url: Optional[str] = Field(None, description="Document URL if available")

class SearchResponse(BaseModel):
    results: List[DocumentSearchResult] = Field(..., description="Search results")
    total: int = Field(..., description="Total number of results")
    query: str = Field(..., description="Original search query")
    search_type: str = Field(..., description="Type of search performed")
    processing_time: float = Field(..., description="Search processing time")

class RAGContext(BaseModel):
    query: str = Field(..., description="User query")
    context: List[str] = Field(..., description="Retrieved context chunks")
    sources: List[Dict] = Field(..., description="Source documents")
    total_sources: int = Field(..., description="Total number of source documents")

class OpenWebUISearchAPI:
    def __init__(self):
        # Service URLs
        self.vector_search_url = os.getenv('VECTOR_SEARCH_SERVICE_URL', 'http://vector-search-service:8002')
        self.embedding_service_url = os.getenv('EMBEDDING_SERVICE_URL', 'http://embedding-service:8001')
        self.indexer_service_url = os.getenv('INDEXER_SERVICE_URL', 'http://document-indexer:8003')
        
        # Search configuration
        self.default_limit = int(os.getenv('DEFAULT_SEARCH_LIMIT', '10'))
        self.max_limit = int(os.getenv('MAX_SEARCH_LIMIT', '50'))
        self.default_threshold = float(os.getenv('DEFAULT_THRESHOLD', '0.7'))
        self.context_window = int(os.getenv('CONTEXT_WINDOW', '4000'))
        self.max_context_chunks = int(os.getenv('MAX_CONTEXT_CHUNKS', '5'))
        
        # RAG configuration
        self.enable_rag = os.getenv('ENABLE_RAG', 'true').lower() == 'true'
        self.rag_prompt_template = os.getenv('RAG_PROMPT_TEMPLATE', self._get_default_rag_template())
        
    def _get_default_rag_template(self) -> str:
        """Get default RAG prompt template"""
        return """Based on the following context, please answer the user's question. If the context doesn't contain enough information to answer the question, please say so.

Context:
{context}

Question: {question}

Answer:"""
    
    async def search_documents(self, 
                             query: str,
                             limit: int = 10,
                             threshold: float = 0.7,
                             search_type: str = "hybrid",
                             filters: Dict = None) -> SearchResponse:
        """Search documents and return formatted results"""
        try:
            start_time = time.time()
            
            # Validate parameters
            limit = min(limit, self.max_limit)
            
            # Prepare search request
            search_request = {
                "query": query,
                "limit": limit,
                "score_threshold": threshold,
                "search_type": search_type,
                "filters": filters,
                "with_payload": True,
                "with_vectors": False
            }
            
            # Call vector search service
            response = await asyncio.to_thread(
                requests.post,
                f"{self.vector_search_url}/search",
                json=search_request,
                timeout=30
            )
            response.raise_for_status()
            
            search_results = response.json()
            
            # Format results for Open WebUI
            formatted_results = []
            for result in search_results['results']:
                payload = result.get('payload', {})
                
                # Extract relevant information
                document_id = payload.get('document_id', result['id'])
                title = payload.get('title') or payload.get('filename', 'Unknown Document')
                content = payload.get('content', '')
                
                # Truncate content if too long
                if len(content) > 500:
                    content = content[:500] + "..."
                
                formatted_result = DocumentSearchResult(
                    id=result['id'],
                    document_id=document_id,
                    title=title,
                    content=content,
                    score=result['score'],
                    metadata=payload,
                    url=self._generate_document_url(document_id, payload)
                )
                formatted_results.append(formatted_result)
            
            processing_time = time.time() - start_time
            
            return SearchResponse(
                results=formatted_results,
                total=len(formatted_results),
                query=query,
                search_type=search_type,
                processing_time=processing_time
            )
            
        except Exception as e:
            logger.error(f"Document search failed: {e}")
            raise
    
    def _generate_document_url(self, document_id: str, metadata: Dict) -> Optional[str]:
        """Generate URL for document if available"""
        # This would be customized based on your document storage setup
        # For now, return None as we don't have a document viewer
        return None
    
    async def get_rag_context(self, query: str, limit: int = None) -> RAGContext:
        """Get context for RAG (Retrieval Augmented Generation)"""
        try:
            limit = limit or self.max_context_chunks
            
            # Search for relevant documents
            search_results = await self.search_documents(
                query=query,
                limit=limit,
                threshold=self.default_threshold,
                search_type="hybrid"
            )
            
            # Extract context chunks
            context_chunks = []
            sources = []
            
            for result in search_results.results:
                # Add content to context
                context_chunks.append(result.content)
                
                # Add source information
                source_info = {
                    'document_id': result.document_id,
                    'title': result.title,
                    'score': result.score,
                    'chunk_id': result.id
                }
                sources.append(source_info)
            
            # Combine context chunks
            combined_context = '\n\n'.join(context_chunks)
            
            # Truncate if too long
            if len(combined_context) > self.context_window:
                combined_context = combined_context[:self.context_window] + "..."
            
            return RAGContext(
                query=query,
                context=context_chunks,
                sources=sources,
                total_sources=len(sources)
            )
            
        except Exception as e:
            logger.error(f"Failed to get RAG context: {e}")
            raise
    
    async def generate_rag_prompt(self, query: str, context: RAGContext) -> str:
        """Generate RAG prompt with context"""
        try:
            # Combine context chunks
            context_text = '\n\n'.join(context.context)
            
            # Format prompt
            prompt = self.rag_prompt_template.format(
                context=context_text,
                question=query
            )
            
            return prompt
            
        except Exception as e:
            logger.error(f"Failed to generate RAG prompt: {e}")
            return query  # Fallback to original query
    
    async def search_and_rank(self, 
                            query: str,
                            conversation_history: List[ChatMessage] = None,
                            limit: int = 10) -> SearchResponse:
        """Search documents with conversation context for better ranking"""
        try:
            # Extract context from conversation history
            context_queries = [query]
            
            if conversation_history:
                # Add recent user messages as additional context
                for message in conversation_history[-3:]:  # Last 3 messages
                    if message.role == "user" and message.content.strip():
                        context_queries.append(message.content)
            
            # Perform search with main query
            search_results = await self.search_documents(
                query=query,
                limit=limit * 2,  # Get more results for reranking
                threshold=self.default_threshold * 0.8,  # Lower threshold for more results
                search_type="hybrid"
            )
            
            # Rerank results based on conversation context
            if conversation_history and len(search_results.results) > 1:
                reranked_results = await self._rerank_with_context(
                    search_results.results,
                    context_queries
                )
                search_results.results = reranked_results[:limit]
                search_results.total = len(search_results.results)
            
            return search_results
            
        except Exception as e:
            logger.error(f"Search and rank failed: {e}")
            raise
    
    async def _rerank_with_context(self, 
                                 results: List[DocumentSearchResult],
                                 context_queries: List[str]) -> List[DocumentSearchResult]:
        """Rerank results based on multiple context queries"""
        try:
            # Simple reranking based on keyword overlap
            # In production, you might use a more sophisticated reranking model
            
            for result in results:
                context_score = 0
                content_lower = result.content.lower()
                
                for context_query in context_queries:
                    query_words = context_query.lower().split()
                    matches = sum(1 for word in query_words if word in content_lower)
                    context_score += matches / len(query_words) if query_words else 0
                
                # Combine original score with context score
                result.score = (result.score * 0.7) + (context_score * 0.3)
            
            # Sort by updated score
            return sorted(results, key=lambda x: x.score, reverse=True)
            
        except Exception as e:
            logger.error(f"Reranking failed: {e}")
            return results
    
    async def get_document_suggestions(self, partial_query: str, limit: int = 5) -> List[str]:
        """Get document-based query suggestions"""
        try:
            if len(partial_query) < 3:
                return []
            
            # Search for documents matching partial query
            search_results = await self.search_documents(
                query=partial_query,
                limit=limit * 2,
                threshold=0.5,
                search_type="text"
            )
            
            # Extract unique suggestions from document titles and content
            suggestions = set()
            
            for result in search_results.results:
                # Add document title if relevant
                title = result.title.lower()
                if partial_query.lower() in title:
                    suggestions.add(result.title)
                
                # Extract phrases from content
                content_words = result.content.split()
                for i in range(len(content_words) - 2):
                    phrase = ' '.join(content_words[i:i+3])
                    if partial_query.lower() in phrase.lower():
                        suggestions.add(phrase)
                
                if len(suggestions) >= limit:
                    break
            
            return list(suggestions)[:limit]
            
        except Exception as e:
            logger.error(f"Failed to get document suggestions: {e}")
            return []
    
    async def health_check(self) -> Dict:
        """Perform health check on all services"""
        try:
            services_status = {}
            
            # Check vector search service
            try:
                response = await asyncio.to_thread(
                    requests.get,
                    f"{self.vector_search_url}/health",
                    timeout=10
                )
                services_status['vector_search'] = {
                    'healthy': response.status_code == 200,
                    'response_time': response.elapsed.total_seconds() if hasattr(response, 'elapsed') else 0
                }
            except Exception as e:
                services_status['vector_search'] = {
                    'healthy': False,
                    'error': str(e)
                }
            
            # Check embedding service
            try:
                response = await asyncio.to_thread(
                    requests.get,
                    f"{self.embedding_service_url}/health",
                    timeout=10
                )
                services_status['embedding_service'] = {
                    'healthy': response.status_code == 200,
                    'response_time': response.elapsed.total_seconds() if hasattr(response, 'elapsed') else 0
                }
            except Exception as e:
                services_status['embedding_service'] = {
                    'healthy': False,
                    'error': str(e)
                }
            
            # Check indexer service
            try:
                response = await asyncio.to_thread(
                    requests.get,
                    f"{self.indexer_service_url}/health",
                    timeout=10
                )
                services_status['indexer_service'] = {
                    'healthy': response.status_code == 200,
                    'response_time': response.elapsed.total_seconds() if hasattr(response, 'elapsed') else 0
                }
            except Exception as e:
                services_status['indexer_service'] = {
                    'healthy': False,
                    'error': str(e)
                }
            
            # Overall health
            all_healthy = all(service.get('healthy', False) for service in services_status.values())
            
            return {
                'status': 'healthy' if all_healthy else 'unhealthy',
                'services': services_status,
                'rag_enabled': self.enable_rag,
                'configuration': {
                    'default_limit': self.default_limit,
                    'max_limit': self.max_limit,
                    'default_threshold': self.default_threshold,
                    'context_window': self.context_window,
                    'max_context_chunks': self.max_context_chunks
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
    title="Search API for Open WebUI",
    description="Unified search API for Open WebUI Qdrant integration",
    version="1.0.0"
)

# Add CORS middleware for Open WebUI compatibility
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize service
search_api = OpenWebUISearchAPI()

@app.post("/search", response_model=SearchResponse)
async def search_documents(query: SearchQuery):
    """Search documents"""
    try:
        result = await search_api.search_documents(
            query=query.query,
            limit=query.limit or search_api.default_limit,
            threshold=query.threshold or search_api.default_threshold,
            search_type=query.search_type or "hybrid",
            filters=query.filters
        )
        return result
        
    except Exception as e:
        logger.error(f"Search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/rag/context", response_model=RAGContext)
async def get_rag_context(query: SearchQuery):
    """Get context for RAG"""
    try:
        if not search_api.enable_rag:
            raise HTTPException(status_code=404, detail="RAG not enabled")
        
        context = await search_api.get_rag_context(
            query=query.query,
            limit=query.limit or search_api.max_context_chunks
        )
        return context
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"RAG context retrieval failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/rag/prompt")
async def generate_rag_prompt(query: SearchQuery):
    """Generate RAG prompt with context"""
    try:
        if not search_api.enable_rag:
            raise HTTPException(status_code=404, detail="RAG not enabled")
        
        # Get context
        context = await search_api.get_rag_context(query.query)
        
        # Generate prompt
        prompt = await search_api.generate_rag_prompt(query.query, context)
        
        return {
            'prompt': prompt,
            'context': context,
            'query': query.query
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"RAG prompt generation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/search/contextual", response_model=SearchResponse)
async def contextual_search(request: Dict):
    """Search with conversation context"""
    try:
        query = request.get('query', '')
        conversation_history = request.get('conversation_history', [])
        limit = request.get('limit', search_api.default_limit)
        
        # Convert conversation history to ChatMessage objects
        chat_history = []
        for msg in conversation_history:
            if isinstance(msg, dict) and 'role' in msg and 'content' in msg:
                chat_history.append(ChatMessage(**msg))
        
        result = await search_api.search_and_rank(
            query=query,
            conversation_history=chat_history,
            limit=limit
        )
        return result
        
    except Exception as e:
        logger.error(f"Contextual search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/suggestions")
async def get_suggestions(q: str = Query(..., description="Partial query"), limit: int = Query(5, description="Number of suggestions")):
    """Get query suggestions based on documents"""
    try:
        suggestions = await search_api.get_document_suggestions(q, limit)
        return {'suggestions': suggestions}
        
    except Exception as e:
        logger.error(f"Suggestions failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        health_status = await search_api.health_check()
        return health_status
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/ready")
async def readiness_check():
    """Readiness check endpoint"""
    try:
        health_status = await search_api.health_check()
        if health_status['status'] == 'healthy':
            return {"status": "ready"}
        else:
            raise HTTPException(status_code=503, detail="Service not ready")
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail=str(e))

# Open WebUI specific endpoints
@app.get("/api/v1/documents/search")
async def openwebui_search(q: str = Query(..., description="Search query"), limit: int = Query(10, description="Result limit")):
    """Open WebUI compatible search endpoint"""
    try:
        result = await search_api.search_documents(
            query=q,
            limit=limit,
            threshold=search_api.default_threshold,
            search_type="hybrid"
        )
        
        # Format for Open WebUI compatibility
        return {
            'documents': [
                {
                    'id': r.id,
                    'title': r.title,
                    'content': r.content,
                    'score': r.score,
                    'metadata': r.metadata
                }
                for r in result.results
            ],
            'total': result.total,
            'query': result.query
        }
        
    except Exception as e:
        logger.error(f"Open WebUI search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(
        "search_api:app",
        host="0.0.0.0",
        port=8004,
        log_level="info"
    )