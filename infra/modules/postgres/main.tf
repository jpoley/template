variable "name_prefix" { type = string }
variable "suffix" { type = string }
variable "location" { type = string }
variable "resource_group" { type = string }
variable "sku_name" { type = string }
variable "storage_mb" { type = number }
variable "postgres_version" { type = string }
variable "administrator_login" { type = string }
variable "administrator_password" {
  type      = string
  sensitive = true
}
variable "tags" { type = map(string) }

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "pg-${var.name_prefix}-${var.suffix}"
  location                      = var.location
  resource_group_name           = var.resource_group
  version                       = var.postgres_version
  sku_name                      = var.sku_name
  storage_mb                    = var.storage_mb
  administrator_login           = var.administrator_login
  administrator_password        = var.administrator_password
  zone                          = "1"
  public_network_access_enabled = true
  tags                          = var.tags

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = "projecttemplate"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# Allow Azure services (Container Apps egress) to reach the server. Lock down
# via VNet integration in production.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

output "server_id" { value = azurerm_postgresql_flexible_server.main.id }
output "server_name" { value = azurerm_postgresql_flexible_server.main.name }
output "fqdn" { value = azurerm_postgresql_flexible_server.main.fqdn }
output "database_name" { value = azurerm_postgresql_flexible_server_database.main.name }
output "connection_string" {
  value     = "Host=${azurerm_postgresql_flexible_server.main.fqdn};Port=5432;Database=${azurerm_postgresql_flexible_server_database.main.name};Username=${var.administrator_login};Password=${var.administrator_password};SslMode=Require"
  sensitive = true
}
