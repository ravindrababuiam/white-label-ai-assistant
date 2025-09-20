import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import { MCPServerConfig } from './types.js';
import * as fs from 'fs';
import * as path from 'path';

export class MCPConfigValidator {
  private ajv: Ajv;
  private schema: any;

  constructor() {
    this.ajv = new Ajv({ allErrors: true });
    addFormats(this.ajv);
    
    // Load the JSON schema
    const schemaPath = path.join(__dirname, '../schemas/mcp-server-config.json');
    this.schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
    this.ajv.addSchema(this.schema, 'mcp-server-config');
  }

  validateServerConfig(config: MCPServerConfig): ValidationResult {
    const validate = this.ajv.getSchema('mcp-server-config#/definitions/mcpServer');
    if (!validate) {
      throw new Error('Schema not found');
    }

    const valid = validate(config);
    
    if (!valid) {
      return {
        valid: false,
        errors: validate.errors?.map(error => ({
          field: error.instancePath || error.schemaPath,
          message: error.message || 'Unknown validation error',
          value: error.data
        })) || []
      };
    }

    // Additional custom validations
    const customErrors = this.performCustomValidations(config);
    
    return {
      valid: customErrors.length === 0,
      errors: customErrors
    };
  }

  validateServerList(configs: MCPServerConfig[]): ValidationResult {
    const validate = this.ajv.getSchema('mcp-server-config');
    if (!validate) {
      throw new Error('Schema not found');
    }

    const valid = validate({ servers: configs });
    
    if (!valid) {
      return {
        valid: false,
        errors: validate.errors?.map(error => ({
          field: error.instancePath || error.schemaPath,
          message: error.message || 'Unknown validation error',
          value: error.data
        })) || []
      };
    }

    // Check for duplicate IDs
    const ids = new Set<string>();
    const duplicateErrors: ValidationError[] = [];
    
    configs.forEach((config, index) => {
      if (ids.has(config.id)) {
        duplicateErrors.push({
          field: `servers[${index}].id`,
          message: `Duplicate server ID: ${config.id}`,
          value: config.id
        });
      }
      ids.add(config.id);
    });

    return {
      valid: duplicateErrors.length === 0,
      errors: duplicateErrors
    };
  }

  private performCustomValidations(config: MCPServerConfig): ValidationError[] {
    const errors: ValidationError[] = [];

    // Validate protocol-specific requirements
    if (config.protocol === 'stdio' && !config.command) {
      errors.push({
        field: 'command',
        message: 'Command is required for stdio protocol',
        value: config.command
      });
    }

    // Validate authentication configuration
    if (config.authentication) {
      const auth = config.authentication;
      
      if (auth.type === 'bearer' && !auth.token) {
        errors.push({
          field: 'authentication.token',
          message: 'Token is required for bearer authentication',
          value: auth.token
        });
      }
      
      if (auth.type === 'api-key' && !auth.token) {
        errors.push({
          field: 'authentication.token',
          message: 'Token is required for api-key authentication',
          value: auth.token
        });
      }
      
      if (auth.type === 'basic' && (!auth.username || !auth.password)) {
        errors.push({
          field: 'authentication',
          message: 'Username and password are required for basic authentication',
          value: { username: auth.username, password: auth.password }
        });
      }
    }

    // Validate endpoint format based on protocol
    if (config.protocol === 'websocket' && !config.endpoint.startsWith('ws://') && !config.endpoint.startsWith('wss://')) {
      errors.push({
        field: 'endpoint',
        message: 'WebSocket endpoints must start with ws:// or wss://',
        value: config.endpoint
      });
    }

    return errors;
  }
}

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
}

export interface ValidationError {
  field: string;
  message: string;
  value: any;
}