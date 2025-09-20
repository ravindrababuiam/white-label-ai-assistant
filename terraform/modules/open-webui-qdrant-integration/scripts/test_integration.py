#!/usr/bin/env python3
"""
Integration Test Script for Open WebUI Qdrant Integration

This script tests the complete integration pipeline:
1. Embedding generation
2. Document indexing
3. Vector search
4. RAG functionality
"""

import asyncio
import json
import logging
import time
from typing import Dict, List
import requests
import sys

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class QdrantIntegrationTester:
    def __init__(self, base_url: str = "http://localhost"):
        self.embedding_url = f"{base_url}:8001"
        self.search_url = f"{base_url}:8002"
        self.indexer_url = f"{base_url}:8003"
        self.api_url = f"{base_url}:8004"
        
        self.test_results = {}
    
    async def test_service_health(self) -> Dict:
        """Test health endpoints of all services"""
        logger.info("Testing service health...")
        
        services = {
            "embedding_service": f"{self.embedding_url}/health",
            "search_service": f"{self.search_url}/health",
            "indexer_service": f"{self.indexer_url}/health",
            "api_service": f"{self.api_url}/health"
        }
        
        results = {}
        
        for service_name, health_url in services.items():
            try:
                response = requests.get(health_url, timeout=10)
                results[service_name] = {
                    "healthy": response.status_code == 200,
                    "response_time": response.elapsed.total_seconds(),
                    "status": response.json() if response.status_code == 200 else None
                }
                logger.info(f"✓ {service_name} is healthy")
            except Exception as e:
                results[service_name] = {
                    "healthy": False,
                    "error": str(e)
                }
                logger.error(f"✗ {service_name} health check failed: {e}")
        
        return results
    
    async def test_embedding_generation(self) -> Dict:
        """Test embedding generation"""
        logger.info("Testing embedding generation...")
        
        test_text = "This is a test document for embedding generation."
        
        try:
            # Test single embedding
            response = requests.post(
                f"{self.embedding_url}/embeddings",
                json={"text": test_text},
                timeout=30
            )
            response.raise_for_status()
            
            result = response.json()
            embedding = result.get("embedding", [])
            
            success = len(embedding) > 0 and isinstance(embedding[0], float)
            
            logger.info(f"✓ Generated embedding with {len(embedding)} dimensions")
            
            return {
                "success": success,
                "embedding_size": len(embedding),
                "processing_time": result.get("processing_time", 0),
                "model": result.get("model", "unknown")
            }
            
        except Exception as e:
            logger.error(f"✗ Embedding generation failed: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    async def test_batch_embedding_generation(self) -> Dict:
        """Test batch embedding generation"""
        logger.info("Testing batch embedding generation...")
        
        test_texts = [
            "First test document for batch processing.",
            "Second test document with different content.",
            "Third document to test batch embedding capabilities."
        ]
        
        try:
            response = requests.post(
                f"{self.embedding_url}/embeddings/batch",
                json={"texts": test_texts},
                timeout=60
            )
            response.raise_for_status()
            
            result = response.json()
            embeddings = result.get("embeddings", [])
            
            success = (len(embeddings) == len(test_texts) and 
                      all(len(emb) > 0 for emb in embeddings))
            
            logger.info(f"✓ Generated {len(embeddings)} batch embeddings")
            
            return {
                "success": success,
                "batch_size": len(embeddings),
                "processing_time": result.get("processing_time", 0),
                "total_texts": result.get("total_texts", 0)
            }
            
        except Exception as e:
            logger.error(f"✗ Batch embedding generation failed: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    async def test_document_search(self) -> Dict:
        """Test document search functionality"""
        logger.info("Testing document search...")
        
        # First, we need to have some documents indexed
        # For this test, we'll assume documents are already indexed
        # In a real scenario, you'd index test documents first
        
        test_query = "test document"
        
        try:
            response = requests.post(
                f"{self.search_url}/search",
                json={
                    "query": test_query,
                    "limit": 5,
                    "search_type": "hybrid",
                    "with_payload": True
                },
                timeout=30
            )
            response.raise_for_status()
            
            result = response.json()
            results = result.get("results", [])
            
            logger.info(f"✓ Search returned {len(results)} results")
            
            return {
                "success": True,
                "results_count": len(results),
                "search_type": result.get("search_type", "unknown"),
                "processing_time": result.get("processing_time", 0)
            }
            
        except Exception as e:
            logger.error(f"✗ Document search failed: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    async def test_vector_search(self) -> Dict:
        """Test direct vector search"""
        logger.info("Testing vector search...")
        
        # Generate a test vector first
        embedding_result = await self.test_embedding_generation()
        if not embedding_result.get("success"):
            return {
                "success": False,
                "error": "Could not generate test embedding"
            }
        
        # Get embedding for search
        test_text = "This is a test document for vector search."
        response = requests.post(
            f"{self.embedding_url}/embeddings",
            json={"text": test_text},
            timeout=30
        )
        
        if response.status_code != 200:
            return {
                "success": False,
                "error": "Could not generate search embedding"
            }
        
        embedding = response.json()["embedding"]
        
        try:
            # Perform vector search
            response = requests.post(
                f"{self.search_url}/search/vector",
                json={
                    "vector": embedding,
                    "limit": 5,
                    "with_payload": True
                },
                timeout=30
            )
            response.raise_for_status()
            
            result = response.json()
            results = result.get("results", [])
            
            logger.info(f"✓ Vector search returned {len(results)} results")
            
            return {
                "success": True,
                "results_count": len(results),
                "search_type": result.get("search_type", "vector"),
                "processing_time": result.get("processing_time", 0)
            }
            
        except Exception as e:
            logger.error(f"✗ Vector search failed: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    async def test_rag_functionality(self) -> Dict:
        """Test RAG (Retrieval Augmented Generation) functionality"""
        logger.info("Testing RAG functionality...")
        
        test_query = "What is the main topic of the documents?"
        
        try:
            # Test RAG context retrieval
            response = requests.post(
                f"{self.api_url}/rag/context",
                json={"query": test_query},
                timeout=30
            )
            response.raise_for_status()
            
            context_result = response.json()
            context_chunks = context_result.get("context", [])
            sources = context_result.get("sources", [])
            
            logger.info(f"✓ RAG context retrieved: {len(context_chunks)} chunks, {len(sources)} sources")
            
            # Test RAG prompt generation
            response = requests.post(
                f"{self.api_url}/rag/prompt",
                json={"query": test_query},
                timeout=30
            )
            response.raise_for_status()
            
            prompt_result = response.json()
            prompt = prompt_result.get("prompt", "")
            
            logger.info(f"✓ RAG prompt generated: {len(prompt)} characters")
            
            return {
                "success": True,
                "context_chunks": len(context_chunks),
                "sources_count": len(sources),
                "prompt_length": len(prompt),
                "context_available": len(context_chunks) > 0
            }
            
        except Exception as e:
            logger.error(f"✗ RAG functionality test failed: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    async def test_unified_search_api(self) -> Dict:
        """Test the unified search API"""
        logger.info("Testing unified search API...")
        
        test_query = "test document search"
        
        try:
            response = requests.post(
                f"{self.api_url}/search",
                json={
                    "query": test_query,
                    "limit": 5,
                    "threshold": 0.5
                },
                timeout=30
            )
            response.raise_for_status()
            
            result = response.json()
            results = result.get("results", [])
            
            logger.info(f"✓ Unified API search returned {len(results)} results")
            
            return {
                "success": True,
                "results_count": len(results),
                "total": result.get("total", 0),
                "processing_time": result.get("processing_time", 0)
            }
            
        except Exception as e:
            logger.error(f"✗ Unified search API test failed: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    async def test_openwebui_compatibility(self) -> Dict:
        """Test Open WebUI compatibility endpoint"""
        logger.info("Testing Open WebUI compatibility...")
        
        try:
            response = requests.get(
                f"{self.api_url}/api/v1/documents/search",
                params={"q": "test", "limit": 5},
                timeout=30
            )
            response.raise_for_status()
            
            result = response.json()
            documents = result.get("documents", [])
            
            logger.info(f"✓ Open WebUI endpoint returned {len(documents)} documents")
            
            return {
                "success": True,
                "documents_count": len(documents),
                "total": result.get("total", 0),
                "query": result.get("query", "")
            }
            
        except Exception as e:
            logger.error(f"✗ Open WebUI compatibility test failed: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    async def run_all_tests(self) -> Dict:
        """Run all integration tests"""
        logger.info("Starting Qdrant integration tests...")
        
        start_time = time.time()
        
        # Run all tests
        tests = [
            ("health_check", self.test_service_health()),
            ("embedding_generation", self.test_embedding_generation()),
            ("batch_embedding", self.test_batch_embedding_generation()),
            ("document_search", self.test_document_search()),
            ("vector_search", self.test_vector_search()),
            ("rag_functionality", self.test_rag_functionality()),
            ("unified_search_api", self.test_unified_search_api()),
            ("openwebui_compatibility", self.test_openwebui_compatibility())
        ]
        
        results = {}
        passed_tests = 0
        total_tests = len(tests)
        
        for test_name, test_coro in tests:
            logger.info(f"\n--- Running {test_name} ---")
            try:
                result = await test_coro
                results[test_name] = result
                
                if result.get("success", False):
                    passed_tests += 1
                    logger.info(f"✓ {test_name} PASSED")
                else:
                    logger.error(f"✗ {test_name} FAILED: {result.get('error', 'Unknown error')}")
                    
            except Exception as e:
                logger.error(f"✗ {test_name} FAILED with exception: {e}")
                results[test_name] = {
                    "success": False,
                    "error": str(e)
                }
        
        total_time = time.time() - start_time
        
        # Summary
        logger.info(f"\n{'='*50}")
        logger.info(f"INTEGRATION TEST SUMMARY")
        logger.info(f"{'='*50}")
        logger.info(f"Total tests: {total_tests}")
        logger.info(f"Passed: {passed_tests}")
        logger.info(f"Failed: {total_tests - passed_tests}")
        logger.info(f"Success rate: {(passed_tests/total_tests)*100:.1f}%")
        logger.info(f"Total time: {total_time:.2f}s")
        
        return {
            "summary": {
                "total_tests": total_tests,
                "passed_tests": passed_tests,
                "failed_tests": total_tests - passed_tests,
                "success_rate": (passed_tests/total_tests)*100,
                "total_time": total_time
            },
            "test_results": results
        }

async def main():
    """Main test function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Test Qdrant Integration")
    parser.add_argument("--base-url", default="http://localhost", 
                       help="Base URL for services (default: http://localhost)")
    parser.add_argument("--output", help="Output file for test results (JSON)")
    parser.add_argument("--verbose", "-v", action="store_true", 
                       help="Verbose logging")
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Run tests
    tester = QdrantIntegrationTester(args.base_url)
    results = await tester.run_all_tests()
    
    # Save results if requested
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        logger.info(f"Test results saved to {args.output}")
    
    # Exit with appropriate code
    success_rate = results["summary"]["success_rate"]
    if success_rate == 100:
        logger.info("All tests passed! 🎉")
        sys.exit(0)
    elif success_rate >= 80:
        logger.warning("Most tests passed, but some issues detected.")
        sys.exit(1)
    else:
        logger.error("Many tests failed. Integration has serious issues.")
        sys.exit(2)

if __name__ == "__main__":
    asyncio.run(main())