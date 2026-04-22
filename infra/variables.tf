variable "project_name" {
  description = "Short project name used as base for resource names. Lowercase, no spaces."
  type        = string
  default     = "projecttemplate"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,14}$", var.project_name))
    error_message = "project_name must be 3-15 chars, lowercase alphanumerics, start with a letter."
  }
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "eastus2"
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}

# --- Cosmos DB ----------------------------------------------------------
variable "cosmos_consistency_level" {
  description = "Cosmos default consistency level."
  type        = string
  default     = "Session"
}

variable "cosmos_throughput_mode" {
  description = "provisioned | serverless"
  type        = string
  default     = "serverless"
  validation {
    condition     = contains(["provisioned", "serverless"], var.cosmos_throughput_mode)
    error_message = "cosmos_throughput_mode must be provisioned or serverless."
  }
}

variable "cosmos_provisioned_throughput" {
  description = "RU/s when cosmos_throughput_mode = provisioned."
  type        = number
  default     = 400
}

# --- Container Apps -----------------------------------------------------
variable "container_registry_sku" {
  description = "Azure Container Registry SKU."
  type        = string
  default     = "Basic"
}

variable "backend_image" {
  description = "Fully-qualified backend image (repo:tag). Pushed by CI before apply."
  type        = string
}

variable "frontend_image" {
  description = "Fully-qualified frontend image (repo:tag)."
  type        = string
}

variable "admin_image" {
  description = "Fully-qualified admin image (repo:tag)."
  type        = string
}

variable "backend_min_replicas" {
  description = "Minimum backend replicas."
  type        = number
  default     = 1
}

variable "backend_max_replicas" {
  description = "Maximum backend replicas."
  type        = number
  default     = 5
}

# --- Observability ------------------------------------------------------
variable "log_analytics_retention_days" {
  description = "Days of log retention."
  type        = number
  default     = 30
}

# --- Front Door ---------------------------------------------------------
variable "frontdoor_sku" {
  description = "Front Door SKU (Standard_AzureFrontDoor or Premium_AzureFrontDoor)."
  type        = string
  default     = "Standard_AzureFrontDoor"
}

variable "custom_domain" {
  description = "Optional custom domain for Front Door (empty = no custom domain)."
  type        = string
  default     = ""
}

# --- Admin access restrictions -----------------------------------------
variable "admin_allowed_ips" {
  description = "IP CIDRs allowed to reach the admin UI via Front Door. Empty = open (NOT recommended for prod)."
  type        = list(string)
  default     = []
}
