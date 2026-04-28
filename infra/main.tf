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

  name_prefix            = local.name_prefix
  suffix                 = random_string.suffix.result
  location               = azurerm_resource_group.main.location
  resource_group         = azurerm_resource_group.main.name
  sku_name               = var.postgres_sku_name
  storage_mb             = var.postgres_storage_mb
  postgres_version       = var.postgres_version
  administrator_login    = var.postgres_administrator_login
  administrator_password = var.postgres_administrator_password
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

  postgres_connection_string = module.postgres.connection_string

  backend_image        = var.backend_image
  frontend_image       = var.frontend_image
  internal_image       = var.internal_image
  backend_min_replicas = var.backend_min_replicas
  backend_max_replicas = var.backend_max_replicas

  app_insights_connection_string = module.observability.app_insights_connection_string

  tags = local.base_tags
}

module "frontdoor" {
  source = "./modules/frontdoor"

  name_prefix          = local.name_prefix
  resource_group       = azurerm_resource_group.main.name
  sku                  = var.frontdoor_sku
  backend_fqdn         = module.container_apps.backend_fqdn
  frontend_fqdn        = module.container_apps.frontend_fqdn
  internal_fqdn        = module.container_apps.internal_fqdn
  custom_domain        = var.custom_domain
  internal_allowed_ips = var.internal_allowed_ips
  tags                 = local.base_tags
}
