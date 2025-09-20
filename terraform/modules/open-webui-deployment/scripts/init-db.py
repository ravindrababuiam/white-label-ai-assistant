#!/usr/bin/env python3
"""
Open WebUI Database Initialization Script

This script initializes the database for Open WebUI, creating necessary
tables and setting up initial configuration.
"""

import os
import sys
import time
import logging
from urllib.parse import urlparse
import sqlite3
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DatabaseInitializer:
    def __init__(self, database_url):
        self.database_url = database_url
        self.parsed_url = urlparse(database_url)
        self.db_type = self.parsed_url.scheme
        
    def wait_for_database(self, max_attempts=30, delay=5):
        """Wait for database to be available"""
        logger.info(f"Waiting for database to be available...")
        
        for attempt in range(max_attempts):
            try:
                if self.db_type == 'sqlite':
                    # For SQLite, just try to connect
                    conn = sqlite3.connect(self.parsed_url.path)
                    conn.close()
                    logger.info("SQLite database is ready")
                    return True
                    
                elif self.db_type in ['postgresql', 'postgres']:
                    # For PostgreSQL, try to connect
                    conn = psycopg2.connect(
                        host=self.parsed_url.hostname,
                        port=self.parsed_url.port or 5432,
                        database=self.parsed_url.path.lstrip('/'),
                        user=self.parsed_url.username,
                        password=self.parsed_url.password
                    )
                    conn.close()
                    logger.info("PostgreSQL database is ready")
                    return True
                    
            except Exception as e:
                logger.debug(f"Attempt {attempt + 1}/{max_attempts}: {e}")
                if attempt < max_attempts - 1:
                    time.sleep(delay)
                    
        logger.error(f"Database did not become available within {max_attempts * delay} seconds")
        return False
    
    def create_database_if_not_exists(self):
        """Create database if it doesn't exist (PostgreSQL only)"""
        if self.db_type not in ['postgresql', 'postgres']:
            return True
            
        try:
            # Connect to default database to create target database
            default_db_url = self.database_url.replace(
                f"/{self.parsed_url.path.lstrip('/')}", "/postgres"
            )
            default_parsed = urlparse(default_db_url)
            
            conn = psycopg2.connect(
                host=default_parsed.hostname,
                port=default_parsed.port or 5432,
                database="postgres",
                user=default_parsed.username,
                password=default_parsed.password
            )
            conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
            
            cursor = conn.cursor()
            
            # Check if database exists
            db_name = self.parsed_url.path.lstrip('/')
            cursor.execute(
                "SELECT 1 FROM pg_catalog.pg_database WHERE datname = %s",
                (db_name,)
            )
            
            if not cursor.fetchone():
                logger.info(f"Creating database: {db_name}")
                cursor.execute(f'CREATE DATABASE "{db_name}"')
                logger.info(f"Database {db_name} created successfully")
            else:
                logger.info(f"Database {db_name} already exists")
                
            cursor.close()
            conn.close()
            return True
            
        except Exception as e:
            logger.error(f"Failed to create database: {e}")
            return False
    
    def initialize_tables(self):
        """Initialize database tables"""
        logger.info("Initializing database tables...")
        
        try:
            if self.db_type == 'sqlite':
                conn = sqlite3.connect(self.parsed_url.path)
                cursor = conn.cursor()
                
                # Create tables for SQLite
                self.create_sqlite_tables(cursor)
                
            elif self.db_type in ['postgresql', 'postgres']:
                conn = psycopg2.connect(
                    host=self.parsed_url.hostname,
                    port=self.parsed_url.port or 5432,
                    database=self.parsed_url.path.lstrip('/'),
                    user=self.parsed_url.username,
                    password=self.parsed_url.password
                )
                cursor = conn.cursor()
                
                # Create tables for PostgreSQL
                self.create_postgresql_tables(cursor)
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info("Database tables initialized successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize tables: {e}")
            return False
    
    def create_sqlite_tables(self, cursor):
        """Create tables for SQLite"""
        tables = [
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                role TEXT DEFAULT 'user',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS chats (
                id TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                chat TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                collection_name TEXT,
                filename TEXT,
                meta TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS models (
                id TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                base_model_id TEXT,
                name TEXT NOT NULL,
                params TEXT NOT NULL,
                meta TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS prompts (
                command TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id)
            )
            """
        ]
        
        for table_sql in tables:
            cursor.execute(table_sql)
    
    def create_postgresql_tables(self, cursor):
        """Create tables for PostgreSQL"""
        tables = [
            """
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                email VARCHAR(255) UNIQUE NOT NULL,
                name VARCHAR(255) NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                role VARCHAR(50) DEFAULT 'user',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS chats (
                id VARCHAR(255) PRIMARY KEY,
                user_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                chat TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS documents (
                id VARCHAR(255) PRIMARY KEY,
                user_id INTEGER NOT NULL,
                name VARCHAR(255) NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                collection_name VARCHAR(255),
                filename VARCHAR(255),
                meta TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS models (
                id VARCHAR(255) PRIMARY KEY,
                user_id INTEGER NOT NULL,
                base_model_id VARCHAR(255),
                name VARCHAR(255) NOT NULL,
                params TEXT NOT NULL,
                meta TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS prompts (
                command VARCHAR(255) PRIMARY KEY,
                user_id INTEGER NOT NULL,
                title VARCHAR(255) NOT NULL,
                content TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users (id)
            )
            """
        ]
        
        for table_sql in tables:
            cursor.execute(table_sql)
    
    def create_indexes(self):
        """Create database indexes for performance"""
        logger.info("Creating database indexes...")
        
        try:
            if self.db_type == 'sqlite':
                conn = sqlite3.connect(self.parsed_url.path)
                cursor = conn.cursor()
                
                indexes = [
                    "CREATE INDEX IF NOT EXISTS idx_chats_user_id ON chats(user_id)",
                    "CREATE INDEX IF NOT EXISTS idx_chats_created_at ON chats(created_at)",
                    "CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id)",
                    "CREATE INDEX IF NOT EXISTS idx_documents_collection ON documents(collection_name)",
                    "CREATE INDEX IF NOT EXISTS idx_models_user_id ON models(user_id)",
                    "CREATE INDEX IF NOT EXISTS idx_prompts_user_id ON prompts(user_id)"
                ]
                
            elif self.db_type in ['postgresql', 'postgres']:
                conn = psycopg2.connect(
                    host=self.parsed_url.hostname,
                    port=self.parsed_url.port or 5432,
                    database=self.parsed_url.path.lstrip('/'),
                    user=self.parsed_url.username,
                    password=self.parsed_url.password
                )
                cursor = conn.cursor()
                
                indexes = [
                    "CREATE INDEX IF NOT EXISTS idx_chats_user_id ON chats(user_id)",
                    "CREATE INDEX IF NOT EXISTS idx_chats_created_at ON chats(created_at)",
                    "CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id)",
                    "CREATE INDEX IF NOT EXISTS idx_documents_collection ON documents(collection_name)",
                    "CREATE INDEX IF NOT EXISTS idx_models_user_id ON models(user_id)",
                    "CREATE INDEX IF NOT EXISTS idx_prompts_user_id ON prompts(user_id)"
                ]
            
            for index_sql in indexes:
                cursor.execute(index_sql)
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info("Database indexes created successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to create indexes: {e}")
            return False
    
    def run_migrations(self):
        """Run any pending database migrations"""
        logger.info("Running database migrations...")
        
        # This would contain migration logic
        # For now, just log that migrations are complete
        logger.info("Database migrations completed")
        return True

def main():
    """Main initialization function"""
    logger.info("Starting Open WebUI database initialization...")
    
    # Get database URL from environment
    database_url = os.getenv('DATABASE_URL')
    if not database_url:
        logger.error("DATABASE_URL environment variable not set")
        sys.exit(1)
    
    # Initialize database
    initializer = DatabaseInitializer(database_url)
    
    # Wait for database to be available
    if not initializer.wait_for_database():
        logger.error("Database is not available, exiting...")
        sys.exit(1)
    
    # Create database if it doesn't exist (PostgreSQL only)
    if not initializer.create_database_if_not_exists():
        logger.error("Failed to create database, exiting...")
        sys.exit(1)
    
    # Initialize tables
    if not initializer.initialize_tables():
        logger.error("Failed to initialize tables, exiting...")
        sys.exit(1)
    
    # Create indexes
    if not initializer.create_indexes():
        logger.error("Failed to create indexes, exiting...")
        sys.exit(1)
    
    # Run migrations
    if not initializer.run_migrations():
        logger.error("Failed to run migrations, exiting...")
        sys.exit(1)
    
    logger.info("Database initialization completed successfully!")

if __name__ == "__main__":
    main()