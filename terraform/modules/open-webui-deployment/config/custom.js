// Custom JavaScript for White Label AI Assistant

(function() {
    'use strict';

    // Configuration
    const CONFIG = {
        brandName: 'White Label AI Assistant',
        supportEmail: 'support@example.com',
        documentationUrl: 'https://docs.example.com',
        maxFileSize: 100 * 1024 * 1024, // 100MB
        allowedFileTypes: ['.pdf', '.txt', '.docx', '.md', '.csv', '.json'],
        autoSaveInterval: 30000, // 30 seconds
        maxChatHistory: 100
    };

    // Utility functions
    const utils = {
        // Debounce function for performance
        debounce: function(func, wait) {
            let timeout;
            return function executedFunction(...args) {
                const later = () => {
                    clearTimeout(timeout);
                    func(...args);
                };
                clearTimeout(timeout);
                timeout = setTimeout(later, wait);
            };
        },

        // Format file size
        formatFileSize: function(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        },

        // Validate file type
        isValidFileType: function(filename) {
            const extension = '.' + filename.split('.').pop().toLowerCase();
            return CONFIG.allowedFileTypes.includes(extension);
        },

        // Show notification
        showNotification: function(message, type = 'info') {
            const notification = document.createElement('div');
            notification.className = `notification notification-${type}`;
            notification.textContent = message;
            
            // Style the notification
            Object.assign(notification.style, {
                position: 'fixed',
                top: '20px',
                right: '20px',
                padding: '12px 20px',
                borderRadius: '8px',
                color: 'white',
                fontWeight: '500',
                zIndex: '10000',
                maxWidth: '400px',
                boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)'
            });

            // Set background color based on type
            const colors = {
                info: '#3b82f6',
                success: '#10b981',
                warning: '#f59e0b',
                error: '#ef4444'
            };
            notification.style.backgroundColor = colors[type] || colors.info;

            document.body.appendChild(notification);

            // Auto remove after 5 seconds
            setTimeout(() => {
                if (notification.parentNode) {
                    notification.parentNode.removeChild(notification);
                }
            }, 5000);
        }
    };

    // Enhanced file upload functionality
    const fileUpload = {
        init: function() {
            this.setupDragAndDrop();
            this.setupFileInput();
            this.setupProgressTracking();
        },

        setupDragAndDrop: function() {
            const uploadArea = document.querySelector('.upload-area');
            if (!uploadArea) return;

            ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
                uploadArea.addEventListener(eventName, this.preventDefaults, false);
                document.body.addEventListener(eventName, this.preventDefaults, false);
            });

            ['dragenter', 'dragover'].forEach(eventName => {
                uploadArea.addEventListener(eventName, () => uploadArea.classList.add('dragover'), false);
            });

            ['dragleave', 'drop'].forEach(eventName => {
                uploadArea.addEventListener(eventName, () => uploadArea.classList.remove('dragover'), false);
            });

            uploadArea.addEventListener('drop', this.handleDrop.bind(this), false);
        },

        preventDefaults: function(e) {
            e.preventDefault();
            e.stopPropagation();
        },

        handleDrop: function(e) {
            const files = e.dataTransfer.files;
            this.handleFiles(files);
        },

        setupFileInput: function() {
            const fileInput = document.querySelector('input[type="file"]');
            if (fileInput) {
                fileInput.addEventListener('change', (e) => {
                    this.handleFiles(e.target.files);
                });
            }
        },

        handleFiles: function(files) {
            Array.from(files).forEach(file => {
                if (this.validateFile(file)) {
                    this.uploadFile(file);
                }
            });
        },

        validateFile: function(file) {
            // Check file size
            if (file.size > CONFIG.maxFileSize) {
                utils.showNotification(
                    `File "${file.name}" is too large. Maximum size is ${utils.formatFileSize(CONFIG.maxFileSize)}.`,
                    'error'
                );
                return false;
            }

            // Check file type
            if (!utils.isValidFileType(file.name)) {
                utils.showNotification(
                    `File type not supported. Allowed types: ${CONFIG.allowedFileTypes.join(', ')}`,
                    'error'
                );
                return false;
            }

            return true;
        },

        uploadFile: function(file) {
            const formData = new FormData();
            formData.append('file', file);

            // Create progress indicator
            const progressId = 'upload-' + Date.now();
            this.createProgressIndicator(progressId, file.name);

            fetch('/api/v1/documents/upload', {
                method: 'POST',
                body: formData,
                headers: {
                    'Authorization': `Bearer ${this.getAuthToken()}`
                }
            })
            .then(response => {
                if (!response.ok) {
                    throw new Error(`Upload failed: ${response.statusText}`);
                }
                return response.json();
            })
            .then(data => {
                this.removeProgressIndicator(progressId);
                utils.showNotification(`File "${file.name}" uploaded successfully!`, 'success');
                this.onUploadSuccess(data);
            })
            .catch(error => {
                this.removeProgressIndicator(progressId);
                utils.showNotification(`Upload failed: ${error.message}`, 'error');
                console.error('Upload error:', error);
            });
        },

        createProgressIndicator: function(id, filename) {
            const indicator = document.createElement('div');
            indicator.id = id;
            indicator.className = 'upload-progress';
            indicator.innerHTML = `
                <div class="upload-progress-bar">
                    <div class="upload-progress-fill"></div>
                </div>
                <div class="upload-progress-text">Uploading ${filename}...</div>
            `;
            
            // Add styles
            Object.assign(indicator.style, {
                position: 'fixed',
                bottom: '20px',
                right: '20px',
                background: 'white',
                border: '1px solid #e2e8f0',
                borderRadius: '8px',
                padding: '16px',
                boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)',
                minWidth: '300px',
                zIndex: '9999'
            });

            document.body.appendChild(indicator);
        },

        removeProgressIndicator: function(id) {
            const indicator = document.getElementById(id);
            if (indicator) {
                indicator.parentNode.removeChild(indicator);
            }
        },

        setupProgressTracking: function() {
            // Override XMLHttpRequest to track upload progress
            const originalXHR = window.XMLHttpRequest;
            window.XMLHttpRequest = function() {
                const xhr = new originalXHR();
                const originalSend = xhr.send;
                
                xhr.send = function(data) {
                    if (data instanceof FormData) {
                        xhr.upload.addEventListener('progress', (e) => {
                            if (e.lengthComputable) {
                                const percentComplete = (e.loaded / e.total) * 100;
                                // Update progress bar if exists
                                const progressFill = document.querySelector('.upload-progress-fill');
                                if (progressFill) {
                                    progressFill.style.width = percentComplete + '%';
                                }
                            }
                        });
                    }
                    return originalSend.call(this, data);
                };
                
                return xhr;
            };
        },

        getAuthToken: function() {
            // Get auth token from localStorage or cookie
            return localStorage.getItem('authToken') || '';
        },

        onUploadSuccess: function(data) {
            // Trigger document processing if needed
            if (data.documentId) {
                this.processDocument(data.documentId);
            }
        },

        processDocument: function(documentId) {
            fetch(`/api/v1/documents/${documentId}/process`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.getAuthToken()}`,
                    'Content-Type': 'application/json'
                }
            })
            .then(response => response.json())
            .then(data => {
                utils.showNotification('Document processing started', 'info');
            })
            .catch(error => {
                console.error('Document processing error:', error);
            });
        }
    };

    // Auto-save functionality
    const autoSave = {
        init: function() {
            this.setupAutoSave();
        },

        setupAutoSave: function() {
            const chatInput = document.querySelector('.chat-input');
            if (chatInput) {
                chatInput.addEventListener('input', utils.debounce(() => {
                    this.saveDraft(chatInput.value);
                }, 1000));
            }
        },

        saveDraft: function(content) {
            if (content.trim()) {
                localStorage.setItem('chatDraft', content);
                localStorage.setItem('chatDraftTimestamp', Date.now().toString());
            }
        },

        loadDraft: function() {
            const draft = localStorage.getItem('chatDraft');
            const timestamp = localStorage.getItem('chatDraftTimestamp');
            
            if (draft && timestamp) {
                const age = Date.now() - parseInt(timestamp);
                // Only load drafts less than 1 hour old
                if (age < 3600000) {
                    const chatInput = document.querySelector('.chat-input');
                    if (chatInput) {
                        chatInput.value = draft;
                    }
                }
            }
        },

        clearDraft: function() {
            localStorage.removeItem('chatDraft');
            localStorage.removeItem('chatDraftTimestamp');
        }
    };

    // Chat history management
    const chatHistory = {
        init: function() {
            this.loadHistory();
            this.setupHistoryManagement();
        },

        loadHistory: function() {
            const history = this.getHistory();
            // Populate chat history UI
            this.renderHistory(history);
        },

        getHistory: function() {
            const history = localStorage.getItem('chatHistory');
            return history ? JSON.parse(history) : [];
        },

        saveHistory: function(history) {
            // Limit history size
            if (history.length > CONFIG.maxChatHistory) {
                history = history.slice(-CONFIG.maxChatHistory);
            }
            localStorage.setItem('chatHistory', JSON.stringify(history));
        },

        addToHistory: function(message) {
            const history = this.getHistory();
            history.push({
                ...message,
                timestamp: Date.now()
            });
            this.saveHistory(history);
        },

        renderHistory: function(history) {
            // Implementation depends on UI structure
            console.log('Chat history loaded:', history.length, 'messages');
        },

        setupHistoryManagement: function() {
            // Listen for new messages and add to history
            document.addEventListener('newMessage', (e) => {
                this.addToHistory(e.detail);
            });
        }
    };

    // Keyboard shortcuts
    const shortcuts = {
        init: function() {
            document.addEventListener('keydown', this.handleKeydown.bind(this));
        },

        handleKeydown: function(e) {
            // Ctrl/Cmd + Enter to send message
            if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
                const sendButton = document.querySelector('.send-button');
                if (sendButton) {
                    sendButton.click();
                }
            }

            // Ctrl/Cmd + K to focus search
            if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
                e.preventDefault();
                const searchInput = document.querySelector('.search-input');
                if (searchInput) {
                    searchInput.focus();
                }
            }

            // Escape to clear input
            if (e.key === 'Escape') {
                const chatInput = document.querySelector('.chat-input');
                if (chatInput && chatInput === document.activeElement) {
                    chatInput.value = '';
                }
            }
        }
    };

    // Theme management
    const theme = {
        init: function() {
            this.loadTheme();
            this.setupThemeToggle();
        },

        loadTheme: function() {
            const savedTheme = localStorage.getItem('theme');
            const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
            const theme = savedTheme || (prefersDark ? 'dark' : 'light');
            this.setTheme(theme);
        },

        setTheme: function(theme) {
            document.documentElement.setAttribute('data-theme', theme);
            localStorage.setItem('theme', theme);
        },

        setupThemeToggle: function() {
            const themeToggle = document.querySelector('.theme-toggle');
            if (themeToggle) {
                themeToggle.addEventListener('click', () => {
                    const currentTheme = document.documentElement.getAttribute('data-theme');
                    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
                    this.setTheme(newTheme);
                });
            }
        }
    };

    // Initialize all modules when DOM is ready
    function init() {
        fileUpload.init();
        autoSave.init();
        chatHistory.init();
        shortcuts.init();
        theme.init();

        // Load draft on page load
        autoSave.loadDraft();

        // Clear draft when message is sent
        document.addEventListener('messageSent', () => {
            autoSave.clearDraft();
        });

        console.log('White Label AI Assistant custom scripts loaded');
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    // Expose utilities globally for debugging
    window.WLAI = {
        utils,
        fileUpload,
        autoSave,
        chatHistory,
        shortcuts,
        theme,
        CONFIG
    };

})();