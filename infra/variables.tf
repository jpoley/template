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

# --- Deployment toggles -------------------------------------------------
variable "db_provider" {
  description = "Database provider: postgres (Azure Database for PostgreSQL Flexible Server), sqlserver (Azure SQL Database), or none (in-memory; dev/demo only)."
  type        = string
  default     = "postgres"
  validation {
    condition     = contains(["postgres", "sqlserver", "none"], var.db_provider)
    error_message = "db_provider must be one of: postgres, sqlserver, none."
  }
}

variable "deploy_admin" {
  description = "Deploy the admin Container App."
  type        = bool
  default     = true
}

variable "deploy_frontdoor" {
  description = "Front Door + WAF in front of the Container Apps. When false, Container App ingress is hit directly."
  type        = bool
  default     = true
}

# --- Database (postgres) ------------------------------------------------
variable "postgres_sku_name" {
  description = "Azure Database for PostgreSQL Flexible Server SKU (e.g. B_Standard_B1ms, GP_Standard_D2s_v3)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Storage for the Flexible Server in MB."
  type        = number
  default     = 32768
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

# --- Database (sqlserver) -----------------------------------------------
variable "sqlserver_database_sku" {
  description = "Azure SQL Database SKU (e.g. Basic, S0, GP_S_Gen5_2)."
  type        = string
  default     = "S0"
}

variable "sqlserver_max_size_gb" {
  description = "Max storage for the SQL database in GB."
  type        = number
  default     = 2
}

# --- Database (shared) --------------------------------------------------
variable "db_administrator_login" {
  description = "Administrator login for the managed database. Ignored when db_provider = none."
  type        = string
  default     = "dbadmin"
}

variable "db_administrator_password" {
  description = "Administrator password for the managed database. Required when db_provider != none. Supply via TF_VAR_db_administrator_password or a sensitive *.auto.tfvars file; never commit."
  type        = string
  sensitive   = true
  default     = ""
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
  description = "Fully-qualified admin image (repo:tag). Ignored when deploy_admin = false."
  type        = string
  default     = ""
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
  description = "Front Door SKU (Standard_AzureFrontDoor or Premium_AzureFrontDoor). Ignored when deploy_frontdoor = false."
  type        = string
  default     = "Standard_AzureFrontDoor"
}

# --- Admin access restrictions -----------------------------------------
variable "admin_allowed_ips" {
  description = "IP CIDRs allowed to reach the admin UI via Front Door. Empty = open (NOT recommended for prod). Ignored when deploy_admin = false or deploy_frontdoor = false."
  type        = list(string)
  default     = []
}
