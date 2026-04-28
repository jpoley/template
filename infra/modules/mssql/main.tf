variable "name_prefix" { type = string }
variable "suffix" { type = string }
variable "location" { type = string }
variable "resource_group" { type = string }
variable "administrator_login" { type = string }
variable "administrator_password" {
  type      = string
  sensitive = true
}
variable "database_sku_name" {
  type        = string
  description = "SKU for the database (e.g. Basic, S0, GP_S_Gen5_2)."
  default     = "S0"
}
variable "max_size_gb" {
  type    = number
  default = 2
}
variable "tags" { type = map(string) }

resource "azurerm_mssql_server" "main" {
  name                         = "sql-${var.name_prefix}-${var.suffix}"
  location                     = var.location
  resource_group_name          = var.resource_group
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_password
  minimum_tls_version          = "1.2"
  tags                         = var.tags
}

resource "azurerm_mssql_database" "main" {
  name        = "projecttemplate"
  server_id   = azurerm_mssql_server.main.id
  sku_name    = var.database_sku_name
  max_size_gb = var.max_size_gb
  collation   = "SQL_Latin1_General_CP1_CI_AS"
  tags        = var.tags
}

# Allow Azure services. Tighten via VNet/private endpoints in prod.
resource "azurerm_mssql_firewall_rule" "allow_azure" {
  name             = "allow-azure-services"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

output "server_id" { value = azurerm_mssql_server.main.id }
output "server_name" { value = azurerm_mssql_server.main.name }
output "fqdn" { value = azurerm_mssql_server.main.fully_qualified_domain_name }
output "database_name" { value = azurerm_mssql_database.main.name }
output "connection_string" {
  value     = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${var.administrator_login};Password=${var.administrator_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sensitive = true
}
