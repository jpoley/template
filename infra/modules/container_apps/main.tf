variable "name_prefix" { type = string }
variable "location" { type = string }
variable "resource_group" { type = string }
variable "log_analytics_workspace_id" { type = string }
variable "acr_login_server" { type = string }
variable "acr_id" { type = string }
variable "cosmos_endpoint" { type = string }
variable "cosmos_account_id" { type = string }
variable "cosmos_database_name" { type = string }
variable "cosmos_container_name" { type = string }
variable "backend_image" { type = string }
variable "frontend_image" { type = string }
variable "admin_image" { type = string }
variable "backend_min_replicas" { type = number }
variable "backend_max_replicas" { type = number }
variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}
variable "tags" { type = map(string) }

resource "azurerm_user_assigned_identity" "apps" {
  name                = "id-${var.name_prefix}-apps"
  resource_group_name = var.resource_group
  location            = var.location
  tags                = var.tags
}

# ACR pull permission for the managed identity
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.apps.principal_id
}

# Cosmos DB built-in Data Contributor
resource "azurerm_cosmosdb_sql_role_assignment" "backend" {
  resource_group_name = var.resource_group
  account_name        = reverse(split("/", var.cosmos_account_id))[0]
  role_definition_id  = "${var.cosmos_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.apps.principal_id
  scope               = var.cosmos_account_id
}

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.name_prefix}"
  location                   = var.location
  resource_group_name        = var.resource_group
  log_analytics_workspace_id = var.log_analytics_workspace_id
  tags                       = var.tags
}

# --- backend ------------------------------------------------------------
resource "azurerm_container_app" "backend" {
  name                         = "ca-${var.name_prefix}-backend"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = var.resource_group
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.apps.id
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = var.backend_min_replicas
    max_replicas = var.backend_max_replicas

    container {
      name   = "backend"
      image  = var.backend_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = "Production"
      }
      env {
        name  = "Cosmos__Endpoint"
        value = var.cosmos_endpoint
      }
      env {
        name  = "Cosmos__DatabaseName"
        value = var.cosmos_database_name
      }
      env {
        name  = "Cosmos__ContainerName"
        value = var.cosmos_container_name
      }
      env {
        name  = "Cosmos__UseManagedIdentity"
        value = "true"
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.apps.client_id
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.app_insights_connection_string
      }
    }
  }
}

# --- frontend -----------------------------------------------------------
resource "azurerm_container_app" "frontend" {
  name                         = "ca-${var.name_prefix}-frontend"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = var.resource_group
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.apps.id
  }

  ingress {
    external_enabled = true
    target_port      = 80
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3
    container {
      name   = "frontend"
      image  = var.frontend_image
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }
}

# --- admin --------------------------------------------------------------
resource "azurerm_container_app" "admin" {
  name                         = "ca-${var.name_prefix}-admin"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = var.resource_group
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.apps.id
  }

  ingress {
    external_enabled = true
    target_port      = 80
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 2
    container {
      name   = "admin"
      image  = var.admin_image
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }
}

output "backend_fqdn" { value = azurerm_container_app.backend.latest_revision_fqdn }
output "frontend_fqdn" { value = azurerm_container_app.frontend.latest_revision_fqdn }
output "admin_fqdn" { value = azurerm_container_app.admin.latest_revision_fqdn }
