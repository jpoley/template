locals {
  name_prefix = "${var.project_name}-${var.environment}"
  base_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      managed_by  = "terraform"
    },
    var.tags,
  )

  needs_db_password = var.db_provider != "none"

  db_connection_string = (
    var.db_provider == "postgres" ? try(module.postgres[0].connection_string, "") :
    var.db_provider == "sqlserver" ? try(module.mssql[0].connection_string, "") :
    ""
  )

  # Mapped to the backend's Database:Provider config key.
  backend_db_provider = (
    var.db_provider == "postgres" ? "Postgres" :
    var.db_provider == "sqlserver" ? "SqlServer" :
    "InMemory"
  )

  # Connection-string env var name expected by the backend.
  backend_db_connection_env = (
    var.db_provider == "postgres" ? "ConnectionStrings__Postgres" :
    var.db_provider == "sqlserver" ? "ConnectionStrings__SqlServer" :
    "ConnectionStrings__Unused"
  )
}

# Fail fast if a managed DB was requested without a password.
resource "terraform_data" "validate_db_password" {
  count = local.needs_db_password ? 1 : 0
  lifecycle {
    precondition {
      condition     = length(var.db_administrator_password) > 0
      error_message = "db_administrator_password must be set when db_provider != \"none\". Supply TF_VAR_db_administrator_password or use deploy.sh."
    }
  }
}

resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  special = false
  numeric = true
  keepers = {
    project = var.project_name
    env     = var.environment
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.base_tags
}

module "observability" {
  source = "./modules/observability"

  name_prefix    = local.name_prefix
  location       = azurerm_resource_group.main.location
  resource_group = azurerm_resource_group.main.name
  retention_days = var.log_analytics_retention_days
  tags           = local.base_tags
}

module "registry" {
  source = "./modules/registry"

  name           = replace("${local.name_prefix}${random_string.suffix.result}", "-", "")
  location       = azurerm_resource_group.main.location
  resource_group = azurerm_resource_group.main.name
  sku            = var.container_registry_sku
  tags           = local.base_tags
}

module "postgres" {
  source = "./modules/postgres"
  count  = var.db_provider == "postgres" ? 1 : 0

  name_prefix            = local.name_prefix
  suffix                 = random_string.suffix.result
  location               = azurerm_resource_group.main.location
  resource_group         = azurerm_resource_group.main.name
  sku_name               = var.postgres_sku_name
  storage_mb             = var.postgres_storage_mb
  postgres_version       = var.postgres_version
  administrator_login    = var.db_administrator_login
  administrator_password = var.db_administrator_password
  tags                   = local.base_tags
}

module "mssql" {
  source = "./modules/mssql"
  count  = var.db_provider == "sqlserver" ? 1 : 0

  name_prefix            = local.name_prefix
  suffix                 = random_string.suffix.result
  location               = azurerm_resource_group.main.location
  resource_group         = azurerm_resource_group.main.name
  administrator_login    = var.db_administrator_login
  administrator_password = var.db_administrator_password
  database_sku_name      = var.sqlserver_database_sku
  max_size_gb            = var.sqlserver_max_size_gb
  tags                   = local.base_tags
}

module "container_apps" {
  source = "./modules/container_apps"

  name_prefix                = local.name_prefix
  location                   = azurerm_resource_group.main.location
  resource_group             = azurerm_resource_group.main.name
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id
  acr_login_server           = module.registry.login_server
  acr_id                     = module.registry.id

  db_provider            = local.backend_db_provider
  db_connection_env_name = local.backend_db_connection_env
  db_connection_string   = local.db_connection_string

  backend_image        = var.backend_image
  frontend_image       = var.frontend_image
  internal_image       = var.internal_image
  deploy_internal      = var.deploy_internal
  backend_min_replicas = var.backend_min_replicas
  backend_max_replicas = var.backend_max_replicas

  app_insights_connection_string = module.observability.app_insights_connection_string

  tags = local.base_tags
}

module "frontdoor" {
  source = "./modules/frontdoor"
  count  = var.deploy_frontdoor ? 1 : 0

  name_prefix          = local.name_prefix
  resource_group       = azurerm_resource_group.main.name
  sku                  = var.frontdoor_sku
  backend_fqdn         = module.container_apps.backend_fqdn
  frontend_fqdn        = module.container_apps.frontend_fqdn
  deploy_internal      = var.deploy_internal
  internal_fqdn        = var.deploy_internal ? module.container_apps.internal_fqdn : ""
  custom_domain        = var.custom_domain
  internal_allowed_ips = var.internal_allowed_ips
  tags                 = local.base_tags
}
